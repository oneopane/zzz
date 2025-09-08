# mcp-integration

## Objective
Implement Model Context Protocol (MCP) client and server capabilities in zzz for standardized AI-tool integration

## Directory Structure
```
src/
├── lib.zig                      # Update to expose MCP module
└── mcp/
    ├── lib.zig                  # MCP module entry point
    ├── common/
    │   ├── protocol.zig         # JSON-RPC message types
    │   ├── errors.zig           # MCP error codes and handling
    │   ├── types.zig            # Shared types (Tool, Resource, etc.)
    │   └── transport.zig        # Transport interface
    ├── client/
    │   ├── client.zig           # MCPClient implementation
    │   ├── connection.zig       # Connection management
    │   └── session.zig          # Client session state
    └── server/
        ├── server.zig           # MCPServer implementation
        ├── handlers.zig         # Protocol method handlers
        ├── middleware.zig       # zzz middleware integration
        └── registry.zig         # Tool/resource registry

examples/
├── mcp_server_basic.zig         # Basic MCP server example
└── mcp_client_basic.zig         # Basic MCP client example
```

## Walking Skeleton Phases
**Philosophy**: Build minimal end-to-end functionality first

### Phase S1: Core Data Types
**Goal**: Minimal data structures
**Demo**: Can create and store basic MCP messages
- [ ] Create `src/mcp/common/protocol.zig` with JsonRpcRequest struct (id, method, params fields)
- [ ] Add JsonRpcResponse struct to `protocol.zig` (id, result, error fields)
- [ ] Create `src/mcp/common/errors.zig` with basic MCP error codes (-32700 to -32603)
- [ ] Add `src/mcp/lib.zig` to expose common module
- [ ] Update `src/lib.zig` to export mcp module
- [ ] Test in `src/mcp/common/protocol_test.zig`: roundtrip (create → serialize → parse)

### Phase S2: Basic Transport
**Goal**: Simple transport operations
**Demo**: Messages survive process boundary
- [ ] Create `src/mcp/common/transport.zig` with Transport interface (start, send, close)
- [ ] Implement StdioTransport in `src/mcp/common/stdio_transport.zig` (subprocess communication)
- [ ] Add message framing in StdioTransport (newline-delimited JSON)
- [ ] Create `src/mcp/server/server.zig` with basic message receiver
- [ ] Test in `src/mcp/common/stdio_transport_test.zig`: send/receive roundtrip
- [ ] Example in `examples/mcp_stdio_test.zig`: subprocess communication demo

### Phase S3: Minimal Service Layer
**Goal**: Working MCP surface
**Demo**: External client can call a tool
- [ ] Add initialize handler to `src/mcp/server/handlers.zig` (return capabilities)
- [ ] Create `src/mcp/common/types.zig` with Tool struct (name, description, handler)
- [ ] Implement tools/list handler in `handlers.zig` (return single hardcoded tool)
- [ ] Implement tools/call handler in `handlers.zig` (execute hardcoded "echo" tool)
- [ ] Create `src/mcp/client/client.zig` with initialize() and callTool() methods
- [ ] Integration test in `src/mcp/integration_test.zig`: client → server tool execution
- [ ] Example in `examples/mcp_server_basic.zig`: working MCP server with echo tool

## Enhancement Phases
**Philosophy**: Flesh out the skeleton systematically

### Phase E1: Robust Foundation
**Goal**: Production-ready core
- [ ] Extend `src/mcp/server/handlers.zig` with all protocol methods:
  - [ ] resources/list, resources/read handlers
  - [ ] prompts/list, prompts/get handlers
  - [ ] notifications/progress handler
- [ ] Update `src/mcp/common/errors.zig` with MCP-specific codes (-32000 to -32099)
- [ ] Create `src/mcp/server/registry.zig` for dynamic tool/resource registration
- [ ] Add `src/mcp/client/session.zig` for capability negotiation and state management
- [ ] Create `src/mcp/common/capabilities.zig` with ClientCapabilities and ServerCapabilities
- [ ] Protocol compliance tests in `src/mcp/protocol_compliance_test.zig`

