# HTTP Client Examples

This directory contains examples of using zzz's HTTP client capabilities.

## Examples

### basic
A minimal example that demonstrates how to perform a simple GET request using the HTTP client.

**Features:**
- Single GET request to httpbin.org
- Display response status
- Show response headers
- Print response body

**Run:**
```bash
zig build run_client_basic
```

### http_client
A comprehensive HTTP client example showing various request methods and features.

**Features:**
- GET, POST, PUT, DELETE requests
- Custom headers
- Request body handling
- Error handling
- Multiple endpoints

**Run:**
```bash
zig build run_http_client
```

### http_client_simple
A simplified version showing common HTTP client use cases.

**Features:**
- Simple GET requests
- HEAD requests
- Status code handling
- JSON API responses

**Run:**
```bash
zig build run_http_client_simple
```

## Building

To build all client examples:
```bash
zig build client_basic
zig build http_client
zig build http_client_simple
```