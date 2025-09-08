# Model Context Protocol (MCP) Specification and Implementation Guide

## Executive Summary

The Model Context Protocol (MCP) is an open standard developed by Anthropic in November 2024 that standardizes how AI applications integrate with external data sources and tools. Built on JSON-RPC 2.0, MCP enables LLM applications to securely and efficiently interact with external services through a client-server architecture that emphasizes user consent, data privacy, and tool safety.

This document provides comprehensive technical specifications for implementing MCP within the zzz HTTP framework, covering protocol details, architectural patterns, security considerations, and performance optimization strategies.

## 1. MCP Protocol Overview

### 1.1 Core Purpose

MCP addresses the "N×M problem" where M different AI applications need to integrate with N different tools/systems, requiring M×N custom integrations. MCP transforms this into an "M+N problem" by providing a universal protocol that any AI application can use to interact with any MCP-compliant service.

### 1.2 Design Principles

- **Standardization**: Universal protocol for AI-external system integration
- **Security**: Human-in-the-loop design with explicit user consent
- **Privacy**: Data stays local unless explicitly permitted
- **Modularity**: Composable integrations and workflows
- **Performance**: Efficient message exchange with minimal overhead
- **Extensibility**: Support for custom transports and capabilities

### 1.3 Architecture Components

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│      Host       │    │     Client      │    │     Server      │
│ (LLM App like   │◄──►│ (MCP Protocol   │◄──►│ (External       │
│  Claude, GPT)   │    │  Implementation)│    │  Service/Tool)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

**Host**: The AI-powered application users interact with
**Client**: MCP implementation within the host managing server connections
**Server**: External services exposing tools, resources, and prompts via MCP

## 2. Protocol Specification Details

### 2.1 Message Format and Structure

MCP uses JSON-RPC 2.0 as its wire format with UTF-8 encoding mandatory. Three fundamental message types:

#### 2.1.1 Request Messages
```json
{
  "jsonrpc": "2.0",
  "id": "string | number",
  "method": "string",
  "params": { /* optional parameters */ }
}
```

#### 2.1.2 Response Messages
```json
{
  "jsonrpc": "2.0",
  "id": "string | number",
  "result": { /* success response */ },
  "error": {
    "code": "number",
    "message": "string",
    "data": "unknown"
  }
}
```

#### 2.1.3 Notification Messages
```json
{
  "jsonrpc": "2.0",
  "method": "string",
  "params": { /* optional parameters */ }
}
```

### 2.2 Transport Mechanisms

#### 2.2.1 STDIO Transport
- **Use Case**: Local integrations where server runs as subprocess
- **Communication**: JSON-RPC messages via stdin/stdout
- **Format**: Newline-delimited UTF-8 encoded messages
- **Security**: Inherits OS-level security, extremely low latency
- **Lifecycle**: Client launches server subprocess, manages lifecycle

#### 2.2.2 Streamable HTTP Transport
- **Use Case**: Remote servers, web-friendly deployments
- **Client-to-Server**: HTTP POST requests to `/mcp` endpoint
- **Server-to-Client**: Server-Sent Events (SSE) stream
- **Security**: HTTPS mandatory, Origin header validation, localhost binding
- **Session Management**: Cryptographically secure session IDs
- **Authentication**: OAuth 2.0/2.1 with Authorization Code + PKCE

#### 2.2.3 Custom Transports
- Protocol-agnostic design allows custom transport implementations
- Must preserve JSON-RPC message format and lifecycle requirements
- Transport interface requires: `start()`, `send()`, `close()` methods
- Event handling: `onclose`, `onerror`, `onmessage` callbacks

### 2.3 Core Protocol Methods

#### 2.3.1 Initialization Sequence
1. **initialize**: Client sends supported protocol version and capabilities
2. **initialized**: Client confirms readiness after server response
3. **ping**: Heartbeat mechanism for connection health

