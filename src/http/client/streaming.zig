const std = @import("std");

const Runtime = @import("tardy").Runtime;
const Connection = @import("connection.zig").Connection;
const ClientRequest = @import("request.zig").ClientRequest;
const ClientResponse = @import("response.zig").ClientResponse;
const TransferEncoding = @import("response.zig").TransferEncoding;
const SSEParser = @import("sse_parser.zig").SSEParser;
const SSEMessage = @import("sse_parser.zig").SSEMessage;
const ChunkedParser = @import("chunked_parser.zig").ChunkedParser;

/// Policy for handling arena overflow during SSE parsing
pub const ArenaOverflowPolicy = enum {
    /// Return error.EventTooLarge when arena is exhausted
    return_error,
    /// Fall back to general allocator for oversized fields
    heap_fallback,
};

/// Configuration for streaming operations
pub const StreamConfig = struct {
    /// Buffer size for reading chunks from network
    chunk_buffer_size: usize = 8192,
    /// Maximum time to wait for next chunk (milliseconds)
    timeout_ms: u32 = 30000,
    /// Whether to automatically parse SSE messages
    parse_sse: bool = true,
    /// Policy for handling arena overflow in SSE parsing
    overflow_policy: ArenaOverflowPolicy = .return_error,
};

/// Callback function type for processing chunks
pub const ChunkCallback = *const fn (chunk: []const u8, user_context: ?*anyopaque) anyerror!void;

/// Callback function type for processing SSE messages
/// The message is only valid during the callback execution
pub const SSECallback = *const fn (message: *const SSEMessage, user_context: ?*anyopaque) anyerror!void;

