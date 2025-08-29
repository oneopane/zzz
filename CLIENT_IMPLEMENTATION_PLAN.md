# HTTP Client Implementation Plan for zzz

## Overview
This document outlines the implementation steps for adding an HTTP client to the zzz library that integrates cleanly with the existing server architecture, supports both normal HTTP requests and SSE streaming, and enables easy API-to-API proxy patterns.

## Phase 1: Core Client Infrastructure

### 1.1 Create Basic Client Structure
- Create new file `src/http/client.zig`
- Define the `Client` struct with fields for allocator, runtime, and connection pool
- Define `ClientConfig` struct for configuration options (timeouts, max connections, keepalive settings)
- Implement `init()` and `deinit()` methods for the Client

### 1.2 Connection Pool Implementation
- Create new file `src/http/connection_pool.zig`
- Design connection pool structure to manage and reuse TCP/TLS connections
- Implement connection acquisition and release mechanisms
- Add connection lifecycle management (creation, validation, expiration)
- Implement connection limits and queuing strategies
- Add support for both HTTP and HTTPS connections using secsock

### 1.3 Client Response Structure
- Create `ClientResponse` struct in `src/http/client.zig`
- Include fields for status code, headers, body, and underlying socket
- Design response to support both buffered (normal HTTP) and streaming (SSE) modes
- Implement methods to access response data and convert to streaming modes

## Phase 2: Request Building and Sending

### 2.1 Extend Request Structure
- Modify `src/http/request.zig` to support client-side operations
- Add builder pattern methods for constructing requests (`.get()`, `.post()`, `.put()`, etc.)
- Implement header management methods (`.header()`, `.headers()`)
- Add request body handling for different content types
- Implement URL parsing and validation

### 2.2 Request Execution
- Implement `client.request()` method in Client struct
- Add HTTP/1.1 request serialization
- Implement request sending using tardy runtime and secsock
- Handle connection acquisition from pool
- Implement response parsing and deserialization
- Add proper error handling for network failures

### 2.3 DNS Resolution and Connection Establishment
- Integrate DNS resolution for hostnames
- Implement TCP connection establishment
- Add TLS/SSL support through secsock for HTTPS
- Handle connection timeouts and retries
- Implement proper certificate validation for HTTPS

## Phase 3: SSE Client Implementation

### 3.1 SSE Client Structure
- Create new file `src/http/sse_client.zig`
- Define `SSEClient` struct for consuming SSE streams
- Implement SSE event parser for incoming data
- Add buffering for partial event handling
- Design iterator interface for event consumption

### 3.2 SSE Stream Consumption
- Implement `.sse()` method on ClientResponse
- Create event parsing logic following SSE specification
- Handle reconnection with Last-Event-ID support
- Implement retry delay handling
- Add proper stream cleanup and connection closure

### 3.3 SSE Proxy Pattern
- Design efficient event forwarding mechanism
- Implement zero-copy event passing where possible
- Add transformation hooks for event modification
- Handle backpressure between client and server SSE streams
- Implement proper error propagation

## Phase 4: Server Integration

### 4.1 Server Configuration Updates
- Modify `ServerConfig` in `src/http/server.zig` to optionally accept a Client reference
- Update Server struct to store client reference
- Ensure client lifecycle is properly managed

### 4.2 Context Injection
- Modify server request handling to inject client into Context storage
- Update Context initialization in server connection handling
- Ensure client is available to all request handlers
- Add helper methods for retrieving client from context

### 4.3 Integration Testing
- Create example proxy handlers demonstrating the integration
- Test client injection and retrieval from context
- Verify connection pool sharing across requests
- Ensure proper cleanup on server shutdown

## Phase 5: Library Export and API Surface

### 5.1 Update Library Exports
- Add Client export to `src/http/lib.zig`
- Export SSEClient and related types
- Ensure all necessary types are publicly accessible
- Maintain backward compatibility with existing API

### 5.2 Documentation and Examples
- Create example showing standalone client usage
- Create example demonstrating proxy pattern
- Create example showing SSE streaming proxy
- Add comprehensive documentation comments
- Update README with client usage instructions

## Phase 6: Testing and Validation

### 6.1 Unit Tests
- Add tests for Client initialization and configuration
- Test connection pool behavior and limits
- Verify request building and serialization
- Test response parsing for various scenarios
- Add SSE event parsing tests

### 6.2 Integration Tests
- Test client against real HTTP servers
- Verify SSE stream consumption
- Test proxy patterns with server integration
- Validate connection reuse and pooling
- Test error handling and recovery scenarios

### 6.3 Performance Testing
- Benchmark connection pool performance
- Measure request/response latency
- Test SSE streaming throughput
- Validate memory usage and leak detection
- Compare performance with and without connection pooling

## Phase 7: Error Handling and Resilience

### 7.1 Network Error Handling
- Implement comprehensive error types for client operations
- Add timeout handling at multiple levels (connect, request, response)
- Implement retry logic with exponential backoff
- Handle partial response scenarios
- Add circuit breaker pattern for failing endpoints

### 7.2 Resource Management
- Ensure proper cleanup on all error paths
- Implement connection pool drainage on shutdown
- Add memory pressure handling
- Validate socket cleanup and file descriptor management
- Implement graceful degradation under load

## Phase 8: Advanced Features

### 8.1 HTTP/2 Preparation
- Design client architecture to support future HTTP/2
- Ensure connection pool can handle multiplexed connections
- Plan migration path for SSE to HTTP/2 Server-Sent Events

### 8.2 Observability
- Add metrics collection for client operations
- Implement request/response logging capabilities
- Add distributed tracing support preparation
- Include connection pool statistics
- Design hooks for monitoring integration

## Phase 9: Final Integration and Polish

### 9.1 Code Review and Refactoring
- Review all new code for consistency with zzz patterns
- Ensure proper error handling throughout
- Validate memory management and allocations
- Check for proper use of tardy runtime
- Verify secsock integration correctness

### 9.2 Documentation Finalization
- Complete API documentation
- Add migration guide for users
- Document best practices for proxy patterns
- Include performance tuning guidelines
- Create troubleshooting guide

### 9.3 Release Preparation
- Run full test suite
- Perform memory leak analysis
- Validate on multiple platforms
- Update version numbers
- Prepare release notes

## Success Criteria
- Client can make HTTP/HTTPS requests independently of server
- Server can optionally initialize with client for proxy scenarios
- SSE streams can be efficiently proxied through the server
- Connection pooling provides measurable performance benefits
- All existing server functionality remains unchanged
- Clean, intuitive API that follows zzz conventions
- Comprehensive test coverage for new functionality
- Documentation and examples for common use cases