```json
// Initialize request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-03-26",
    "capabilities": {
      "tools": {},
      "resources": {},
      "prompts": {},
      "sampling": {}
    },
    "clientInfo": {
      "name": "zzz-mcp-client",
      "version": "1.0.0"
    }
  }
}
```

#### 2.3.2 Tool Methods
- **tools/list**: Discover available tools with pagination support
- **tools/call**: Execute tool with name and arguments

```json
// Tool execution
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "get_weather",
    "arguments": {
      "location": "New York",
      "units": "celsius"
    }
  }
}
```

#### 2.3.3 Resource Methods
- **resources/list**: List available data resources
- **resources/read**: Retrieve specific resource content
- **resources/subscribe**: Subscribe to resource changes (if supported)

#### 2.3.4 Prompt Methods
- **prompts/list**: List available prompt templates
- **prompts/get**: Retrieve specific prompt with interpolation

### 2.4 Capability Negotiation

MCP uses explicit capability negotiation during initialization:

```json
{
  "capabilities": {
    "tools": {
      "listChanged": true
    },
    "resources": {
      "subscribe": true,
      "listChanged": true
    },
    "prompts": {
      "listChanged": true
    },
    "sampling": {}
  }
}
```

### 2.5 Error Handling and Status Codes

#### 2.5.1 Standard JSON-RPC Error Codes
- `-32700`: Parse error
- `-32600`: Invalid Request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

#### 2.5.2 MCP-Specific Error Codes
- `-32000` to `-32099`: Server-defined errors
- Authentication errors: Invalid/missing/expired tokens
- Authorization errors: Insufficient permissions
- Resource errors: Not found, access denied
- Tool errors: Execution failure, timeout

## 3. MCP Client Requirements

### 3.1 Core Client Functionality

#### 3.1.1 Connection Management
- Establish and maintain connections to multiple MCP servers
- Handle transport-specific connection logic (stdio, HTTP+SSE)
- Implement connection pooling and reuse strategies
- Graceful connection failure handling and retry logic

#### 3.1.2 Protocol Lifecycle
```zig
const MCPClient = struct {
    transport: Transport,
    capabilities: ClientCapabilities,
    servers: std.HashMap([]const u8, ServerConnection),
    
    pub fn initialize(self: *MCPClient, server_config: ServerConfig) !void {
        // Send initialize request
        // Handle capability negotiation
        // Send initialized notification
    }
    
    pub fn listTools(self: *MCPClient, server_id: []const u8) ![]Tool {
        // Send tools/list request
        // Parse response
        // Return tool definitions
    }
    
    pub fn callTool(self: *MCPClient, server_id: []const u8, name: []const u8, args: anytype) !ToolResult {
        // Validate tool exists
        // Send tools/call request
        // Handle response/error
    }
};
```

### 3.2 Request/Response Handling

#### 3.2.1 Asynchronous Operations
- Non-blocking request handling using zzz's async runtime
- Request queuing and batching for performance
- Timeout handling and cancellation support
- Parallel request execution to multiple servers

#### 3.2.2 Message Routing
- Route requests to appropriate server connections
- Handle bidirectional communication (server-initiated requests)
- Manage request/response correlation with unique IDs
- Support for notifications (one-way messages)

### 3.3 Resource Management

#### 3.3.1 Tool Discovery and Caching
- Cache tool definitions to reduce discovery overhead
- Implement cache invalidation on `tools/list_changed` notifications
- Support dynamic tool discovery during runtime
- Validate tool schemas before execution

#### 3.3.2 Resource Access Patterns
```zig
const ResourceManager = struct {
    cache: std.HashMap([]const u8, Resource),
    subscriptions: std.HashMap([]const u8, ResourceSubscription),
    
    pub fn getResource(self: *ResourceManager, uri: []const u8) !Resource {
        if (self.cache.get(uri)) |cached| {
            return cached;
        }
        
        const resource = try self.fetchResource(uri);
        try self.cache.put(uri, resource);
        return resource;
    }
    
    pub fn subscribeToResource(self: *ResourceManager, uri: []const u8, callback: ResourceCallback) !void {
        // Send resources/subscribe request
        // Store callback for updates
    }
};
```

