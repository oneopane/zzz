# Async HTTP Client Implementation Roadmap

## Overview
This roadmap provides a step-by-step implementation plan for adding an async HTTP client to zzz. Each phase is designed to be atomic, testable, and immediately useful.

## Implementation Phases

### Phase 1: URL Utilities & Query Parameters 🔗
**Status:** ✅ Complete (stubs created)  
**Files:** `src/http/client/url.zig`, `src/http/client/query.zig`

#### Architecture Decision
- Use Zig's built-in `std.Uri` for URL parsing (RFC 3986 compliant)
- Provide free functions that operate on `std.Uri` directly (no wrapper type)
- Separate `QueryParams` into its own module for API client building

#### Implemented (as stubs)
- `url.isSecure(uri: Uri)` - Check if HTTPS/WSS using case-insensitive comparison
- `url.port(uri: Uri, policy: PortPolicy)` - Get port with explicit policy handling
- `url.host(uri: Uri, buf: []u8)` - Get decoded host (handles IPv6 literals)
- `url.writeRequestTarget(uri: Uri, writer, form: TargetForm)` - Write HTTP/1.1 request-target
- `url.decodeComponent(buffer: []u8, component: Uri.Component)` - Decode URI components
- `QueryParams` struct in separate file for building complex API queries

#### Verification
```zig
// Test file: src/http/client/url_test.zig
test "parse HTTP URL with std.Uri" {
    const uri = try std.Uri.parse("http://example.com:8080/path?key=value");
    
    try expect(std.ascii.eqlIgnoreCase(uri.scheme, "http"));
    try expect(uri.port.? == 8080);
    
    var host_buf: [256]u8 = undefined;
    const host = try url.host(uri, &host_buf);
    try expect(eql(host, "example.com"));
}

test "explicit port policies" {
    const uri = try std.Uri.parse("https://api.example.com/v1/users");
    
    // Explicit policy for port handling
    const port = try url.port(uri, .default_for_known_schemes);
    try expect(port == 443);
    try expect(url.isSecure(uri));
}

test "HTTP/1.1 request-target forms" {
    const uri = try std.Uri.parse("http://proxy.example.com/api");
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    // Origin form for normal requests
    try url.writeRequestTarget(uri, buf.writer(), .origin);
    try expect(eql(buf.items, "/api"));
    
    // Absolute form for proxy requests
    buf.clearRetainingCapacity();
    try url.writeRequestTarget(uri, buf.writer(), .absolute);
    try expect(std.mem.startsWith(u8, buf.items, "http://"));
}
```

**User Benefit:** Leverages standard library for URL parsing, provides HTTP-specific utilities without unnecessary abstraction.

---

### Phase 2: Basic Connection 🔌
**Status:** ⏳ Pending  
**Files:** `src/http/client/connection.zig`

#### Implement
- `Connection.init()` - Create connection object
- `Connection.connect()` - Establish TCP connection (no TLS yet)
- `Connection.send_all()` - Send raw bytes
- `Connection.recv_all()` - Receive raw bytes  
- `Connection.close()` - Close connection
- `Connection.is_alive()` - Check connection state

#### Verification
```zig
// Manual test against httpbin.org
test "raw HTTP connection" {
    var conn = try Connection.init(allocator, "httpbin.org", 80, false);
    defer conn.close();
    
    try conn.connect(runtime);
    try conn.send_all(runtime, "GET / HTTP/1.1\r\nHost: httpbin.org\r\n\r\n");
    
    var buffer: [4096]u8 = undefined;
    const bytes_read = try conn.recv_all(runtime, &buffer);
    
    // Should see "HTTP/1.1 200 OK" in response
    try expect(std.mem.indexOf(u8, buffer[0..bytes_read], "HTTP/1.1") != null);
}
```

**User Benefit:** Can make raw HTTP requests manually, debug protocol issues.

---

### Phase 3: Request Serialization 📤
**Status:** ✅ Complete  
**Files:** `src/http/client/request.zig`

#### Architecture Decision
- Use `std.Uri` directly in `ClientRequest` (no wrapper type)
- Leverage `url.writeRequestTarget()` for proper HTTP/1.1 request-target generation
- Support all HTTP/1.1 request forms (origin, absolute, authority, asterisk)

#### Implemented
- ✅ `ClientRequest.init()` - Create request with method and parsed `std.Uri`
- ✅ `ClientRequest.deinit()` - Clean up resources with proper memory management
- ✅ `ClientRequest.set_header()` - Add/update headers with memory allocation
- ✅ `ClientRequest.set_body()` - Set request body (reference, not owned)
- ✅ `ClientRequest.serialize_headers()` - Generate HTTP/1.1 request headers
- ✅ `ClientRequest.serialize_full()` - Generate complete HTTP request with body
- ✅ Use `url.writeRequestTarget()` for proper path generation
- ✅ Automatic Host header generation with port handling
- ✅ Content-Length header management with override support

