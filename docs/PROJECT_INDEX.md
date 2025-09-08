# ZZZ Project Index

## Project Overview
**Name:** zzz  
**Description:** Fast and simple web framework for Zig  
**Status:** Active Development - Adding Async HTTP Client  
**Zig Version:** 0.15.1 (Recently migrated)  
**Last Updated:** 2025-08-29

## Current Development Focus

### 🚀 Async HTTP Client Implementation
**Status:** In Progress - Phase 1/9  
**Goal:** Add a full-featured async HTTP client to complement the existing server framework

#### Implementation Progress
| Phase | Component | Status | Files | Notes |
|-------|-----------|--------|-------|-------|
| 1 | URL Parsing | 🟡 Partial | `url.zig` | Basic structure using std.Uri |
| 2 | Basic Connection | ⏳ Pending | `connection.zig` | Stub implementation |
| 3 | Request Serialization | ⏳ Pending | `request.zig` | Stub implementation |
| 4 | Response Parsing | ⏳ Pending | `response.zig` | Stub implementation |
| 5 | Basic HTTP Client | ⏳ Pending | `client.zig` | Main client stub |
| 6 | POST Support | ⏳ Pending | - | Not started |
| 7 | HTTPS Support | ⏳ Pending | - | Will use secsock |
| 8 | Connection Pooling | ⏳ Pending | `connection_pool.zig` | Stub implementation |
| 9 | Advanced Features | ⏳ Pending | `proxy.zig` | Includes proxy support |

## Project Structure

### Core Components
```
zzz/
├── src/
│   ├── lib.zig                    # Main library export
│   ├── http/
│   │   ├── lib.zig               # HTTP module exports (includes Client)
│   │   ├── server.zig            # HTTP server implementation
│   │   ├── router.zig            # Request routing
│   │   ├── client/               # NEW: HTTP client module
│   │   │   ├── lib.zig          # Client module exports
│   │   │   ├── client.zig       # HTTPClient main implementation
│   │   │   ├── connection.zig   # TCP/TLS connections
│   │   │   ├── connection_pool.zig # Connection pooling
│   │   │   ├── request.zig      # Request building/serialization
│   │   │   ├── response.zig     # Response parsing
│   │   │   ├── url.zig          # URL utilities
│   │   │   └── proxy.zig        # Proxy support
│   │   └── middlewares/          # Server middleware
│   └── core/                     # Core utilities
├── examples/                     # Example applications
├── docs/                        # Documentation
└── build.zig                    # Build configuration
```

### Key Files Status

#### Modified Files
- `src/http/lib.zig` - Added Client module export
- `test_arraylist.zig` - Test file for ArrayList migration

#### New Files (HTTP Client)
- `src/http/client/lib.zig` - Client module exports ✅
- `src/http/client/client.zig` - Main HTTPClient (stub)
- `src/http/client/connection.zig` - Connection management (stub)
- `src/http/client/connection_pool.zig` - Connection pooling (stub)
- `src/http/client/request.zig` - Request handling (stub)
- `src/http/client/response.zig` - Response parsing (stub)
- `src/http/client/url.zig` - URL utilities (partial implementation)
- `src/http/client/proxy.zig` - Proxy support (stub)

#### Documentation
- `ASYNC_CLIENT_ROADMAP.md` - Detailed implementation plan ✅
- `PROJECT_INDEX.md` - This file (current project state)

## Dependencies

### Core Dependencies
- **tardy** - Async runtime (integrated)
- **secsock** - TLS support (integrated)
- **jetzig** - Related framework

### Zig Version Compatibility
- **Current:** Zig 0.15.1
- **Migration Status:** Complete
- **Key Changes:** 
  - ArrayList API updates (requires allocator for operations)
  - Compression module API changes
  - Dependency updates for 0.15.1 compatibility

## Recent Commits
```
24d34e9 test: Verify all zzz tests pass with Zig 0.15.1
a507144 refactor: Complete zzz migration to Zig 0.15.1
19ae31a fix: Update compression module API for Zig 0.15.1
cb11354 refactor: Update ArrayList methods to pass allocator
ddb381a deps: Update dependencies to Zig 0.15.1 compatible versions
```

