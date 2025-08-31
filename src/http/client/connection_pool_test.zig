const std = @import("std");
const testing = std.testing;

const Runtime = @import("tardy").Runtime;
const Connection = @import("connection.zig").Connection;
const ConnectionPool = @import("connection_pool.zig").ConnectionPool;

test "ConnectionPool.init creates empty pool" {
    const allocator = testing.allocator;
    
    // Create a dummy runtime for testing
    var rt = try Runtime.init(allocator, .{});
    defer rt.deinit();
    
    var pool = ConnectionPool.init(allocator, &rt);
    defer pool.deinit();
    
    // Pool should start empty
    try testing.expectEqual(@as(usize, 0), pool.connections.count());
    
    const stats = pool.get_stats();
    try testing.expectEqual(@as(usize, 0), stats.total_idle);
    try testing.expectEqual(@as(usize, 0), stats.total_active);
    try testing.expectEqual(@as(usize, 0), stats.total_pools);
}

test "ConnectionPool creates pool key correctly" {
    const allocator = testing.allocator;
    
    var rt = try Runtime.init(allocator, .{});
    defer rt.deinit();
    
    var pool = ConnectionPool.init(allocator, &rt);
    defer pool.deinit();
    
    // Test key generation
    const key1 = try pool.make_pool_key("example.com", 80, false);
    defer allocator.free(key1);
    try testing.expectEqualStrings("example.com:80:false", key1);
    
    const key2 = try pool.make_pool_key("secure.example.com", 443, true);
    defer allocator.free(key2);
    try testing.expectEqualStrings("secure.example.com:443:true", key2);
}

test "ConnectionPool configuration" {
    const allocator = testing.allocator;
    
    var rt = try Runtime.init(allocator, .{});
    defer rt.deinit();
    
    var pool = ConnectionPool.init(allocator, &rt);
    defer pool.deinit();
    
    // Test default configuration
    try testing.expectEqual(@as(u32, 10), pool.max_connections_per_host);
    try testing.expectEqual(@as(i64, 60000), pool.max_idle_time_ms);
    try testing.expectEqual(@as(u32, 100), pool.max_keepalive_requests);
    
    // Test configuration changes
    pool.max_connections_per_host = 20;
    pool.max_idle_time_ms = 30000;
    pool.max_keepalive_requests = 50;
    
    try testing.expectEqual(@as(u32, 20), pool.max_connections_per_host);
    try testing.expectEqual(@as(i64, 30000), pool.max_idle_time_ms);
    try testing.expectEqual(@as(u32, 50), pool.max_keepalive_requests);
}

test "ConnectionList operations" {
    const allocator = testing.allocator;
    
    var list = ConnectionPool.ConnectionList.init(allocator);
    defer list.deinit();
    
    // Create a test connection
    var conn = try allocator.create(Connection);
    defer allocator.destroy(conn);
    
    conn.* = try Connection.init(allocator, "test.com", 80, false);
    defer conn.deinit();
    
    // Test adding to active
    try list.add_active(conn);
    try testing.expectEqual(@as(usize, 1), list.active.items.len);
    try testing.expectEqual(@as(usize, 0), list.idle.items.len);
    try testing.expectEqual(Connection.ConnectionState.active, conn.state);
    
    // Test moving to idle
    try list.move_to_idle(conn);
    try testing.expectEqual(@as(usize, 0), list.active.items.len);
    try testing.expectEqual(@as(usize, 1), list.idle.items.len);
    try testing.expectEqual(Connection.ConnectionState.idle, conn.state);
    
    // Test getting idle connection
    const retrieved = list.get_idle();
    try testing.expect(retrieved != null);
    try testing.expectEqual(conn, retrieved.?);
    try testing.expectEqual(@as(usize, 0), list.idle.items.len);
}

test "ConnectionList stale cleanup" {
    const allocator = testing.allocator;
    
    var list = ConnectionPool.ConnectionList.init(allocator);
    defer list.deinit();
    
    // Create test connections with different last_used times
    const now = std.time.milliTimestamp();
    
    var conn1 = try allocator.create(Connection);
    conn1.* = try Connection.init(allocator, "test.com", 80, false);
    conn1.last_used = now - 70000; // 70 seconds old
    conn1.state = .idle;
    try list.idle.append(conn1);
    
    var conn2 = try allocator.create(Connection);
    conn2.* = try Connection.init(allocator, "test.com", 80, false);
    conn2.last_used = now - 30000; // 30 seconds old
    conn2.state = .idle;
    try list.idle.append(conn2);
    
    // Cleanup with 60 second timeout
    list.cleanup_stale(60000);
    
    // Only conn2 should remain
    try testing.expectEqual(@as(usize, 1), list.idle.items.len);
    try testing.expectEqual(conn2, list.idle.items[0]);
    
    // Cleanup remaining for proper test cleanup
    conn2.deinit();
    allocator.destroy(conn2);
    list.idle.clearRetainingCapacity();
}

// Note: Full integration tests would require a running server
// These can be added as separate integration tests that are conditionally compiled

test "HTTPClient with connection pool disabled" {
    const HTTPClient = @import("client.zig").HTTPClient;
    const allocator = testing.allocator;
    
    // This test just verifies the client can be configured without pool
    var rt = try Runtime.init(allocator, .{});
    defer rt.deinit();
    
    var client = try HTTPClient.init(allocator, &rt);
    defer client.deinit();
    
    // Test disabling pool
    client.use_connection_pool = false;
    try testing.expectEqual(false, client.use_connection_pool);
    
    // Test pool configuration methods work even when disabled
    client.set_max_connections_per_host(5);
    client.set_max_idle_time(30000);
    client.cleanup_idle_connections();
    
    const stats = client.get_pool_stats();
    try testing.expectEqual(@as(usize, 0), stats.total_idle);
    try testing.expectEqual(@as(usize, 0), stats.total_active);
}