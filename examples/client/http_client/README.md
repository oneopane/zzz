# HTTP Client Example

This example demonstrates how to use the ZZZ HTTP client with Tardy's async runtime.

## Features Demonstrated

1. **Basic GET Requests** - Making simple HTTP GET requests and handling responses
2. **HEAD Requests** - Requesting headers only without body content
3. **Redirect Handling** - Automatic following of HTTP redirects (301, 302, etc.)
4. **JSON Responses** - Handling JSON API responses
5. **Status Code Handling** - Working with different HTTP status codes (200, 404, 500)

## Running the Example

```bash
# From the zzz project root:
zig build run-http-client-example

# Or compile and run directly:
zig build-exe examples/http_client/main.zig -I src --deps zzz,tardy
./main
```

## Code Structure

The example is organized into several functions:

- `main()` - Sets up the allocator and Tardy runtime
- `run_examples()` - Initializes the HTTP client and runs all examples
- `example_get_request()` - Demonstrates basic GET requests
- `example_head_request()` - Shows HEAD request usage
- `example_redirect_handling()` - Tests redirect following
- `example_json_response()` - Handles JSON API responses
- `example_status_codes()` - Tests different HTTP status codes

## Key Concepts

### Tardy Integration

The HTTP client requires Tardy's async runtime. All HTTP operations must be run within a Tardy task:

```zig
try rt.spawn(.{ rt, allocator }, run_examples, stack_size);
```

### Response Handling

Always use `defer response.deinit()` to clean up response resources:

```zig
var response = try client.get(url);
defer response.deinit();
```

### Error Handling

HTTP operations can fail for various reasons. Always handle errors appropriately:

```zig
var response = client.get(url) catch |err| {
    log.err("Request failed: {}", .{err});
    return err;
};
```

## Configuration

The example uses httpbin.org as a test server. You can modify the `Config` struct to use different endpoints:

```zig
const Config = struct {
    const stack_size = 1024 * 1024; // 1MB stack
    const httpbin_base = "http://httpbin.org";
};
```

## Output

The example produces structured log output showing:
- Request URLs
- Response status codes
- Headers (Content-Type, Server, etc.)
- Body size and preview
- Success/redirect status
- Error conditions

## Next Steps

- Try modifying the URLs to test against your own APIs
- Experiment with different HTTP methods (when implemented)
- Add custom headers to requests
- Parse JSON responses into Zig structures