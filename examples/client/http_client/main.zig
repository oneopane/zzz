const std = @import("std");
const zzz = @import("zzz");
const tardy = zzz.tardy;
const log = std.log.scoped(.http_client_example);

const HTTPClient = zzz.HTTP.Client.HTTPClient;

// Configuration
const Config = struct {
    const stack_size = 1024 * 1024; // 1MB stack for HTTP client task
    const httpbin_base = "http://httpbin.org";
};

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize Tardy runtime
    const Tardy = tardy.Tardy(.auto);
    var t = try Tardy.init(allocator, .{ .threading = .single });
    defer t.deinit();
    
    // Run HTTP client examples
    try t.entry(
        allocator,
        struct {
            fn entry(rt: *tardy.Runtime, alloc: std.mem.Allocator) !void {
                try rt.spawn(.{ rt, alloc }, run_examples, Config.stack_size);
            }
        }.entry,
    );
}

fn run_examples(rt: *tardy.Runtime, allocator: std.mem.Allocator) !void {
    log.info("HTTP Client Examples\n", .{});
    log.info("====================\n", .{});
    
    // Initialize HTTP client
    var client = try HTTPClient.init(allocator, rt);
    defer client.deinit();
    
    // Run examples
    try example_get_request(&client);
    try example_head_request(&client);
    try example_redirect_handling(&client);
    try example_json_response(&client);
    try example_status_codes(&client);
    
    log.info("\nAll examples completed successfully!\n", .{});
}

// Example 1: Basic GET request
fn example_get_request(client: *HTTPClient) !void {
    log.info("\n1. GET Request Example\n", .{});
    log.info("----------------------\n", .{});
    
    const url = Config.httpbin_base ++ "/get";
    log.info("   URL: {s}\n", .{url});
    
    var response = try client.get(url);
    defer response.deinit();
    
    log.info("   Status: {} ({s})\n", .{ @intFromEnum(response.status), @tagName(response.status) });
    log.info("   Success: {}\n", .{response.is_success()});
    
    // Display headers
    if (response.get_header("Content-Type")) |ct| {
        log.info("   Content-Type: {s}\n", .{ct});
    }
    if (response.get_header("Server")) |server| {
        log.info("   Server: {s}\n", .{server});
    }
    
    // Display body info
    if (response.body) |body| {
        log.info("   Body size: {} bytes\n", .{body.len});
        
        // Show a preview of the response
        const preview_len = @min(body.len, 100);
        log.info("   Body preview: {s}...\n", .{body[0..preview_len]});
    }
}

// Example 2: HEAD request
fn example_head_request(client: *HTTPClient) !void {
    log.info("\n2. HEAD Request Example\n", .{});
    log.info("-----------------------\n", .{});
    
    const url = Config.httpbin_base ++ "/status/200";
    log.info("   URL: {s}\n", .{url});
    
    var response = try client.head(url);
    defer response.deinit();
    
    log.info("   Status: {} ({s})\n", .{ @intFromEnum(response.status), @tagName(response.status) });
    log.info("   Has body: {} (should be false for HEAD)\n", .{response.body != null});
    
    if (response.get_content_length()) |len| {
        log.info("   Content-Length: {}\n", .{len});
    }
}

// Example 3: Redirect handling
fn example_redirect_handling(client: *HTTPClient) !void {
    log.info("\n3. Redirect Handling Example\n", .{});
    log.info("-----------------------------\n", .{});
    
    // Configure redirect behavior
    const original_max = client.max_redirects;
    client.max_redirects = 3;
    defer client.max_redirects = original_max;
    
    const url = Config.httpbin_base ++ "/redirect/2";
    log.info("   URL: {s}\n", .{url});
    log.info("   Max redirects: {}\n", .{client.max_redirects});
    
    var response = client.get(url) catch |err| {
        log.err("   Redirect failed: {}\n", .{err});
        return err;
    };
    defer response.deinit();
    
    log.info("   Final status: {} ({s})\n", .{ @intFromEnum(response.status), @tagName(response.status) });
    log.info("   Success: {}\n", .{response.is_success()});
    
    // Show final URL info if available
    if (response.body) |body| {
        log.info("   Reached final destination (body size: {} bytes)\n", .{body.len});
    }
}

// Example 4: JSON response handling
fn example_json_response(client: *HTTPClient) !void {
    log.info("\n4. JSON Response Example\n", .{});
    log.info("------------------------\n", .{});
    
    const url = Config.httpbin_base ++ "/json";
    log.info("   URL: {s}\n", .{url});
    
    var response = try client.get(url);
    defer response.deinit();
    
    log.info("   Status: {} ({s})\n", .{ @intFromEnum(response.status), @tagName(response.status) });
    
    if (response.get_header("Content-Type")) |ct| {
        log.info("   Content-Type: {s}\n", .{ct});
    }
    
    if (response.body) |body| {
        log.info("   JSON response size: {} bytes\n", .{body.len});
        
        // Show formatted JSON preview
        const preview_len = @min(body.len, 150);
        log.info("   JSON preview: {s}...\n", .{body[0..preview_len]});
    }
}

// Example 5: Different status codes
fn example_status_codes(client: *HTTPClient) !void {
    log.info("\n5. Status Codes Example\n", .{});
    log.info("------------------------\n", .{});
    
    const test_codes = [_]u16{ 200, 404, 500 };
    
    for (test_codes) |code| {
        const url = try std.fmt.allocPrint(
            client.allocator,
            "{s}/status/{}",
            .{ Config.httpbin_base, code },
        );
        defer client.allocator.free(url);
        
        log.info("\n   Testing status code: {}\n", .{code});
        log.info("   URL: {s}\n", .{url});
        
        var response = client.get(url) catch |err| {
            // Some status codes might be treated as errors
            log.info("   Request returned error: {}\n", .{err});
            continue;
        };
        defer response.deinit();
        
        log.info("   Received: {} ({s})\n", .{ @intFromEnum(response.status), @tagName(response.status) });
        log.info("   Is success (2xx): {}\n", .{response.is_success()});
        log.info("   Is redirect (3xx): {}\n", .{response.is_redirect()});
    }
}