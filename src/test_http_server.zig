const std = @import("std");
const testing = std.testing;

// Test HTTP server modules separately  
test "HTTP Server modules" {
    testing.refAllDecls(@import("./http/server/context.zig"));
    testing.refAllDecls(@import("./http/server/request.zig"));
    testing.refAllDecls(@import("./http/server/response.zig"));
    testing.refAllDecls(@import("./http/server/server.zig"));
    testing.refAllDecls(@import("./http/server/sse.zig"));
    testing.refAllDecls(@import("./http/server/router.zig"));
    testing.refAllDecls(@import("./http/server/router/route.zig"));
    testing.refAllDecls(@import("./http/server/router/routing_trie.zig"));
}