const std = @import("std");
const builtin = @import("builtin");
const tag = builtin.os.tag;
const assert = std.debug.assert;
const log = std.log.scoped(.@"zzz/http/server");

const TypedStorage = @import("../core/typed_storage.zig").TypedStorage;
const Pseudoslice = @import("../core/pseudoslice.zig").Pseudoslice;
const AnyCaseStringMap = @import("../core/any_case_string_map.zig").AnyCaseStringMap;

const Context = @import("context.zig").Context;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Respond = @import("response.zig").Respond;
const Capture = @import("router/routing_trie.zig").Capture;
const SSE = @import("sse.zig").SSE;

const Mime = @import("mime.zig").Mime;
const Router = @import("router.zig").Router;
const Route = @import("router/route.zig").Route;
const Layer = @import("router/middleware.zig").Layer;
const Middleware = @import("router/middleware.zig").Middleware;
const HTTPError = @import("lib.zig").HTTPError;

const HandlerWithData = @import("router/route.zig").HandlerWithData;

const Next = @import("router/middleware.zig").Next;

pub const Runtime = @import("tardy").Runtime;
pub const Task = @import("tardy").Task;
const TardyCreator = @import("tardy").Tardy;

const Cross = @import("tardy").Cross;
const Pool = @import("tardy").Pool;
const PoolKind = @import("tardy").PoolKind;
const Socket = @import("tardy").Socket;
const ZeroCopy = @import("tardy").ZeroCopy;

const AcceptResult = @import("tardy").AcceptResult;
const RecvResult = @import("tardy").RecvResult;
const SendResult = @import("tardy").SendResult;

const secsock = @import("secsock");
const SecureSocket = secsock.SecureSocket;

pub const TLSFileOptions = union(enum) {
    buffer: []const u8,
    file: struct {
        path: []const u8,
        size_buffer_max: u32 = 1024 * 1024,
    },
};

/// These are various general configuration
/// options that are important for the actual framework.
///
/// This includes various different options and limits
/// for interacting with the underlying network.
pub const ServerConfig = struct {
    /// Stack Size
    ///
    /// If you have a large number of middlewares or
    /// create a LOT of stack memory, you may want to increase this.
    ///
    /// P.S: A lot of functions in the standard library do end up allocating
    /// a lot on the stack (such as std.log).
    ///
    /// Default: 1MB
    stack_size: usize = 1024 * 1024,
    /// Number of Maximum Concurrent Connections.
    ///
    /// This is applied PER runtime.
    /// zzz will drop/close any connections greater
    /// than this.
    ///
    /// You can set this to `null` to have no maximum.
    ///
    /// Default: `null`
    connection_count_max: ?u32 = null,
    /// Number of times a Request-Response can happen with keep-alive.
    ///
    /// Setting this to `null` will set no limit.
    ///
    /// Default: `null`
    keepalive_count_max: ?u16 = null,
    /// Amount of allocated memory retained
    /// after an arena is cleared.
    ///
    /// A higher value will increase memory usage but
    /// should make allocators faster.
    ///
    /// A lower value will reduce memory usage but
    /// will make allocators slower.
    ///
    /// Default: 1KB
    connection_arena_bytes_retain: u32 = 1024,
    /// Amount of space on the `recv_buffer` retained
    /// after every send.
    ///
    /// Default: 1KB
    list_recv_bytes_retain: u32 = 1024,
    /// Maximum size (in bytes) of the Recv buffer.
    /// This is mainly a concern when you are reading in
    /// large requests before responding.
    ///
    /// Default: 2MB
    list_recv_bytes_max: u32 = 1024 * 1024 * 2,
    /// Size of the buffer (in bytes) used for
    /// interacting with the socket.
    ///
    /// Default: 1 KB
    socket_buffer_bytes: u32 = 1024,
    /// Maximum number of Captures in a Route
    ///
    /// Default: 8
    capture_count_max: u16 = 8,
    /// Maximum size (in bytes) of the Request.
    ///
    /// Default: 2MB
    request_bytes_max: u32 = 1024 * 1024 * 2,
    /// Maximum size (in bytes) of the Request URI.
    ///
    /// Default: 2KB
    request_uri_bytes_max: u32 = 1024 * 2,
};

