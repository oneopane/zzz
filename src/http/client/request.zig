const std = @import("std");

const Method = @import("../lib.zig").Method;
const Uri = std.Uri;
const url = @import("url.zig").url;
const AnyCaseStringMap = @import("../../core/any_case_string_map.zig").AnyCaseStringMap;
const CookieMap = @import("../common/cookie.zig").CookieMap;
const Cookie = @import("../common/cookie.zig").Cookie;

pub const ClientRequest = struct {
    allocator: std.mem.Allocator,
    method: Method,
    uri: Uri,
    headers: AnyCaseStringMap,
    cookies: CookieMap,
    body: ?[]const u8 = null,
    timeout_ms: ?u32 = null,
    follow_redirects: ?bool = null,

    pub fn init(allocator: std.mem.Allocator, method: Method, url_string: []const u8) !ClientRequest {
        const parsed_uri = try Uri.parse(url_string);
        
        var headers = AnyCaseStringMap.init(allocator);
        errdefer headers.deinit();
        
        // Set Host header from URI
        var host_buf: [Uri.host_name_max + 6]u8 = undefined; // +6 for :port
        const host_value = blk: {
            var stream = std.io.fixedBufferStream(&host_buf);
            const writer = stream.writer();
            
            var tmp: [Uri.host_name_max]u8 = undefined;
            const h = try parsed_uri.getHost(&tmp);
            try writer.writeAll(h);
            
            // Add port if non-standard
            if (parsed_uri.port) |p| {
                const is_standard = (std.ascii.eqlIgnoreCase(parsed_uri.scheme, "http") and p == 80) or
                                   (std.ascii.eqlIgnoreCase(parsed_uri.scheme, "https") and p == 443);
                if (!is_standard) {
                    try writer.print(":{d}", .{p});
                }
            }
            
            break :blk stream.getWritten();
        };
        
        try headers.put("Host", try allocator.dupe(u8, host_value));
        
        return ClientRequest{
            .allocator = allocator,
            .method = method,
            .uri = parsed_uri,
            .headers = headers,
            .cookies = CookieMap.init(allocator),
            .body = null,
            .timeout_ms = null,
            .follow_redirects = null,
        };
    }

    pub fn deinit(self: *ClientRequest) void {
        // Free all header values
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        
        // Free cookies
        self.cookies.deinit();
        
        // Free body if allocated
        if (self.body) |body| {
            self.allocator.free(body);
        }
    }

    // Builder methods
    pub fn set_header(self: *ClientRequest, key: []const u8, value: []const u8) !*ClientRequest {
        const duped_value = try self.allocator.dupe(u8, value);
        
        // If key exists, free old value before replacing
        if (self.headers.get(key)) |old_value| {
            self.allocator.free(old_value);
        }
        
        try self.headers.put(key, duped_value);
        return self;
    }

    pub fn set_body(self: *ClientRequest, body: []const u8) *ClientRequest {
        // Don't allocate, just reference the provided slice
        // Caller is responsible for keeping it alive
        self.body = body;
        return self;
    }

    pub fn set_json(self: *ClientRequest, value: anytype) !*ClientRequest {
        _ = self;
        _ = value;
        @panic("Not implemented");
    }

    pub fn set_timeout(self: *ClientRequest, timeout_ms: u32) *ClientRequest {
        _ = self;
        _ = timeout_ms;
        @panic("Not implemented");
    }

    pub fn add_cookie(self: *ClientRequest, cookie: Cookie) !*ClientRequest {
        _ = self;
        _ = cookie;
        @panic("Not implemented");
    }

    // Serialization
    pub fn serialize_headers(self: *const ClientRequest, writer: anytype) !void {
        // Write request line: METHOD /path?query HTTP/1.1\r\n
        try writer.writeAll(@tagName(self.method));
        try writer.writeByte(' ');
        
        // Use url.writeRequestTarget for proper path generation
        try url.writeRequestTarget(self.uri, writer, .origin);
        
        try writer.writeAll(" HTTP/1.1\r\n");
        
        // Write headers
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeAll(": ");
            try writer.writeAll(entry.value_ptr.*);
            try writer.writeAll("\r\n");
        }
        
        // Write Content-Length if body exists
        if (self.body) |body| {
            // Only add Content-Length if not already set
            if (!self.headers.contains("Content-Length")) {
                try writer.print("Content-Length: {d}\r\n", .{body.len});
            }
        }
        
        // End headers with empty line
        try writer.writeAll("\r\n");
    }

    pub fn serialize_full(self: *const ClientRequest, writer: anytype) !void {
        // Serialize headers first
        try self.serialize_headers(writer);
        
        // Then write body if present
        if (self.body) |body| {
            try writer.writeAll(body);
        }
    }

    // Internal
    fn build_path_with_query(self: *const ClientRequest) ![]const u8 {
        _ = self;
        @panic("Not implemented");
    }
};

pub const RequestBuilder = struct {
    request: ClientRequest,

    pub fn init(allocator: std.mem.Allocator) RequestBuilder {
        _ = allocator;
        @panic("Not implemented");
    }

    pub fn method(self: *RequestBuilder, m: Method) *RequestBuilder {
        _ = self;
        _ = m;
        @panic("Not implemented");
    }

    pub fn url(self: *RequestBuilder, url_string: []const u8) !*RequestBuilder {
        _ = self;
        _ = url_string;
        @panic("Not implemented");
    }

    pub fn header(self: *RequestBuilder, key: []const u8, value: []const u8) !*RequestBuilder {
        _ = self;
        _ = key;
        _ = value;
        @panic("Not implemented");
    }

    pub fn body(self: *RequestBuilder, b: []const u8) *RequestBuilder {
        _ = self;
        _ = b;
        @panic("Not implemented");
    }

    pub fn json(self: *RequestBuilder, value: anytype) !*RequestBuilder {
        _ = self;
        _ = value;
        @panic("Not implemented");
    }

    pub fn build(self: *RequestBuilder) ClientRequest {
        _ = self;
        @panic("Not implemented");
    }
};

