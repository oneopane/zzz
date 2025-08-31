const std = @import("std");
const zzz = @import("zzz");
const http = zzz.HTTP;
const tardy = zzz.tardy;

/// Simple SSE test server for testing SSE client implementation
/// Sends Server-Sent Events every second
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Tardy = tardy.Tardy(.auto);
    var t = try Tardy.init(allocator, .{ .threading = .single });
    defer t.deinit();

    var router = http.Router.init(allocator);
    defer router.deinit();
    
    // SSE endpoint
    router.serve("/events", &.{serve_sse});
    
    // Test endpoint that sends events periodically
    router.serve("/test-sse", &.{serve_test_sse});

    // Create and bind socket
    const tcp = try std.net.tcpConnectToAddress(
        try std.net.Address.parseIp4("127.0.0.1", 8081),
    );
    defer tcp.close();

    std.debug.print("SSE Test Server running on http://127.0.0.1:8081\n", .{});
    std.debug.print("Endpoints:\n", .{});
    std.debug.print("  /events     - SSE endpoint with periodic events\n", .{});
    std.debug.print("  /test-sse   - Test SSE with counter\n\n", .{});

    const Server = http.Server(.plain);
    try t.entry(
        allocator,
        try Server.init(.{
            .allocator = allocator,
            .socket = tcp,
            .router = &router,
        }),
        Server.serve,
        Server.clean,
    );
}

/// Serve SSE events
fn serve_sse(ctx: *const http.Context, _: *const anyopaque) !http.Response {
    // Set SSE headers
    try ctx.response.headers.put("Content-Type", "text/event-stream");
    try ctx.response.headers.put("Cache-Control", "no-cache");
    try ctx.response.headers.put("Connection", "keep-alive");
    try ctx.response.headers.put("X-Accel-Buffering", "no"); // Disable Nginx buffering
    
    // Send initial response headers
    try ctx.response.writeHead(.OK);
    
    // Send some events
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        // Format SSE event
        var buf: [256]u8 = undefined;
        const event = try std.fmt.bufPrint(&buf, 
            "id: {d}\ndata: Event number {d} at {d}\n\n", 
            .{ i, i, std.time.milliTimestamp() }
        );
        
        // Send event
        try ctx.response.write(event);
        try ctx.response.flush();
        
        // Wait 1 second
        std.time.sleep(1 * std.time.ns_per_s);
    }
    
    // Send completion event
    try ctx.response.write("event: complete\ndata: Stream complete\n\n");
    try ctx.response.flush();
    
    return .streaming;
}

/// Test SSE endpoint with simple counter
fn serve_test_sse(ctx: *const http.Context, _: *const anyopaque) !http.Response {
    // Set SSE headers
    try ctx.response.headers.put("Content-Type", "text/event-stream");
    try ctx.response.headers.put("Cache-Control", "no-cache");
    
    try ctx.response.writeHead(.OK);
    
    // Send a few test events
    try ctx.response.write(": This is a comment\n\n");
    try ctx.response.write("data: First message\n\n");
    try ctx.response.write("id: 1\ndata: Message with ID\n\n");
    try ctx.response.write("event: custom\ndata: Custom event type\n\n");
    try ctx.response.write("data: Multi-line\ndata: message\ndata: here\n\n");
    try ctx.response.write("retry: 5000\ndata: Message with retry\n\n");
    
    // Final event
    try ctx.response.write("event: close\ndata: [DONE]\n\n");
    try ctx.response.flush();
    
    return .streaming;
}