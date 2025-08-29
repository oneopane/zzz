const std = @import("std");
const testing = std.testing;

test "zzz unit tests" {
    // Core
    testing.refAllDecls(@import("./core/any_case_string_map.zig"));
    testing.refAllDecls(@import("./core/pseudoslice.zig"));
    testing.refAllDecls(@import("./core/typed_storage.zig"));

    // HTTP Common
    testing.refAllDecls(@import("./http/common/date.zig"));
    testing.refAllDecls(@import("./http/common/method.zig"));
    testing.refAllDecls(@import("./http/common/mime.zig"));
    testing.refAllDecls(@import("./http/common/status.zig"));
    testing.refAllDecls(@import("./http/common/form.zig"));

    // HTTP Server
    testing.refAllDecls(@import("./http/server/context.zig"));
    testing.refAllDecls(@import("./http/server/request.zig"));
    testing.refAllDecls(@import("./http/server/response.zig"));
    testing.refAllDecls(@import("./http/server/server.zig"));
    testing.refAllDecls(@import("./http/server/sse.zig"));
    testing.refAllDecls(@import("./http/server/router.zig"));
    testing.refAllDecls(@import("./http/server/router/route.zig"));
    testing.refAllDecls(@import("./http/server/router/routing_trie.zig"));
}
