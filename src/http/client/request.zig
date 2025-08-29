const std = @import("std");

const Method = @import("../lib.zig").Method;
const Uri = std.Uri;
const url = @import("url.zig").url;
const AnyCaseStringMap = @import("../../core/any_case_string_map.zig").AnyCaseStringMap;
const CookieMap = @import("../common/cookie.zig").CookieMap;
const Cookie = @import("../common/cookie.zig").Cookie;

pub const ClientRequest = struct {
    allocator: std.mem.Allocator,
    method: Method,
    uri: Uri,
    headers: AnyCaseStringMap,
    cookies: CookieMap,
    body: ?[]const u8 = null,
    timeout_ms: ?u32 = null,
    follow_redirects: ?bool = null,

    pub fn init(allocator: std.mem.Allocator, method: Method, url_string: []const u8) !ClientRequest {
        _ = allocator;
        _ = method;
        _ = url_string;
        @panic("Not implemented");
    }

    pub fn deinit(self: *ClientRequest) void {
        _ = self;
        @panic("Not implemented");
    }

    // Builder methods
    pub fn set_header(self: *ClientRequest, key: []const u8, value: []const u8) !*ClientRequest {
        _ = self;
        _ = key;
        _ = value;
        @panic("Not implemented");
    }

    pub fn set_body(self: *ClientRequest, body: []const u8) *ClientRequest {
        _ = self;
        _ = body;
        @panic("Not implemented");
    }

    pub fn set_json(self: *ClientRequest, value: anytype) !*ClientRequest {
        _ = self;
        _ = value;
        @panic("Not implemented");
    }

    pub fn set_timeout(self: *ClientRequest, timeout_ms: u32) *ClientRequest {
        _ = self;
        _ = timeout_ms;
        @panic("Not implemented");
    }

    pub fn add_cookie(self: *ClientRequest, cookie: Cookie) !*ClientRequest {
        _ = self;
        _ = cookie;
        @panic("Not implemented");
    }

    // Serialization
    pub fn serialize_headers(self: *const ClientRequest, writer: anytype) !void {
        _ = self;
        _ = writer;
        @panic("Not implemented");
    }

    pub fn serialize_full(self: *const ClientRequest, writer: anytype) !void {
        _ = self;
        _ = writer;
        @panic("Not implemented");
    }

    // Internal
    fn build_path_with_query(self: *const ClientRequest) ![]const u8 {
        _ = self;
        @panic("Not implemented");
    }
};

pub const RequestBuilder = struct {
    request: ClientRequest,

    pub fn init(allocator: std.mem.Allocator) RequestBuilder {
        _ = allocator;
        @panic("Not implemented");
    }

    pub fn method(self: *RequestBuilder, m: Method) *RequestBuilder {
        _ = self;
        _ = m;
        @panic("Not implemented");
    }

    pub fn url(self: *RequestBuilder, url_string: []const u8) !*RequestBuilder {
        _ = self;
        _ = url_string;
        @panic("Not implemented");
    }

    pub fn header(self: *RequestBuilder, key: []const u8, value: []const u8) !*RequestBuilder {
        _ = self;
        _ = key;
        _ = value;
        @panic("Not implemented");
    }

    pub fn body(self: *RequestBuilder, b: []const u8) *RequestBuilder {
        _ = self;
        _ = b;
        @panic("Not implemented");
    }

    pub fn json(self: *RequestBuilder, value: anytype) !*RequestBuilder {
        _ = self;
        _ = value;
        @panic("Not implemented");
    }

    pub fn build(self: *RequestBuilder) ClientRequest {
        _ = self;
        @panic("Not implemented");
    }
};