# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
zzz is a high-performance networking framework for Zig that supports HTTP/1.1 and HTTPS. It's built on top of Tardy (async runtime) and focuses on modularity, performance, and minimal memory usage. The project is actively developing an async HTTP client to complement the existing server framework.

## Key Development Commands

### Building
```bash
# Build the library module
zig build

# Build specific examples
zig build basic           # Basic HTTP server
zig build client_basic    # Basic HTTP client
zig build tls            # TLS/HTTPS server (requires libc)

# Run examples directly
zig build run_basic      # Run basic server example
zig build run_client_basic # Run basic client example
```

### Testing
```bash
# Run all enabled tests
zig build test

# Run specific test modules (useful for debugging)
zig build test-core          # Core module tests
zig build test-http-common   # HTTP common tests  
zig build test-http-server   # HTTP server tests
zig build test-http-client   # HTTP client tests (currently disabled - causes crashes)

# Run a single test file (when debugging)
zig test src/http/client/url_test.zig
```

**Note**: HTTP client tests are currently disabled in `build.zig:112` due to test runner crashes. Re-enable by uncommenting when fixed.

## Architecture & Module Structure

### Core Dependencies
- **Tardy**: Async runtime providing IO operations (io_uring, epoll, kqueue, poll) - Currently at `../tardy`
- **Secsock**: TLS/SSL support - Currently at `../secsock`
- **Local Paths**: Using local dependencies while porting to Zig 0.15.1 - will change to git URLs for official release

### Module Organization
```
src/
├── lib.zig                 # Root module exposing tardy, secsock, and HTTP
├── core/                   # Core utilities (storage, maps, wrapping)
├── http/
│   ├── lib.zig            # HTTP module entry point
│   ├── common/            # Shared HTTP components (status, methods, cookies, forms)
│   ├── server/            # Server implementation
│   │   ├── server.zig     # Main server with Runtime integration
│   │   ├── context.zig    # Request/Response context
│   │   ├── router.zig     # Route matching and handling
│   │   ├── router/        # Routing trie, middleware system
│   │   └── middlewares/   # Built-in middleware (compression, rate limiting)
│   └── client/            # HTTP client implementation
│       ├── client.zig     # High-level HTTPClient interface
│       ├── connection.zig # Connection management
│       └── request.zig    # Request building
```

### Key Architectural Patterns

1. **Tardy Integration**: All network operations go through Tardy's Runtime
   - Server creates tasks via `Runtime.spawn()`
   - Client uses Runtime for async socket operations

2. **Router & Middleware**: Layered routing system
   - Routes defined with method chaining: `Route.init("/").get({}, handler).layer()`
   - Middleware applied via `.layer()` for composable request processing

3. **Context Pattern**: Request handlers receive a Context containing:
   - Request data (method, headers, body)
   - Response builders
   - Runtime reference for async operations

4. **Memory Management**: 
   - Pool allocators for request/response buffers
   - Configurable stack sizes and buffer limits
   - Explicit cleanup with defer patterns

## Development Notes

### HTTP Client Development Status
The HTTP client is being implemented in phases (see `ASYNC_CLIENT_ROADMAP.md`):
- Phase 1: URL Parsing (🟡 Partial - basic structure using std.Uri)
- Phase 2-5: Connection, Request/Response, Basic Client (⏳ Pending)
- Phase 6-9: POST Support, HTTPS, Connection Pooling, Advanced Features (⏳ Pending)

Current capabilities:
- Basic GET/HEAD operations functional
- POST/PUT/PATCH/DELETE marked as "Not implemented"
- Connection pooling structure exists but not fully utilized
- Redirect following supported but limited

### Testing Infrastructure
Tests are split into modules for isolation:
- `test_core.zig`: Core utilities
- `test_http_common.zig`: HTTP primitives
- `test_http_server.zig`: Server functionality
- `test_http_client.zig`: Client functionality (disabled due to crashes)

### Zig Version Compatibility
- **Current**: Zig 0.15.1 (recently migrated)
- **build.zig.zon**: Still shows 0.14.0 minimum but running on 0.15.1
- **Key Migration Changes**:
  - ArrayList API requires allocator for operations
  - Compression module API updates
  - Some test infrastructure adjustments needed

### Common Patterns

#### Server Example Pattern
All server examples follow this structure:
1. Initialize allocator (GeneralPurposeAllocator)
2. Create Tardy runtime with threading configuration
3. Setup router with handlers using method chaining
4. Create and bind socket (TCP or Unix)
5. Pass to Tardy.entry() with server configuration

#### Handler Signature
```zig
fn handler(ctx: *const Context, _: void) !Respond {
    return ctx.response.apply(.{
        .status = .OK,
        .mime = http.Mime.HTML,
        .body = "Response content",
    });
}
```

#### Router Configuration
```zig
var router = try Router.init(allocator, &.{
    Route.init("/").get({}, handler).layer(),
    Route.init("/api/:id").post({}, api_handler).layer(),
}, .{});
```

### Performance Notes
- Default server configuration uses 4MB stack size (`stack_size: 1024 * 1024 * 4`)
- Socket buffer default is 2KB (`socket_buffer_bytes: 1024 * 2`)
- Connection count configurable (default 1024)
- The framework achieves ~70% better performance than zap with ~3% memory usage