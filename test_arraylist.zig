const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test ArrayList initialization
    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);
    
    try list.append(allocator, 42);
    std.debug.print("Value: {}\n", .{list.items[0]});
}
