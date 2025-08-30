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
    pub fn get(self: *HTTPClient, url: []const u8) !ClientResponse {
        const uri = try std.Uri.parse(url);
        var req = try ClientRequest.init(self.allocator, .GET, uri);
        defer req.deinit();
        
        return self.execute_request(&req);
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

    pub fn head(self: *HTTPClient, url: []const u8) !ClientResponse {
        const uri = try std.Uri.parse(url);
        var req = try ClientRequest.init(self.allocator, .HEAD, uri);
        defer req.deinit();
        
        return self.execute_request(&req);
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
    fn execute_request(self: *HTTPClient, req: *ClientRequest) !ClientResponse {
        // Add default headers if they exist
        if (self.default_headers) |headers| {
            var it = headers.iterator();
            while (it.next()) |entry| {
                // Don't override existing headers
                if (req.get_header(entry.key_ptr.*) == null) {
                    try req.set_header(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }
        
        // Parse the host and port from the URI
        var host_buf: [256]u8 = undefined;
        const host = req.uri.host orelse return error.NoHostInURI;
        const host_str = try std.fmt.bufPrint(&host_buf, "{s}", .{host});
        
        const default_port: u16 = if (std.ascii.eqlIgnoreCase(req.uri.scheme, "https")) 443 else 80;
        const port = req.uri.port orelse default_port;
        const use_tls = std.ascii.eqlIgnoreCase(req.uri.scheme, "https");
        
        // Create a connection (no pooling in Phase 5)
        var conn = try Connection.init(self.allocator, host_str, port, use_tls);
        defer conn.deinit();
        
        // Connect to the server
        try conn.connect(self.runtime);
        
        // Serialize and send the request
        var request_buf = std.ArrayList(u8).init(self.allocator);
        defer request_buf.deinit();
        
        try req.serialize_full(request_buf.writer());
        try conn.send_all(self.runtime, request_buf.items);
        
        // Receive the response
        // Start with initial buffer for headers
        var response_buf = std.ArrayList(u8).init(self.allocator);
        defer response_buf.deinit();
        
        // Read initial chunk (headers + some body)
        var initial_buf: [8192]u8 = undefined;
        const initial_bytes = try conn.recv_all(self.runtime, &initial_buf);
        
        if (initial_bytes == 0) {
            return error.EmptyResponse;
        }
        
        try response_buf.appendSlice(initial_buf[0..initial_bytes]);
        
        // Parse the response
        var response = ClientResponse.init(self.allocator);
        errdefer response.deinit();
        
        const header_size = try response.parse_headers(response_buf.items);
        
        // For HEAD requests, there's no body
        if (req.method != .HEAD) {
            // Check if we need to read more data
            if (response.is_chunked()) {
                // Handle chunked encoding
                var full_body = std.ArrayList(u8).init(self.allocator);
                defer full_body.deinit();
                
                // Add what we already have after headers
                if (header_size < response_buf.items.len) {
                    try full_body.appendSlice(response_buf.items[header_size..]);
                }
                
                // Continue reading until we get all chunks
                while (true) {
                    var chunk_buf: [8192]u8 = undefined;
                    const chunk_bytes = conn.recv_all(self.runtime, &chunk_buf) catch |err| {
                        if (err == error.ConnectionClosed) break;
                        return err;
                    };
                    
                    if (chunk_bytes == 0) break;
                    try full_body.appendSlice(chunk_buf[0..chunk_bytes]);
                    
                    // Check if we've received the final chunk (0\r\n\r\n)
                    if (full_body.items.len >= 5) {
                        const tail = full_body.items[full_body.items.len - 5 ..];
                        if (std.mem.eql(u8, tail, "0\r\n\r\n")) {
                            break;
                        }
                    }
                }
                
                // Parse chunked body
                try response.parse_chunked_body(full_body.items);
            } else if (response.get_content_length()) |content_length| {
                // Read exact content length
                const body_start = if (header_size < response_buf.items.len) 
                    response_buf.items[header_size..] 
                else 
                    &[_]u8{};
                
                if (body_start.len < content_length) {
                    // Need to read more
                    var full_body = std.ArrayList(u8).init(self.allocator);
                    defer full_body.deinit();
                    
                    try full_body.appendSlice(body_start);
                    
                    while (full_body.items.len < content_length) {
                        var chunk_buf: [8192]u8 = undefined;
                        const remaining = content_length - full_body.items.len;
                        const to_read = @min(remaining, chunk_buf.len);
                        const chunk_bytes = try conn.recv_all(self.runtime, chunk_buf[0..to_read]);
                        
                        if (chunk_bytes == 0) {
                            return error.UnexpectedEndOfStream;
                        }
                        
                        try full_body.appendSlice(chunk_buf[0..chunk_bytes]);
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
        
        // Handle redirects if enabled
        if (self.follow_redirects and response.is_redirect()) {
            return self.handle_redirects(&response, req);
        }
        
        return response;
    }

    fn handle_redirects(self: *HTTPClient, response: *ClientResponse, original_req: *ClientRequest) !ClientResponse {
        var current_response = response.*;
        var redirect_count: u8 = 0;
        
        while (current_response.is_redirect() and redirect_count < self.max_redirects) {
            defer {
                if (redirect_count > 0) current_response.deinit();
                redirect_count += 1;
            }
            
            // Get the Location header
            const location = current_response.get_location() orelse return error.MissingLocationHeader;
            
            // Parse the new URL
            const new_uri = std.Uri.parse(location) catch {
                // If it's a relative URL, resolve it against the original URL
                var resolved_buf: [2048]u8 = undefined;
                const resolved = try std.Uri.resolve_inplace(original_req.uri, location, &resolved_buf);
                break try std.Uri.parse(resolved);
            };
            
            // Create a new request with the redirect URL
            var new_req = try ClientRequest.init(self.allocator, original_req.method, new_uri);
            defer new_req.deinit();
            
            // Copy headers from original request
            var it = original_req.headers.iterator();
            while (it.next()) |entry| {
                try new_req.set_header(entry.key_ptr.*, entry.value_ptr.*);
            }
            
            // Execute the new request
            current_response = try self.execute_request(&new_req);
        }
        
        if (redirect_count >= self.max_redirects) {
            return error.TooManyRedirects;
        }
        
        return current_response;
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