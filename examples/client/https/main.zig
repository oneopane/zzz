const std = @import("std");
const zzz = @import("zzz");
const http = zzz.HTTP;
const tardy = zzz.tardy;

// Example: HTTPS GET request
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize Tardy runtime
    const Tardy = tardy.Tardy(.auto);
    var t = try Tardy.init(allocator, .{ .threading = .single });
    defer t.deinit();

    // Run HTTPS client tests
    try t.entry(
        allocator,
        struct {
            fn entry(rt: *tardy.Runtime, alloc: std.mem.Allocator) !void {
                try rt.spawn(.{ rt, alloc }, run_https_tests, 1024 * 256);
            }
        }.entry,
    );
}

fn run_https_tests(rt: *tardy.Runtime, allocator: std.mem.Allocator) !void {
    // Create HTTP client
    var client = try http.Client.HTTPClient.init(allocator, rt);
    defer client.deinit();

    // Test 1: HTTPS GET request to httpbin.org
    {
        std.debug.print("\n=== Test 1: HTTPS GET request ===\n", .{});
        
        var req = try http.Client.ClientRequest.get(allocator, "https://httpbin.org/get");
        defer req.deinit();
        
        _ = try req.set_header("User-Agent", "zzz-https-client/1.0");
        
        var response = http.Client.ClientResponse.init(allocator);
        defer response.deinit();
        
        client.send(&req, &response) catch |err| {
            std.debug.print("HTTPS request failed: {}\n", .{err});
            std.debug.print("Note: Certificate validation may need configuration\n", .{});
            return err;
        };
        
        std.debug.print("Status: {} {s}\n", .{@intFromEnum(response.status), @tagName(response.status)});
        std.debug.print("Content-Type: {s}\n", .{response.get_header("Content-Type") orelse "not set"});
        
        if (response.body) |body| {
            if (body.len > 500) {
                std.debug.print("Body (first 500 chars):\n{s}...\n", .{body[0..500]});
            } else {
                std.debug.print("Body:\n{s}\n", .{body});
            }
        }
    }

    // Test 2: HTTPS POST request with JSON
    {
        std.debug.print("\n=== Test 2: HTTPS POST request with JSON ===\n", .{});
        
        const json_body = "{\"name\": \"HTTPS Test\", \"secure\": true}";
        var req = try http.Client.ClientRequest.post(allocator, "https://httpbin.org/post", json_body);
        defer req.deinit();
                    
        _ = try req.set_header("Content-Type", "application/json");
        _ = try req.set_header("User-Agent", "zzz-https-client/1.0");
        
        var response = http.Client.ClientResponse.init(allocator);
        defer response.deinit();
        
        client.send(&req, &response) catch |err| {
            std.debug.print("HTTPS POST request failed: {}\n", .{err});
            return err;
        };
        
        std.debug.print("Status: {} {s}\n", .{@intFromEnum(response.status), @tagName(response.status)});
        
        if (response.body) |body| {
            // Parse JSON response to verify our data was received
            const json = try std.json.parseFromSlice(
                struct { 
                    data: []const u8,
                    headers: struct {
                        @"Content-Type": []const u8,
                        @"User-Agent": []const u8,
                    },
                }, 
                allocator, 
                body, 
                .{}
            );
            defer json.deinit();
            
            std.debug.print("Server received our data: {s}\n", .{json.value.data});
            std.debug.print("Server saw Content-Type: {s}\n", .{json.value.headers.@"Content-Type"});
            std.debug.print("Server saw User-Agent: {s}\n", .{json.value.headers.@"User-Agent"});
        }
    }

    // Test 3: HTTPS redirect following
    {
        std.debug.print("\n=== Test 3: HTTPS redirect following ===\n", .{});
        
        var req = try http.Client.ClientRequest.get(allocator, "https://httpbin.org/redirect/2");
        defer req.deinit();
        
        var response = http.Client.ClientResponse.init(allocator);
        defer response.deinit();
        
        client.follow_redirects = true;
        client.max_redirects = 5;
        
        client.send(&req, &response) catch |err| {
            std.debug.print("HTTPS redirect test failed: {}\n", .{err});
            return err;
        };
        
        std.debug.print("Final status after redirects: {} {s}\n", .{@intFromEnum(response.status), @tagName(response.status)});
        
        // Should end up at /get after 2 redirects
        if (response.is_success()) {
            std.debug.print("Successfully followed HTTPS redirects!\n", .{});
        }
    }

    std.debug.print("\n=== All HTTPS tests completed ===\n", .{});
}