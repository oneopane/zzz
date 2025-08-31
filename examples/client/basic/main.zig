const std = @import("std");
const zzz = @import("zzz");
const tardy = zzz.tardy;

const HTTPClient = zzz.HTTP.Client.HTTPClient;

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize Tardy runtime
    const Tardy = tardy.Tardy(.auto);
    var t = try Tardy.init(allocator, .{ .threading = .single });
    defer t.deinit();
    
    // Run HTTP client
    try t.entry(
        allocator,
        struct {
            fn entry(rt: *tardy.Runtime, alloc: std.mem.Allocator) !void {
                try rt.spawn(.{ rt, alloc }, run_client, 1024 * 256);
            }
        }.entry,
    );
}

fn run_client(rt: *tardy.Runtime, allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Basic HTTP GET Request ===\n\n", .{});
    
    // Initialize HTTP client
    var client = try HTTPClient.init(allocator, rt);
    defer client.deinit();
    
    // Perform a simple GET request
    const url = "http://httpbin.org/get";
    std.debug.print("Fetching: {s}\n", .{url});
    
    // Create request object that we own
    var request = try zzz.HTTP.Client.ClientRequest.get(allocator, url);
    defer request.deinit();
    
    // Create response object that we own
    var response = zzz.HTTP.Client.ClientResponse.init(allocator);
    defer response.deinit();
    
    // Send the request
    try client.send(&request, &response);
    
    // Print response status
    std.debug.print("Status: {} {s}\n", .{ 
        @intFromEnum(response.status),
        @tagName(response.status)
    });
    
    // Print response headers
    std.debug.print("\nHeaders:\n", .{});
    var header_iter = response.headers.iterator();
    while (header_iter.next()) |entry| {
        std.debug.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    
    // Print response body
    if (response.body) |body| {
        std.debug.print("\nBody ({} bytes):\n{s}\n", .{ body.len, body });
    } else {
        std.debug.print("\nNo response body\n", .{});
    }
    
    std.debug.print("\n=== Request completed successfully! ===\n\n", .{});
}