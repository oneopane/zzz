const std = @import("std");
const zzz = @import("zzz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Example 1: Simple GET request
    {
        std.debug.print("\n=== Simple GET Request ===\n", .{});
        var req = try zzz.HTTP.Client.ClientRequest.get(allocator, "http://example.com/api");
        defer req.deinit();
        std.debug.print("Method: {s}, URL: {s}\n", .{ @tagName(req.method), req.uri.scheme });
    }
    
    // Example 2: POST with body
    {
        std.debug.print("\n=== POST Request ===\n", .{});
        const body = "{\"name\": \"test\"}";
        var req = try zzz.HTTP.Client.ClientRequest.post(allocator, "http://api.example.com/users", body);
        defer req.deinit();
        std.debug.print("Method: {s}, Body: {s}\n", .{ @tagName(req.method), req.body.? });
    }
    
    // Example 3: Complex request with builder
    {
        std.debug.print("\n=== Builder Pattern ===\n", .{});
        
        var builder = zzz.HTTP.Client.ClientRequest.builder(allocator);
        defer builder.deinit();
        
        _ = builder.post("https://api.openai.com/v1/chat/completions", "{\"model\":\"gpt-4\"}");
        _ = try builder.header("Authorization", "Bearer sk-test123");
        _ = try builder.header("Content-Type", "application/json");
        _ = builder.timeout(30000);
        _ = builder.follow_redirects(false);
        
        var req = try builder.build();
        defer req.deinit();
        
        std.debug.print("Method: {s}\n", .{@tagName(req.method)});
        std.debug.print("URL: {s}\n", .{req.uri.scheme});
        std.debug.print("Headers count: {}\n", .{req.headers.count()});
        std.debug.print("Timeout: {}ms\n", .{req.timeout_ms.?});
        std.debug.print("Follow redirects: {}\n", .{req.follow_redirects.?});
    }
    
    std.debug.print("\n=== All tests passed! ===\n", .{});
}