// Tests
const testing = std.testing;
const expect = testing.expect;
const expectEqualStrings = testing.expectEqualStrings;

test "ClientRequest.init creates request with parsed URI and Host header" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.init(allocator, .GET, "http://example.com:8080/api/users?page=1");
    defer req.deinit();
    
    try expect(req.method == .GET);
    try expectEqualStrings(req.uri.scheme, "http");
    try expect(req.uri.port.? == 8080);
    
    // Check Host header was set correctly (with non-standard port)
    const host = req.headers.get("Host").?;
    try expectEqualStrings(host, "example.com:8080");
}

test "ClientRequest.init sets Host header without port for standard ports" {
    const allocator = testing.allocator;
    
    // Test HTTP on port 80
    var req1 = try ClientRequest.init(allocator, .GET, "http://example.com/path");
    defer req1.deinit();
    try expectEqualStrings(req1.headers.get("Host").?, "example.com");
    
    // Test HTTPS on port 443
    var req2 = try ClientRequest.init(allocator, .GET, "https://secure.example.com:443/path");
    defer req2.deinit();
    try expectEqualStrings(req2.headers.get("Host").?, "secure.example.com");
}

test "ClientRequest.set_header adds and updates headers" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.init(allocator, .POST, "http://api.example.com/users");
    defer req.deinit();
    
    // Add headers
    _ = try req.set_header("User-Agent", "zzz-client/1.0");
    _ = try req.set_header("Accept", "application/json");
    
    try expectEqualStrings(req.headers.get("User-Agent").?, "zzz-client/1.0");
    try expectEqualStrings(req.headers.get("Accept").?, "application/json");
    
    // Update existing header
    _ = try req.set_header("User-Agent", "zzz-client/2.0");
    try expectEqualStrings(req.headers.get("User-Agent").?, "zzz-client/2.0");
}

test "ClientRequest.set_body sets request body" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.init(allocator, .POST, "http://api.example.com/users");
    defer req.deinit();
    
    const body = "{\"name\":\"John\"}";
    _ = req.set_body(body);
    
    try expect(req.body != null);
    try expectEqualStrings(req.body.?, body);
}

test "serialize GET request without body" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.init(allocator, .GET, "http://example.com/api/users?page=1");
    defer req.deinit();
    
    _ = try req.set_header("User-Agent", "zzz-client/1.0");
    _ = try req.set_header("Accept", "application/json");
    
    var buf = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buf.deinit(allocator);
    
    try req.serialize_headers(buf.writer(allocator));
    
    const expected = 
        "GET /api/users?page=1 HTTP/1.1\r\n" ++
        "Host: example.com\r\n" ++
        "User-Agent: zzz-client/1.0\r\n" ++
        "Accept: application/json\r\n" ++
        "\r\n";
    
    try expectEqualStrings(buf.items, expected);
}

test "serialize POST request with body" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.init(allocator, .POST, "http://api.example.com/users");
    defer req.deinit();
    
    _ = try req.set_header("Content-Type", "application/json");
    const body = "{\"name\":\"John\",\"age\":30}";
    _ = req.set_body(body);
    
    var buf = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buf.deinit(allocator);
    
    try req.serialize_full(buf.writer(allocator));
    
    // Verify headers include Content-Length
    try expect(std.mem.indexOf(u8, buf.items, "Content-Length: 24\r\n") != null);
    
    // Verify body is included
    try expect(std.mem.endsWith(u8, buf.items, body));
}

test "serialize request with various HTTP methods" {
    const allocator = testing.allocator;
    
    const methods = [_]Method{ .PUT, .DELETE, .PATCH, .HEAD, .OPTIONS };
    
    for (methods) |method| {
        var req = try ClientRequest.init(allocator, method, "http://example.com/resource");
        defer req.deinit();
        
        var buf = try std.ArrayList(u8).initCapacity(allocator, 256);
        defer buf.deinit(allocator);
        
        try req.serialize_headers(buf.writer(allocator));
        
        // Verify method is correctly serialized
        const method_str = @tagName(method);
        try expect(std.mem.startsWith(u8, buf.items, method_str));
    }
}

test "serialize request with root path" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.init(allocator, .GET, "http://example.com");
    defer req.deinit();
    
    var buf = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buf.deinit(allocator);
    
    try req.serialize_headers(buf.writer(allocator));
    
    // Should use "/" for empty path
    try expect(std.mem.indexOf(u8, buf.items, "GET / HTTP/1.1") != null);
}

test "serialize request preserves custom Content-Length header" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.init(allocator, .POST, "http://api.example.com/data");
    defer req.deinit();
    
    // Set custom Content-Length
    _ = try req.set_header("Content-Length", "100");
    _ = req.set_body("test");
    
    var buf = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buf.deinit(allocator);
    
    try req.serialize_headers(buf.writer(allocator));
    
    // Should preserve custom Content-Length, not calculate from body
    try expect(std.mem.indexOf(u8, buf.items, "Content-Length: 100\r\n") != null);
    // Should NOT have Content-Length: 4
    try expect(std.mem.indexOf(u8, buf.items, "Content-Length: 4\r\n") == null);
}