### 3.4 Security and Authentication

#### 3.4.1 User Consent Framework
- Implement explicit user authorization for all tool/resource access
- Provide clear UI for reviewing pending operations
- Store user preferences and permission grants
- Support revocation of previously granted permissions

#### 3.4.2 Authentication Handling
```zig
const AuthManager = struct {
    oauth_client: OAuth2Client,
    token_store: TokenStore,
    
    pub fn authenticate(self: *AuthManager, server_config: ServerConfig) !AuthToken {
        // Implement OAuth 2.0 Authorization Code + PKCE flow
        // Store tokens securely
        // Handle token refresh
    }
    
    pub fn addAuthHeaders(self: *AuthManager, request: *HttpRequest) !void {
        const token = try self.getValidToken();
        try request.addHeader("Authorization", "Bearer {s}", .{token.access_token});
    }
};
```

## 4. MCP Server Requirements

### 4.1 Core Server Functionality

#### 4.1.1 Service Discovery and Advertisement
- Expose server capabilities during initialization
- Provide tool definitions with schemas and descriptions
- Advertise available resources and their types
- Support capability updates via notifications

#### 4.1.2 Request Processing Pipeline
```zig
const MCPServer = struct {
    router: Router,
    tools: std.HashMap([]const u8, Tool),
    resources: std.HashMap([]const u8, Resource),
    prompts: std.HashMap([]const u8, Prompt),
    
    pub fn handleRequest(self: *MCPServer, request: JsonRpcRequest) !JsonRpcResponse {
        switch (request.method) {
            "initialize" => return self.handleInitialize(request),
            "tools/list" => return self.handleToolsList(request),
            "tools/call" => return self.handleToolCall(request),
            "resources/list" => return self.handleResourcesList(request),
            "resources/read" => return self.handleResourceRead(request),
            else => return JsonRpcError.methodNotFound(),
        }
    }
};
```

### 4.2 Tool Execution Framework

#### 4.2.1 Tool Registration and Validation
```zig
const Tool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: JsonSchema,
    handler: ToolHandler,
    
    pub fn validate(self: *const Tool, args: anytype) !void {
        // Validate arguments against input_schema
        // Throw validation errors if invalid
    }
    
    pub fn execute(self: *const Tool, ctx: *ExecutionContext, args: anytype) !ToolResult {
        try self.validate(args);
        return self.handler.call(ctx, args);
    }
};

const ToolHandler = union(enum) {
    sync: fn(*ExecutionContext, anytype) anyerror!ToolResult,
    async: fn(*ExecutionContext, anytype) anyerror!ToolResult,
};
```

#### 4.2.2 Execution Context and Isolation
- Provide execution context with user information and permissions
- Implement sandboxing for tool execution security
- Support timeout and resource limits per tool
- Handle tool execution failures gracefully

### 4.3 Resource Provision System

#### 4.3.1 Resource Types and Management
```zig
const Resource = struct {
    uri: []const u8,
    name: []const u8,
    description: []const u8,
    mime_type: []const u8,
    provider: ResourceProvider,
    
    pub fn read(self: *const Resource, ctx: *ExecutionContext) !ResourceContent {
        return self.provider.read(ctx, self.uri);
    }
};

const ResourceProvider = union(enum) {
    file: FileProvider,
    database: DatabaseProvider,
    api: ApiProvider,
    memory: MemoryProvider,
};
```

#### 4.3.2 Resource Change Notifications
- Implement resource subscription mechanism
- Send notifications when subscribed resources change
- Support batch notifications for efficiency
- Handle subscription lifecycle management

### 4.4 State Management and Session Handling

