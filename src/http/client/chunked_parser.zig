const std = @import("std");

/// HTTP/1.1 Chunked Transfer Encoding parser
/// Handles incremental parsing of chunked data according to RFC 7230
pub const ChunkedParser = struct {
    allocator: std.mem.Allocator,
    state: State,
    /// Buffer for incomplete chunk size line
    size_buffer: std.ArrayList(u8),
    /// Expected size of current chunk
    expected_size: usize = 0,
    /// Bytes received for current chunk
    received_size: usize = 0,
    /// Whether we've reached the final chunk
    complete: bool = false,

    const State = enum {
        /// Waiting for chunk size line
        waiting_size,
        /// Reading chunk data
        reading_data,
        /// Reading \r\n after chunk data
        reading_data_trailer,
        /// Reading final chunk trailers (headers after last chunk)
        reading_trailers,
        /// All chunks have been received
        complete,
    };

    pub fn init(allocator: std.mem.Allocator) !ChunkedParser {
        return .{
            .allocator = allocator,
            .state = .waiting_size,
            .size_buffer = try std.ArrayList(u8).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *ChunkedParser) void {
        self.size_buffer.deinit(self.allocator);
    }

    /// Parse a chunk of data, returning the actual data without chunk metadata
    /// The output buffer will contain the decoded data
    /// Returns the number of bytes written to output
    pub fn parse(self: *ChunkedParser, input: []const u8, output: *std.ArrayList(u8)) !usize {
        var input_offset: usize = 0;
        var bytes_written: usize = 0;

        while (input_offset < input.len and self.state != .complete) {
            switch (self.state) {
                .waiting_size => {
                    // Look for end of chunk size line (\r\n)
                    const newline_pos = std.mem.indexOfScalarPos(u8, input, input_offset, '\n');
                    
                    if (newline_pos) |pos| {
                        // Found newline, complete the size line
                        const line_fragment = input[input_offset..pos];
                        
                        // Combine with any buffered data
                        if (self.size_buffer.items.len > 0) {
                            try self.size_buffer.appendSlice(self.allocator, line_fragment);
                            try self.parse_size_line(self.size_buffer.items);
                            self.size_buffer.clearRetainingCapacity();
                        } else {
                            try self.parse_size_line(line_fragment);
                        }
                        
                        input_offset = pos + 1;
                        
                        // Check if this was the final chunk
                        if (self.expected_size == 0) {
                            self.state = .reading_trailers;
                        } else {
                            self.state = .reading_data;
                            self.received_size = 0;
                        }
                    } else {
                        // No newline found, buffer the partial line
                        try self.size_buffer.appendSlice(self.allocator, input[input_offset..]);
                        break;
                    }
                },
                
                .reading_data => {
                    // Read chunk data up to expected_size
                    const remaining = self.expected_size - self.received_size;
                    const available = input.len - input_offset;
                    const to_read = @min(remaining, available);
                    
                    // Copy data to output
                    try output.appendSlice(self.allocator, input[input_offset..input_offset + to_read]);
                    bytes_written += to_read;
                    
                    self.received_size += to_read;
                    input_offset += to_read;
                    
                    // Check if chunk is complete
                    if (self.received_size >= self.expected_size) {
                        self.state = .reading_data_trailer;
                    }
                },
                
                .reading_data_trailer => {
                    // Skip the \r\n after chunk data
                    const remaining = input.len - input_offset;
                    if (remaining >= 2) {
                        // We have both \r and \n
                        if (input[input_offset] == '\r' and input[input_offset + 1] == '\n') {
                            input_offset += 2;
                            self.state = .waiting_size;
                        } else {
                            // Malformed chunk trailer
                            return error.MalformedChunk;
                        }
                    } else if (remaining == 1) {
                        // Only have \r, need to wait for \n
                        if (input[input_offset] == '\r') {
                            input_offset += 1;
                            // Stay in this state to get the \n
                        } else {
                            return error.MalformedChunk;
                        }
                        break;
                    } else {
                        // No data available, stay in this state
                        break;
                    }
                },
                
                .reading_trailers => {
                    // Read until we find \r\n\r\n (end of trailers)
                    // For now, we'll just look for a blank line
                    const newline_pos = std.mem.indexOfScalarPos(u8, input, input_offset, '\n');
                    
                    if (newline_pos) |pos| {
                        const line = input[input_offset..pos];
                        
                        // Check if this is an empty line (just \r or empty)
                        if (line.len == 0 or (line.len == 1 and line[0] == '\r')) {
                            // End of chunked encoding
                            self.state = .complete;
                            self.complete = true;
                            input_offset = pos + 1;
                        } else {
                            // Skip this trailer line
                            input_offset = pos + 1;
                        }
                    } else {
                        // Need more data
                        break;
                    }
                },
                
                .complete => break,
            }
        }
        
        return bytes_written;
    }

    /// Parse a chunk size line (e.g., "1a4" or "0")
    fn parse_size_line(self: *ChunkedParser, line: []const u8) !void {
        // Remove \r if present
        const trimmed = if (line.len > 0 and line[line.len - 1] == '\r')
            line[0..line.len - 1]
        else
            line;
        
        // Chunk size can have extensions after ';' which we ignore
        const size_end = std.mem.indexOfScalar(u8, trimmed, ';') orelse trimmed.len;
        const size_str = trimmed[0..size_end];
        
        // Parse hexadecimal chunk size
        self.expected_size = std.fmt.parseInt(usize, size_str, 16) catch {
            return error.InvalidChunkSize;
        };
    }

    /// Check if all chunks have been received
    pub fn is_complete(self: *const ChunkedParser) bool {
        return self.complete;
    }

    /// Reset parser state for reuse
    pub fn reset(self: *ChunkedParser) void {
        self.state = .waiting_size;
        self.size_buffer.clearRetainingCapacity();
        self.expected_size = 0;
        self.received_size = 0;
        self.complete = false;
    }
};

// Tests
test "ChunkedParser parses simple chunk" {
    const allocator = std.testing.allocator;
    
    var parser = try ChunkedParser.init(allocator);
    defer parser.deinit();
    
    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);
    
    // Simple chunk: "5\r\nHello\r\n0\r\n\r\n"
    const input = "5\r\nHello\r\n0\r\n\r\n";
    _ = try parser.parse(input, &output);
    
    try std.testing.expectEqualStrings("Hello", output.items);
    try std.testing.expect(parser.is_complete());
}