## Current Tasks

### Immediate Next Steps
1. **Complete Phase 1: URL Parsing**
   - [ ] Implement QueryParams struct and methods
   - [ ] Add comprehensive URL parsing tests
   - [ ] Create url_test.zig
   - [ ] Verify all URL edge cases

2. **Begin Phase 2: Basic Connection**
   - [ ] Implement Connection.init()
   - [ ] Add TCP connection support
   - [ ] Implement send/receive methods
   - [ ] Create connection tests

3. **Testing Infrastructure**
   - [ ] Set up test framework for client
   - [ ] Add httpbin.org integration tests
   - [ ] Create example programs

### Medium-term Goals
- Complete Phases 1-5 for basic HTTP functionality
- Add HTTPS support (Phase 7)
- Implement connection pooling (Phase 8)
- Full test coverage

### Long-term Vision
- Feature parity with modern HTTP clients
- WebSocket support
- HTTP/2 support
- Comprehensive middleware system

## API Design

### Client Usage (Planned)
```zig
// Simple GET request
var client = try HTTPClient.init(allocator, runtime);
defer client.deinit();

const response = try client.get("https://api.example.com/data");
defer response.deinit();

if (response.is_success()) {
    const data = try response.json(MyStruct);
    // Use data...
}

// Advanced request with builder
var request = RequestBuilder.init(allocator)
    .method(.POST)
    .url("https://api.example.com/users")
    .header("Authorization", "Bearer token")
    .json(.{ .name = "John", .age = 30 })
    .timeout(5000)
    .build();

const response = try client.request(request);
```

## Testing Strategy

### Unit Tests
- URL parsing without network
- Request serialization
- Response parsing
- Connection pool logic

### Integration Tests
- Real HTTP/HTTPS requests
- Connection pooling verification
- Redirect following
- Error handling

### Performance Goals
- <3s load time on 3G
- 100+ concurrent requests
- <10MB memory with 100 connections
- 50% latency reduction with pooling

## Documentation Status

### Available
- [ASYNC_CLIENT_ROADMAP.md](ASYNC_CLIENT_ROADMAP.md) - Detailed implementation plan
- [README.md](README.md) - Project overview
- [docs/getting_started.md](docs/getting_started.md) - Server framework guide
- [docs/https.md](docs/https.md) - HTTPS server setup

### Needed
- HTTP client user guide
- API reference documentation
- Migration guide from other clients
- Performance tuning guide

## Build & Development

### Build Commands
```bash
# Build the library
zig build

# Run tests
zig build test

# Run specific example
zig build run-example-basic

# Build with optimizations
zig build -Doptimize=ReleaseFast
```

### Development Workflow
1. Make changes to client module
2. Run tests: `zig test src/http/client/[module]_test.zig`
3. Test with examples
4. Update documentation
5. Mark phase complete in roadmap

## Contributing

### Current Priorities
1. HTTP client implementation (following roadmap)
2. Test coverage improvements
3. Documentation updates
4. Performance optimizations

### Code Style
- Follow existing patterns in codebase
- Use allocator for all dynamic memory
- Implement proper error handling
- Add comprehensive tests
- Document public APIs

## Resources

### Internal
- [Roadmap](ASYNC_CLIENT_ROADMAP.md)
- [Examples](examples/)
- [Tests](src/tests.zig)

### External
- [Zig Documentation](https://ziglang.org/documentation/0.15.1/)
- [HTTP/1.1 Specification](https://www.rfc-editor.org/rfc/rfc7230)
- [tardy async runtime](https://github.com/mookums/tardy)

## Notes

### Known Issues
- HTTP client implementation incomplete
- No HTTP/2 support yet
- WebSocket support pending

### Design Decisions
- Using std.Uri for URL parsing
- Async-first design with tardy runtime
- Connection pooling from the start
- Modular architecture for extensibility

---

*This index provides a comprehensive overview of the zzz project's current state, focusing on the ongoing HTTP client implementation. It serves as a central reference for developers working on or with the project.*