#### 4.4.1 Connection State
```zig
const ServerSession = struct {
    id: []const u8,
    client_info: ClientInfo,
    capabilities: ClientCapabilities,
    auth_context: AuthContext,
    subscriptions: std.ArrayList(ResourceSubscription),
    
    pub fn isAuthorized(self: *const ServerSession, operation: Operation) bool {
        return self.auth_context.hasPermission(operation);
    }
    
    pub fn addSubscription(self: *ServerSession, subscription: ResourceSubscription) !void {
        try self.subscriptions.append(subscription);
    }
};
```

#### 4.4.2 Session Lifecycle Management
- Track active client connections and their state
- Clean up resources when connections close
- Handle session timeout and cleanup
- Support session persistence across reconnections

### 4.5 Performance and Scalability

#### 4.5.1 Request Processing Optimization
- Implement request batching for efficiency
- Use connection pooling for external resource access
- Cache frequently accessed resources
- Implement backpressure handling for high load

#### 4.5.2 Resource Usage Management
```zig
const ResourceLimits = struct {
    max_concurrent_tools: u32,
    max_memory_per_tool: usize,
    max_execution_time: u64, // milliseconds
    max_resource_size: usize,
};

const ResourceMonitor = struct {
    limits: ResourceLimits,
    current_usage: ResourceUsage,
    
    pub fn checkLimits(self: *ResourceMonitor, operation: Operation) !void {
        if (self.current_usage.exceedsLimits(self.limits, operation)) {
            return error.ResourceLimitExceeded;
        }
    }
};
```

## 5. Integration with zzz HTTP Framework

### 5.1 Architecture Integration

#### 5.1.1 MCP Server as zzz Middleware
```zig
const MCPMiddleware = struct {
    mcp_server: MCPServer,
    
    pub fn handler(ctx: *const Context, next: anytype) !Respond {
        const path = ctx.request.path();
        
        if (std.mem.eql(u8, path, "/mcp")) {
            return self.handleMCPRequest(ctx);
        }
        
        return next.call(ctx);
    }
    
    fn handleMCPRequest(self: *MCPMiddleware, ctx: *const Context) !Respond {
        const json_body = try ctx.request.json(JsonRpcRequest);
        const response = try self.mcp_server.handleRequest(json_body);
        
        return ctx.response.apply(.{
            .status = .OK,
            .mime = http.Mime.JSON,
            .body = try std.json.stringify(response, .{}, ctx.allocator),
        });
    }
};
```

#### 5.1.2 Transport Layer Integration
```zig
const MCPTransport = union(enum) {
    stdio: StdioTransport,
    http: HttpTransport,
    
    const HttpTransport = struct {
        server: *zzz.Server,
        endpoint: []const u8,
        sse_clients: std.HashMap([]const u8, SSEClient),
        
        pub fn start(self: *HttpTransport, config: TransportConfig) !void {
            // Configure zzz server with MCP endpoint
            // Setup SSE endpoint for server-to-client communication
            // Handle authentication and security headers
        }
        
        pub fn sendToClient(self: *HttpTransport, client_id: []const u8, message: JsonRpcMessage) !void {
            if (self.sse_clients.get(client_id)) |sse_client| {
                try sse_client.send(message);
            }
        }
    };
};
```

### 5.2 Async Integration with Tardy Runtime

#### 5.2.1 Async Tool Execution
```zig
pub fn executeToolAsync(runtime: *tardy.Runtime, tool: *Tool, args: anytype) !void {
    const task = runtime.spawn(struct {
        fn run(rt: *tardy.Runtime, t: *Tool, a: anytype) !void {
            const result = try t.execute(a);
            // Send result back through channel or callback
        }
    }.run, .{ runtime, tool, args });
    
    return task;
}
```

#### 5.2.2 Resource Streaming
```zig
const ResourceStreamer = struct {
    runtime: *tardy.Runtime,
    
    pub fn streamResource(self: *ResourceStreamer, resource: *Resource, writer: anytype) !void {
        var buffer: [4096]u8 = undefined;
        const reader = try resource.getReader();
        
        while (true) {
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) break;
            
            try writer.write(buffer[0..bytes_read]);
            
            // Yield to allow other tasks to run
            try self.runtime.yield();
        }
    }
};
```

