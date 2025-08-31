const std = @import("std");
const Connection = @import("connection.zig").Connection;

// HTTPS Connection Tests

test "Connection.init with HTTPS creates secure connection" {
    const allocator = std.testing.allocator;
    
    // Test HTTPS connection initialization
    var conn = try Connection.init(allocator, "example.com", 443, true);
    defer conn.deinit();
    
    try std.testing.expectEqualStrings(conn.host, "example.com");
    try std.testing.expectEqual(conn.port, 443);
    try std.testing.expectEqual(conn.state, .disconnected);
    try std.testing.expectEqual(conn.use_tls, true);
    try std.testing.expect(!conn.is_alive());
}

test "Connection.init with HTTP creates plain connection" {
    const allocator = std.testing.allocator;
    
    // Test HTTP connection initialization
    var conn = try Connection.init(allocator, "example.com", 80, false);
    defer conn.deinit();
    
    try std.testing.expectEqualStrings(conn.host, "example.com");
    try std.testing.expectEqual(conn.port, 80);
    try std.testing.expectEqual(conn.state, .disconnected);
    try std.testing.expectEqual(conn.use_tls, false);
    try std.testing.expect(!conn.is_alive());
}

test "Connection socket type matches TLS setting" {
    const allocator = std.testing.allocator;
    
    // Test that socket union type is correctly initialized
    var https_conn = try Connection.init(allocator, "secure.example.com", 443, true);
    defer https_conn.deinit();
    
    // Before connect, socket union should be initialized with correct variant
    switch (https_conn.socket) {
        .secure => {},  // Expected for HTTPS
        .plain => return error.UnexpectedSocketType,
    }
    
    var http_conn = try Connection.init(allocator, "example.com", 80, false);
    defer http_conn.deinit();
    
    switch (http_conn.socket) {
        .plain => {},  // Expected for HTTP
        .secure => return error.UnexpectedSocketType,
    }
}

// Integration test to verify HTTPS readiness
// NOTE: This test doesn't actually connect to avoid network dependencies in unit tests
test "HTTPS connection lifecycle states" {
    const allocator = std.testing.allocator;
    
    var conn = try Connection.init(allocator, "api.github.com", 443, true);
    defer conn.deinit();
    
    // Initial state
    try std.testing.expectEqual(conn.state, .disconnected);
    try std.testing.expectEqual(conn.use_tls, true);
    try std.testing.expect(conn.bearssl == null); // Not initialized until connect
    
    // Verify state transitions
    conn.state = .connecting;
    try std.testing.expect(!conn.is_alive());
    
    conn.state = .connected;
    try std.testing.expect(conn.is_alive());
    
    conn.state = .active;
    try std.testing.expect(conn.is_alive());
    
    conn.state = .idle;
    try std.testing.expect(conn.is_alive());
    
    conn.state = .closing;
    try std.testing.expect(!conn.is_alive());
    
    conn.state = .closed;
    try std.testing.expect(!conn.is_alive());
}