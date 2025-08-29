const std = @import("std");
const Uri = std.Uri;

/// URL utilities for HTTP client - operates directly on std.Uri
pub const url = struct {
    pub const PortPolicy = enum { 
        exact_only, 
        default_for_known_schemes, 
        error_on_unknown 
    };
    
    pub const TargetForm = enum { 
        origin,     // /path?query (normal requests)
        absolute,   // http://host/path?query (proxy requests)
        authority,  // host:port (CONNECT)
        asterisk    // * (OPTIONS)
    };

    /// Case-insensitive scheme check for secure protocols
    pub fn isSecure(uri: Uri) bool {
        return std.ascii.eqlIgnoreCase(uri.scheme, "https") or
               std.ascii.eqlIgnoreCase(uri.scheme, "wss");
    }

    /// Get port with explicit policy for handling missing ports
    pub fn port(uri: Uri, policy: PortPolicy) !u16 {
        if (uri.port) |p| return p;

        switch (policy) {
            .exact_only => return error.PortMissing,
            .default_for_known_schemes => {
                if (std.ascii.eqlIgnoreCase(uri.scheme, "https") or 
                    std.ascii.eqlIgnoreCase(uri.scheme, "wss"))
                    return 443;
                if (std.ascii.eqlIgnoreCase(uri.scheme, "http") or 
                    std.ascii.eqlIgnoreCase(uri.scheme, "ws"))
                    return 80;
                return error.UnknownSchemeNoDefault;
            },
            .error_on_unknown => return error.UnknownSchemeNoDefault,
        }
    }

    /// Get decoded host into caller-provided buffer (no allocations)
    pub fn host(uri: Uri, buf: []u8) ![]const u8 {
        // std.Uri.getHost handles IPv6 literals + percent-decoding
        return try uri.getHost(buf);
    }

    /// Write HTTP/1.1 request-target in the specified form
    pub fn writeRequestTarget(uri: Uri, writer: anytype, form: TargetForm) !void {
        switch (form) {
            .origin => {
                // path (default "/") + optional ?query
                if (uri.path.isEmpty()) {
                    try writer.writeAll("/");
                } else {
                    switch (uri.path) {
                        .raw => |raw| try writer.writeAll(raw),
                        .percent_encoded => |encoded| try writer.writeAll(encoded),
                    }
                }
                
                if (uri.query) |q| {
                    try writer.writeByte('?');
                    switch (q) {
                        .raw => |raw| try writer.writeAll(raw),
                        .percent_encoded => |encoded| try writer.writeAll(encoded),
                    }
                }
            },
            .absolute => {
                // scheme://authority + origin-form (RFC 7230 §5.3.2)
                try writer.writeAll(uri.scheme);
                try writer.writeAll("://");

                // authority = host[:port]
                var tmp: [Uri.host_name_max]u8 = undefined;
                const h = try uri.getHost(&tmp);
                try writer.writeAll(h);

                if (uri.port) |p| {
                    try writer.print(":{d}", .{p});
                }

                // then origin-form
                try writeRequestTarget(uri, writer, .origin);
            },
            .authority => {
                // For CONNECT method: "host[:port]"
                var tmp: [Uri.host_name_max]u8 = undefined;
                const h = try uri.getHost(&tmp);
                try writer.writeAll(h);
                
                if (uri.port) |p| {
                    try writer.print(":{d}", .{p});
                }
            },
            .asterisk => {
                // For OPTIONS * requests
                try writer.writeByte('*');
            },
        }
    }

    /// Helper to decode a URI component into a buffer
    pub fn decodeComponent(buffer: []u8, component: Uri.Component) ![]const u8 {
        switch (component) {
            .raw => |raw| {
                @memcpy(buffer[0..raw.len], raw);
                return buffer[0..raw.len];
            },
            .percent_encoded => |encoded| {
                @memcpy(buffer[0..encoded.len], encoded);
                return Uri.percentDecodeInPlace(buffer[0..encoded.len]);
            },
        }
    }
};