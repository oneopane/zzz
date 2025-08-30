const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

const tardy = @import("tardy");
const HTTPClient = @import("client.zig").HTTPClient;
const ClientRequest = @import("request.zig").ClientRequest;
const ClientResponse = @import("response.zig").ClientResponse;

test "HTTPClient init and deinit" {
    var rt = try tardy.Runtime.init(.{});
    defer rt.deinit();
    
    var client = try HTTPClient.init(testing.allocator, &rt);
    defer client.deinit();
    
    try expect(client.default_timeout_ms == 30000);
    try expect(client.follow_redirects == true);
    try expect(client.max_redirects == 10);
}

test "HTTPClient GET request (mock)" {
    // This test requires a mock server or network access
    // For now, we'll test the client initialization and structure
    var rt = try tardy.Runtime.init(.{});
    defer rt.deinit();
    
    var client = try HTTPClient.init(testing.allocator, &rt);
    defer client.deinit();
    
    // Verify client structure
    try expect(client.runtime == &rt);
    try expect(client.allocator.ptr == testing.allocator.ptr);
}

test "HTTPClient HEAD request (mock)" {
    // This test requires a mock server or network access
    // For now, we'll test the client initialization
    var rt = try tardy.Runtime.init(.{});
    defer rt.deinit();
    
    var client = try HTTPClient.init(testing.allocator, &rt);
    defer client.deinit();
    
    // Verify client is properly initialized
    try expect(client.follow_redirects == true);
}

// Integration tests (require network access)
// These would be skipped in CI unless explicitly enabled

test "HTTPClient real GET request" {
    if (std.os.getenv("RUN_INTEGRATION_TESTS") == null) {
        return error.SkipZigTest;
    }
    
    var rt = try tardy.Runtime.init(.{});
    defer rt.deinit();
    
    var client = try HTTPClient.init(testing.allocator, &rt);
    defer client.deinit();
    
    const response = try client.get("http://httpbin.org/get");
    defer response.deinit();
    
    try expect(response.is_success());
    try expect(response.get_header("Content-Type") != null);
}

test "HTTPClient real HEAD request" {
    if (std.os.getenv("RUN_INTEGRATION_TESTS") == null) {
        return error.SkipZigTest;
    }
    
    var rt = try tardy.Runtime.init(.{});
    defer rt.deinit();
    
    var client = try HTTPClient.init(testing.allocator, &rt);
    defer client.deinit();
    
    const response = try client.head("http://httpbin.org/status/200");
    defer response.deinit();
    
    try expect(response.is_success());
    try expect(response.body == null); // HEAD has no body
}

test "HTTPClient redirect handling" {
    if (std.os.getenv("RUN_INTEGRATION_TESTS") == null) {
        return error.SkipZigTest;
    }
    
    var rt = try tardy.Runtime.init(.{});
    defer rt.deinit();
    
    var client = try HTTPClient.init(testing.allocator, &rt);
    defer client.deinit();
    
    client.follow_redirects = true;
    client.max_redirects = 5;
    
    const response = try client.get("http://httpbin.org/redirect/2");
    defer response.deinit();
    
    try expect(response.is_success());
    // Should end up at /get after 2 redirects
}

test "HTTPClient max redirects limit" {
    if (std.os.getenv("RUN_INTEGRATION_TESTS") == null) {
        return error.SkipZigTest;
    }
    
    var rt = try tardy.Runtime.init(.{});
    defer rt.deinit();
    
    var client = try HTTPClient.init(testing.allocator, &rt);
    defer client.deinit();
    
    client.follow_redirects = true;
    client.max_redirects = 2;
    
    // Try to follow more redirects than allowed
    const result = client.get("http://httpbin.org/redirect/5");
    try testing.expectError(error.TooManyRedirects, result);
}