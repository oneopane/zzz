const std = @import("std");

/// Simple standalone SSE server for testing
/// Run this separately to test the SSE client
pub fn main() !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 8082);
    
    var server = try address.listen(.{});
    defer server.deinit();
    
    std.debug.print("Simple SSE Server listening on http://127.0.0.1:8082/\n", .{});
    std.debug.print("Connect SSE client to: http://127.0.0.1:8082/events\n\n", .{});
    
    while (true) {
        const connection = try server.accept();
        std.debug.print("Client connected from {any}\n", .{connection.address});
        
        // Handle connection in a simple way
        const allocator = std.heap.page_allocator;
        try handleConnection(allocator, connection.stream);
    }
}

fn handleConnection(_: std.mem.Allocator, stream: std.net.Stream) !void {
    defer stream.close();
    
    // Read request (we'll just assume it's for /events)
    var buf: [4096]u8 = undefined;
    const bytes_read = try stream.read(&buf);
    
    std.debug.print("Request received:\n{s}\n", .{buf[0..bytes_read]});
    
    // Send SSE response headers
    const headers = 
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/event-stream\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "Connection: keep-alive\r\n" ++
        "Access-Control-Allow-Origin: *\r\n" ++
        "\r\n";
    
    _ = try stream.write(headers);
    
    std.debug.print("Sending SSE events...\n", .{});
    
    // Send initial comment
    _ = try stream.write(": Welcome to SSE test server\n\n");
    
    // Send some test events
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        var event_buf: [256]u8 = undefined;
        
        // Send different types of events
        const event = switch (i) {
            0 => try std.fmt.bufPrint(&event_buf, "data: Simple message {d}\n\n", .{i}),
            1 => try std.fmt.bufPrint(&event_buf, "id: {d}\ndata: Message with ID\n\n", .{i}),
            2 => try std.fmt.bufPrint(&event_buf, "event: custom\ndata: Custom event type\n\n", .{}),
            3 => "data: Line 1\ndata: Line 2\ndata: Line 3\n\n",
            4 => "retry: 3000\ndata: Message with retry interval\n\n",
            else => unreachable,
        };
        
        _ = try stream.write(event);
        std.debug.print("Sent event {d}\n", .{i});
        
        // Small delay between events
        std.Thread.sleep(500 * std.time.ns_per_ms);
    }
    
    // Send completion
    _ = try stream.write("event: complete\ndata: [DONE]\n\n");
    std.debug.print("Stream complete\n", .{});
}