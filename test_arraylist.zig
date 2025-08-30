const std = @import("std");

test "ArrayList API" {
    const allocator = std.testing.allocator;
    
    // Test current API
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    
    try list.append('a');
}