test "ChunkedParser handles multiple chunks" {
    const allocator = std.testing.allocator;
    
    var parser = try ChunkedParser.init(allocator);
    defer parser.deinit();
    
    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);
    
    // Multiple chunks
    const input = "5\r\nHello\r\n6\r\n World\r\n0\r\n\r\n";
    _ = try parser.parse(input, &output);
    
    try std.testing.expectEqualStrings("Hello World", output.items);
    try std.testing.expect(parser.is_complete());
}

test "ChunkedParser handles partial chunks" {
    const allocator = std.testing.allocator;
    
    var parser = try ChunkedParser.init(allocator);
    defer parser.deinit();
    
    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);
    
    // First part: chunk size and partial data
    _ = try parser.parse("5\r\nHel", &output);
    try std.testing.expectEqualStrings("Hel", output.items);
    try std.testing.expect(!parser.is_complete());
    
    // Second part: rest of data and final chunk
    _ = try parser.parse("lo\r\n0\r\n\r\n", &output);
    try std.testing.expectEqualStrings("Hello", output.items);
    try std.testing.expect(parser.is_complete());
}

test "ChunkedParser handles chunk extensions" {
    const allocator = std.testing.allocator;
    
    var parser = try ChunkedParser.init(allocator);
    defer parser.deinit();
    
    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);
    
    // Chunk with extension (should be ignored)
    const input = "5;name=value\r\nHello\r\n0\r\n\r\n";
    _ = try parser.parse(input, &output);
    
    try std.testing.expectEqualStrings("Hello", output.items);
    try std.testing.expect(parser.is_complete());
}

test "ChunkedParser handles hex chunk sizes" {
    const allocator = std.testing.allocator;
    
    var parser = try ChunkedParser.init(allocator);
    defer parser.deinit();
    
    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer output.deinit(allocator);
    
    // Hex chunk size (0x10 = 16 bytes)
    const input = "10\r\n0123456789ABCDEF\r\n0\r\n\r\n";
    _ = try parser.parse(input, &output);
    
    try std.testing.expectEqualStrings("0123456789ABCDEF", output.items);
    try std.testing.expect(parser.is_complete());
}