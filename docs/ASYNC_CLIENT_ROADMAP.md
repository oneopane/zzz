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
**Status:** ✅ Complete (Refactored to send pattern)  
**Files:** `src/http/client/client.zig`, `src/http/client/request.zig`

#### Implemented
- ✅ `HTTPClient.init()` / `deinit()` - Client lifecycle with proper resource management
- ✅ `HTTPClient.send()` - Single unified method for all requests (no hidden allocations)
- ✅ `ClientRequest.get()`, `.post()`, `.put()`, etc. - Convenience constructors
- ✅ `ClientRequest.builder()` - RequestBuilder pattern for complex requests
- ✅ `RequestBuilder` - Fluent API with method chaining
- ✅ Error handling for network failures and stream errors
- ✅ Redirect following with configurable limits
- ✅ Support for chunked encoding and variable content lengths
- ✅ Fixed memory leaks in header parsing
- ✅ Explicit ownership model - caller owns both request and response

#### Verification
```zig
test "simple HTTP GET request" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    // Caller owns both request and response
    var req = try ClientRequest.get(allocator, "http://httpbin.org/get");
    defer req.deinit();
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&req, &response);
    
    try expect(response.is_success());
    try expect(response.get_header("Content-Type") != null);
}

test "complex request with builder" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    // Builder pattern for complex requests
    var builder = ClientRequest.builder(allocator);
    defer builder.deinit();
    
    var req = try builder
        .post("https://api.example.com/v1/users", body)
        .header("Authorization", "Bearer token")
        .header("Content-Type", "application/json")
        .timeout(30000)
        .build();
    defer req.deinit();
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&req, &response);
}
```

**User Benefit:** No hidden allocations! Explicit ownership for both requests and responses, with ergonomic builder pattern for complex cases.

---

### Phase 6: POST and Body Handling 📝
**Status:** ✅ Complete  
**Files:** Update `request.zig`, `response.zig`

#### Implemented
- ✅ `ClientRequest.post()`, `.put()`, `.patch()`, `.delete()` - Convenience constructors
- ✅ `RequestBuilder` HTTP method helpers for all verbs
- ✅ `ClientRequest.set_json()` - JSON body serialization with std.json.stringify
- ✅ `RequestBuilder.json()` - JSON serialization for builder pattern
- ✅ `ClientResponse.json()` - Parse JSON response
- ✅ `ClientResponse.text()` - Get body as text
- ✅ Automatic Content-Type header for JSON requests
- ✅ Memory management for serialized JSON bodies

#### Verification
```zig
test "POST request with JSON" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    const json_body = "{\"name\": \"Test User\"}";
    var req = try ClientRequest.post(allocator, "http://httpbin.org/post", json_body);
    defer req.deinit();
    _ = try req.set_header("Content-Type", "application/json");
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&req, &response);
    
    try expect(response.is_success());
    
    const result = try response.json(struct {
        data: []const u8,
        headers: struct {
            @"Content-Type": []const u8,
        },
    });
    
    try expect(eql(result.data, json_body));
}

test "PUT request with builder" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    var builder = ClientRequest.builder(allocator);
    defer builder.deinit();
    
    var req = try builder
        .put("http://httpbin.org/put", "updated data")
        .header("Content-Type", "text/plain")
        .build();
    defer req.deinit();
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&req, &response);
    try expect(response.is_success());
}
```

**User Benefit:** Full CRUD operations support, JSON handling.

---

### Phase 7: HTTPS Support 🔒
**Status:** ✅ Complete  
**Files:** Updated `connection.zig`, integrated with secsock

#### Implemented
- ✅ Added TLS support to Connection via secsock
- ✅ Detect HTTPS from URL scheme in HTTPClient
- ✅ BearSSL integration for client-mode TLS
- ✅ All HTTP methods work with HTTPS
- ✅ Proper resource cleanup for TLS connections
- ✅ Socket union type for plain/secure connections

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
**Status:** ✅ Complete  
**Files:** `src/http/client/connection_pool.zig`, updated `client.zig`

