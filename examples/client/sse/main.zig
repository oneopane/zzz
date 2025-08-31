const std = @import("std");
const zzz = @import("zzz");
const http = zzz.HTTP;
const tardy = zzz.tardy;

const SSEMessage = http.Client.sse_parser.SSEMessage;

// Structure to store a captured SSE message
const StoredSSEMessage = struct {
    id: ?[]const u8 = null,
    event: ?[]const u8 = null,
    data: ?[]const u8 = null,
    retry: ?u64 = null,
    
    fn deinit(self: *StoredSSEMessage, allocator: std.mem.Allocator) void {
        if (self.id) |id| allocator.free(id);
        if (self.event) |event| allocator.free(event);
        if (self.data) |data| allocator.free(data);
    }
    
    fn print(self: StoredSSEMessage, index: usize) void {
        std.debug.print("  [Event #{d}]\n", .{index});
        if (self.id) |id| {
            std.debug.print("    id: {s}\n", .{id});
        }
        if (self.event) |event| {
            std.debug.print("    event: {s}\n", .{event});
        }
        if (self.data) |data| {
            std.debug.print("    data: {s}\n", .{data});
        }
        if (self.retry) |retry| {
            std.debug.print("    retry: {d}ms\n", .{retry});
        }
        std.debug.print("\n", .{});
    }
};

// Template for consistent output formatting
const SSEExampleResult = struct {
    name: []const u8,
    url: []const u8,
    allocator: std.mem.Allocator,
    messages: std.ArrayList(StoredSSEMessage),
    success: bool,
    
    fn init(allocator: std.mem.Allocator, name: []const u8, url: []const u8) !SSEExampleResult {
        return SSEExampleResult{
            .name = name,
            .url = url,
            .allocator = allocator,
            .messages = try std.ArrayList(StoredSSEMessage).initCapacity(allocator, 0),
            .success = false,
        };
    }
    
    fn deinit(self: *SSEExampleResult) void {
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.deinit(self.allocator);
    }
    
    fn print(self: SSEExampleResult) void {
        const last_event_id = if (self.messages.items.len > 0) 
            self.messages.items[self.messages.items.len - 1].id 
        else 
            null;
            
        var had_retry = false;
        for (self.messages.items) |msg| {
            if (msg.retry != null) {
                had_retry = true;
                break;
            }
        }
        
        std.debug.print(
            \\
            \\=== {s} ===
            \\  URL:           {s}
            \\  Events:        {d} received
            \\  Last Event ID: {s}
            \\  Retry Set:     {s}
            \\  Result:        {s}
            \\
            \\  Messages:
            \\
        , .{
            self.name,
            self.url,
            self.messages.items.len,
            last_event_id orelse "none",
            if (had_retry) "yes" else "no",
            if (self.success) "✓ Success" else "✗ Failed",
        });
        
        for (self.messages.items, 1..) |msg, i| {
            msg.print(i);
        }
    }
};

/// Example SSE client that could connect to an LLM API
/// This demonstrates the pattern for OpenAI/Anthropic style streaming
pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize Tardy runtime
    const Tardy = tardy.Tardy(.auto);
    var t = try Tardy.init(allocator, .{ .threading = .single });
    defer t.deinit();
    
    // Run HTTP client in async context
    try t.entry(
        allocator,
        struct {
            fn entry(rt: *tardy.Runtime, alloc: std.mem.Allocator) !void {
                try rt.spawn(.{ rt, alloc }, run_sse_examples, 1024 * 256);
            }
        }.entry,
    );
}