pub const Provision = struct {
    initalized: bool = false,
    recv_slice: []u8,
    zc_recv_buffer: ZeroCopy(u8),
    header_buffer: std.ArrayList(u8),
    arena: std.heap.ArenaAllocator,
    storage: TypedStorage,
    captures: []Capture,
    queries: AnyCaseStringMap,
    request: Request,
    response: Response,
};

pub const Server = struct {
    const Self = @This();
    config: ServerConfig,

    pub fn init(config: ServerConfig) Self {
        return Self{ .config = config };
    }

    pub fn deinit(self: *const Self) void {
        if (self.tls_ctx) |tls| {
            tls.deinit();
        }
    }

    const RequestBodyState = struct {
        content_length: usize,
        current_length: usize,
    };

    const RequestState = union(enum) {
        header,
        body: RequestBodyState,
    };

    const State = union(enum) {
        request: RequestState,
        handler,
        respond,
    };

    fn prepare_new_request(state: ?*State, provision: *Provision, config: ServerConfig) !void {
        assert(provision.initalized);
        provision.request.clear();
        provision.response.clear();
        provision.storage.clear();
        provision.zc_recv_buffer.clear_retaining_capacity();
        provision.header_buffer.clearRetainingCapacity();
        _ = provision.arena.reset(.{ .retain_with_limit = config.connection_arena_bytes_retain });
        provision.recv_slice = try provision.zc_recv_buffer.get_write_area(config.socket_buffer_bytes);

        if (state) |s| s.* = .{ .request = .header };
    }

    pub fn main_frame(
        rt: *Runtime,
        config: ServerConfig,
        router: *const Router,
        server_socket: SecureSocket,
        provisions: *Pool(Provision),
        connection_count: *usize,
        accept_queued: *bool,
    ) !void {
        accept_queued.* = false;
        const secure = server_socket.accept(rt) catch |e| {
            if (!accept_queued.*) {
                try rt.spawn(
                    .{ rt, config, router, server_socket, provisions, connection_count, accept_queued },
                    main_frame,
                    config.stack_size,
                );
                accept_queued.* = true;
            }
            return e;
        };
        defer secure.socket.close_blocking();
        defer secure.deinit();

        connection_count.* += 1;
        defer connection_count.* -= 1;

        if (secure.socket.addr.any.family != std.posix.AF.UNIX) {
            try Cross.socket.disable_nagle(secure.socket.handle);
        }

        if (config.connection_count_max) |max| if (connection_count.* > max) {
            log.debug("over connection max, closing", .{});
            return;
        };

        log.debug("queuing up a new accept request", .{});
        try rt.spawn(
            .{ rt, config, router, server_socket, provisions, connection_count, accept_queued },
            main_frame,
            config.stack_size,
        );
        accept_queued.* = true;

        const index = try provisions.borrow();
        defer provisions.release(index);
        const provision = provisions.get_ptr(index);

        // if we are growing, we can handle a newly allocated provision here.
        // otherwise, it should be initalized.
        if (!provision.initalized) {
            log.debug("initalizing new provision", .{});
            provision.zc_recv_buffer = ZeroCopy(u8).init(rt.allocator, config.socket_buffer_bytes) catch {
                @panic("attempting to allocate more memory than available. (ZeroCopyBuffer)");
            };
            provision.header_buffer = std.ArrayList(u8){};
            provision.arena = std.heap.ArenaAllocator.init(rt.allocator);
            provision.captures = rt.allocator.alloc(Capture, config.capture_count_max) catch {
                @panic("attempting to allocate more memory than available. (Captures)");
            };
            provision.queries = AnyCaseStringMap.init(rt.allocator);
            provision.storage = TypedStorage.init(rt.allocator);
            provision.request = Request.init(rt.allocator);
            provision.response = Response.init(rt.allocator);
            provision.initalized = true;
        }
        defer prepare_new_request(null, provision, config) catch unreachable;

        var state: State = .{ .request = .header };
        const buffer = try provision.zc_recv_buffer.get_write_area(config.socket_buffer_bytes);
        _ = buffer;
        provision.recv_slice = try provision.zc_recv_buffer.get_write_area(config.socket_buffer_bytes);

        var keepalive_count: u16 = 0;

        http_loop: while (true) switch (state) {
            .request => |*kind| switch (kind.*) {
                .header => {
                    const recv_count = secure.recv(rt, provision.recv_slice) catch |e| switch (e) {
                        error.Closed => break,
                        else => {
                            log.debug("recv failed on socket | {}", .{e});
                            break;
                        },
                    };

                    provision.zc_recv_buffer.mark_written(recv_count);
                    provision.recv_slice = try provision.zc_recv_buffer.get_write_area(config.socket_buffer_bytes);
                    if (provision.zc_recv_buffer.len > config.request_bytes_max) break;
                    const search_area_start = (provision.zc_recv_buffer.len - recv_count) -| 4;

                    if (std.mem.indexOf(
                        u8,
                        // Minimize the search area.
                        provision.zc_recv_buffer.subslice(.{ .start = search_area_start }),
                        "\r\n\r\n",
                    )) |header_end| {
                        const real_header_end = header_end + 4;
                        try provision.request.parse_headers(
                            // Add 4 to account for the actual header end sequence.
                            provision.zc_recv_buffer.subslice(.{ .end = real_header_end }),
                            .{
                                .request_bytes_max = config.request_bytes_max,
                                .request_uri_bytes_max = config.request_uri_bytes_max,
                            },
                        );

                        log.info("rt{d} - \"{s} {s}\" {s} ({})", .{
                            rt.id,
                            @tagName(provision.request.method.?),
                            provision.request.uri.?,
                            provision.request.headers.get("User-Agent") orelse "N/A",
                            secure.socket.addr,
                        });

                        const content_length_str = provision.request.headers.get("Content-Length") orelse "0";
                        const content_length = try std.fmt.parseUnsigned(usize, content_length_str, 10);
                        log.debug("content length={d}", .{content_length});

                        if (provision.request.expect_body() and content_length != 0) {
                            state = .{
                                .request = .{
                                    .body = .{
                                        .current_length = provision.zc_recv_buffer.len - real_header_end,
                                        .content_length = content_length,
                                    },
                                },
                            };
                        } else state = .handler;
                    }
                },
                .body => |*info| {
                    if (info.current_length == info.content_length) {
                        provision.request.body = provision.zc_recv_buffer.subslice(
                            .{ .start = provision.zc_recv_buffer.len - info.content_length },
                        );
                        state = .handler;
                        continue;
                    }

                    const recv_count = secure.recv(rt, provision.recv_slice) catch |e| switch (e) {
                        error.Closed => break,
                        else => {
                            log.debug("recv failed on socket | {}", .{e});
                            break;
                        },
                    };

                    provision.zc_recv_buffer.mark_written(recv_count);
                    provision.recv_slice = try provision.zc_recv_buffer.get_write_area(config.socket_buffer_bytes);
                    if (provision.zc_recv_buffer.len > config.request_bytes_max) break;

                    info.current_length += recv_count;
                    assert(info.current_length <= info.content_length);
                },
            },
            .handler => {
                const found = try router.get_bundle_from_host(
                    rt.allocator,
                    provision.request.uri.?,
                    provision.captures,
                    &provision.queries,
                );
                defer rt.allocator.free(found.duped);
                defer for (found.duped) |dupe| rt.allocator.free(dupe);

                const h_with_data: HandlerWithData = found.route.get_handler(
                    provision.request.method.?,
                ) orelse {
                    provision.response.headers.clearRetainingCapacity();
                    provision.response.status = .@"Method Not Allowed";
                    provision.response.mime = Mime.TEXT;
                    provision.response.body = "";

                    state = .respond;
                    continue;
                };

                const context: Context = .{
                    .runtime = rt,
                    .allocator = provision.arena.allocator(),
                    .header_buffer = &provision.header_buffer,
                    .request = &provision.request,
                    .response = &provision.response,
                    .storage = &provision.storage,
                    .socket = secure,
                    .captures = found.captures,
                    .queries = found.queries,
                };

                var next: Next = .{
                    .context = &context,
                    .middlewares = h_with_data.middlewares,
                    .handler = h_with_data,
                };

                const next_respond: Respond = next.run() catch |e| blk: {
                    log.warn("rt{d} - \"{s} {s}\" {} ({})", .{
                        rt.id,
                        @tagName(provision.request.method.?),
                        provision.request.uri.?,
                        e,
                        secure.socket.addr,
                    });

                    // If in Debug Mode, we will return the error name. In other modes,
                    // we won't to avoid leaking implemenation details.
                    const body = if (comptime builtin.mode == .Debug) @errorName(e) else "";

                    break :blk try provision.response.apply(.{
                        .status = .@"Internal Server Error",
                        .mime = Mime.TEXT,
                        .body = body,
                    });
                };

                switch (next_respond) {
                    .standard => {
                        // applies the respond onto the response
                        //try provision.response.apply(respond);
                        state = .respond;
                    },
                    .responded => {
                        const connection = provision.request.headers.get("Connection") orelse "keep-alive";
                        if (std.mem.eql(u8, connection, "close")) break :http_loop;
                        if (config.keepalive_count_max) |max| {
                            if (keepalive_count > max) {
                                log.debug("closing connection, exceeded keepalive max", .{});
                                break :http_loop;
                            }

                            keepalive_count += 1;
                        }

                        try prepare_new_request(&state, provision, config);
                    },
                    .close => break :http_loop,
                }
            },
            .respond => {
                const body = provision.response.body orelse "";
                const content_length = body.len;

                try provision.response.headers_into_writer(provision.header_buffer.writer(rt.allocator), content_length);
                const headers = provision.header_buffer.items;

                var sent: usize = 0;
                const pseudo = Pseudoslice.init(headers, body, provision.recv_slice);

                while (sent < pseudo.len) {
                    const send_slice = pseudo.get(sent, sent + provision.recv_slice.len);

                    const sent_length = secure.send_all(rt, send_slice) catch |e| {
                        log.debug("send failed on socket | {}", .{e});
                        break;
                    };
                    if (sent_length != send_slice.len) break :http_loop;
                    sent += sent_length;
                }

                const connection = provision.request.headers.get("Connection") orelse "keep-alive";
                if (std.mem.eql(u8, connection, "close")) break;
                if (config.keepalive_count_max) |max| {
                    if (keepalive_count > max) {
                        log.debug("closing connection, exceeded keepalive max", .{});
                        break;
                    }

                    keepalive_count += 1;
                }

                try prepare_new_request(&state, provision, config);
            },
        };

        log.info("connection ({}) closed", .{secure.socket.addr});

        if (!accept_queued.*) {
            try rt.spawn(
                .{ rt, config, router, server_socket, provisions, connection_count, accept_queued },
                main_frame,
                config.stack_size,
            );
            accept_queued.* = true;
        }
    }

    const SocketKind = union(enum) {
        normal: Socket,
        secure: SecureSocket,
    };

    /// Serve an HTTP server.
    pub fn serve(self: *Self, rt: *Runtime, router: *const Router, sock: SocketKind) !void {
        log.info("security mode: {s}", .{@tagName(sock)});

        const secure: SecureSocket = switch (sock) {
            .normal => |s| SecureSocket.unsecured(s),
            .secure => |sec| sec,
        };

        const count = self.config.connection_count_max orelse 1024;
        const pooling: PoolKind = if (self.config.connection_count_max == null) .grow else .static;

        const provision_pool = try rt.allocator.create(Pool(Provision));
        provision_pool.* = try Pool(Provision).init(rt.allocator, count, pooling);
        errdefer rt.allocator.destroy(provision_pool);

        const connection_count = try rt.allocator.create(usize);
        errdefer rt.allocator.destroy(connection_count);
        connection_count.* = 0;

        const accept_queued = try rt.allocator.create(bool);
        errdefer rt.allocator.destroy(accept_queued);
        accept_queued.* = true;

        // initialize first batch of provisions :)
        for (provision_pool.items) |*provision| {
            provision.initalized = true;
            provision.zc_recv_buffer = ZeroCopy(u8).init(
                rt.allocator,
                self.config.socket_buffer_bytes,
            ) catch {
                @panic("attempting to allocate more memory than available. (ZeroCopy)");
            };
            provision.header_buffer = std.ArrayList(u8){};
            provision.arena = std.heap.ArenaAllocator.init(rt.allocator);
            provision.captures = rt.allocator.alloc(Capture, self.config.capture_count_max) catch {
                @panic("attempting to allocate more memory than available. (Captures)");
            };
            provision.queries = AnyCaseStringMap.init(rt.allocator);
            provision.storage = TypedStorage.init(rt.allocator);
            provision.request = Request.init(rt.allocator);
            provision.response = Response.init(rt.allocator);
        }

        try rt.spawn(
            .{
                rt,
                self.config,
                router,
                secure,
                provision_pool,
                connection_count,
                accept_queued,
            },
            main_frame,
            self.config.stack_size,
        );
    }
};
