const std = @import("std");
const zzz = @import("zzz");
const tardy = @import("tardy");

const HTTPClient = zzz.http.client.HTTPClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize the async runtime
    var rt = try tardy.Runtime.init(.{});
    defer rt.deinit();
    
    // Create HTTP client
    var client = try HTTPClient.init(allocator, &rt);
    defer client.deinit();
    
    // Example: GET request
    std.debug.print("Making GET request to http://httpbin.org/get\n", .{});
    
    const get_response = client.get("http://httpbin.org/get") catch |err| {
        std.debug.print("GET request failed: {}\n", .{err});
        return;
    };
    defer get_response.deinit();
    
    std.debug.print("GET Status: {}\n", .{get_response.status});
    std.debug.print("GET Success: {}\n", .{get_response.is_success()});
    
    if (get_response.get_header("Content-Type")) |ct| {
        std.debug.print("Content-Type: {s}\n", .{ct});
    }
    
    if (get_response.body) |body| {
        std.debug.print("Body length: {}\n", .{body.len});
        // Print first 200 chars of body
        const preview_len = @min(body.len, 200);
        std.debug.print("Body preview: {s}\n", .{body[0..preview_len]});
    }
    
    // Example: HEAD request
    std.debug.print("\nMaking HEAD request to http://httpbin.org/status/200\n", .{});
    
    const head_response = client.head("http://httpbin.org/status/200") catch |err| {
        std.debug.print("HEAD request failed: {}\n", .{err});
        return;
    };
    defer head_response.deinit();
    
    std.debug.print("HEAD Status: {}\n", .{head_response.status});
    std.debug.print("HEAD Has body: {}\n", .{head_response.body != null});
    
    // Example: Following redirects
    std.debug.print("\nTesting redirect handling (max 2 redirects)\n", .{});
    client.max_redirects = 2;
    
    const redirect_response = client.get("http://httpbin.org/redirect/1") catch |err| {
        std.debug.print("Redirect request failed: {}\n", .{err});
        return;
    };
    defer redirect_response.deinit();
    
    std.debug.print("Final status after redirects: {}\n", .{redirect_response.status});
    std.debug.print("Success: {}\n", .{redirect_response.is_success()});
}