#### Verification
```zig
test "serialize GET request using std.Uri" {
    const uri = try std.Uri.parse("http://example.com/api/users?page=1");
    var req = try ClientRequest.init(allocator, .GET, uri);
    defer req.deinit();
    
    try req.set_header("User-Agent", "zzz-client/1.0");
    try req.set_header("Accept", "application/json");
    
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try req.serialize_headers(buf.writer());
    
    const expected = 
        "GET /api/users?page=1 HTTP/1.1\r\n" ++
        "Host: example.com\r\n" ++
        "User-Agent: zzz-client/1.0\r\n" ++
        "Accept: application/json\r\n" ++
        "\r\n";
    
    try expect(eql(buf.items, expected));
}

test "serialize POST with QueryParams builder" {
    const uri = try std.Uri.parse("http://api.example.com/users");
    var req = try ClientRequest.init(allocator, .POST, uri);
    defer req.deinit();
    
    // Build complex query with QueryParams for API clients
    var params = QueryParams.init(allocator);
    defer params.deinit();
    try params.set("filter", "active");
    try params.setInt("limit", 100);
    try params.setBool("verbose", true);
    
    const body = "{\"name\":\"John\"}";
    req.set_body(body);
    try req.set_header("Content-Type", "application/json");
    
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try req.serialize_full(buf.writer());
    try expect(std.mem.endsWith(u8, buf.items, body));
}
```

**User Benefit:** Can build HTTP requests programmatically, understand HTTP protocol.

---

### Phase 4: Response Parsing 📥
**Status:** ⏳ Pending  
**Files:** `src/http/client/response.zig`

#### Implement
- `ClientResponse.init()` / `deinit()` - Lifecycle management
- `ClientResponse.parse_headers()` - Parse status line and headers
- `ClientResponse.parse_body()` - Parse response body
- `ClientResponse.get_header()` - Get header value
- `ClientResponse.get_content_length()` - Extract Content-Length
- `ClientResponse.is_success()` - Check 2xx status
- `ClientResponse.is_redirect()` - Check 3xx status
- `ClientResponse.is_chunked()` - Check for chunked encoding

#### Verification
```zig
test "parse HTTP response" {
    const response_text = 
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 13\r\n" ++
        "\r\n" ++
        "{\"ok\": true}";
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    const header_size = try resp.parse_headers(response_text);
    try expect(resp.status == .OK);
    try expect(resp.is_success());
    try expect(eql(resp.get_header("Content-Type").?, "application/json"));
    try expect(resp.get_content_length().? == 13);
    
    try resp.parse_body(response_text[header_size..]);
    try expect(eql(resp.body.?, "{\"ok\": true}"));
}

test "parse redirect response" {
    const response_text = 
        "HTTP/1.1 301 Moved Permanently\r\n" ++
        "Location: https://example.com/new\r\n" ++
        "\r\n";
    
    var resp = ClientResponse.init(allocator);
    defer resp.deinit();
    
    _ = try resp.parse_headers(response_text);
    try expect(resp.is_redirect());
    try expect(eql(resp.get_location().?, "https://example.com/new"));
}
```

**User Benefit:** Can parse HTTP responses, handle different status codes.

---

### Phase 5: Basic HTTP Client 🚀
**Status:** ⏳ Pending  
**Files:** `src/http/client/client.zig`

#### Implement
- `HTTPClient.init()` / `deinit()` - Client lifecycle
- `HTTPClient.execute_request()` - Single request without pooling
- `HTTPClient.get()` - Simple GET request
- `HTTPClient.head()` - HEAD request
- Error handling for network failures

#### Verification
```zig
test "first real HTTP GET request" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    const response = try client.get("http://httpbin.org/get");
    defer response.deinit();
    
    try expect(response.is_success());
    try expect(response.get_header("Content-Type") != null);
}

test "HTTP HEAD request" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    const response = try client.head("http://httpbin.org/status/200");
    defer response.deinit();
    
    try expect(response.is_success());
    try expect(response.body == null); // HEAD has no body
}
```

**User Benefit:** Can make actual HTTP GET/HEAD requests! First working client.

---

### Phase 6: POST and Body Handling 📝
**Status:** ⏳ Pending  
**Files:** Update `client.zig`, `request.zig`, `response.zig`

#### Implement
- `HTTPClient.post()` - POST with body
- `HTTPClient.put()` - PUT with body
- `HTTPClient.patch()` - PATCH with body
- `HTTPClient.delete()` - DELETE request
- `ClientRequest.set_json()` - JSON body helper
- `ClientResponse.json()` - Parse JSON response
- `ClientResponse.text()` - Get body as text