fn run_sse_examples(rt: *tardy.Runtime, allocator: std.mem.Allocator) !void {
    // Create HTTP client
    var client = try http.Client.HTTPClient.init(allocator, rt);
    defer client.deinit();

    std.debug.print("\n🚀 zzz SSE Client Examples - Streaming Support\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    
    // Run different SSE examples
    try demo_high_level_api(&client, allocator);
    try demo_low_level_api(&client, allocator);
    
    std.debug.print("\n✅ All SSE examples completed successfully!\n\n", .{});
}

fn demo_high_level_api(client: *http.Client.HTTPClient, allocator: std.mem.Allocator) !void {
    const url = "http://127.0.0.1:8082/events";  // Local SSE test server
    
    // Create GET request for SSE endpoint  
    var req = try http.Client.ClientRequest.get(allocator, url);
    defer req.deinit();
    
    // Set SSE headers
    _ = try req.set_header("Accept", "text/event-stream");
    _ = try req.set_header("Cache-Control", "no-cache");
    
    // Initialize result structure
    var result = try SSEExampleResult.init(allocator, "High-Level SSE API", url);
    defer result.deinit();
    
    // SSE event handler - message is only valid during callback
    const event_handler = struct {
        fn callback(message: *const SSEMessage, user_context: ?*anyopaque) anyerror!void {
            const res = @as(*SSEExampleResult, @ptrCast(@alignCast(user_context.?)));
            
            // Store the message (duping strings since they're only valid during callback)
            const stored = StoredSSEMessage{
                .id = if (message.id) |id| try res.allocator.dupe(u8, id) else null,
                .event = if (message.event) |evt| try res.allocator.dupe(u8, evt) else null,
                .data = if (message.data) |d| try res.allocator.dupe(u8, d) else null,
                .retry = message.retry,
            };
            
            try res.messages.append(res.allocator, stored);
            
            // Check for completion markers
            if (message.data) |data| {
                if (std.mem.indexOf(u8, data, "DONE") != null or 
                    std.mem.indexOf(u8, data, "complete") != null) {
                    return error.StopStreaming;
                }
            }
            
            // Check for error events
            if (message.event) |event| {
                if (std.mem.eql(u8, event, "error")) {
                    return error.StreamError;
                } else if (std.mem.eql(u8, event, "complete")) {
                    return error.StopStreaming;
                }
            }
        }
    }.callback;
    
    const config = http.Client.streaming.StreamConfig{
        .chunk_buffer_size = 8192,
        .parse_sse = true,
        .timeout_ms = 30000,
        .overflow_policy = http.Client.streaming.ArenaOverflowPolicy.return_error,
    };
    
    // Stream the response with 8KB arena for SSE message strings
    const arena_size = 8192;
    
    client.send_streaming_sse(&req, event_handler, &result, config, arena_size) catch |err| {
        switch (err) {
            error.StopStreaming => {
                // Normal completion
                result.success = true;
            },
            else => {
                // Actual error
                result.success = false;
            },
        }
    };
    
    // Print results
    result.print();
}

/// Example using low-level SSE API with caller-owned memory
fn demo_low_level_api(client: *http.Client.HTTPClient, allocator: std.mem.Allocator) !void {
    const url = "http://127.0.0.1:8082/events";
    
    // Create GET request for SSE endpoint
    var req = try http.Client.ClientRequest.get(allocator, url);
    defer req.deinit();
    
    _ = try req.set_header("Accept", "text/event-stream");
    _ = try req.set_header("Cache-Control", "no-cache");
    
    // Initialize result structure
    var result = try SSEExampleResult.init(allocator, "Low-Level SSE API (Production Pattern)", url);
    defer result.deinit();
    
    // Caller-owned message struct (stack allocated)
    var message = http.Client.sse_parser.SSEMessage{
        .id = null,
        .event = null,
        .data = null,
        .retry = null,
    };
    
    // Caller-owned arena for string data
    var arena_buffer: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_buffer);
    var arena = std.heap.ArenaAllocator.init(fba.allocator());
    defer arena.deinit();
    
    const event_handler = struct {
        fn callback(msg: *const http.Client.sse_parser.SSEMessage, user_context: ?*anyopaque) anyerror!void {
            const res = @as(*SSEExampleResult, @ptrCast(@alignCast(user_context.?)));
            
            // Store the message (duping strings since the arena will be reset)
            // Note: In low-level API, we must copy the strings as they'll be invalid after callback
            const stored = StoredSSEMessage{
                .id = if (msg.id) |id| try res.allocator.dupe(u8, id) else null,
                .event = if (msg.event) |evt| try res.allocator.dupe(u8, evt) else null,
                .data = if (msg.data) |d| try res.allocator.dupe(u8, d) else null,
                .retry = msg.retry,
            };
            
            try res.messages.append(res.allocator, stored);
            
            // Check for completion
            if (msg.data) |data| {
                if (std.mem.indexOf(u8, data, "DONE") != null or
                    std.mem.indexOf(u8, data, "complete") != null) {
                    return error.StopStreaming;
                }
            }
            
            // Check for error events
            if (msg.event) |event| {
                if (std.mem.eql(u8, event, "error")) {
                    return error.StreamError;
                } else if (std.mem.eql(u8, event, "complete")) {
                    return error.StopStreaming;
                }
            }
        }
    }.callback;
    
    const config = http.Client.streaming.StreamConfig{
        .chunk_buffer_size = 8192,
        .parse_sse = true,
        .overflow_policy = http.Client.streaming.ArenaOverflowPolicy.return_error, // Could use .heap_fallback with general allocator
    };
    
    // Use low-level API - caller owns all memory
    client.send_streaming_sse_raw(
        &req,
        event_handler,
        &result,
        config,
        &arena,
        &message,
        null, // No general allocator (using .return_error policy)
    ) catch |err| {
        switch (err) {
            error.StopStreaming => {
                result.success = true;
            },
            error.EventTooLarge => {
                // Arena was too small
                result.success = false;
            },
            else => {
                result.success = false;
            },
        }
    };
    
    // Print results
    result.print();
}

