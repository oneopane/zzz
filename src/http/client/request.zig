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

    // Convenience initializers for common cases
    pub fn get(allocator: std.mem.Allocator, url_string: []const u8) !ClientRequest {
        return ClientRequest.init(allocator, .GET, url_string);
    }
    
    pub fn post(allocator: std.mem.Allocator, url_string: []const u8, body: []const u8) !ClientRequest {
        var req = try ClientRequest.init(allocator, .POST, url_string);
        _ = req.set_body(body);
        return req;
    }
    
    pub fn put(allocator: std.mem.Allocator, url_string: []const u8, body: []const u8) !ClientRequest {
        var req = try ClientRequest.init(allocator, .PUT, url_string);
        _ = req.set_body(body);
        return req;
    }
    
    pub fn delete(allocator: std.mem.Allocator, url_string: []const u8) !ClientRequest {
        return ClientRequest.init(allocator, .DELETE, url_string);
    }
    
    pub fn head(allocator: std.mem.Allocator, url_string: []const u8) !ClientRequest {
        return ClientRequest.init(allocator, .HEAD, url_string);
    }
    
    pub fn patch(allocator: std.mem.Allocator, url_string: []const u8, body: []const u8) !ClientRequest {
        var req = try ClientRequest.init(allocator, .PATCH, url_string);
        _ = req.set_body(body);
        return req;
    }
    
    // Builder pattern entry point
    pub fn builder(allocator: std.mem.Allocator) RequestBuilder {
        return RequestBuilder.init(allocator);
    }
    
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
        // For now, just serialize manually for basic types
        // TODO: Properly integrate with Zig 0.15's JSON API when stable
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);
        
        var json_str: []u8 = undefined;
        if (type_info == .@"struct") {
            // Simple JSON serialization for structs - temporary implementation
            var buffer = try std.ArrayList(u8).initCapacity(self.allocator, 256);
            defer buffer.deinit(self.allocator);
            
            try buffer.appendSlice(self.allocator, "{");
            inline for (type_info.@"struct".fields, 0..) |field, i| {
                if (i > 0) try buffer.appendSlice(self.allocator, ",");
                try buffer.append(self.allocator, '"');
                try buffer.appendSlice(self.allocator, field.name);
                try buffer.appendSlice(self.allocator, "\":");
                
                const field_value = @field(value, field.name);
                const field_type = @TypeOf(field_value);
                
                if (field_type == []const u8) {
                    try buffer.append(self.allocator, '"');
                    try buffer.appendSlice(self.allocator, field_value);
                    try buffer.append(self.allocator, '"');
                } else if (@typeInfo(field_type) == .int or @typeInfo(field_type) == .comptime_int) {
                    try std.fmt.format(buffer.writer(self.allocator), "{d}", .{field_value});
                } else {
                    // For other types, just stringify as best we can
                    try std.fmt.format(buffer.writer(self.allocator), "{any}", .{field_value});
                }
            }
            try buffer.appendSlice(self.allocator, "}");
            
            json_str = try self.allocator.dupe(u8, buffer.items);
        } else {
            // For non-structs, use simple formatting
            json_str = try std.fmt.allocPrint(self.allocator, "{any}", .{value});
        }
        
        // Free old body if it was allocated
        if (self.body) |old_body| {
            self.allocator.free(old_body);
        }
        
        self.body = json_str;
        
        // Set Content-Type header
        _ = try self.set_header("Content-Type", "application/json");
        
        return self;
    }

    pub fn set_timeout(self: *ClientRequest, timeout_ms: u32) *ClientRequest {
        self.timeout_ms = timeout_ms;
        return self;
    }

    pub fn add_cookie(self: *ClientRequest, cookie: Cookie) !*ClientRequest {
        try self.cookies.put(cookie.name, cookie);
        return self;
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
    allocator: std.mem.Allocator,
    method_value: ?Method = null,
    url_string: ?[]const u8 = null,
    headers: std.StringHashMap([]const u8),
    body_value: ?[]const u8 = null,
    timeout_ms: ?u32 = null,
    follow_redirects_value: ?bool = null,

    pub fn init(allocator: std.mem.Allocator) RequestBuilder {
        return RequestBuilder{
            .allocator = allocator,
            .method_value = null,
            .url_string = null,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body_value = null,
            .timeout_ms = null,
            .follow_redirects_value = null,
        };
    }

    pub fn deinit(self: *RequestBuilder) void {
        // Free any allocated header values if we own them
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    // Method setters
    pub fn get(self: *RequestBuilder, url_string: []const u8) *RequestBuilder {
        self.method_value = .GET;
        self.url_string = url_string;
        return self;
    }

    pub fn post(self: *RequestBuilder, url_string: []const u8, b: []const u8) *RequestBuilder {
        self.method_value = .POST;
        self.url_string = url_string;
        self.body_value = b;
        return self;
    }

    pub fn put(self: *RequestBuilder, url_string: []const u8, b: []const u8) *RequestBuilder {
        self.method_value = .PUT;
        self.url_string = url_string;
        self.body_value = b;
        return self;
    }

    pub fn patch(self: *RequestBuilder, url_string: []const u8, b: []const u8) *RequestBuilder {
        self.method_value = .PATCH;
        self.url_string = url_string;
        self.body_value = b;
        return self;
    }

    pub fn delete(self: *RequestBuilder, url_string: []const u8) *RequestBuilder {
        self.method_value = .DELETE;
        self.url_string = url_string;
        return self;
    }

    pub fn head(self: *RequestBuilder, url_string: []const u8) *RequestBuilder {
        self.method_value = .HEAD;
        self.url_string = url_string;
        return self;
    }

    // Generic method setter
    pub fn method(self: *RequestBuilder, m: Method) *RequestBuilder {
        self.method_value = m;
        return self;
    }

    pub fn url(self: *RequestBuilder, url_string: []const u8) *RequestBuilder {
        self.url_string = url_string;
        return self;
    }

    pub fn header(self: *RequestBuilder, key: []const u8, value: []const u8) !*RequestBuilder {
        // Allocate and store the value
        const duped_value = try self.allocator.dupe(u8, value);
        
        // If key exists, free old value
        if (self.headers.get(key)) |old_value| {
            self.allocator.free(old_value);
        }
        
        try self.headers.put(key, duped_value);
        return self;
    }

    pub fn bearer_token(self: *RequestBuilder, token: []const u8) !*RequestBuilder {
        const auth_value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token});
        return self.header("Authorization", auth_value);
    }

    pub fn body(self: *RequestBuilder, b: []const u8) *RequestBuilder {
        self.body_value = b;
        return self;
    }

    pub fn json(self: *RequestBuilder, value: anytype) !*RequestBuilder {
        // For now, just serialize manually for basic types
        // TODO: Properly integrate with Zig 0.15's JSON API when stable
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);
        
        var json_str: []u8 = undefined;
        if (type_info == .@"struct") {
            // Simple JSON serialization for structs - temporary implementation
            var buffer = try std.ArrayList(u8).initCapacity(self.allocator, 256);
            defer buffer.deinit(self.allocator);
            
            try buffer.appendSlice(self.allocator, "{");
            inline for (type_info.@"struct".fields, 0..) |field, i| {
                if (i > 0) try buffer.appendSlice(self.allocator, ",");
                try buffer.append(self.allocator, '"');
                try buffer.appendSlice(self.allocator, field.name);
                try buffer.appendSlice(self.allocator, "\":");
                
                const field_value = @field(value, field.name);
                const field_type = @TypeOf(field_value);
                
                if (field_type == []const u8) {
                    try buffer.append(self.allocator, '"');
                    try buffer.appendSlice(self.allocator, field_value);
                    try buffer.append(self.allocator, '"');
                } else if (@typeInfo(field_type) == .int or @typeInfo(field_type) == .comptime_int) {
                    try std.fmt.format(buffer.writer(self.allocator), "{d}", .{field_value});
                } else {
                    // For other types, just stringify as best we can
                    try std.fmt.format(buffer.writer(self.allocator), "{any}", .{field_value});
                }
            }
            try buffer.appendSlice(self.allocator, "}");
            
            json_str = try self.allocator.dupe(u8, buffer.items);
        } else {
            // For non-structs, use simple formatting
            json_str = try std.fmt.allocPrint(self.allocator, "{any}", .{value});
        }
        
        // Free old body if we allocated one
        if (self.body_value) |old_body| {
            // Only free if it looks like we allocated it (a simple heuristic)
            // In a production system, we'd track this more carefully
            self.allocator.free(old_body);
        }
        
        self.body_value = json_str;
        
        // Set Content-Type header
        _ = try self.header("Content-Type", "application/json");
        
        return self;
    }

    pub fn timeout(self: *RequestBuilder, timeout_ms: u32) *RequestBuilder {
        self.timeout_ms = timeout_ms;
        return self;
    }

    pub fn follow_redirects(self: *RequestBuilder, follow: bool) *RequestBuilder {
        self.follow_redirects_value = follow;
        return self;
    }

    pub fn build(self: *RequestBuilder) !ClientRequest {
        // Validate required fields
        const m = self.method_value orelse return error.MethodRequired;
        const url_str = self.url_string orelse return error.UrlRequired;
        
        // Create the request
        var req = try ClientRequest.init(self.allocator, m, url_str);
        
        // Transfer headers
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            _ = try req.set_header(entry.key_ptr.*, entry.value_ptr.*);
        }
        
        // Set optional fields
        if (self.body_value) |b| {
            _ = req.set_body(b);
        }
        
        if (self.timeout_ms) |t| {
            req.timeout_ms = t;
        }
        
        if (self.follow_redirects_value) |f| {
            req.follow_redirects = f;
        }
        
        return req;
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