#### Verification
```zig
test "POST request with JSON" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    const json_body = "{\"name\": \"Test User\"}";
    const response = try client.post("http://httpbin.org/post", json_body);
    defer response.deinit();
    
    try expect(response.is_success());
    
    const result = try response.json(struct {
        data: []const u8,
        headers: struct {
            @"Content-Type": []const u8,
        },
    });
    
    try expect(eql(result.data, json_body));
}

test "PUT request" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    const response = try client.put("http://httpbin.org/put", "updated data");
    defer response.deinit();
    
    try expect(response.is_success());
}
```

**User Benefit:** Full CRUD operations support, JSON handling.

---

### Phase 7: HTTPS Support 🔒
**Status:** ⏳ Pending  
**Files:** Update `connection.zig`, integrate with secsock

#### Implement
- Add TLS support to Connection via secsock
- Detect HTTPS from URL scheme
- Certificate validation setup
- Update all HTTP methods to work with HTTPS

#### Verification
```zig
test "HTTPS GET request" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    const response = try client.get("https://httpbin.org/get");
    defer response.deinit();
    
    try expect(response.is_success());
}

test "HTTPS POST request" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    const response = try client.post("https://httpbin.org/post", "secure data");
    defer response.deinit();
    
    try expect(response.is_success());
}
```

**User Benefit:** Secure HTTPS requests, production-ready client.

---

### Phase 8: Connection Pooling ⚡
**Status:** ⏳ Pending  
**Files:** `src/http/client/connection_pool.zig`, update `client.zig`

#### Implement
- `ConnectionPool.init()` / `deinit()`
- `ConnectionPool.get_connection()` - Get or create connection
- `ConnectionPool.return_connection()` - Return to pool
- `ConnectionPool.cleanup_idle()` - Remove stale connections
- Keep-alive support
- Per-host connection limits
- Integrate with HTTPClient

#### Verification
```zig
test "connection reuse" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    // Make multiple requests to same host
    const start = std.time.milliTimestamp();
    
    const resp1 = try client.get("http://httpbin.org/get");
    defer resp1.deinit();
    
    const time1 = std.time.milliTimestamp() - start;
    
    const resp2 = try client.get("http://httpbin.org/get");
    defer resp2.deinit();
    
    const time2 = std.time.milliTimestamp() - start - time1;
    
    // Second request should be faster (no handshake)
    try expect(time2 < time1);
    
    // Verify both successful
    try expect(resp1.is_success());
    try expect(resp2.is_success());
}

test "multiple hosts" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    // Different hosts should use different connections
    const resp1 = try client.get("http://httpbin.org/get");
    defer resp1.deinit();
    
    const resp2 = try client.get("http://example.com/");
    defer resp2.deinit();
    
    try expect(resp1.is_success());
    try expect(resp2.is_success());
    
    // Should have 2 connections in pool
    try expect(client.connection_pool.connections.count() == 2);
}
```

**User Benefit:** Dramatic performance improvement, production-ready pooling.

---

### Phase 9: Advanced Features 🎯
**Status:** ⏳ Pending  
**Files:** Various updates

#### Implement
- **Redirect Following**: Auto-follow 3xx responses
- **Timeout Support**: Request timeouts
- **Cookie Jar**: Automatic cookie handling
- **Request Builder**: Fluent API for building requests
- **Chunked Encoding**: Support chunked transfer encoding
- **Compression**: gzip/deflate support
- **Proxy Support**: HTTP proxy integration

#### Verification
```zig
test "redirect following" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    client.follow_redirects = true;
    client.max_redirects = 5;
    
    const response = try client.get("http://httpbin.org/redirect/2");
    defer response.deinit();
    
    try expect(response.is_success());
    // Should end up at /get after 2 redirects
}

test "request timeout" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    client.default_timeout_ms = 1000; // 1 second
    
    const result = client.get("http://httpbin.org/delay/10");
    try expect(result == error.Timeout);
}

test "request builder pattern" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    var request = RequestBuilder.init(allocator)
        .method(.POST)
        .url("https://api.example.com/users")
        .header("Authorization", "Bearer token123")
        .json(.{ .name = "John", .age = 30 })
        .build();
    
    const response = try client.request(request);
    defer response.deinit();
}
```

**User Benefit:** Full-featured HTTP client with all modern conveniences.

---

## Testing Strategy

### Unit Tests
Each phase includes unit tests that can run without network access:
- URL parsing tests
- Request serialization tests  
- Response parsing tests