### 5.3 Memory Management with zzz Patterns

#### 5.3.1 Pool Allocation for MCP Messages
```zig
const MCPMessagePool = struct {
    request_pool: std.heap.MemoryPool(JsonRpcRequest),
    response_pool: std.heap.MemoryPool(JsonRpcResponse),
    
    pub fn createRequest(self: *MCPMessagePool) !*JsonRpcRequest {
        return try self.request_pool.create();
    }
    
    pub fn destroyRequest(self: *MCPMessagePool, request: *JsonRpcRequest) void {
        self.request_pool.destroy(request);
    }
};
```

#### 5.3.2 Resource Cleanup Patterns
```zig
pub fn withMCPSession(allocator: std.mem.Allocator, config: SessionConfig, handler: anytype) !void {
    var session = try MCPSession.init(allocator, config);
    defer session.deinit();
    
    try handler(&session);
}
```

## 6. Security Model and Access Controls

### 6.1 Authentication and Authorization

#### 6.1.1 OAuth 2.0 Implementation
```zig
const OAuth2Flow = struct {
    client_id: []const u8,
    redirect_uri: []const u8,
    state: []const u8,
    code_verifier: []const u8,
    
    pub fn generateAuthUrl(self: *OAuth2Flow, scopes: []const []const u8) ![]const u8 {
        const code_challenge = try self.generateCodeChallenge();
        
        return std.fmt.allocPrint(allocator, 
            "https://auth.example.com/oauth/authorize?response_type=code&client_id={s}&redirect_uri={s}&scope={s}&state={s}&code_challenge={s}&code_challenge_method=S256",
            .{ self.client_id, self.redirect_uri, scopes, self.state, code_challenge }
        );
    }
};
```

#### 6.1.2 Permission System
```zig
const Permission = enum {
    read_resources,
    execute_tools,
    subscribe_resources,
    sample_llm,
};

const PermissionManager = struct {
    user_permissions: std.HashMap([]const u8, std.EnumSet(Permission)),
    
    pub fn checkPermission(self: *PermissionManager, user_id: []const u8, permission: Permission) bool {
        if (self.user_permissions.get(user_id)) |perms| {
            return perms.contains(permission);
        }
        return false;
    }
    
    pub fn requestPermission(self: *PermissionManager, user_id: []const u8, permission: Permission) !bool {
        // Present user consent dialog
        // Return user's decision
        // Update permissions if granted
    }
};
```

### 6.2 Input Validation and Sanitization

#### 6.2.1 JSON Schema Validation
```zig
const SchemaValidator = struct {
    schemas: std.HashMap([]const u8, JsonSchema),
    
    pub fn validate(self: *SchemaValidator, schema_name: []const u8, data: anytype) !void {
        const schema = self.schemas.get(schema_name) orelse return error.SchemaNotFound;
        
        // Implement JSON schema validation
        // Throw specific validation errors
    }
};
```

#### 6.2.2 Sanitization Pipeline
```zig
pub fn sanitizeToolArguments(args: anytype) !anytype {
    // Remove potentially dangerous fields
    // Validate string lengths and types
    // Escape special characters
    // Return sanitized arguments
}
```

### 6.3 Transport Security

#### 6.3.1 HTTPS Configuration
```zig
const TLSConfig = struct {
    cert_path: []const u8,
    key_path: []const u8,
    min_version: TLSVersion,
    cipher_suites: []const CipherSuite,
    
    pub fn apply(self: *TLSConfig, server: *zzz.Server) !void {
        try server.tls.setCertificate(self.cert_path, self.key_path);
        try server.tls.setMinVersion(self.min_version);
        try server.tls.setCipherSuites(self.cipher_suites);
    }
};
```