#### Implemented
- ✅ `ConnectionPool.init()` / `deinit()` - Pool lifecycle management
- ✅ `ConnectionList` - Per-host idle/active connection tracking
- ✅ `get_connection()` - Reuse idle or create new connections
- ✅ `return_connection()` - Smart return based on keep-alive status
- ✅ `cleanup_idle()` - Time-based stale connection removal
- ✅ Keep-alive support with request counting
- ✅ Per-host connection limits (default 10, configurable)
- ✅ HTTPClient integration with pool enable/disable flag
- ✅ Connection state management (idle, active, closed)
- ✅ Pool statistics and monitoring

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

### Phase 9: SSE/Streaming Support 🌊
**Status:** ✅ Complete  
**Files:** `src/http/client/sse_parser.zig`, `src/http/client/streaming.zig`, `client.zig` (updated)

#### Implement
- **SSE Parser**: Parse Server-Sent Events from response stream
- **Streaming Response Handler**: Process responses chunk-by-chunk without buffering
- **Callback Interface**: Allow user-provided callbacks for each chunk/event
- **Iterator Pattern**: Alternative to callbacks for consuming streams
- **Event Types**: Support all SSE event types (data, event, id, retry)
- **Reconnection Support**: Handle Last-Event-ID for SSE reconnection
- **Partial Message Handling**: Buffer incomplete messages across chunks

#### Verification
```zig
test "SSE parsing" {
    var parser = SSEParser.init(allocator);
    defer parser.deinit();
    
    const chunk = "data: {\"message\": \"Hello\"}\n\n";
    const event = try parser.parse_chunk(chunk);
    
    try expect(event != null);
    try expect(std.mem.eql(u8, event.?.data.?, "{\"message\": \"Hello\"}"));
}

test "streaming response with callback" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    var req = try ClientRequest.post(allocator, "https://api.openai.com/v1/chat/completions", body);
    defer req.deinit();
    
    var message_count: usize = 0;
    try client.send_streaming(&req, struct {
        fn on_event(event: SSEMessage) void {
            // Process each SSE event as it arrives
            if (event.data) |data| {
                message_count += 1;
                std.debug.print("Received: {s}\n", .{data});
            }
        }
    }.on_event);
    
    try expect(message_count > 0);
}

test "streaming with iterator pattern" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    var req = try ClientRequest.get(allocator, "http://httpbin.org/stream/10");
    defer req.deinit();
    
    var stream = try client.send_streaming_iter(&req);
    defer stream.deinit();
    
    var line_count: usize = 0;
    while (try stream.next()) |chunk| {
        line_count += 1;
        // Process each chunk
    }
    
    try expect(line_count == 10);
}
```

**User Benefit:** Real-time streaming responses for LLM APIs, Server-Sent Events, and chunked data processing without memory buffering.

---

### Phase 10: Advanced Features 🎯
**Status:** ⏳ Pending  
**Files:** Various updates

#### Implement
- **Redirect Following**: Auto-follow 3xx responses (already partially done)
- **Timeout Support**: Request timeouts
- **Cookie Jar**: Automatic cookie handling
- **Request Builder**: Fluent API for building requests (already done)
- **Chunked Encoding**: Support chunked transfer encoding (partially done)
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

test "compression support" {
    var client = try HTTPClient.init(allocator, runtime);
    defer client.deinit();
    
    var req = try ClientRequest.get(allocator, "http://httpbin.org/gzip");
    defer req.deinit();
    try req.set_header("Accept-Encoding", "gzip, deflate");
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&req, &response);
    
    // Response should be automatically decompressed
    try expect(response.is_success());
    const body = try response.json(struct { gzipped: bool });
    try expect(body.gzipped == true);
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
6. **No Hidden Allocations**: Single `send()` method with explicit request/response ownership
7. **RequestBuilder Pattern**: Fluent API for complex requests without hiding allocations
8. **Explicit Ownership**: Caller owns both request and response objects (Zig philosophy)

### Module Organization
- `url.zig` - Free functions operating on `std.Uri` for HTTP-specific needs
- `query.zig` - `QueryParams` builder for API client use cases
- `connection.zig` - Connection wrapper with metadata for pooling
- `connection_pool.zig` - Per-host connection management
- `request.zig` - Request building using `std.Uri` directly
- `response.zig` - Response parsing (client-specific)
- `client.zig` - High-level HTTP client API
- `sse_parser.zig` - Server-Sent Events parser for streaming responses
- `streaming.zig` - Streaming response handler and iterator
- `proxy.zig` - HTTP proxy support

