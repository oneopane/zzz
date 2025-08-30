const std = @import("std");
const testing = std.testing;

// Test core modules separately
test "Core modules" {
    // Core modules - test these separately from HTTP modules
    testing.refAllDecls(@import("./core/any_case_string_map.zig"));
    testing.refAllDecls(@import("./core/pseudoslice.zig"));
    testing.refAllDecls(@import("./core/typed_storage.zig"));
}