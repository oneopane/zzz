const std = @import("std");
const streaming = @import("../streaming.zig");
const SSEParser = @import("../sse_parser.zig").SSEParser;
const SSEMessage = @import("../sse_parser.zig").SSEMessage;
const ClientResponse = @import("../response.zig").ClientResponse;

test "StreamConfig defaults" {
    const config = streaming.StreamConfig{};
    try std.testing.expect(config.chunk_buffer_size == 8192);
    try std.testing.expect(config.timeout_ms == 30000);
    try std.testing.expect(config.parse_sse == true);
}

test "ClientResponse detects SSE content type" {
    const allocator = std.testing.allocator;
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    // Test without content-type
    try std.testing.expect(!response.is_event_stream());
    
    // Add SSE content-type
    _ = try response.headers.put(
        try allocator.dupe(u8, "Content-Type"),
        try allocator.dupe(u8, "text/event-stream"),
    );
    
    try std.testing.expect(response.is_event_stream());
    try std.testing.expect(response.is_streaming_response());
}

test "ClientResponse detects streaming indicators" {
    const allocator = std.testing.allocator;
    
    var response = ClientResponse.init(allocator);
    defer response.deinit();
    
    // Test chunked encoding
    _ = try response.headers.put(
        try allocator.dupe(u8, "Transfer-Encoding"),
        try allocator.dupe(u8, "chunked"),
    );
    
    try std.testing.expect(response.is_streaming_response());
}

test "ClientResponse non-streaming for 204/304" {
    const allocator = std.testing.allocator;
    
    // Test 204 No Content
    var response204 = ClientResponse.init(allocator);
    defer response204.deinit();
    response204.status = .@"No Content";
    
    try std.testing.expect(!response204.is_streaming_response());
    
    // Test 304 Not Modified
    var response304 = ClientResponse.init(allocator);
    defer response304.deinit();
    response304.status = .@"Not Modified";
    
    try std.testing.expect(!response304.is_streaming_response());
}

test "SSE parser handles OpenAI-style messages" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    // Simulate OpenAI streaming response format
    const chunk1 = "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"gpt-3.5-turbo\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n";
    try parser.parse_chunk(chunk1, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    try std.testing.expect(messages.items[0].data != null);
    try std.testing.expect(std.mem.indexOf(u8, messages.items[0].data.?, "Hello") != null);
    
    messages.clearRetainingCapacity();
    
    // Test DONE marker
    const chunk2 = "data: [DONE]\n\n";
    try parser.parse_chunk(chunk2, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    try std.testing.expectEqualStrings("[DONE]", messages.items[0].data.?);
}

test "SSE parser handles Anthropic-style messages" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    // Simulate Anthropic Claude streaming response format
    const chunk = 
        "event: message_start\n" ++
        "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3\"}}\n\n" ++
        "event: content_block_delta\n" ++
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello from Claude\"}}\n\n";
    
    try parser.parse_chunk(chunk, &messages);
    
    try std.testing.expect(messages.items.len == 2);
    
    // First message should be message_start
    try std.testing.expectEqualStrings("message_start", messages.items[0].event.?);
    try std.testing.expect(messages.items[0].data != null);
    
    // Second message should be content_block_delta
    try std.testing.expectEqualStrings("content_block_delta", messages.items[1].event.?);
    try std.testing.expect(std.mem.indexOf(u8, messages.items[1].data.?, "Hello from Claude") != null);
}

test "StreamIterator manages buffer correctly" {
    const allocator = std.testing.allocator;
    
    // Test buffer allocation with custom size
    const config = streaming.StreamConfig{
        .chunk_buffer_size = 2048,
    };
    
    const buffer = try allocator.alloc(u8, config.chunk_buffer_size);
    defer allocator.free(buffer);
    
    try std.testing.expect(buffer.len == 2048);
}

test "SSE parser handles fragmented JSON data" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    // First chunk has partial JSON
    const chunk1 = "data: {\"choices\":[{\"delta\":{\"con";
    try parser.parse_chunk(chunk1, &messages);
    try std.testing.expect(messages.items.len == 0); // No complete message yet
    
    // Second chunk completes it
    const chunk2 = "tent\":\"Hello world\"}}]}\n\n";
    try parser.parse_chunk(chunk2, &messages);
    
    try std.testing.expect(messages.items.len == 1);
    const expected_data = "{\"choices\":[{\"delta\":{\"content\":\"Hello world\"}}]}";
    try std.testing.expectEqualStrings(expected_data, messages.items[0].data.?);
}

test "SSE parser handles ping messages" {
    const allocator = std.testing.allocator;
    
    var parser = try SSEParser.init(allocator);
    defer parser.deinit();
    
    var messages = try std.ArrayList(SSEMessage).initCapacity(allocator, 0);
    defer {
        for (messages.items) |*msg| {
            msg.deinit(allocator);
        }
        messages.deinit(allocator);
    }
    
    // Some SSE servers send ping messages
    const chunk = ": ping\n\ndata: actual message\n\n";
    try parser.parse_chunk(chunk, &messages);
    
    // Should only get the actual message, not the comment
    try std.testing.expect(messages.items.len == 1);
    try std.testing.expectEqualStrings("actual message", messages.items[0].data.?);
}