#### 6.3.2 Origin Validation
```zig
pub fn validateOrigin(ctx: *const Context, allowed_origins: []const []const u8) !void {
    const origin = ctx.request.header("Origin") orelse return error.MissingOrigin;
    
    for (allowed_origins) |allowed| {
        if (std.mem.eql(u8, origin, allowed)) {
            return;
        }
    }
    
    return error.InvalidOrigin;
}
```

## 7. Performance Considerations

### 7.1 Benchmarking and Optimization

#### 7.1.1 Performance Metrics
```zig
const MCPMetrics = struct {
    request_count: std.atomic.Atomic(u64),
    request_duration: std.atomic.Atomic(u64),
    active_connections: std.atomic.Atomic(u32),
    tool_execution_time: std.HashMap([]const u8, u64),
    
    pub fn recordRequest(self: *MCPMetrics, duration_ns: u64) void {
        _ = self.request_count.fetchAdd(1, .Monotonic);
        _ = self.request_duration.fetchAdd(duration_ns, .Monotonic);
    }
    
    pub fn getAverageRequestTime(self: *MCPMetrics) u64 {
        const count = self.request_count.load(.Monotonic);
        const total_duration = self.request_duration.load(.Monotonic);
        return if (count > 0) total_duration / count else 0;
    }
};
```

#### 7.1.2 Connection Pooling
```zig
const ConnectionPool = struct {
    available: std.fifo.LinearFifo(*Connection, .Dynamic),
    active: std.HashMap(*Connection, bool),
    max_connections: u32,
    
    pub fn getConnection(self: *ConnectionPool) !*Connection {
        if (self.available.readItem()) |conn| {
            try self.active.put(conn, true);
            return conn;
        }
        
        if (self.active.count() < self.max_connections) {
            const conn = try Connection.create();
            try self.active.put(conn, true);
            return conn;
        }
        
        return error.ConnectionPoolExhausted;
    }
    
    pub fn releaseConnection(self: *ConnectionPool, conn: *Connection) !void {
        _ = self.active.remove(conn);
        try self.available.writeItem(conn);
    }
};
```

### 7.2 Memory Optimization

#### 7.2.1 Message Buffer Reuse
```zig
const MessageBufferPool = struct {
    small_buffers: std.fifo.LinearFifo([]u8, .Dynamic), // 1KB buffers
    medium_buffers: std.fifo.LinearFifo([]u8, .Dynamic), // 8KB buffers
    large_buffers: std.fifo.LinearFifo([]u8, .Dynamic), // 32KB buffers
    
    pub fn getBuffer(self: *MessageBufferPool, size: usize) ![]u8 {
        if (size <= 1024) {
            if (self.small_buffers.readItem()) |buf| return buf;
            return try allocator.alloc(u8, 1024);
        } else if (size <= 8192) {
            if (self.medium_buffers.readItem()) |buf| return buf;
            return try allocator.alloc(u8, 8192);
        } else {
            if (self.large_buffers.readItem()) |buf| return buf;
            return try allocator.alloc(u8, 32768);
        }
    }
    
    pub fn returnBuffer(self: *MessageBufferPool, buf: []u8) void {
        switch (buf.len) {
            1024 => self.small_buffers.writeItem(buf) catch {},
            8192 => self.medium_buffers.writeItem(buf) catch {},
            32768 => self.large_buffers.writeItem(buf) catch {},
            else => allocator.free(buf),
        }
    }
};
```

#### 7.2.2 Resource Streaming for Large Data
```zig
const StreamingResource = struct {
    provider: ResourceProvider,
    chunk_size: usize,
    
    pub fn stream(self: *StreamingResource, writer: anytype) !void {
        var buffer = try allocator.alloc(u8, self.chunk_size);
        defer allocator.free(buffer);
        
        var reader = try self.provider.getReader();
        defer reader.close();
        
        while (try reader.read(buffer)) |bytes_read| {
            if (bytes_read == 0) break;
            try writer.write(buffer[0..bytes_read]);
        }
    }
};
```

