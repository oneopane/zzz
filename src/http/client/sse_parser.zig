const std = @import("std");

/// Server-Sent Events message structure
/// Follows the W3C EventSource specification
pub const SSEMessage = struct {
    /// Event ID for reconnection support
    id: ?[]const u8 = null,
    /// Event type (defaults to "message" if not specified)
    event: ?[]const u8 = null,
    /// Event data (can be multiline)
    data: ?[]const u8 = null,
    /// Retry interval in milliseconds
    retry: ?u64 = null,

    pub fn deinit(self: *SSEMessage, allocator: std.mem.Allocator) void {
        if (self.id) |id| allocator.free(id);
        if (self.event) |event| allocator.free(event);
        if (self.data) |data| allocator.free(data);
        self.* = .{};
    }
};

/// SSE parser for incremental parsing of Server-Sent Events
/// Handles partial messages across network chunks
pub const SSEParser = struct {
    allocator: std.mem.Allocator,
    /// Buffer for incomplete lines that span chunks
    partial_line: std.ArrayList(u8),
    /// Current message being assembled
    current_message: MessageBuilder,
    /// Last event ID for reconnection support
    last_event_id: ?[]const u8 = null,
    
    const MessageBuilder = struct {
        id: ?[]const u8 = null,
        event: ?[]const u8 = null,
        data: std.ArrayList(u8),
        retry: ?u64 = null,
        has_data: bool = false,
        
        fn init(allocator: std.mem.Allocator) !MessageBuilder {
            return .{
                .data = try std.ArrayList(u8).initCapacity(allocator, 0),
            };
        }
        
        fn deinit(self: *MessageBuilder, allocator: std.mem.Allocator) void {
            self.data.deinit(allocator);
            if (self.id) |id| allocator.free(id);
            if (self.event) |event| allocator.free(event);
        }
        
        fn reset(self: *MessageBuilder, allocator: std.mem.Allocator) void {
            if (self.id) |id| allocator.free(id);
            if (self.event) |event| allocator.free(event);
            self.id = null;
            self.event = null;
            self.data.clearRetainingCapacity();
            self.retry = null;
            self.has_data = false;
        }
        
        fn build(self: *MessageBuilder, allocator: std.mem.Allocator) !?SSEMessage {
            // Only build a message if we have data
            if (!self.has_data) return null;
            
            // Trim trailing newline from data if present
            var data_str = self.data.items;
            if (data_str.len > 0 and data_str[data_str.len - 1] == '\n') {
                data_str = data_str[0..data_str.len - 1];
            }
            
            return SSEMessage{
                .id = if (self.id) |id| try allocator.dupe(u8, id) else null,
                .event = if (self.event) |event| try allocator.dupe(u8, event) else null,
                .data = if (data_str.len > 0) try allocator.dupe(u8, data_str) else null,
                .retry = self.retry,
            };
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) !SSEParser {
        return .{
            .allocator = allocator,
            .partial_line = try std.ArrayList(u8).initCapacity(allocator, 0),
            .current_message = try MessageBuilder.init(allocator),
        };
    }
    
    pub fn deinit(self: *SSEParser) void {
        self.partial_line.deinit(self.allocator);
        self.current_message.deinit(self.allocator);
        if (self.last_event_id) |id| {
            self.allocator.free(id);
        }
    }
    
    /// Parse a chunk of data, returning messages as they become complete
    /// Handles partial lines that span chunks
    pub fn parse_chunk(self: *SSEParser, chunk: []const u8, messages: *std.ArrayList(SSEMessage)) !void {
        var offset: usize = 0;
        
        while (offset < chunk.len) {
            // Find the next newline
            const newline_pos = std.mem.indexOfScalarPos(u8, chunk, offset, '\n');
            
            if (newline_pos) |pos| {
                // We found a newline - complete the line
                const line_fragment = chunk[offset..pos];
                
                // Combine with any partial line from previous chunk
                if (self.partial_line.items.len > 0) {
                    try self.partial_line.appendSlice(self.allocator, line_fragment);
                    try self.process_line(self.partial_line.items, messages);
                    self.partial_line.clearRetainingCapacity();
                } else {
                    try self.process_line(line_fragment, messages);
                }
                
                offset = pos + 1;
            } else {
                // No newline found - save partial line for next chunk
                try self.partial_line.appendSlice(self.allocator, chunk[offset..]);
                break;
            }
        }
    }
    
    /// Process a complete line according to SSE specification
    fn process_line(self: *SSEParser, line: []const u8, messages: *std.ArrayList(SSEMessage)) !void {
        // Remove \r if present (for \r\n line endings)
        const trimmed = if (line.len > 0 and line[line.len - 1] == '\r')
            line[0..line.len - 1]
        else
            line;
        
        // Empty line dispatches the message
        if (trimmed.len == 0) {
            if (try self.current_message.build(self.allocator)) |msg| {
                // Update last event ID if present
                if (msg.id) |id| {
                    if (self.last_event_id) |old_id| {
                        self.allocator.free(old_id);
                    }
                    self.last_event_id = try self.allocator.dupe(u8, id);
                }
                try messages.append(self.allocator, msg);
            }
            self.current_message.reset(self.allocator);
            return;
        }
        
        // Lines starting with ':' are comments
        if (trimmed[0] == ':') {
            return;
        }
        
        // Find the field separator
        const colon_pos = std.mem.indexOfScalar(u8, trimmed, ':');
        
        if (colon_pos) |pos| {
            const field = trimmed[0..pos];
            var value = trimmed[pos + 1..];
            
            // Remove leading space from value if present
            if (value.len > 0 and value[0] == ' ') {
                value = value[1..];
            }
            
            try self.process_field(field, value);
        } else {
            // No colon - treat entire line as field with empty value
            try self.process_field(trimmed, "");
        }
    }
    
    /// Process a field according to SSE specification
    fn process_field(self: *SSEParser, field: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, field, "id")) {
            if (self.current_message.id) |old_id| {
                self.allocator.free(old_id);
            }
            self.current_message.id = try self.allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, field, "event")) {
            if (self.current_message.event) |old_event| {
                self.allocator.free(old_event);
            }
            self.current_message.event = try self.allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, field, "data")) {
            // Append to data field (handles multiline data)
            if (self.current_message.has_data) {
                try self.current_message.data.append(self.allocator, '\n');
            }
            try self.current_message.data.appendSlice(self.allocator, value);
            self.current_message.has_data = true;
        } else if (std.mem.eql(u8, field, "retry")) {
            // Parse retry interval (must be valid integer)
            self.current_message.retry = std.fmt.parseInt(u64, value, 10) catch null;
        }
        // Unknown fields are ignored per specification
    }
    
    /// Reset parser state (useful for reconnection)
    pub fn reset(self: *SSEParser) void {
        self.partial_line.clearRetainingCapacity();
        self.current_message.reset();
    }
    
    /// Get the last event ID for reconnection
    pub fn get_last_event_id(self: *const SSEParser) ?[]const u8 {
        return self.last_event_id;
    }
};