### Integration Tests
Tests that require network access (can be disabled in CI):
- Real HTTP requests to httpbin.org
- HTTPS connection tests
- Connection pooling verification

### Example Programs
Create example programs for each phase:
```bash
zig build run-example-url-parse
zig build run-example-simple-get
zig build run-example-post-json
zig build run-example-connection-pool
```

## Success Metrics

### Phase Completion Criteria
- [ ] All unit tests pass
- [ ] Integration tests pass (when network available)
- [ ] Example program runs successfully
- [ ] No memory leaks (tested with valgrind)
- [ ] Documentation updated

### Performance Goals
- Connection pooling should reduce latency by >50% for subsequent requests
- Support minimum 100 concurrent requests
- Memory usage <1MB for idle client with empty pool
- Memory usage <10MB with 100 pooled connections

## Dependencies

### Required
- ✅ tardy (async runtime) - already integrated
- ✅ secsock (TLS support) - already integrated
- ✅ zzz existing HTTP types - available

### Optional
- compression libraries (for gzip/deflate support)
- JSON library (using std.json is fine)

## Architecture Decisions

### Key Design Choices
1. **URL Handling**: Use `std.Uri` directly with free functions for HTTP-specific operations
2. **No Wrapper Types**: Operate on standard library types directly for better composability
3. **Explicit Policies**: Make decisions explicit (e.g., PortPolicy) rather than hidden defaults
4. **Query Parameters**: Separate module for building complex API queries programmatically
5. **Connection Pooling**: Client-specific pooling (different from server's ephemeral connections)

### Module Organization
- `url.zig` - Free functions operating on `std.Uri` for HTTP-specific needs
- `query.zig` - `QueryParams` builder for API client use cases
- `connection.zig` - Connection wrapper with metadata for pooling
- `connection_pool.zig` - Per-host connection management
- `request.zig` - Request building using `std.Uri` directly
- `response.zig` - Response parsing (client-specific)
- `client.zig` - High-level HTTP client API
- `proxy.zig` - HTTP proxy support

## Current Status

| Phase | Status | Completion | Notes |
|-------|--------|------------|-------|
| Phase 1: URL Utilities & Query Parameters | ✅ Complete | 100% | Stubs created, architecture finalized |
| Phase 2: Basic Connection | ✅ Complete | 100% | TCP connection implemented with tardy, tests passing |
| Phase 3: Request Serialization | ✅ Complete | 100% | All methods implemented, 9 tests passing |
| Phase 4: Response Parsing | ⏳ Pending | 0% | |
| Phase 5: Basic HTTP Client | ⏳ Pending | 0% | |
| Phase 6: POST Support | ⏳ Pending | 0% | |
| Phase 7: HTTPS Support | ⏳ Pending | 0% | |
| Phase 8: Connection Pooling | ⏳ Pending | 0% | |
| Phase 9: Advanced Features | ⏳ Pending | 0% | |

## Next Steps

1. **Phase 4 Implementation**: Implement response parsing in `response.zig`
2. **Create ClientResponse struct**: Status, headers, body parsing
3. **Handle response variations**: Success, redirects, errors, chunked encoding
4. **Test response parsing**: Unit tests for various response types
5. **Update roadmap**: Document progress and move to Phase 5

## Implementation Log

### Phase 3: Request Serialization (Completed 2025-08-29)
- ✅ Implemented ClientRequest struct with std.Uri integration
- ✅ Created init/deinit with proper memory management for headers
- ✅ Implemented set_header() with duplicate detection and memory cleanup
- ✅ Added set_body() for request body management
- ✅ Implemented serialize_headers() using url.writeRequestTarget()
- ✅ Added serialize_full() for complete request serialization
- ✅ Automatic Host header generation with smart port handling
- ✅ Content-Length header auto-calculation with manual override support
- ✅ Added comprehensive unit tests (9 tests, all passing)
- **Key Design**: Direct std.Uri usage without wrapper types
- **Memory Model**: Headers owned by request, body referenced (not owned)

### Phase 2: Basic Connection (Completed 2025-08-29)
- ✅ Implemented Connection struct with state management
- ✅ Created init/deinit methods for resource management
- ✅ Implemented connect() using tardy Socket API
- ✅ Added send_all() and recv_all() for raw byte operations
- ✅ Implemented close() and is_alive() methods
- ✅ Added comprehensive unit tests (6 tests, all passing)
- ✅ Integrated with existing test suite
- **Key Learning**: tardy uses Socket.send/recv methods (not Runtime methods)
- **Note**: TLS support deferred to Phase 7 (returns error.TLSNotImplementedYet)

---

*Last Updated: 2025-08-29*  
*Estimated Total Implementation Time: 2-3 weeks for core features (Phases 1-8)*