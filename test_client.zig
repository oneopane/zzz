const std = @import("std");
const testing = std.testing;

test "import and compile client" {
    // Just test that it compiles
    _ = @import("src/http/client/client.zig");
    try testing.expect(true);
}