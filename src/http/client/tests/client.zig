const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

const tardy = @import("tardy");
const HTTPClient = @import("../client.zig").HTTPClient;
const ClientRequest = @import("../request.zig").ClientRequest;
const ClientResponse = @import("../response.zig").ClientResponse;

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
// NOTE: These tests are currently disabled as GET/HEAD methods are not yet implemented

// TODO: Re-enable when HTTPClient.get() is implemented
// test "HTTPClient real GET request" {
//     // Skip integration tests unless explicitly enabled
//     // To enable: export RUN_INTEGRATION_TESTS=1
//     const run_integration = std.process.getEnvVarOwned(testing.allocator, "RUN_INTEGRATION_TESTS") catch {
//         return error.SkipZigTest;
//     };
//     defer testing.allocator.free(run_integration);
//     
//     const Tardy = tardy.Tardy(.auto);
//     var t = try Tardy.init(testing.allocator, .{ .threading = .single });
//     defer t.deinit();
//     
//     const TestParams = struct {
//         allocator: std.mem.Allocator,
//         success: *bool,
//     };
//     
//     var success = false;
//     
//     try t.entry(
//         TestParams{ .allocator = testing.allocator, .success = &success },
//         struct {
//             fn entry(rt: *tardy.Runtime, params: TestParams) !void {
//                 var client = try HTTPClient.init(params.allocator, rt);
//                 defer client.deinit();
//                 
//                 const response = try client.get("http://httpbin.org/get");
//                 defer response.deinit();
//                 
//                 if (!response.is_success()) return error.TestFailure;
//                 if (response.get_header("Content-Type") == null) return error.TestFailure;
//                 
//                 params.success.* = true;
//             }
//         }.entry,
//     );
//     
//     try expect(success);
// }

// TODO: Re-enable when HTTPClient.head() is implemented
// test "HTTPClient real HEAD request" {
//     // Skip integration tests unless explicitly enabled
//     const run_integration = std.process.getEnvVarOwned(testing.allocator, "RUN_INTEGRATION_TESTS") catch {
//         return error.SkipZigTest;
//     };
//     defer testing.allocator.free(run_integration);
//     
//     const Tardy = tardy.Tardy(.auto);
//     var t = try Tardy.init(testing.allocator, .{ .threading = .single });
//     defer t.deinit();
//     
//     const TestParams = struct {
//         allocator: std.mem.Allocator,
//         success: *bool,
//     };
//     
//     var success = false;
//     
//     try t.entry(
//         TestParams{ .allocator = testing.allocator, .success = &success },
//         struct {
//             fn entry(rt: *tardy.Runtime, params: TestParams) !void {
//                 var client = try HTTPClient.init(params.allocator, rt);
//                 defer client.deinit();
//                 
//                 const response = try client.head("http://httpbin.org/status/200");
//                 defer response.deinit();
//                 
//                 if (!response.is_success()) return error.TestFailure;
//                 if (response.body != null) return error.TestFailure; // HEAD has no body
//                 
//                 params.success.* = true;
//             }
//         }.entry,
//     );
//     
//     try expect(success);
// }

// TODO: Re-enable when HTTPClient.get() with redirects is implemented
// test "HTTPClient redirect handling" {
//     // Skip integration tests unless explicitly enabled
//     const run_integration = std.process.getEnvVarOwned(testing.allocator, "RUN_INTEGRATION_TESTS") catch {
        return error.SkipZigTest;
    };
    defer testing.allocator.free(run_integration);
    
    const Tardy = tardy.Tardy(.auto);
    var t = try Tardy.init(testing.allocator, .{ .threading = .single });
    defer t.deinit();
    
    const TestParams = struct {
        allocator: std.mem.Allocator,
        success: *bool,
    };
    
    var success = false;
    
    try t.entry(
        TestParams{ .allocator = testing.allocator, .success = &success },
        struct {
            fn entry(rt: *tardy.Runtime, params: TestParams) !void {
                var client = try HTTPClient.init(params.allocator, rt);
                defer client.deinit();
                
                client.follow_redirects = true;
                client.max_redirects = 5;
                
                const response = try client.get("http://httpbin.org/redirect/2");
                defer response.deinit();
                
                if (!response.is_success()) return error.TestFailure;
                // Should end up at /get after 2 redirects
                
                params.success.* = true;
            }
        }.entry,
    );
    
//     try expect(success);
// }

// TODO: Re-enable when HTTPClient.get() with redirects is implemented
// test "HTTPClient max redirects limit" {
    // Skip integration tests unless explicitly enabled
    const run_integration = std.process.getEnvVarOwned(testing.allocator, "RUN_INTEGRATION_TESTS") catch {
        return error.SkipZigTest;
    };
    defer testing.allocator.free(run_integration);
    
    const Tardy = tardy.Tardy(.auto);
    var t = try Tardy.init(testing.allocator, .{ .threading = .single });
    defer t.deinit();
    
    const TestParams = struct {
        allocator: std.mem.Allocator,
        got_error: *bool,
    };
    
    var got_error = false;
    
    try t.entry(
        TestParams{ .allocator = testing.allocator, .got_error = &got_error },
        struct {
            fn entry(rt: *tardy.Runtime, params: TestParams) !void {
                var client = try HTTPClient.init(params.allocator, rt);
                defer client.deinit();
                
                client.follow_redirects = true;
                client.max_redirects = 2;
                
                // Try to follow more redirects than allowed
                const result = client.get("http://httpbin.org/redirect/5");
                if (result) |_| {
                    return error.TestFailure; // Should have failed
                } else |err| {
                    if (err == error.TooManyRedirects) {
                        params.got_error.* = true;
                    }
                }
            }
        }.entry,
    );
    
//     try expect(got_error);
// }