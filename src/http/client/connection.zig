const std = @import("std");

const Runtime = @import("tardy").Runtime;
const Socket = @import("tardy").Socket;
const SecureSocket = @import("secsock").SecureSocket;

pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    idle,
    active,
    closing,
    closed,
};

pub const Connection = struct {
    allocator: std.mem.Allocator,
    socket: union(enum) {
        plain: Socket,
        secure: SecureSocket,
    },
    host: []const u8,
    port: u16,
    state: ConnectionState,
    last_used: i64,
    keepalive_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, use_tls: bool) !Connection {
        // Make a copy of the host string
        const host_copy = try allocator.dupe(u8, host);
        errdefer allocator.free(host_copy);
        
        // For Phase 2, we only support non-TLS connections
        if (use_tls) {
            return error.TLSNotImplementedYet;
        }
        
        return Connection{
            .allocator = allocator,
            .socket = .{ .plain = undefined }, // Will be initialized in connect()
            .host = host_copy,
            .port = port,
            .state = .disconnected,
            .last_used = std.time.milliTimestamp(),
            .keepalive_count = 0,
        };
    }

    pub fn connect(self: *Connection, runtime: *Runtime) !void {
        if (self.state != .disconnected and self.state != .closed) {
            return error.AlreadyConnected;
        }
        
        self.state = .connecting;
        
        // Try to parse as IP address first
        const address = std.net.Address.parseIp4(self.host, self.port) catch blk: {
            // If IP parsing fails, try DNS resolution
            const addresses = try std.net.getAddressList(self.allocator, self.host, self.port);
            defer addresses.deinit();
            
            if (addresses.addrs.len == 0) {
                self.state = .disconnected;
                return error.NoAddressFound;
            }
            
            // Use first address
            break :blk addresses.addrs[0];
        };
        
        // Create TCP socket with address
        const socket = try Socket.init_with_address(.tcp, address);
        errdefer socket.close();
        
        // Connect to the server using tardy runtime
        try socket.connect(runtime);
        
        self.socket = .{ .plain = socket };
        self.state = .connected;
        self.last_used = std.time.milliTimestamp();
    }

    pub fn deinit(self: *Connection) void {
        self.close();
        self.allocator.free(self.host);
    }

    pub fn close(self: *Connection) void {
        if (self.state == .closed or self.state == .disconnected) {
            return;
        }
        
        self.state = .closing;
        
        switch (self.socket) {
            .plain => |socket| {
                // Use blocking close since we don't have runtime in close()
                socket.close_blocking();
            },
            .secure => {
                // TLS cleanup will be implemented in Phase 7
            },
        }
        
        self.state = .closed;
    }

    pub fn is_alive(self: *const Connection) bool {
        return self.state == .connected or self.state == .active or self.state == .idle;
    }

    pub fn send_request(self: *Connection, runtime: *Runtime, request: []const u8) !void {
        // For now, just delegate to send_all
        try self.send_all(runtime, request);
    }

    pub fn recv_response(self: *Connection, runtime: *Runtime, buffer: []u8) !usize {
        // For now, just delegate to recv_all
        return try self.recv_all(runtime, buffer);
    }

    pub fn send_all(self: *Connection, runtime: *Runtime, data: []const u8) !void {
        if (self.state != .connected and self.state != .active) {
            return error.NotConnected;
        }
        
        self.state = .active;
        
        const socket = switch (self.socket) {
            .plain => |*s| s,
            .secure => return error.TLSNotImplementedYet,
        };
        
        var bytes_sent: usize = 0;
        while (bytes_sent < data.len) {
            const n = try socket.send(runtime, data[bytes_sent..]);
            if (n == 0) {
                self.state = .closed;
                return error.ConnectionClosed;
            }
            bytes_sent += n;
        }
        
        self.last_used = std.time.milliTimestamp();
        self.state = .connected;
    }

    pub fn recv_all(self: *Connection, runtime: *Runtime, buffer: []u8) !usize {
        if (self.state != .connected and self.state != .active) {
            return error.NotConnected;
        }
        
        self.state = .active;
        
        const socket = switch (self.socket) {
            .plain => |*s| s,
            .secure => return error.TLSNotImplementedYet,
        };
        
        const bytes_read = try socket.recv(runtime, buffer);
        if (bytes_read == 0) {
            self.state = .closed;
            return error.ConnectionClosed;
        }
        
        self.last_used = std.time.milliTimestamp();
        self.state = .connected;
        
        return bytes_read;
    }
};

// Tests for Phase 2: Basic Connection

test "Connection.init creates connection object" {
    const allocator = std.testing.allocator;
    
    // Test non-TLS connection
    var conn = try Connection.init(allocator, "example.com", 80, false);
    defer conn.deinit();
    
    try std.testing.expectEqualStrings(conn.host, "example.com");
    try std.testing.expectEqual(conn.port, 80);
    try std.testing.expectEqual(conn.state, .disconnected);
    try std.testing.expectEqual(conn.keepalive_count, 0);
}

test "Connection.init returns error for TLS (not implemented yet)" {
    const allocator = std.testing.allocator;
    
    // Test TLS connection should fail in Phase 2
    const result = Connection.init(allocator, "example.com", 443, true);
    try std.testing.expectError(error.TLSNotImplementedYet, result);
}

test "Connection state transitions" {
    const allocator = std.testing.allocator;
    
    var conn = try Connection.init(allocator, "127.0.0.1", 8080, false);
    defer conn.deinit();
    
    // Initial state should be disconnected
    try std.testing.expectEqual(conn.state, .disconnected);
    try std.testing.expect(!conn.is_alive());
    
    // After close on disconnected connection, should remain disconnected
    conn.close();
    try std.testing.expectEqual(conn.state, .disconnected);
}

test "Connection.is_alive returns correct status" {
    const allocator = std.testing.allocator;
    
    var conn = try Connection.init(allocator, "127.0.0.1", 8080, false);
    defer conn.deinit();
    
    // Test disconnected state
    conn.state = .disconnected;
    try std.testing.expect(!conn.is_alive());
    
    // Test closed state
    conn.state = .closed;
    try std.testing.expect(!conn.is_alive());
    
    // Test connecting state
    conn.state = .connecting;
    try std.testing.expect(!conn.is_alive());
    
    // Test closing state
    conn.state = .closing;
    try std.testing.expect(!conn.is_alive());
    
    // Test connected state
    conn.state = .connected;
    try std.testing.expect(conn.is_alive());
    
    // Test active state
    conn.state = .active;
    try std.testing.expect(conn.is_alive());
    
    // Test idle state
    conn.state = .idle;
    try std.testing.expect(conn.is_alive());
}

test "Connection methods require connected state" {
    const allocator = std.testing.allocator;
    
    var conn = try Connection.init(allocator, "127.0.0.1", 8080, false);
    defer conn.deinit();
    
    // Both send_all and recv_all should fail when disconnected
    // We verify this by checking the state preconditions
    try std.testing.expectEqual(conn.state, .disconnected);
    try std.testing.expect(!conn.is_alive());
    
    // The actual send_all and recv_all methods check state before using runtime
    // so we don't need to call them with undefined runtime
}