## 8. Testing Strategies

### 8.1 Unit Testing Framework

#### 8.1.1 Protocol Message Testing
```zig
test "JSON-RPC request parsing" {
    const json_text = 
        \\{
        \\  "jsonrpc": "2.0",
        \\  "id": 1,
        \\  "method": "tools/call",
        \\  "params": {
        \\    "name": "test_tool",
        \\    "arguments": {"arg1": "value1"}
        \\  }
        \\}
    ;
    
    const request = try std.json.parseFromSlice(JsonRpcRequest, allocator, json_text, .{});
    defer request.deinit();
    
    try std.testing.expectEqualStrings("2.0", request.value.jsonrpc);
    try std.testing.expectEqual(@as(u32, 1), request.value.id.number);
    try std.testing.expectEqualStrings("tools/call", request.value.method);
}
```

#### 8.1.2 Tool Execution Testing
```zig
test "tool execution with validation" {
    var tool = Tool{
        .name = "test_tool",
        .description = "Test tool for unit testing",
        .input_schema = createTestSchema(),
        .handler = .{ .sync = testToolHandler },
    };
    
    const args = TestArgs{ .input = "test_value" };
    const result = try tool.execute(&test_context, args);
    
    try std.testing.expectEqualStrings("test_result", result.output);
}

fn testToolHandler(ctx: *ExecutionContext, args: TestArgs) !ToolResult {
    return ToolResult{ .output = "test_result" };
}
```

### 8.2 Integration Testing

#### 8.2.1 End-to-End Protocol Testing
```zig
test "full MCP protocol flow" {
    // Setup test server and client
    var server = try MCPServer.init(allocator, test_config);
    defer server.deinit();
    
    var client = try MCPClient.init(allocator, test_transport);
    defer client.deinit();
    
    // Test initialization
    try client.initialize(server_info);
    
    // Test tool discovery
    const tools = try client.listTools();
    try std.testing.expect(tools.len > 0);
    
    // Test tool execution
    const result = try client.callTool("test_tool", .{ .input = "test" });
    try std.testing.expectEqualStrings("expected_output", result.output);
}
```

#### 8.2.2 Transport Layer Testing
```zig
test "HTTP transport with SSE" {
    var transport = try HttpTransport.init(allocator, .{
        .endpoint = "/mcp",
        .port = 8080,
    });
    defer transport.deinit();
    
    try transport.start();
    
    // Test HTTP POST request
    const response = try testHttpRequest("POST", "/mcp", test_json_rpc);
    try std.testing.expectEqual(@as(u16, 200), response.status);
    
    // Test SSE stream
    const sse_client = try transport.openSSEStream();
    defer sse_client.close();
    
    try transport.sendToClient(sse_client.id, test_notification);
    const received = try sse_client.waitForMessage();
    try std.testing.expectEqualDeep(test_notification, received);
}
```

### 8.3 Performance Testing

#### 8.3.1 Load Testing Framework
```zig
test "concurrent tool execution load test" {
    const concurrent_requests = 1000;
    const server = try setupTestServer();
    defer server.deinit();
    
    var threads: [10]std.Thread = undefined;
    var results: [10]TestResult = undefined;
    
    for (threads) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, loadTestWorker, .{ server, concurrent_requests / 10, &results[i] });
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    // Analyze results
    var total_requests: u64 = 0;
    var total_duration: u64 = 0;
    for (results) |result| {
        total_requests += result.request_count;
        total_duration += result.total_duration;
    }
    
    const avg_request_time = total_duration / total_requests;
    try std.testing.expect(avg_request_time < 1000_000); // Less than 1ms average
}
```

