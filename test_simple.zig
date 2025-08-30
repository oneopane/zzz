const std = @import("std");
const testing = std.testing;

// Test that the main library compiles
test "Library compilation" {
    _ = @import("src/lib.zig");
    try testing.expect(true);
}

// Test basic HTTP client compilation
test "HTTP client compilation" {
    const client = @import("src/http/client/client.zig");
    try testing.expect(@TypeOf(client.HTTPClient) != void);
}

// Test basic connection structure
test "Connection structure" {
    const conn = @import("src/http/client/connection.zig");
    try testing.expect(@TypeOf(conn.Connection) != void);
}

// Test request structure
test "Request structure" {
    const req = @import("src/http/client/request.zig");
    try testing.expect(@TypeOf(req.ClientRequest) != void);
}

// Test response structure
test "Response structure" {
    const resp = @import("src/http/client/response.zig");
    try testing.expect(@TypeOf(resp.ClientResponse) != void);
}