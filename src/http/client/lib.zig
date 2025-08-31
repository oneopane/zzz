// Client module exports
const std = @import("std");

pub const HTTPClient = @import("client.zig").HTTPClient;
pub const ClientRequest = @import("request.zig").ClientRequest;
pub const ClientResponse = @import("response.zig").ClientResponse;
pub const RequestBuilder = @import("request.zig").RequestBuilder;
pub const Connection = @import("connection.zig").Connection;
pub const ConnectionPool = @import("connection_pool.zig").ConnectionPool;
pub const url = @import("url.zig").url;
pub const QueryParams = @import("query.zig").QueryParams;
pub const HTTPProxy = @import("proxy.zig").HTTPProxy;
pub const ProxyConfig = @import("proxy.zig").ProxyConfig;
pub const Upstream = @import("proxy.zig").Upstream;

// Streaming support
pub const streaming = @import("streaming.zig");
pub const sse_parser = @import("sse_parser.zig");
pub const chunked_parser = @import("chunked_parser.zig");
pub const StreamingResponse = streaming.StreamingResponse;
pub const StreamIterator = streaming.StreamIterator;
pub const StreamConfig = streaming.StreamConfig;
pub const SSEParser = sse_parser.SSEParser;
pub const SSEMessage = sse_parser.SSEMessage;
pub const ChunkedParser = chunked_parser.ChunkedParser;

// Re-export commonly used types for convenience
pub const Client = HTTPClient;
pub const Request = ClientRequest;
pub const Response = ClientResponse;
pub const Proxy = HTTPProxy;