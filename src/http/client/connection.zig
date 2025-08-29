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
        _ = allocator;
        _ = host;
        _ = port;
        _ = use_tls;
        @panic("Not implemented");
    }

    pub fn connect(self: *Connection, runtime: *Runtime) !void {
        _ = self;
        _ = runtime;
        @panic("Not implemented");
    }

    pub fn close(self: *Connection) void {
        _ = self;
        @panic("Not implemented");
    }

    pub fn is_alive(self: *const Connection) bool {
        _ = self;
        @panic("Not implemented");
    }

    pub fn send_request(self: *Connection, runtime: *Runtime, request: []const u8) !void {
        _ = self;
        _ = runtime;
        _ = request;
        @panic("Not implemented");
    }

    pub fn recv_response(self: *Connection, runtime: *Runtime, buffer: []u8) !usize {
        _ = self;
        _ = runtime;
        _ = buffer;
        @panic("Not implemented");
    }

    pub fn send_all(self: *Connection, runtime: *Runtime, data: []const u8) !void {
        _ = self;
        _ = runtime;
        _ = data;
        @panic("Not implemented");
    }

    pub fn recv_all(self: *Connection, runtime: *Runtime, buffer: []u8) !usize {
        _ = self;
        _ = runtime;
        _ = buffer;
        @panic("Not implemented");
    }
};