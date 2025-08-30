const std = @import("std");

const Status = @import("../lib.zig").Status;
const AnyCaseStringMap = @import("../../core/any_case_string_map.zig").AnyCaseStringMap;
const CookieMap = @import("../common/cookie.zig").CookieMap;

pub const ClientResponse = struct {
    allocator: std.mem.Allocator,
    status: Status,
    headers: AnyCaseStringMap,
    cookies: CookieMap,
    body: ?[]const u8 = null,
    version: std.http.Version = .@"HTTP/1.1",
    owns_body: bool = false,

    pub fn init(allocator: std.mem.Allocator) ClientResponse {
        return .{
            .allocator = allocator,
            .status = .OK,
            .headers = AnyCaseStringMap.init(allocator),
            .cookies = CookieMap.init(allocator),
            .body = null,
            .version = .@"HTTP/1.1",
            .owns_body = false,
        };
    }

    pub fn deinit(self: *ClientResponse) void {
        // Free all allocated header strings
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        self.cookies.deinit();
        if (self.owns_body) {
            if (self.body) |body| {
                self.allocator.free(body);
            }
        }
    }


    // Parsing
    pub fn parse_headers(self: *ClientResponse, bytes: []const u8) !usize {
        var offset: usize = 0;
        
        // Parse status line: "HTTP/1.1 200 OK\r\n"
        const status_line_end = std.mem.indexOf(u8, bytes, "\r\n") orelse return error.MalformedResponse;
        const status_line = bytes[0..status_line_end];
        
        // Parse HTTP version
        const version_end = std.mem.indexOf(u8, status_line, " ") orelse return error.MalformedResponse;
        const version_str = status_line[0..version_end];
        
        if (std.mem.eql(u8, version_str, "HTTP/1.0")) {
            self.version = .@"HTTP/1.0";
        } else if (std.mem.eql(u8, version_str, "HTTP/1.1")) {
            self.version = .@"HTTP/1.1";
        } else if (std.mem.eql(u8, version_str, "HTTP/2") or std.mem.eql(u8, version_str, "HTTP/2.0")) {
            // HTTP/2 not supported in std.http.Version, treat as HTTP/1.1
            self.version = .@"HTTP/1.1";
        } else if (std.mem.eql(u8, version_str, "HTTP/3") or std.mem.eql(u8, version_str, "HTTP/3.0")) {
            // HTTP/3 not supported in std.http.Version, treat as HTTP/1.1
            self.version = .@"HTTP/1.1";
        } else {
            return error.HTTPVersionNotSupported;
        }
        
        // Parse status code
        const status_start = version_end + 1;
        const status_code_end = std.mem.indexOfPos(u8, status_line, status_start, " ") orelse status_line.len;
        const status_code_str = status_line[status_start..status_code_end];
        const status_code = try std.fmt.parseInt(u16, status_code_str, 10);
        
        // Set status from numeric code
        self.status = @enumFromInt(status_code);
        
        offset = status_line_end + 2; // Skip "\r\n"
        
        // Parse headers
        while (offset < bytes.len) {
            // Check for end of headers (empty line)
            if (offset + 1 < bytes.len and bytes[offset] == '\r' and bytes[offset + 1] == '\n') {
                offset += 2;
                break;
            }
            
            // Find end of header line
            const header_end = std.mem.indexOfPos(u8, bytes, offset, "\r\n") orelse return error.MalformedResponse;
            const header_line = bytes[offset..header_end];
            
            // Parse header key:value
            const colon_pos = std.mem.indexOf(u8, header_line, ":") orelse return error.MalformedResponse;
            const key = std.mem.trim(u8, header_line[0..colon_pos], " \t");
            const value = std.mem.trim(u8, header_line[colon_pos + 1..], " \t");
            
            // Store header (allocate copies)
            const key_copy = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(key_copy);
            const value_copy = try self.allocator.dupe(u8, value);
            errdefer self.allocator.free(value_copy);
            
            try self.headers.put(key_copy, value_copy);
            
            offset = header_end + 2; // Skip "\r\n"
        }
        
        return offset;
    }

    pub fn parse_body(self: *ClientResponse, bytes: []const u8) !void {
        // If we already have a body and own it, free it
        if (self.owns_body) {
            if (self.body) |body| {
                self.allocator.free(body);
            }
        }
        
        // Allocate and copy the body
        const body_copy = try self.allocator.dupe(u8, bytes);
        self.body = body_copy;
        self.owns_body = true;
    }

    pub fn parse_chunked_body(self: *ClientResponse, reader: anytype) !void {
        var chunks = try std.ArrayList(u8).initCapacity(self.allocator, 4096);
        defer chunks.deinit(self.allocator);
        
        while (true) {
            // Read chunk size line
            var chunk_size_buf: [32]u8 = undefined;
            const chunk_size_line = try reader.readUntilDelimiter(&chunk_size_buf, '\n');
            
            // Remove potential \r
            const size_str = if (chunk_size_line.len > 0 and chunk_size_line[chunk_size_line.len - 1] == '\r')
                chunk_size_line[0..chunk_size_line.len - 1]
            else
                chunk_size_line;
            
            // Parse chunk size (may have chunk extensions after semicolon)
            const size_end = std.mem.indexOf(u8, size_str, ";") orelse size_str.len;
            const chunk_size = try std.fmt.parseInt(usize, size_str[0..size_end], 16);
            
            // If chunk size is 0, we're done
            if (chunk_size == 0) {
                // Read trailing \r\n
                _ = try reader.readByte(); // \r
                _ = try reader.readByte(); // \n
                break;
            }
            
            // Read chunk data
            const old_len = chunks.items.len;
            try chunks.resize(self.allocator, old_len + chunk_size);
            _ = try reader.readAll(chunks.items[old_len..]);
            
            // Read trailing \r\n after chunk data
            _ = try reader.readByte(); // \r
            _ = try reader.readByte(); // \n
        }
        
        // Store the complete body
        if (self.owns_body) {
            if (self.body) |body| {
                self.allocator.free(body);
            }
        }
        
        self.body = try chunks.toOwnedSlice(self.allocator);
        self.owns_body = true;
    }

    // Convenience methods
    pub fn get_header(self: *const ClientResponse, key: []const u8) ?[]const u8 {
        return self.headers.get(key);
    }

    pub fn get_content_length(self: *const ClientResponse) ?usize {
        const content_length_str = self.get_header("Content-Length") orelse return null;
        return std.fmt.parseInt(usize, content_length_str, 10) catch null;
    }

    pub fn is_chunked(self: *const ClientResponse) bool {
        const transfer_encoding = self.get_header("Transfer-Encoding") orelse return false;
        // Check if "chunked" appears in the transfer encoding
        // It should be the last encoding if multiple are specified
        return std.mem.indexOf(u8, transfer_encoding, "chunked") != null;
    }

    pub fn is_success(self: *const ClientResponse) bool {
        const status_code = @intFromEnum(self.status);
        return status_code >= 200 and status_code < 300;
    }

    pub fn is_redirect(self: *const ClientResponse) bool {
        const status_code = @intFromEnum(self.status);
        return status_code >= 300 and status_code < 400;
    }

    pub fn get_location(self: *const ClientResponse) ?[]const u8 {
        return self.get_header("Location");
    }

    // Body handling
    pub fn json(self: *const ClientResponse, comptime T: type) !T {
        const body = self.body orelse return error.NoBody;
        const parsed = try std.json.parseFromSlice(T, self.allocator, body, .{});
        defer parsed.deinit();
        // Return a copy of the parsed value
        return parsed.value;
    }

    pub fn text(self: *const ClientResponse) []const u8 {
        return self.body orelse "";
    }
};

