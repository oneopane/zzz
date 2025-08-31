const std = @import("std");
const zzz = @import("zzz");
const http = zzz.HTTP;
const tardy = zzz.tardy;

/// Example demonstrating HTTP client streaming capabilities
/// Shows both callback-based and iterator-based streaming patterns
pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize Tardy runtime
    const Tardy = tardy.Tardy(.auto);
    var t = try Tardy.init(allocator, .{ .threading = .single });
    defer t.deinit();
    
    // Run HTTP client in async context
    try t.entry(
        allocator,
        struct {
            fn entry(rt: *tardy.Runtime, alloc: std.mem.Allocator) !void {
                try rt.spawn(.{ rt, alloc }, run_streaming_examples, 1024 * 256);
            }
        }.entry,
    );
}

fn run_streaming_examples(rt: *tardy.Runtime, allocator: std.mem.Allocator) !void {
    // Create HTTP client
    var client = try http.Client.HTTPClient.init(allocator, rt);
    defer client.deinit();

    std.debug.print("\n=== HTTP Client Streaming Examples ===\n\n", .{});

    // Example 1: Stream chunked data with callback
    try stream_with_callback(&client, allocator);
    
    // Example 2: Stream with iterator pattern
    try stream_with_iterator(&client, allocator);
    
    // Example 3: Stream SSE (Server-Sent Events)
    // Note: This would require an SSE endpoint to test against
    // try stream_sse(&client, allocator);
}

fn stream_with_callback(client: *http.Client.HTTPClient, allocator: std.mem.Allocator) !void {
    std.debug.print("1. Streaming with callback pattern:\n", .{});
    std.debug.print("   Requesting httpbin.org/stream/5...\n\n", .{});
    
    // Create request for streaming endpoint
    var req = try http.Client.ClientRequest.get(allocator, "http://httpbin.org/stream/5");
    defer req.deinit();
    
    // Context for callback
    const CallbackContext = struct {
        line_count: usize = 0,
    };
    
    var context = CallbackContext{};
    
    // Define callback function
    const chunk_handler = struct {
        fn callback(chunk: []const u8, user_context: ?*anyopaque) anyerror!void {
            const ctx = @as(*CallbackContext, @ptrCast(@alignCast(user_context.?)));
            
            // Count lines in chunk
            var lines = std.mem.tokenizeSequence(u8, chunk, "\n");
            while (lines.next()) |line| {
                if (line.len > 0) {
                    ctx.line_count += 1;
                    std.debug.print("   [Line {d}] Received {d} bytes\n", .{ ctx.line_count, line.len });
                    
                    // Parse and display a sample of the JSON data
                    if (ctx.line_count == 1) {
                        const parsed = std.json.parseFromSlice(
                            struct { url: []const u8, id: u32 },
                            std.heap.page_allocator,
                            line,
                            .{},
                        ) catch {
                            std.debug.print("     (Could not parse JSON)\n", .{});
                            continue;
                        };
                        defer parsed.deinit();
                        std.debug.print("     Sample: url={s}, id={d}\n", .{ parsed.value.url, parsed.value.id });
                    }
                }
            }
        }
    }.callback;
    
    // Stream with callback
    const config = http.Client.streaming.StreamConfig{
        .chunk_buffer_size = 4096,
        .parse_sse = false, // This is not SSE
    };
    
    try client.send_streaming(&req, chunk_handler, &context, config);
    
    std.debug.print("   Total lines received: {d}\n\n", .{context.line_count});
}

fn stream_with_iterator(client: *http.Client.HTTPClient, allocator: std.mem.Allocator) !void {
    std.debug.print("2. Streaming with iterator pattern:\n", .{});
    std.debug.print("   Requesting httpbin.org/stream/3...\n\n", .{});
    
    // Create request
    var req = try http.Client.ClientRequest.get(allocator, "http://httpbin.org/stream/3");
    defer req.deinit();
    
    // Get stream iterator
    const config = http.Client.streaming.StreamConfig{
        .chunk_buffer_size = 4096,
        .parse_sse = false,
    };
    
    var iter = try client.send_streaming_iter(&req, config);
    defer client.destroy_stream_iterator(iter);
    
    var line_count: usize = 0;
    
    // Consume chunks with iterator
    while (try iter.next_chunk()) |chunk| {
        // Process each line in the chunk
        var lines = std.mem.tokenizeSequence(u8, chunk, "\n");
        while (lines.next()) |line| {
            if (line.len > 0) {
                line_count += 1;
                std.debug.print("   [Line {d}] Received {d} bytes\n", .{ line_count, line.len });
            }
        }
    }
    
    std.debug.print("   Total lines received: {d}\n\n", .{line_count});
}

// Example SSE streaming (would need a real SSE endpoint)
fn stream_sse(client: *http.Client.HTTPClient, allocator: std.mem.Allocator) !void {
    std.debug.print("3. Streaming Server-Sent Events (SSE):\n", .{});
    
    // This is a mock example - you'd need a real SSE endpoint
    // For example, you could use: https://sse.dev/test
    
    var req = try http.Client.ClientRequest.get(allocator, "https://sse.dev/test");
    defer req.deinit();
    _ = try req.set_header("Accept", "text/event-stream");
    
    const SSEContext = struct {
        event_count: usize = 0,
    };
    
    var context = SSEContext{};
    
    const sse_handler = struct {
        fn callback(message: http.Client.sse_parser.SSEMessage, user_context: ?*anyopaque) anyerror!void {
            const ctx = @as(*SSEContext, @ptrCast(@alignCast(user_context.?)));
            ctx.event_count += 1;
            
            std.debug.print("   [Event {d}]\n", .{ctx.event_count});
            if (message.id) |id| {
                std.debug.print("     ID: {s}\n", .{id});
            }
            if (message.event) |event| {
                std.debug.print("     Type: {s}\n", .{event});
            }
            if (message.data) |data| {
                std.debug.print("     Data: {s}\n", .{data});
            }
            if (message.retry) |retry| {
                std.debug.print("     Retry: {d}ms\n", .{retry});
            }
            
            // Stop after a few events for demo
            if (ctx.event_count >= 5) {
                return error.StopStreaming;
            }
        }
    }.callback;
    
    const config = http.Client.streaming.StreamConfig{
        .chunk_buffer_size = 4096,
        .parse_sse = true,
        .timeout_ms = 10000, // 10 second timeout
    };
    
    client.send_streaming_sse(&req, sse_handler, &context, config) catch |err| {
        if (err == error.StopStreaming) {
            std.debug.print("   Stopped after {d} events\n", .{context.event_count});
        } else {
            return err;
        }
    };
}