## Current Status

| Phase | Status | Completion | Notes |
|-------|--------|------------|-------|
| Phase 1: URL Utilities & Query Parameters | ✅ Complete | 100% | Stubs created, architecture finalized |
| Phase 2: Basic Connection | ✅ Complete | 100% | TCP connection implemented with tardy, tests passing |
| Phase 3: Request Serialization | ✅ Complete | 100% | All methods implemented, 9 tests passing |
| Phase 4: Response Parsing | ✅ Complete | 100% | All methods implemented, 9 tests passing |
| Phase 5: Basic HTTP Client | ✅ Complete | 100% | Refactored to send pattern with RequestBuilder |
| Phase 6: POST Support | ✅ Complete | 100% | JSON serialization, all HTTP methods, builder pattern |
| Phase 7: HTTPS Support | ✅ Complete | 100% | BearSSL integration, all methods support TLS |
| Phase 8: Connection Pooling | ✅ Complete | 100% | Per-host pools, keep-alive, configurable limits |
| Phase 9: SSE/Streaming Support | ✅ Complete | 100% | SSE parser, streaming handlers, callback & iterator APIs |
| Phase 10: Advanced Features | ⏳ Pending | 0% | Redirect following partially done |

## Next Steps

1. **Phase 10 Implementation**: Advanced features
   - **Timeout Support**: Add configurable request timeouts
   - **Cookie Jar**: Automatic cookie handling for session management
   - **Compression**: gzip/deflate support for request and response bodies
   - **Proxy Support**: HTTP/HTTPS proxy integration (forward proxy with CONNECT)

## Implementation Log

### Phase 9: SSE/Streaming Support (Completed 2025-08-31)
- ✅ Implemented SSEParser with W3C EventSource specification compliance
- ✅ Created incremental parser handling partial messages across chunks
- ✅ Added support for all SSE fields: id, event, data (multiline), retry
- ✅ Implemented StreamingResponse for callback-based processing
- ✅ Created StreamIterator for pull-based consumption with backpressure
- ✅ Added streaming methods to HTTPClient (send_streaming, send_streaming_sse, send_streaming_iter)
- ✅ Streaming connections bypass pool for proper lifecycle management
- ✅ Added helper methods to ClientResponse for SSE detection
- ✅ Created comprehensive tests for SSE parsing and streaming scenarios
- ✅ Built example programs demonstrating LLM API streaming patterns
- **Key Design**: Zero-copy streaming with ring buffer for partial messages
- **Architecture**: Dual API pattern (callback and iterator) for flexibility
- **Memory Model**: Fixed-size buffers prevent unbounded growth on long streams

### Phase 8: Connection Pooling (Completed 2025-08-31)
- ✅ Implemented ConnectionPool with per-host connection management
- ✅ Created ConnectionList to track idle and active connections separately
- ✅ Added connection reuse logic with keep-alive request counting
- ✅ Implemented time-based idle connection cleanup (60s default timeout)
- ✅ Added configurable per-host connection limits (10 connections default)
- ✅ Integrated pool with HTTPClient using `use_connection_pool` flag
- ✅ Added pool statistics for monitoring (idle, active, total pools)
- ✅ Created comprehensive tests for pool operations
- ✅ Built example program demonstrating connection reuse performance
- **Key Design**: Separate idle/active lists for efficient connection management
- **Architecture**: Pool keys use "host:port:tls" format for unique identification
- **Performance**: Expected 50%+ latency reduction for subsequent requests

### Phase 7: HTTPS Support (Completed 2025-08-31)
- ✅ Integrated secsock/BearSSL for TLS support in Connection
- ✅ Added socket union type for plain/secure connections
- ✅ Implemented TLS send/recv operations with proper error handling
- ✅ HTTPClient automatically detects HTTPS from URL scheme
- ✅ Proper cleanup and resource management for BearSSL context
- ✅ Created HTTPS test file and example program
- ✅ Updated build.zig to include client_https example
- **Key Design**: Union socket type allows seamless plain/TLS switching
- **Architecture**: BearSSL managed separately with proper lifecycle
- **Certificate Validation**: Uses BearSSL's default validation (production needs CA setup)