test "ClientResponse init and deinit" {
    const allocator = std.testing.allocator;
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    try std.testing.expect(resp.status == .OK);
    try std.testing.expect(resp.body == null);
    try std.testing.expect(resp.version == .@"HTTP/1.1");
}

test "parse HTTP response headers" {
    const allocator = std.testing.allocator;
    
    const response_text = 
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 13\r\n" ++
        "\r\n" ++
        "{\"ok\": true}";
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    const header_size = try resp.parse_headers(response_text);
    
    try std.testing.expect(resp.status == .OK);
    try std.testing.expect(resp.version == .@"HTTP/1.1");
    try std.testing.expect(resp.is_success());
    
    try std.testing.expectEqualStrings("application/json", resp.get_header("Content-Type").?);
    try std.testing.expect(resp.get_content_length().? == 13);
    
    // Parse body
    try resp.parse_body(response_text[header_size..]);
    try std.testing.expectEqualStrings("{\"ok\": true}", resp.body.?);
}

test "parse redirect response" {
    const allocator = std.testing.allocator;
    
    const response_text = 
        "HTTP/1.1 301 Moved Permanently\r\n" ++
        "Location: https://example.com/new\r\n" ++
        "\r\n";
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    _ = try resp.parse_headers(response_text);
    
    try std.testing.expect(resp.status == .@"Moved Permanently");
    try std.testing.expect(resp.is_redirect());
    try std.testing.expectEqualStrings("https://example.com/new", resp.get_location().?);
}

