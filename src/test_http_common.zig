const std = @import("std");
const testing = std.testing;

// Test HTTP common modules separately
test "HTTP Common modules" {
    testing.refAllDecls(@import("./http/common/date.zig"));
    testing.refAllDecls(@import("./http/common/method.zig"));
    testing.refAllDecls(@import("./http/common/mime.zig"));
    testing.refAllDecls(@import("./http/common/status.zig"));
    testing.refAllDecls(@import("./http/common/form.zig"));
}