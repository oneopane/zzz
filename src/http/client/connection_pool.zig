const std = @import("std");

const Runtime = @import("tardy").Runtime;
const Connection = @import("connection.zig").Connection;
const ConnectionState = @import("connection.zig").ConnectionState;

const ConnectionList = struct {
    idle: std.ArrayList(*Connection),
    active: std.ArrayList(*Connection),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConnectionList {
        return .{
            .idle = std.ArrayList(*Connection){},
            .active = std.ArrayList(*Connection){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConnectionList) void {
        // Clean up all connections
        for (self.idle.items) |conn| {
            conn.deinit();
            self.allocator.destroy(conn);
        }
        self.idle.deinit(self.allocator);
        
        for (self.active.items) |conn| {
            conn.deinit();
            self.allocator.destroy(conn);
        }
        self.active.deinit(self.allocator);
    }

    pub fn get_idle(self: *ConnectionList) ?*Connection {
        // Get the most recently used connection (LIFO for better cache locality)
        if (self.idle.items.len > 0) {
            return self.idle.pop();
        }
        return null;
    }

    pub fn add_idle(self: *ConnectionList, conn: *Connection) !void {
        // Update connection state
        conn.state = .idle;
        conn.last_used = std.time.milliTimestamp();
        try self.idle.append(self.allocator, conn);
    }

    pub fn add_active(self: *ConnectionList, conn: *Connection) !void {
        // Update connection state
        conn.state = .active;
        conn.last_used = std.time.milliTimestamp();
        try self.active.append(self.allocator, conn);
    }

    pub fn remove(self: *ConnectionList, conn: *Connection) void {
        // Try to remove from idle list first
        for (self.idle.items, 0..) |item, i| {
            if (item == conn) {
                _ = self.idle.swapRemove(i);
                return;
            }
        }
        
        // Then try active list
        for (self.active.items, 0..) |item, i| {
            if (item == conn) {
                _ = self.active.swapRemove(i);
                return;
            }
        }
    }

    pub fn move_to_idle(self: *ConnectionList, conn: *Connection) !void {
        // Remove from active list
        for (self.active.items, 0..) |item, i| {
            if (item == conn) {
                _ = self.active.swapRemove(i);
                break;
            }
        }
        
        // Add to idle list
        try self.add_idle(conn);
    }

    pub fn cleanup_stale(self: *ConnectionList, max_idle_ms: i64) void {
        const now = std.time.milliTimestamp();
        var i: usize = 0;
        
        while (i < self.idle.items.len) {
            const conn = self.idle.items[i];
            const idle_time = now - conn.last_used;
            
            if (idle_time > max_idle_ms or !conn.is_alive()) {
                // Remove and destroy stale connection
                _ = self.idle.swapRemove(i);
                conn.deinit();
                self.allocator.destroy(conn);
            } else {
                i += 1;
            }
        }
    }
};

pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    connections: std.StringHashMap(ConnectionList),
    runtime: *Runtime,
    max_connections_per_host: u32 = 10,
    max_idle_time_ms: i64 = 60000,
    max_keepalive_requests: u32 = 100,

    pub fn init(allocator: std.mem.Allocator, runtime: *Runtime) ConnectionPool {
        return .{
            .allocator = allocator,
            .connections = std.StringHashMap(ConnectionList).init(allocator),
            .runtime = runtime,
            .max_connections_per_host = 10,
            .max_idle_time_ms = 60000,
            .max_keepalive_requests = 100,
        };
    }

    pub fn deinit(self: *ConnectionPool) void {
        // Clean up all connection lists
        var it = self.connections.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var list = entry.value_ptr;
            list.deinit();
        }
        self.connections.deinit();
    }

    fn make_pool_key(self: *ConnectionPool, host: []const u8, port: u16, use_tls: bool) ![]const u8 {
        // Create a unique key for this host:port:tls combination
        return try std.fmt.allocPrint(self.allocator, "{s}:{d}:{}", .{ host, port, use_tls });
    }

    pub fn get_connection(self: *ConnectionPool, host: []const u8, port: u16, use_tls: bool) !*Connection {
        const key = try self.make_pool_key(host, port, use_tls);
        defer self.allocator.free(key);
        
        // Get or create the connection list for this host
        const gop = try self.connections.getOrPut(key);
        if (!gop.found_existing) {
            // Store a copy of the key since we're about to free it
            const stored_key = try self.allocator.dupe(u8, key);
            gop.key_ptr.* = stored_key;
            gop.value_ptr.* = ConnectionList.init(self.allocator);
        }
        
        var list = gop.value_ptr;
        
        // First, try to get an idle connection
        if (list.get_idle()) |conn| {
            // Validate the connection is still alive
            if (conn.is_alive() and conn.keepalive_count < self.max_keepalive_requests) {
                // Move to active list
                try list.add_active(conn);
                conn.keepalive_count += 1;
                return conn;
            } else {
                // Connection is dead or exhausted, clean it up
                conn.deinit();
                self.allocator.destroy(conn);
            }
        }
        
        // Check if we've hit the per-host connection limit
        const total_connections = list.idle.items.len + list.active.items.len;
        if (total_connections >= self.max_connections_per_host) {
            // Try to clean up idle connections first
            list.cleanup_stale(0); // Force cleanup of all idle
            
            // If still at limit, we have to wait or fail
            if (list.active.items.len >= self.max_connections_per_host) {
                return error.ConnectionPoolExhausted;
            }
        }
        
        // Create a new connection
        const conn = try self.allocator.create(Connection);
        errdefer self.allocator.destroy(conn);
        
        conn.* = try Connection.init(self.allocator, host, port, use_tls);
        errdefer conn.deinit();
        
        // Connect it
        try conn.connect(self.runtime);
        
        // Add to active list
        try list.add_active(conn);
        
        return conn;
    }

    pub fn return_connection(self: *ConnectionPool, conn: *Connection) void {
        // Find the connection's pool
        const key = self.make_pool_key(conn.host, conn.port, conn.use_tls) catch {
            // If we can't make the key, just close the connection
            conn.deinit();
            self.allocator.destroy(conn);
            return;
        };
        defer self.allocator.free(key);
        
        if (self.connections.getPtr(key)) |list| {
            // Check if connection can be reused
            if (conn.is_alive() and conn.keepalive_count < self.max_keepalive_requests) {
                // Move from active to idle
                list.move_to_idle(conn) catch {
                    // If we can't add to idle, close it
                    list.remove(conn);
                    conn.deinit();
                    self.allocator.destroy(conn);
                };
            } else {
                // Connection exhausted or dead, remove it
                list.remove(conn);
                conn.deinit();
                self.allocator.destroy(conn);
            }
        } else {
            // Pool doesn't exist? Just clean up
            conn.deinit();
            self.allocator.destroy(conn);
        }
    }

    pub fn remove_connection(self: *ConnectionPool, conn: *Connection) void {
        // Find and remove a broken connection
        const key = self.make_pool_key(conn.host, conn.port, conn.use_tls) catch {
            // If we can't make the key, just close the connection
            conn.deinit();
            self.allocator.destroy(conn);
            return;
        };
        defer self.allocator.free(key);
        
        if (self.connections.getPtr(key)) |list| {
            list.remove(conn);
            conn.deinit();
            self.allocator.destroy(conn);
        }
    }

    pub fn cleanup_idle(self: *ConnectionPool) void {
        // Clean up stale connections from all pools
        var it = self.connections.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.cleanup_stale(self.max_idle_time_ms);
        }
    }

    pub fn get_stats(self: *const ConnectionPool) PoolStats {
        var stats = PoolStats{
            .total_idle = 0,
            .total_active = 0,
            .total_pools = self.connections.count(),
        };
        
        var it = self.connections.iterator();
        while (it.next()) |entry| {
            stats.total_idle += entry.value_ptr.idle.items.len;
            stats.total_active += entry.value_ptr.active.items.len;
        }
        
        return stats;
    }
};

pub const PoolStats = struct {
    total_idle: usize,
    total_active: usize,
    total_pools: usize,
};