// Tests
test "SSEParser parses complete message" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    const chunk = "id: 123\nevent: test\ndata: Hello World\n\n";
    try parser.parse_chunk(chunk, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    const msg = messages.items[0];
    try std.testing.expectEqualStrings("123", msg.id.?);
    try std.testing.expectEqualStrings("test", msg.event.?);
    try std.testing.expectEqualStrings("Hello World", msg.data.?);
}

test "SSEParser handles multiline data" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    const chunk = "data: Line 1\ndata: Line 2\ndata: Line 3\n\n";
    try parser.parse_chunk(chunk, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    const msg = messages.items[0];
    try std.testing.expectEqualStrings("Line 1\nLine 2\nLine 3", msg.data.?);
}

test "SSEParser handles partial messages across chunks" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    // First chunk ends mid-line
    const chunk1 = "id: 456\ndata: Partial ";
    try parser.parse_chunk(chunk1, &messages);
    try std.testing.expect(messages.items.len == 0);
    
    // Second chunk completes the message
    const chunk2 = "Message\n\n";
    try parser.parse_chunk(chunk2, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    const msg = messages.items[0];
    try std.testing.expectEqualStrings("456", msg.id.?);
    try std.testing.expectEqualStrings("Partial Message", msg.data.?);
}

test "SSEParser ignores comments" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    const chunk = ": This is a comment\ndata: Actual data\n: Another comment\n\n";
    try parser.parse_chunk(chunk, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    const msg = messages.items[0];
    try std.testing.expectEqualStrings("Actual data", msg.data.?);
}

test "SSEParser handles retry field" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    const chunk = "retry: 5000\ndata: Reconnect message\n\n";
    try parser.parse_chunk(chunk, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    const msg = messages.items[0];
    try std.testing.expect(msg.retry.? == 5000);
    try std.testing.expectEqualStrings("Reconnect message", msg.data.?);
}

test "SSEParser handles CRLF line endings" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    const chunk = "data: Windows line\r\ndata: endings\r\n\r\n";
    try parser.parse_chunk(chunk, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    const msg = messages.items[0];
    try std.testing.expectEqualStrings("Windows line\nendings", msg.data.?);
}

test "SSEParser tracks last event ID" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    const chunk1 = "id: first\ndata: Message 1\n\n";
    try parser.parse_chunk(chunk1, &messages);
    try std.testing.expectEqualStrings("first", parser.get_last_event_id().?);
    
    const chunk2 = "id: second\ndata: Message 2\n\n";
    try parser.parse_chunk(chunk2, &messages);
    try std.testing.expectEqualStrings("second", parser.get_last_event_id().?);
}