#### 8.3.2 Memory Usage Testing
```zig
test "memory usage under load" {
    const initial_memory = getCurrentMemoryUsage();
    
    // Run load test
    try runLoadTest(1000);
    
    // Force garbage collection
    std.heap.page_allocator.collectGarbage();
    
    const final_memory = getCurrentMemoryUsage();
    const memory_growth = final_memory - initial_memory;
    
    // Memory growth should be minimal (< 10MB for 1000 requests)
    try std.testing.expect(memory_growth < 10 * 1024 * 1024);
}
```

## 9. Implementation Roadmap for zzz

### 9.1 Phase 1: Core Protocol Foundation (Weeks 1-2)
- [ ] JSON-RPC 2.0 message parsing and generation
- [ ] Basic transport abstraction layer
- [ ] STDIO transport implementation
- [ ] Message routing and correlation
- [ ] Error handling framework
- [ ] Unit tests for core protocol components

### 9.2 Phase 2: Server Implementation (Weeks 3-4)
- [ ] MCP server framework with zzz integration
- [ ] Tool registration and execution system
- [ ] Resource provider abstraction
- [ ] Capability negotiation implementation
- [ ] Basic HTTP transport with zzz middleware
- [ ] Integration tests with simple tools

### 9.3 Phase 3: Client Implementation (Weeks 5-6)
- [ ] MCP client library
- [ ] Server connection management
- [ ] Tool discovery and execution
- [ ] Resource access patterns
- [ ] Connection pooling and reuse
- [ ] Client-side caching mechanisms

### 9.4 Phase 4: HTTP+SSE Transport (Weeks 7-8)
- [ ] Server-Sent Events implementation
- [ ] Bidirectional communication support
- [ ] Session management and persistence
- [ ] HTTP transport security (HTTPS, headers)
- [ ] Load balancing for multiple clients
- [ ] Performance optimization and benchmarking

### 9.5 Phase 5: Security and Authentication (Weeks 9-10)
- [ ] OAuth 2.0 authentication flow
- [ ] Permission system implementation
- [ ] Input validation and sanitization
- [ ] Transport security (TLS configuration)
- [ ] User consent management
- [ ] Security audit and testing

### 9.6 Phase 6: Advanced Features (Weeks 11-12)
- [ ] Resource subscriptions and notifications
- [ ] Prompt template system
- [ ] Custom transport implementations
- [ ] Advanced caching strategies
- [ ] Monitoring and metrics collection
- [ ] Documentation and examples

### 9.7 Phase 7: Production Readiness (Weeks 13-14)
- [ ] Comprehensive test suite
- [ ] Performance benchmarking
- [ ] Memory optimization
- [ ] Error recovery and resilience
- [ ] Production deployment guide
- [ ] Community feedback integration

## 10. Conclusion

The Model Context Protocol represents a significant advancement in AI system integration, providing a standardized, secure, and performant way for LLM applications to interact with external tools and data sources. By implementing MCP support within the zzz HTTP framework, we can leverage Zig's performance characteristics and zzz's architectural strengths to create a highly efficient MCP implementation.

This specification provides the foundation for a comprehensive MCP implementation that maintains security, performance, and usability while integrating seamlessly with zzz's existing architecture. The phased implementation approach ensures steady progress while maintaining code quality and allowing for iterative improvement based on real-world usage and community feedback.

The combination of MCP's standardized protocol with zzz's performance-oriented architecture positions this implementation to be a leading solution for high-performance AI-tool integration scenarios, particularly in environments where low latency and efficient resource utilization are critical requirements.

## References

1. Model Context Protocol Official Specification: https://modelcontextprotocol.io/specification/2025-03-26
2. MCP GitHub Repository: https://github.com/modelcontextprotocol/modelcontextprotocol
3. JSON-RPC 2.0 Specification: https://www.jsonrpc.org/specification
4. OAuth 2.0 Authorization Framework: https://tools.ietf.org/html/rfc6749
5. Server-Sent Events Specification: https://html.spec.whatwg.org/multipage/server-sent-events.html
6. zzz HTTP Framework: https://github.com/zxhoper/zig-http-zzz
7. Tardy Async Runtime: https://github.com/mookums/tardy