### Phase 6: POST and Body Handling (Completed 2025-08-31)
- ✅ Implemented `ClientRequest.set_json()` with full JSON serialization using std.json.stringify
- ✅ Implemented `RequestBuilder.json()` for builder pattern JSON support
- ✅ Added comprehensive tests for JSON body serialization
- ✅ Tested POST requests with complex JSON payloads (structs, arrays)
- ✅ Verified DELETE method support and convenience constructors
- ✅ Automatic Content-Type header setting for JSON requests
- ✅ Proper memory management for allocated JSON strings
- **Key Design**: Allocate JSON strings and track ownership for proper cleanup
- **Architecture**: JSON serialization integrated seamlessly with existing API

### Phase 5 Third Refactoring: Rename execute to send (2025-08-31)
- ✅ Renamed `execute()` method to `send()` for better HTTP semantics
- ✅ Updated internal methods: `execute_request` → `send_request`
- ✅ Updated examples and documentation to use new API
- **Key Change**: More intuitive method name that aligns with HTTP terminology

### Phase 5 Second Refactoring: Execute-Only Pattern (2025-08-30)
- ✅ Refactored from convenience methods to single `execute()` method (now `send()`)
- ✅ Implemented RequestBuilder with fluent API for complex requests
- ✅ Added convenience constructors: `ClientRequest.get()`, `.post()`, etc.
- ✅ Removed all hidden allocations - caller owns both request and response
- ✅ Builder pattern with method chaining for ergonomic API
- **Key Change**: No hidden allocations, follows Zig philosophy
- **API Design**: One execution path through `client.send(&request, &response)`
- **Pattern**: Explicit ownership for both request and response objects

### Phase 5 First Refactoring: Memory Management Fix (2025-08-30)
- ✅ Fixed memory leaks in ClientResponse header parsing
- ✅ Refactored API from returning responses to _into pattern
- ✅ Changed methods: get() → get_into(), head() → head_into()
- ✅ Removed reset() method in favor of simple init/deinit lifecycle
- ✅ Updated example code to use new ownership model
- **Key Fix**: Headers are now properly freed in deinit()
- **API Change**: Caller now owns response object (explicit ownership)
- **Pattern**: Follows Zig stdlib convention of allocation at same scope as deallocation

### Phase 5: Basic HTTP Client (Completed 2025-08-30)
- ✅ Implemented HTTPClient struct with init/deinit lifecycle management
- ✅ Created send_request() for single request execution without pooling
- ✅ Implemented get() and head() methods for simple HTTP requests
- ✅ Added comprehensive error handling for network failures
- ✅ Implemented redirect following with configurable limits (max_redirects)
- ✅ Added support for chunked transfer encoding in response handling
- ✅ Created test file and example program for HTTP client usage
- ✅ Integrated with existing Connection, Request, and Response modules
- **Key Design**: No connection pooling (deferred to Phase 8)
- **Architecture**: Direct connection per request, proper resource cleanup

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

### Phase 4: Response Parsing (Completed 2025-08-29)
- ✅ Implemented ClientResponse struct with allocator-based memory management
- ✅ Created init/deinit/clear methods for lifecycle management
- ✅ Implemented parse_headers() for status line and header parsing
- ✅ Added parse_body() for simple body storage
- ✅ Implemented parse_chunked_body() for chunked transfer encoding
- ✅ Added helper methods: get_header(), get_content_length(), is_success(), is_redirect(), get_location()
- ✅ Implemented json() and text() body handling methods
- ✅ Added comprehensive unit tests (9 tests, all passing)
- ✅ Integrated with existing test suite
- **Key Design**: Owns body memory when parsed, headers stored with case-insensitive lookup
- **Note**: HTTP/2 and HTTP/3 versions mapped to HTTP/1.1 for std.http.Version compatibility

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

*Last Updated: 2025-08-31*  
*Estimated Total Implementation Time: 2-3 weeks for core features (Phases 1-8)*