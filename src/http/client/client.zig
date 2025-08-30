const std = @import("std");

const Runtime = @import("tardy").Runtime;
const Connection = @import("connection.zig").Connection;
const ClientRequest = @import("request.zig").ClientRequest;
const ClientResponse = @import("response.zig").ClientResponse;
const AnyCaseStringMap = @import("../../core/any_case_string_map.zig").AnyCaseStringMap;

pub const HTTPClient = struct {
    runtime: *Runtime,
    allocator: std.mem.Allocator,
    default_timeout_ms: u32 = 30000,
    default_headers: ?AnyCaseStringMap = null,
    follow_redirects: bool = true,
    max_redirects: u8 = 10,

    pub fn init(allocator: std.mem.Allocator, runtime: *Runtime) !HTTPClient {
        return HTTPClient{
            .allocator = allocator,
            .runtime = runtime,
            .default_timeout_ms = 30000,
            .default_headers = null,
            .follow_redirects = true,
            .max_redirects = 10,
        };
    }

    pub fn deinit(self: *HTTPClient) void {
        if (self.default_headers) |*headers| {
            headers.deinit();
        }
    }

    // High-level methods
    pub fn get_into(self: *HTTPClient, url: []const u8, response: *ClientResponse) !void {
        var req = try ClientRequest.init(self.allocator, .GET, url);
        defer req.deinit();
        
        try self.execute_request(&req, response);
    }

    pub fn post(self: *HTTPClient, url: []const u8, body: []const u8) !ClientResponse {
        _ = self;
        _ = url;
        _ = body;
        @panic("Not implemented");
    }

    pub fn put(self: *HTTPClient, url: []const u8, body: []const u8) !ClientResponse {
        _ = self;
        _ = url;
        _ = body;
        @panic("Not implemented");
    }

    pub fn delete(self: *HTTPClient, url: []const u8) !ClientResponse {
        _ = self;
        _ = url;
        @panic("Not implemented");
    }

    pub fn head_into(self: *HTTPClient, url: []const u8, response: *ClientResponse) !void {
        var req = try ClientRequest.init(self.allocator, .HEAD, url);
        defer req.deinit();
        
        try self.execute_request(&req, response);
    }

    pub fn patch(self: *HTTPClient, url: []const u8, body: []const u8) !ClientResponse {
        _ = self;
        _ = url;
        _ = body;
        @panic("Not implemented");
    }

    // Advanced method
    pub fn request(self: *HTTPClient, req: ClientRequest) !ClientResponse {
        _ = self;
        _ = req;
        @panic("Not implemented");
    }

    // Internal methods
    fn execute_request_no_redirect(self: *HTTPClient, req: *ClientRequest, response: *ClientResponse) !void {
        // Add default headers if they exist
        if (self.default_headers) |headers| {
            var it = headers.iterator();
            while (it.next()) |entry| {
                // Don't override existing headers
                if (!req.headers.contains(entry.key_ptr.*)) {
                    _ = try req.set_header(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }
        
        // Parse the host and port from the URI
        var host_buf: [256]u8 = undefined;
        const host_component = req.uri.host orelse return error.NoHostInURI;
        const host_str = switch (host_component) {
            .raw => |raw| raw,
            .percent_encoded => |encoded| std.Uri.percentDecodeBackwards(&host_buf, encoded),
        };
        
        const default_port: u16 = if (std.ascii.eqlIgnoreCase(req.uri.scheme, "https")) 443 else 80;
        const port = req.uri.port orelse default_port;
        const use_tls = std.ascii.eqlIgnoreCase(req.uri.scheme, "https");
        
        // Create a connection (no pooling in Phase 5)
        var conn = try Connection.init(self.allocator, host_str, port, use_tls);
        defer conn.deinit();
        
        // Connect to the server
        try conn.connect(self.runtime);
        
        // Serialize and send the request
        var request_buf = try std.ArrayList(u8).initCapacity(self.allocator, 4096);
        defer request_buf.deinit(self.allocator);
        
        try req.serialize_full(request_buf.writer(self.allocator));
        try conn.send_all(self.runtime, request_buf.items);
        
        // Receive the response
        // Start with initial buffer for headers
        var response_buf = try std.ArrayList(u8).initCapacity(self.allocator, 8192);
        defer response_buf.deinit(self.allocator);
        
        // Read initial chunk (headers + some body)
        var initial_buf: [8192]u8 = undefined;
        const initial_bytes = try conn.recv_all(self.runtime, &initial_buf);
        
        if (initial_bytes == 0) {
            return error.EmptyResponse;
        }
        
        try response_buf.appendSlice(self.allocator, initial_buf[0..initial_bytes]);
        
        // Parse the response
        const header_size = try response.parse_headers(response_buf.items);
        
        // For HEAD requests, there's no body
        if (req.method != .HEAD) {
            // Check if we need to read more data
            if (response.is_chunked()) {
                // Handle chunked encoding
                var full_body = try std.ArrayList(u8).initCapacity(self.allocator, 8192);
                defer full_body.deinit(self.allocator);
                
                // Add what we already have after headers
                if (header_size < response_buf.items.len) {
                    try full_body.appendSlice(self.allocator, response_buf.items[header_size..]);
                }
                
                // Continue reading until we get all chunks
                while (true) {
                    var chunk_buf: [8192]u8 = undefined;
                    const chunk_bytes = conn.recv_all(self.runtime, &chunk_buf) catch |err| {
                        if (err == error.ConnectionClosed) break;
                        return err;
                    };
                    
                    if (chunk_bytes == 0) break;
                    try full_body.appendSlice(self.allocator, chunk_buf[0..chunk_bytes]);
                    
                    // Check if we've received the final chunk (0\r\n\r\n)
                    if (full_body.items.len >= 5) {
                        const tail = full_body.items[full_body.items.len - 5 ..];
                        if (std.mem.eql(u8, tail, "0\r\n\r\n")) {
                            break;
                        }
                    }
                }
                
                // Parse chunked body
                var stream = std.io.fixedBufferStream(full_body.items);
                try response.parse_chunked_body(stream.reader());
            } else if (response.get_content_length()) |content_length| {
                // Read exact content length
                const body_start = if (header_size < response_buf.items.len) 
                    response_buf.items[header_size..] 
                else 
                    &[_]u8{};
                
                if (body_start.len < content_length) {
                    // Need to read more
                    var full_body = try std.ArrayList(u8).initCapacity(self.allocator, 8192);
                    defer full_body.deinit(self.allocator);
                    
                    try full_body.appendSlice(self.allocator, body_start);
                    
                    while (full_body.items.len < content_length) {
                        var chunk_buf: [8192]u8 = undefined;
                        const remaining = content_length - full_body.items.len;
                        const to_read = @min(remaining, chunk_buf.len);
                        const chunk_bytes = try conn.recv_all(self.runtime, chunk_buf[0..to_read]);
                        
                        if (chunk_bytes == 0) {
                            return error.UnexpectedEndOfStream;
                        }
                        
                        try full_body.appendSlice(self.allocator, chunk_buf[0..chunk_bytes]);
                    }
                    
                    try response.parse_body(full_body.items);
                } else {
                    // We already have all the body
                    try response.parse_body(body_start[0..content_length]);
                }
            } else {
                // No content-length, read what we have
                if (header_size < response_buf.items.len) {
                    try response.parse_body(response_buf.items[header_size..]);
                }
            }
        }
        
    }
    
    fn execute_request(self: *HTTPClient, req: *ClientRequest, response: *ClientResponse) !void {
        try self.execute_request_no_redirect(req, response);
        
        // Handle redirects if enabled
        if (self.follow_redirects and response.is_redirect()) {
            try self.handle_redirects(response, req);
        }
    }

    fn handle_redirects(self: *HTTPClient, response: *ClientResponse, original_req: *ClientRequest) !void {
        var redirect_count: u8 = 0;
        
        while (response.is_redirect() and redirect_count < self.max_redirects) {
            defer redirect_count += 1;
            
            const location = response.get_location() 
                orelse return error.MissingLocationHeader;
            
            // 1) Build a Uri for the redirect target (absolute or relative)
            const new_uri: std.Uri = blk: {
                // Fast check for absolute Location
                if (std.mem.startsWith(u8, location, "http://") or
                    std.mem.startsWith(u8, location, "https://"))
                {
                    break :blk try std.Uri.parse(location);
                } else {
                    // Relative: copy into an auxiliary buffer, then resolve in place
                    var resolved_buf: [2048]u8 = undefined;
                    if (location.len > resolved_buf.len)
                        return error.LocationTooLong;
                    
                    // aux_buf is a *slice* that resolveInPlace may grow/modify
                    var aux_buf: []u8 = resolved_buf[0..location.len];
                    @memcpy(aux_buf, location);
                    
                    // This returns a Uri that *references* aux_buf contents
                    const resolved = try std.Uri.resolveInPlace(original_req.uri, location.len, &aux_buf);
                    break :blk resolved;
                }
            };
            
            // OPTIONAL but recommended: normalize method/body per RFCs
            // - 303: always switch to GET, drop body
            // - 301/302: if original was POST, many clients switch to GET (pragmatic)
            var follow_method = original_req.method;
            var drop_body = false;
            switch (@intFromEnum(response.status)) {
                303 => { follow_method = .GET; drop_body = true; },
                301, 302 => if (original_req.method == .POST) { 
                    follow_method = .GET; 
                    drop_body = true; 
                },
                307, 308 => {}, // keep method & body
                else => {},
            }
            
            // OPTIONAL security hygiene: if host/port/scheme changes, drop sensitive headers
            const cross_origin = blk: {
                // Check if schemes differ
                if (!std.mem.eql(u8, new_uri.scheme, original_req.uri.scheme)) {
                    break :blk true;
                }
                // Check if hosts differ (both must be present for comparison)
                if (new_uri.host) |new_host| {
                    if (original_req.uri.host) |orig_host| {
                        if (!std.mem.eql(u8, new_host.percent_encoded, orig_host.percent_encoded)) {
                            break :blk true;
                        }
                    } else {
                        break :blk true;
                    }
                } else {
                    break :blk true;
                }
                // Check if ports differ
                if ((new_uri.port orelse 0) != (original_req.uri.port orelse 0)) {
                    break :blk true;
                }
                break :blk false;
            };
            
            // 2) Construct next request - render Uri to string since ClientRequest.init takes a string
            const url_string = try std.fmt.allocPrint(self.allocator, "{any}", .{new_uri});
            defer self.allocator.free(url_string);
            
            var new_req = try ClientRequest.init(self.allocator, follow_method, url_string);
            defer new_req.deinit();
            
            // Copy/adjust headers from original request
            var it = original_req.headers.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                // Skip Host; it's regenerated by ClientRequest.init
                if (std.ascii.eqlIgnoreCase(name, "host")) continue;
                // Drop sensitive headers on cross-origin redirects
                if (cross_origin and (std.ascii.eqlIgnoreCase(name, "authorization") or
                                     std.ascii.eqlIgnoreCase(name, "cookie"))) continue;
                _ = try new_req.set_header(name, value);
            }
            
            // If we're switching to GET or told to drop body, clear it
            if (drop_body) {
                new_req.body = null;
            } else if (original_req.body) |b| {
                _ = new_req.set_body(b);
            }
            
            // Finally execute (without redirect handling to avoid recursion)
            // Need to create a temporary response for intermediate redirects
            var temp_response = ClientResponse.init(self.allocator);
            defer temp_response.deinit();
            
            try self.execute_request_no_redirect(&new_req, &temp_response);
            
            // Copy temp_response to response
            response.deinit();
            response.* = temp_response;
            // Prevent double-free by resetting temp_response
            temp_response = ClientResponse.init(self.allocator);
        }
        
        if (redirect_count >= self.max_redirects) {
            return error.TooManyRedirects;
        }
    }
};

test "HTTPClient structure" {
    const testing = std.testing;
    
    // Test that the HTTPClient struct compiles and has the expected fields
    const client_fields = @typeInfo(HTTPClient).@"struct".fields;
    
    // Verify required fields exist
    var has_runtime = false;
    var has_allocator = false;
    var has_timeout = false;
    
    inline for (client_fields) |field| {
        if (std.mem.eql(u8, field.name, "runtime")) has_runtime = true;
        if (std.mem.eql(u8, field.name, "allocator")) has_allocator = true;
        if (std.mem.eql(u8, field.name, "default_timeout_ms")) has_timeout = true;
    }
    
    try testing.expect(has_runtime);
    try testing.expect(has_allocator);
    try testing.expect(has_timeout);
}