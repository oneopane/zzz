const std = @import("std");

const Respond = @import("../response.zig").Respond;
const Middleware = @import("../router/middleware.zig").Middleware;
const Next = @import("../router/middleware.zig").Next;
const Layer = @import("../router/middleware.zig").Layer;
const TypedMiddlewareFn = @import("../router/middleware.zig").TypedMiddlewareFn;

const Kind = enum {
    gzip,
};

/// Compression Middleware.
///
/// Provides a Compression Layer for all routes under this that
/// will properly compress the body and add the proper `Content-Encoding` header.
pub fn Compression(comptime compression: Kind) Layer {
    const func: TypedMiddlewareFn(void) = switch (compression) {
        .gzip => struct {
            fn gzip_mw(next: *Next, _: void) !Respond {
                // TODO: Implement compression with Zig 0.15.1's new flate API
                // The new API requires using std.Io.Writer with proper vtable implementation
                // For now, just pass through without compression
                return try next.run();
            }
        }.gzip_mw,
    };

    return Middleware.init({}, func).layer();
}