/// Streaming response handler for processing data as it arrives
pub const StreamingResponse = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,
    runtime: *Runtime,
    response: ClientResponse,
    config: StreamConfig,
    sse_parser: ?SSEParser = null,
    chunked_parser: ?ChunkedParser = null,
    transfer: TransferEncoding,
    closed: bool = false,
    
    // Initial body bytes from header read
    initial: []const u8,
    initial_offset: usize = 0,
    
    /// Initialize a streaming response from a connection
    pub fn init(
        allocator: std.mem.Allocator,
        connection: *Connection,
        runtime: *Runtime,
        response: ClientResponse,
        initial: []const u8,
        transfer: TransferEncoding,
        config: StreamConfig,
    ) !StreamingResponse {
        // Initialize SSE parser if needed
        const sse_parser = if (transfer == .sse and config.parse_sse)
            try SSEParser.init(allocator)
        else
            null;
        
        // Initialize chunked parser if needed
        const chunked_parser = if (transfer == .chunked)
            try ChunkedParser.init(allocator)
        else
            null;
        
        return StreamingResponse{
            .allocator = allocator,
            .connection = connection,
            .runtime = runtime,
            .response = response,
            .config = config,
            .sse_parser = sse_parser,
            .chunked_parser = chunked_parser,
            .transfer = transfer,
            .initial = initial,
            .initial_offset = 0,
            .closed = false,
        };
    }
    
    pub fn deinit(self: *StreamingResponse) void {
        if (self.sse_parser) |*parser| {
            parser.deinit();
        }
        if (self.chunked_parser) |*parser| {
            parser.deinit();
        }
        self.response.deinit();
        self.closed = true;
    }
    
    /// Stream data with a chunk callback
    pub fn stream_chunks(
        self: *StreamingResponse,
        callback: ChunkCallback,
        user_context: ?*anyopaque,
    ) !void {
        if (self.closed) return error.StreamClosed;
        
        var buffer = try self.allocator.alloc(u8, self.config.chunk_buffer_size);
        defer self.allocator.free(buffer);
        
        // Buffer for decoded chunked data if needed
        var decoded_buffer = try std.ArrayList(u8).initCapacity(self.allocator, 
            if (self.transfer == .chunked) self.config.chunk_buffer_size else 0);
        defer decoded_buffer.deinit(self.allocator);
        
        // First, process any initial body bytes
        if (self.initial_offset < self.initial.len) {
            const remaining = self.initial[self.initial_offset..];
            
            if (self.transfer == .chunked and self.chunked_parser != null) {
                // Parse chunked encoding
                decoded_buffer.clearRetainingCapacity();
                _ = try self.chunked_parser.?.parse(remaining, &decoded_buffer);
                if (decoded_buffer.items.len > 0) {
                    try callback(decoded_buffer.items, user_context);
                }
            } else {
                // Direct delivery for non-chunked
                try callback(remaining, user_context);
            }
            
            self.initial_offset = self.initial.len;
        }
        
        while (true) {
            // Read next chunk from connection using recv_some
            const bytes_read = try self.connection.recv_some(self.runtime, buffer);
            
            if (bytes_read == 0) {
                self.closed = true;
                break;
            }
            
            if (self.transfer == .chunked and self.chunked_parser != null) {
                // Parse chunked encoding
                decoded_buffer.clearRetainingCapacity();
                _ = try self.chunked_parser.?.parse(buffer[0..bytes_read], &decoded_buffer);
                
                // Deliver decoded data
                if (decoded_buffer.items.len > 0) {
                    try callback(decoded_buffer.items, user_context);
                }
                
                // Check if chunked transfer is complete
                if (self.chunked_parser.?.is_complete()) {
                    self.closed = true;
                    break;
                }
            } else {
                // Direct delivery for non-chunked
                try callback(buffer[0..bytes_read], user_context);
            }
        }
    }
    
    /// Low-level SSE streaming - caller owns all memory
    /// Arena is reset per message, slices are valid only during callback
    pub fn stream_sse_raw(
        self: *StreamingResponse,
        callback: SSECallback,
        user_context: ?*anyopaque,
        arena: *std.heap.ArenaAllocator,
        message: *SSEMessage,
        general_allocator: ?std.mem.Allocator,
    ) !void {
        if (self.transfer != .sse) return error.NotSSEResponse;
        if (self.closed) return error.StreamClosed;
        if (self.sse_parser == null) return error.SSEParserNotInitialized;
        
        // Validate parameters based on config
        if (self.config.overflow_policy == .heap_fallback and general_allocator == null) {
            return error.HeapFallbackRequiresAllocator;
        }
        
        var buffer = try self.allocator.alloc(u8, self.config.chunk_buffer_size);
        defer self.allocator.free(buffer);
        
        // Process initial data if any
        if (self.initial_offset < self.initial.len) {
            const remaining = self.initial[self.initial_offset..];
            try self.process_sse_chunk(
                remaining,
                arena,
                message,
                callback,
                user_context,
                general_allocator,
            );
            self.initial_offset = self.initial.len;
        }
        
        // Main streaming loop
        while (true) {
            const bytes_read = try self.connection.recv_some(self.runtime, buffer);
            if (bytes_read == 0) {
                self.closed = true;
                break;
            }
            
            try self.process_sse_chunk(
                buffer[0..bytes_read],
                arena,
                message,
                callback,
                user_context,
                general_allocator,
            );
        }
    }
    
    /// High-level SSE streaming with managed memory
    pub fn stream_sse(
        self: *StreamingResponse,
        callback: SSECallback,
        user_context: ?*anyopaque,
        arena_buffer_size: usize,
    ) !void {
        // Stack-allocated message
        var message = SSEMessage{
            .id = null,
            .event = null,
            .data = null,
            .retry = null,
        };
        
        // Create arena with provided size
        const arena_buffer = try self.allocator.alloc(u8, arena_buffer_size);
        defer self.allocator.free(arena_buffer);
        
        var fba = std.heap.FixedBufferAllocator.init(arena_buffer);
        var arena = std.heap.ArenaAllocator.init(fba.allocator());
        defer arena.deinit();
        
        // Delegate to low-level API
        return self.stream_sse_raw(
            callback,
            user_context,
            &arena,
            &message,
            if (self.config.overflow_policy == .heap_fallback) self.allocator else null,
        );
    }
    
    fn process_sse_chunk(
        self: *StreamingResponse,
        chunk: []const u8,
        arena: *std.heap.ArenaAllocator,
        message: *SSEMessage,
        callback: SSECallback,
        user_context: ?*anyopaque,
        general_allocator: ?std.mem.Allocator,
    ) !void {
        // Parse chunk into temporary messages using parser's internal state
        var temp_messages = try std.ArrayList(SSEMessage).initCapacity(self.allocator, 0);
        defer {
            for (temp_messages.items) |*msg| {
                msg.deinit(self.allocator);
            }
            temp_messages.deinit(self.allocator);
        }
        
        try self.sse_parser.?.parse_chunk(chunk, &temp_messages);
        
        for (temp_messages.items) |parsed| {
            // Reset arena for this message - slices valid until next dispatch
            _ = arena.reset(.retain_capacity);
            
            // Copy fields to arena with overflow handling
            message.id = try self.copy_with_overflow(
                parsed.id,
                arena.allocator(),
                general_allocator,
            );
            message.event = try self.copy_with_overflow(
                parsed.event,
                arena.allocator(),
                general_allocator,
            );
            message.data = try self.copy_with_overflow(
                parsed.data,
                arena.allocator(),
                general_allocator,
            );
            message.retry = parsed.retry;
            
            // Dispatch with valid slices
            try callback(message, user_context);
        }
    }
    
    fn copy_with_overflow(
        self: *const StreamingResponse,
        data: ?[]const u8,
        arena: std.mem.Allocator,
        general: ?std.mem.Allocator,
    ) !?[]const u8 {
        const d = data orelse return null;
        
        // Try arena first
        return arena.dupe(u8, d) catch |err| {
            if (err == error.OutOfMemory) {
                switch (self.config.overflow_policy) {
                    .return_error => return error.EventTooLarge,
                    .heap_fallback => {
                        // Use general allocator as fallback
                        return try general.?.dupe(u8, d);
                    },
                }
            }
            return err;
        };
    }
    
    /// Check if stream is still active
    pub fn is_active(self: *const StreamingResponse) bool {
        return !self.closed and self.connection.is_alive();
    }
    
    /// Get the last event ID for SSE reconnection
    pub fn get_last_event_id(self: *const StreamingResponse) ?[]const u8 {
        if (self.sse_parser) |parser| {
            return parser.get_last_event_id();
        }
        return null;
    }
};

