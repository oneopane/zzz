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
    
    // Run HTTP client example
    try t.entry(
        allocator,
        struct {
            fn entry(rt: *tardy.Runtime, alloc: std.mem.Allocator) !void {
                try rt.spawn(.{ rt, alloc }, run_client, 1024 * 512);
            }
        }.entry,
    );
}

fn run_client(rt: *tardy.Runtime, allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Simple HTTP Client Example ===\n\n", .{});
    
    // Initialize HTTP client
    var client = try HTTPClient.init(allocator, rt);
    defer client.deinit();
    
    // Example 1: Simple GET request
    {
        std.debug.print("1. GET Request:\n", .{});
        std.debug.print("   Fetching: http://httpbin.org/get\n", .{});
        
        var response = try client.get("http://httpbin.org/get");
        defer response.deinit();
        
        std.debug.print("   ✓ Status: {} ({s})\n", .{ 
            @intFromEnum(response.status), 
            if (response.is_success()) "success" else "failed" 
        });
        
        if (response.body) |body| {
            std.debug.print("   ✓ Received {} bytes of data\n", .{body.len});
        }
        std.debug.print("\n", .{});
    }
    
    // Example 2: HEAD request (no body)
    {
        std.debug.print("2. HEAD Request:\n", .{});
        std.debug.print("   Checking: http://httpbin.org/status/200\n", .{});
        
        var response = try client.head("http://httpbin.org/status/200");
        defer response.deinit();
        
        std.debug.print("   ✓ Status: {}\n", .{@intFromEnum(response.status)});
        std.debug.print("   ✓ Body present: {}\n", .{response.body != null});
        std.debug.print("\n", .{});
    }
    
    // Example 3: Different status codes
    {
        std.debug.print("3. Status Code Handling:\n", .{});
        
        const urls = [_][]const u8{
            "http://httpbin.org/status/200",
            "http://httpbin.org/status/404",
        };
        
        for (urls) |url| {
            std.debug.print("   Checking: {s}\n", .{url});
            
            var response = client.get(url) catch |err| {
                std.debug.print("   ✗ Error: {}\n", .{err});
                continue;
            };
            defer response.deinit();
            
            const status_code = @intFromEnum(response.status);
            const status_type = if (status_code >= 200 and status_code < 300)
                "success"
            else if (status_code >= 400 and status_code < 500)
                "client error"
            else if (status_code >= 500)
                "server error"
            else
                "other";
            
            std.debug.print("   ✓ Got {} ({s})\n", .{ status_code, status_type });
        }
        std.debug.print("\n", .{});
    }
    
    // Example 4: JSON API response
    {
        std.debug.print("4. JSON Response:\n", .{});
        std.debug.print("   Fetching: http://httpbin.org/json\n", .{});
        
        var response = try client.get("http://httpbin.org/json");
        defer response.deinit();
        
        if (response.is_success()) {
            if (response.get_header("Content-Type")) |ct| {
                std.debug.print("   ✓ Content-Type: {s}\n", .{ct});
            }
            
            if (response.body) |body| {
                std.debug.print("   ✓ JSON data: {} bytes\n", .{body.len});
                
                // Show a preview of the JSON
                const preview_len = @min(body.len, 80);
                std.debug.print("   ✓ Preview: {s}...\n", .{body[0..preview_len]});
            }
        }
        std.debug.print("\n", .{});
    }
    
    std.debug.print("=== All examples completed! ===\n\n", .{});
}