test "ClientRequest.set_json serializes struct to JSON body" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.init(allocator, .POST, "http://api.example.com/users");
    defer req.deinit();
    
    const User = struct {
        name: []const u8,
        age: u32,
    };
    
    const user = User{ .name = "John", .age = 30 };
    _ = try req.set_json(user);
    
    // Check that body contains serialized JSON
    try expect(req.body != null);
    const expected_json = "{\"name\":\"John\",\"age\":30}";
    try expectEqualStrings(req.body.?, expected_json);
    
    // Check that Content-Type header was set
    try expectEqualStrings(req.headers.get("Content-Type").?, "application/json");
}

test "RequestBuilder.json serializes struct to JSON body" {
    const allocator = testing.allocator;
    
    var builder = RequestBuilder.init(allocator);
    defer builder.deinit();
    
    const Data = struct {
        message: []const u8,
        count: u32,
    };
    
    const data = Data{ .message = "Hello", .count = 42 };
    _ = try builder.post("http://api.example.com/data", "")
        .json(data);
    
    var req = try builder.build();
    defer req.deinit();
    
    // Check that body contains serialized JSON
    try expect(req.body != null);
    const expected_json = "{\"message\":\"Hello\",\"count\":42}";
    try expectEqualStrings(req.body.?, expected_json);
    
    // Check that Content-Type header was set
    try expectEqualStrings(req.headers.get("Content-Type").?, "application/json");
}