/// Iterator-based streaming interface for pull-based consumption
pub const StreamIterator = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,
    runtime: *Runtime,
    response: ClientResponse,
    config: StreamConfig,
    buffer: []u8,
    buffer_pos: usize = 0,
    buffer_len: usize = 0,
    sse_parser: ?SSEParser = null,
    chunked_parser: ?ChunkedParser = null,
    transfer: TransferEncoding,
    closed: bool = false,
    pending_messages: std.ArrayList(SSEMessage),
    decoded_buffer: std.ArrayList(u8),
    
    // Initial body bytes from header read
    initial: []const u8,
    initial_offset: usize = 0,
    
    /// Initialize a stream iterator
    pub fn init(
        allocator: std.mem.Allocator,
        connection: *Connection,
        runtime: *Runtime,
        response: ClientResponse,
        initial: []const u8,
        transfer: TransferEncoding,
        config: StreamConfig,
    ) !StreamIterator {
        const buffer = try allocator.alloc(u8, config.chunk_buffer_size);
        errdefer allocator.free(buffer);
        
        // Initialize SSE parser if needed
        const sse_parser = if (transfer == .sse and config.parse_sse)
            try SSEParser.init(allocator)
        else
            null;
        
        // Initialize chunked parser if needed
        const chunked_parser = if (transfer == .chunked)
            try ChunkedParser.init(allocator)
        else
            null;
        
        return StreamIterator{
            .allocator = allocator,
            .connection = connection,
            .runtime = runtime,
            .response = response,
            .config = config,
            .buffer = buffer,
            .sse_parser = sse_parser,
            .chunked_parser = chunked_parser,
            .transfer = transfer,
            .closed = false,
            .pending_messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0),
            .decoded_buffer = try std.ArrayList(u8).initCapacity(allocator, config.chunk_buffer_size),
            .initial = initial,
            .initial_offset = 0,
        };
    }
    
    pub fn deinit(self: *StreamIterator) void {
        for (self.pending_messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.pending_messages.deinit(self.allocator);
        self.decoded_buffer.deinit(self.allocator);
        
        if (self.sse_parser) |*parser| {
            parser.deinit();
        }
        
        if (self.chunked_parser) |*parser| {
            parser.deinit();
        }
        
        self.allocator.free(self.buffer);
        self.response.deinit();
        self.closed = true;
    }
    
    /// Get the next chunk of data
    pub fn next_chunk(self: *StreamIterator) !?[]const u8 {
        if (self.closed) return null;
        
        // First return any initial body bytes
        if (self.initial_offset < self.initial.len) {
            const remaining = self.initial[self.initial_offset..];
            
            if (self.transfer == .chunked and self.chunked_parser != null) {
                // Parse chunked encoding
                self.decoded_buffer.clearRetainingCapacity();
                _ = try self.chunked_parser.?.parse(remaining, &self.decoded_buffer);
                self.initial_offset = self.initial.len;
                
                if (self.decoded_buffer.items.len > 0) {
                    // Copy to buffer for return
                    const to_return = @min(self.decoded_buffer.items.len, self.buffer.len);
                    @memcpy(self.buffer[0..to_return], self.decoded_buffer.items[0..to_return]);
                    return self.buffer[0..to_return];
                }
                
                // Check if already complete
                if (self.chunked_parser.?.is_complete()) {
                    self.closed = true;
                    return null;
                }
            } else {
                // Non-chunked: return directly
                const to_return = @min(remaining.len, self.buffer.len);
                @memcpy(self.buffer[0..to_return], remaining[0..to_return]);
                self.initial_offset += to_return;
                return self.buffer[0..to_return];
            }
        }
        
        // Then read from connection
        const bytes_read = try self.connection.recv_some(self.runtime, self.buffer);
        
        if (bytes_read == 0) {
            self.closed = true;
            return null;
        }
        
        if (self.transfer == .chunked and self.chunked_parser != null) {
            // Parse chunked encoding
            self.decoded_buffer.clearRetainingCapacity();
            _ = try self.chunked_parser.?.parse(self.buffer[0..bytes_read], &self.decoded_buffer);
            
            // Check if chunked transfer is complete
            if (self.chunked_parser.?.is_complete()) {
                self.closed = true;
                if (self.decoded_buffer.items.len > 0) {
                    // Return last data
                    const to_return = @min(self.decoded_buffer.items.len, self.buffer.len);
                    @memcpy(self.buffer[0..to_return], self.decoded_buffer.items[0..to_return]);
                    return self.buffer[0..to_return];
                }
                return null;
            }
            
            if (self.decoded_buffer.items.len > 0) {
                // Copy decoded data to buffer for return
                const to_return = @min(self.decoded_buffer.items.len, self.buffer.len);
                @memcpy(self.buffer[0..to_return], self.decoded_buffer.items[0..to_return]);
                return self.buffer[0..to_return];
            }
            
            // No decoded data yet, need more input
            return &[_]u8{};
        } else {
            // Non-chunked: return raw data
            return self.buffer[0..bytes_read];
        }
    }
    
    /// Get the next SSE message
    pub fn next_sse_message(self: *StreamIterator) !?SSEMessage {
        if (self.transfer != .sse) return error.NotSSEResponse;
        if (self.sse_parser == null) return error.SSEParserNotInitialized;
        
        // Return pending message if available
        if (self.pending_messages.items.len > 0) {
            return self.pending_messages.orderedRemove(0);
        }
        
        // Read chunks until we get at least one message
        while (!self.closed) {
            const chunk = try self.next_chunk();
            if (chunk == null) break;
            
            // Parse messages from chunk
            self.pending_messages.clearRetainingCapacity();
            try self.sse_parser.?.parse_chunk(chunk.?, &self.pending_messages);
            
            // Return first message if we got any
            if (self.pending_messages.items.len > 0) {
                return self.pending_messages.orderedRemove(0);
            }
        }
        
        return null;
    }
    
    /// Check if more data is available
    pub fn has_more(self: *const StreamIterator) bool {
        return !self.closed and self.connection.is_alive();
    }
};

// Tests
test "StreamingResponse initialization" {
    const allocator = std.testing.allocator;
    
    // Create a mock response with SSE content type
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    _ = try response.headers.put(
        try allocator.dupe(u8, "Content-Type"),
        try allocator.dupe(u8, "text/event-stream"),
    );
    
    // Note: We would need a mock connection and runtime for a full test
    // This test just verifies the structure compiles
    
    const config = StreamConfig{};
    _ = config;
    
    try std.testing.expect(response.get_header("Content-Type") != null);
}

test "StreamIterator buffer management" {
    const allocator = std.testing.allocator;
    
    // Test that buffer allocation works correctly
    const config = StreamConfig{
        .chunk_buffer_size = 4096,
    };
    
    const buffer = try allocator.alloc(u8, config.chunk_buffer_size);
    defer allocator.free(buffer);
    
    try std.testing.expect(buffer.len == 4096);
}