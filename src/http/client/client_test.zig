const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

const tardy = @import("tardy");
const HTTPClient = @import("client.zig").HTTPClient;
const ClientRequest = @import("request.zig").ClientRequest;
const ClientResponse = @import("response.zig").ClientResponse;

test "HTTPClient with Tardy runtime" {
    // This test demonstrates proper Tardy initialization
    // For actual HTTP requests, we'd need to run this within Tardy.entry()
    const Tardy = tardy.Tardy(.auto);
    
    var t = try Tardy.init(testing.allocator, .{ .threading = .single });
    defer t.deinit();
    
    // The actual HTTP client usage would happen inside the entry function
    // where a Runtime pointer is provided
    const TestParams = struct {
        allocator: std.mem.Allocator,
        test_complete: *bool,
    };
    
    var test_complete = false;
    
    try t.entry(
        TestParams{ .allocator = testing.allocator, .test_complete = &test_complete },
        struct {
            fn entry(rt: *tardy.Runtime, params: TestParams) !void {
                var client = try HTTPClient.init(params.allocator, rt);
                defer client.deinit();
                
                // Verify client properties
                if (client.default_timeout_ms != 30000) return error.TestFailure;
                if (!client.follow_redirects) return error.TestFailure;
                if (client.max_redirects != 10) return error.TestFailure;
                
                params.test_complete.* = true;
            }
        }.entry,
    );
    
    try expect(test_complete);
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