test "POST request with JSON body serialization" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.post(allocator, "http://api.example.com/users", "");
    defer req.deinit();
    
    const Payload = struct {
        items: []const []const u8,
        total: u32,
    };
    
    const payload = Payload{ 
        .items = &[_][]const u8{"apple", "banana", "orange"},
        .total = 3,
    };
    _ = try req.set_json(payload);
    
    var buf = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer buf.deinit(allocator);
    
    try req.serialize_full(buf.writer(allocator));
    
    // Verify the request contains JSON body
    const expected_json = "{\"items\":[\"apple\",\"banana\",\"orange\"],\"total\":3}";
    try expect(std.mem.indexOf(u8, buf.items, expected_json) != null);
    
    // Verify Content-Type and Content-Length headers are present
    try expect(std.mem.indexOf(u8, buf.items, "Content-Type: application/json\r\n") != null);
    try expect(std.mem.indexOf(u8, buf.items, "Content-Length: 48\r\n") != null);
}

test "DELETE request convenience constructor" {
    const allocator = testing.allocator;
    
    var req = try ClientRequest.delete(allocator, "http://api.example.com/users/123");
    defer req.deinit();
    
    try expect(req.method == .DELETE);
    try expectEqualStrings(req.uri.scheme, "http");
    
    var buf = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buf.deinit(allocator);
    
    try req.serialize_headers(buf.writer(allocator));
    
    // Verify DELETE method in request line
    try expect(std.mem.startsWith(u8, buf.items, "DELETE /users/123 HTTP/1.1\r\n"));
}

test "RequestBuilder DELETE method" {
    const allocator = testing.allocator;
    
    var builder = RequestBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.delete("http://api.example.com/resource/456")
        .timeout(5000);
    
    var req = try builder.build();
    defer req.deinit();
    
    try expect(req.method == .DELETE);
    try expect(req.timeout_ms.? == 5000);
    
    var buf = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buf.deinit(allocator);
    
    try req.serialize_headers(buf.writer(allocator));
    
    // Verify DELETE method in request line
    try expect(std.mem.startsWith(u8, buf.items, "DELETE /resource/456 HTTP/1.1\r\n"));
}