const std = @import("std");
const URL = @import("src/http/client/url.zig").URL;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test the existing URL wrapper
    const url = try URL.parse("https://example.com:8080/path?query=value");
    
    std.debug.print("Port: {d}\n", .{url.get_port()});
    std.debug.print("Is secure: {}\n", .{url.is_secure()});
    
    // Test get_host
    var host_buffer: [256]u8 = undefined;
    const host = try url.get_host(host_buffer[0..]);
    std.debug.print("Host: {s}\n", .{host});
    
    // Test get_request_path
    var path_buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(path_buffer[0..]);
    try url.get_request_path(fbs.writer());
    std.debug.print("Request path: {s}\n", .{fbs.getWritten()});

    // Test more URLs
    const test_urls = [_][]const u8{
        "https://example.com",
        "http://localhost:3000",
        "https://example.com/path",
        "https://example.com/path?query=value&param=test",
        "https://api.github.com/repos/owner/repo",
    };

    for (test_urls) |test_url| {
        const parsed_url = URL.parse(test_url) catch |err| {
            std.debug.print("Error parsing {s}: {}\n", .{ test_url, err });
            continue;
        };
        
        var host_buf: [256]u8 = undefined;
        const decoded_host = parsed_url.get_host(host_buf[0..]) catch |err| {
            std.debug.print("Error getting host for {s}: {}\n", .{ test_url, err });
            continue;
        };
        
        var path_buf: [1024]u8 = undefined;
        var path_fbs = std.io.fixedBufferStream(path_buf[0..]);
        parsed_url.get_request_path(path_fbs.writer()) catch |err| {
            std.debug.print("Error getting request path for {s}: {}\n", .{ test_url, err });
            continue;
        };
        
        std.debug.print("\nURL: {s}\n", .{test_url});
        std.debug.print("  Host: {s}\n", .{decoded_host});
        std.debug.print("  Port: {d}\n", .{parsed_url.get_port()});
        std.debug.print("  Secure: {}\n", .{parsed_url.is_secure()});
        std.debug.print("  Request Path: {s}\n", .{path_fbs.getWritten()});
    }
}