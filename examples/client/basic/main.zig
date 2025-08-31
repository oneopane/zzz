const std = @import("std");
const zzz = @import("zzz");
const tardy = zzz.tardy;

const HTTPClient = zzz.HTTP.Client.HTTPClient;
const ClientRequest = zzz.HTTP.Client.ClientRequest;
const ClientResponse = zzz.HTTP.Client.ClientResponse;

// Template for consistent output formatting
const ExampleResult = struct {
    name: []const u8,
    url: []const u8,
    method: []const u8,
    status_code: u16,
    status_name: []const u8,
    body_size: ?usize,
    
    fn print(self: ExampleResult) void {
        std.debug.print(
            \\
            \\=== {s} ===
            \\  Method:  {s}
            \\  URL:     {s}
            \\  Status:  {} {s}
            \\  Body:    {} bytes
            \\  Result:  ✓ Success
            \\
        , .{
            self.name,
            self.method,
            self.url,
            self.status_code,
            self.status_name,
            self.body_size orelse 0,
        });
    }
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
    // Initialize HTTP client once for all examples
    var client = try HTTPClient.init(allocator, rt);
    defer client.deinit();
    
    std.debug.print("\n🚀 zzz HTTP Client Examples - Phase 6 Features\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    
    // Run all examples
    try example_get_request(&client, allocator);
    try example_post_with_json(&client, allocator);
    try example_delete_request(&client, allocator);
    try example_request_builder(&client, allocator);
    
    std.debug.print("\n✅ All examples completed successfully!\n\n", .{});
}

fn example_get_request(client: *HTTPClient, allocator: std.mem.Allocator) !void {
    const url = "http://httpbin.org/get";
    
    var request = try ClientRequest.get(allocator, url);
    defer request.deinit();
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&request, &response);
    
    const result = ExampleResult{
        .name = "Basic GET Request",
        .url = url,
        .method = "GET",
        .status_code = @intFromEnum(response.status),
        .status_name = @tagName(response.status),
        .body_size = if (response.body) |b| b.len else null,
    };
    result.print();
}

fn example_post_with_json(client: *HTTPClient, allocator: std.mem.Allocator) !void {
    const url = "http://httpbin.org/post";
    
    var request = try ClientRequest.post(allocator, url, "");
    defer request.deinit();
    
    // Define and serialize a struct to JSON
    const User = struct {
        name: []const u8,
        email: []const u8,
        age: u32,
    };
    
    const user = User{
        .name = "Alice",
        .email = "alice@example.com",
        .age = 28,
    };
    
    _ = try request.set_json(user);
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&request, &response);
    
    const result = ExampleResult{
        .name = "POST with JSON Body",
        .url = url,
        .method = "POST",
        .status_code = @intFromEnum(response.status),
        .status_name = @tagName(response.status),
        .body_size = if (response.body) |b| b.len else null,
    };
    result.print();
}

fn example_delete_request(client: *HTTPClient, allocator: std.mem.Allocator) !void {
    const url = "http://httpbin.org/delete";
    
    var request = try ClientRequest.delete(allocator, url);
    defer request.deinit();
    
    _ = try request.set_header("X-Custom-Header", "test-value");
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&request, &response);
    
    const result = ExampleResult{
        .name = "DELETE Request",
        .url = url,
        .method = "DELETE",
        .status_code = @intFromEnum(response.status),
        .status_name = @tagName(response.status),
        .body_size = if (response.body) |b| b.len else null,
    };
    result.print();
}

fn example_request_builder(client: *HTTPClient, allocator: std.mem.Allocator) !void {
    const url = "http://httpbin.org/put";
    
    var builder = ClientRequest.builder(allocator);
    defer builder.deinit();
    
    const Data = struct {
        message: []const u8,
        value: i32,
    };
    
    const data = Data{
        .message = "Hello from zzz!",
        .value = 42,
    };
    
    _ = try builder
        .put(url, "")
        .json(data);
    _ = try builder.header("User-Agent", "zzz-client/1.0");
    _ = builder.timeout(5000);
    
    var request = try builder.build();
    defer request.deinit();
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    try client.send(&request, &response);
    
    const result = ExampleResult{
        .name = "RequestBuilder with JSON",
        .url = url,
        .method = "PUT",
        .status_code = @intFromEnum(response.status),
        .status_name = @tagName(response.status),
        .body_size = if (response.body) |b| b.len else null,
    };
    result.print();
}