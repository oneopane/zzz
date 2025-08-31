const std = @import("std");
const zzz = @import("zzz");
const http = zzz.HTTP;
const tardy = zzz.tardy;
const Tardy = tardy.Tardy(.auto);
const Runtime = tardy.Runtime;

const log = std.log.scoped(.client_pool_example);

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        log.err("Memory leak detected!", .{});
    };
    const allocator = gpa.allocator();

    // Create the Tardy runtime with single threading for client
    log.info("Creating Tardy runtime...", .{});
    var t = try Tardy.init(allocator, .{ .threading = .single });
    defer t.deinit();

    // Run the example in Tardy's entry function
    try t.entry(
        allocator,
        struct {
            fn entry(rt: *Runtime, alloc: std.mem.Allocator) !void {
                try rt.spawn(.{ rt, alloc }, run_pool_demo, 1024 * 256);
            }
        }.entry,
    );
}

fn run_pool_demo(rt: *Runtime, alloc: std.mem.Allocator) !void {
    // Create HTTP client with connection pooling
    log.info("Creating HTTP client with connection pooling...", .{});
    var client = try http.Client.HTTPClient.init(alloc, rt);
    defer client.deinit();

    // Configure the connection pool
    client.set_max_connections_per_host(5);
    client.set_max_idle_time(30000); // 30 seconds

    const url = "http://httpbin.org/get";
    
    log.info("\n=== Connection Pool Demonstration ===\n", .{});
    
    // Make multiple requests to demonstrate connection reuse
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const start_time = std.time.milliTimestamp();
        
        // Create request
        var request = try http.Client.ClientRequest.get(alloc, url);
        defer request.deinit();
        
        // Add query parameter to differentiate requests
        const header_value = try std.fmt.allocPrint(alloc, "{d}", .{i + 1});
        defer alloc.free(header_value);
        _ = try request.set_header("X-Request-Number", header_value);
        
        // Create response object
        var response = http.Client.ClientResponse.init(alloc);
        defer response.deinit();
        
        // Send request
        log.info("Request #{d}: Sending GET to {s}", .{ i + 1, url });
        
        try client.send(&request, &response);
        
        const elapsed = std.time.milliTimestamp() - start_time;
        
        // Check response
        if (response.is_success()) {
            log.info("  ✓ Response: {} - Time: {}ms", .{ response.status, elapsed });
            
            // Show connection pool stats
            const stats = client.get_pool_stats();
            log.info("  Pool Stats: {} idle, {} active, {} pools", .{ 
                stats.total_idle, 
                stats.total_active,
                stats.total_pools 
            });
            
            // Parse and show a bit of the response
            if (response.body) |body| {
                // httpbin returns JSON with our headers
                if (std.mem.indexOf(u8, body, "X-Request-Number")) |_| {
                    log.info("  ✓ Server received our custom header", .{});
                }
            }
        } else {
            log.err("  ✗ Request failed: {}", .{response.status});
        }
        
        // Note: Subsequent requests should be faster due to connection reuse
        if (i == 0) {
            log.info("  (First request includes connection setup)", .{});
        } else if (elapsed < 100) {
            log.info("  ⚡ Fast response - likely reused connection!", .{});
        }
        
        log.info("", .{}); // Empty line for readability
    }
    
    // Show final pool statistics
    log.info("\n=== Final Pool Statistics ===", .{});
    const final_stats = client.get_pool_stats();
    log.info("Idle connections: {}", .{final_stats.total_idle});
    log.info("Active connections: {}", .{final_stats.total_active}); 
    log.info("Total pools: {}", .{final_stats.total_pools});
    
    // Clean up idle connections
    log.info("\nCleaning up idle connections...", .{});
    client.cleanup_idle_connections();
    
    const after_cleanup = client.get_pool_stats();
    log.info("After cleanup - Idle: {}, Active: {}", .{
        after_cleanup.total_idle, 
        after_cleanup.total_active
    });
    
    log.info("\n=== Demonstration Complete ===\n", .{});
    
    // Test with pooling disabled for comparison
    log.info("\n=== Testing without connection pooling ===", .{});
    client.use_connection_pool = false;
    
    const no_pool_start = std.time.milliTimestamp();
    
    var request2 = try http.Client.ClientRequest.get(alloc, url);
    defer request2.deinit();
    
    var response2 = http.Client.ClientResponse.init(alloc);
    defer response2.deinit();
    
    try client.send(&request2, &response2);
    
    const no_pool_elapsed = std.time.milliTimestamp() - no_pool_start;
    
    if (response2.is_success()) {
        log.info("Without pool - Response: {} - Time: {}ms", .{ 
            response2.status, 
            no_pool_elapsed 
        });
        log.info("  (New connection required each time)", .{});
    }
}