### Phase E2: Advanced Features
**Goal**: Full feature set
- [ ] Create `src/mcp/common/http_transport.zig` with HTTP+SSE transport
- [ ] Add `src/mcp/server/middleware.zig` for zzz HTTP server integration
- [ ] Implement SSE endpoint in middleware.zig for server-to-client messages
- [ ] Create `src/mcp/client/connection.zig` with connection pooling
- [ ] Extend registry.zig to support multiple tools/resources with schemas
- [ ] Add `src/mcp/common/auth.zig` with OAuth 2.0 flow (Authorization Code + PKCE)
- [ ] Create `src/mcp/server/session_manager.zig` for multi-client sessions
- [ ] Integration test in `src/mcp/http_integration_test.zig`
- [ ] Example in `examples/mcp_server_http.zig`: HTTP-based MCP server

### Phase E3: Quality & Performance
**Goal**: Production optimization
- [ ] Integrate Tardy async runtime in `src/mcp/server/async_handlers.zig`
- [ ] Create `src/mcp/common/validation.zig` with JSON schema validation
- [ ] Add input sanitization to all handlers (prevent injection attacks)
- [ ] Create `src/mcp/server/sandbox.zig` for tool execution isolation
- [ ] Implement `src/mcp/common/metrics.zig` with performance counters
- [ ] Add memory pooling in `src/mcp/common/memory_pool.zig` for message buffers
- [ ] Create `src/mcp/server/rate_limiter.zig` for request throttling
- [ ] Performance benchmarks in `src/mcp/benchmark_test.zig`
- [ ] Load testing suite in `src/mcp/load_test.zig`
- [ ] Security audit checklist in `docs/mcp_security_audit.md`

## Build Configuration
```zig
// build.zig additions
const mcp_module = b.addModule("mcp", .{
    .root_source_file = b.path("src/mcp/lib.zig"),
    .imports = &.{
        .{ .name = "tardy", .module = tardy_module },
        .{ .name = "zzz", .module = zzz_module },
    },
});

// Test targets
const mcp_test = b.addTest(.{
    .root_source_file = b.path("src/mcp/test_all.zig"),
    .target = target,
    .optimize = optimize,
});
mcp_test.root_module.addImport("mcp", mcp_module);

// Examples
const mcp_server_example = b.addExecutable(.{
    .name = "mcp_server",
    .root_source_file = b.path("examples/mcp_server_basic.zig"),
    .target = target,
    .optimize = optimize,
});
mcp_server_example.root_module.addImport("mcp", mcp_module);
mcp_server_example.root_module.addImport("zzz", zzz_module);
```

## Integration Patterns

### zzz Middleware Integration
```zig
// src/mcp/server/middleware.zig
pub fn mcpMiddleware(mcp_server: *MCPServer) Middleware {
    return .{
        .handler = struct {
            fn handle(ctx: *const Context, _: void) !Respond {
                if (std.mem.eql(u8, ctx.request.path, "/mcp")) {
                    const json_body = try ctx.request.json(JsonRpcRequest);
                    const response = try mcp_server.handleRequest(json_body);
                    return ctx.response.apply(.{
                        .status = .OK,
                        .mime = http.Mime.JSON,
                        .body = try std.json.stringify(response, .{}, ctx.allocator),
                    });
                }
                return error.NotMCPRequest;
            }
        }.handle,
    };
}
```

### Tardy Async Integration
```zig
// src/mcp/server/async_handlers.zig
pub fn executeToolAsync(runtime: *tardy.Runtime, tool: *Tool, args: anytype) !void {
    const task = runtime.spawn(struct {
        fn run(t: *Tool, a: anytype) !ToolResult {
            return t.execute(a);
        }
    }.run, .{ tool, args });
    return task;
}
```

## Success Criteria
- **Skeleton Complete**: Working tool execution via STDIO transport
- **Enhancement Complete**: Full MCP spec compliance with HTTP+SSE
- **Quality Gate**: Security audit passed, <1ms tool execution latency