test "parse response with multiple headers" {
    const allocator = std.testing.allocator;
    
    const response_text = 
        "HTTP/1.1 404 Not Found\r\n" ++
        "Server: nginx/1.18.0\r\n" ++
        "Date: Wed, 29 Aug 2025 12:00:00 GMT\r\n" ++
        "Content-Type: text/html; charset=UTF-8\r\n" ++
        "Content-Length: 169\r\n" ++
        "Connection: keep-alive\r\n" ++
        "\r\n";
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    _ = try resp.parse_headers(response_text);
    
    try std.testing.expect(resp.status == .@"Not Found");
    try std.testing.expect(!resp.is_success());
    try std.testing.expect(!resp.is_redirect());
    
    try std.testing.expectEqualStrings("nginx/1.18.0", resp.get_header("Server").?);
    try std.testing.expectEqualStrings("text/html; charset=UTF-8", resp.get_header("Content-Type").?);
    try std.testing.expectEqualStrings("keep-alive", resp.get_header("Connection").?);
    try std.testing.expect(resp.get_content_length().? == 169);
}

test "parse chunked response indicator" {
    const allocator = std.testing.allocator;
    
    const response_text = 
        "HTTP/1.1 200 OK\r\n" ++
        "Transfer-Encoding: chunked\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "\r\n";
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    _ = try resp.parse_headers(response_text);
    
    try std.testing.expect(resp.is_chunked());
    try std.testing.expect(resp.get_content_length() == null); // No Content-Length with chunked
}

test "parse HTTP/2 response" {
    const allocator = std.testing.allocator;
    
    const response_text = 
        "HTTP/2 200 OK\r\n" ++
        "content-type: application/json\r\n" ++
        "\r\n";
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    _ = try resp.parse_headers(response_text);
    
    // HTTP/2 is treated as HTTP/1.1 for compatibility
    try std.testing.expect(resp.version == .@"HTTP/1.1");
    try std.testing.expect(resp.status == .OK);
    try std.testing.expectEqualStrings("application/json", resp.get_header("content-type").?);
}


test "parse chunked body" {
    const allocator = std.testing.allocator;
    
    const chunked_data = 
        "5\r\n" ++
        "Hello\r\n" ++
        "7\r\n" ++
        " World!\r\n" ++
        "0\r\n" ++
        "\r\n";
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    var stream = std.io.fixedBufferStream(chunked_data);
    try resp.parse_chunked_body(stream.reader());
    
    try std.testing.expectEqualStrings("Hello World!", resp.body.?);
}

test "text and json body handling" {
    const allocator = std.testing.allocator;
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    // Test empty text
    try std.testing.expectEqualStrings("", resp.text());
    
    // Set JSON body
    const json_body = "{\"name\":\"test\",\"value\":42}";
    try resp.parse_body(json_body);
    
    // Test text retrieval
    try std.testing.expectEqualStrings(json_body, resp.text());
    
    // Test JSON parsing
    const TestStruct = struct {
        name: []const u8,
        value: u32,
    };
    
    const parsed = try resp.json(TestStruct);
    try std.testing.expectEqualStrings("test", parsed.name);
    try std.testing.expect(parsed.value == 42);
}