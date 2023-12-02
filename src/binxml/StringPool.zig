//! Android binary xml string pool

const StringPool = @This();

data: Data,

const Data = union(enum) {
    Utf8: struct {
        pool: ArrayList(u8),
        slices: ArrayList(Span),
    },
    Utf16: struct {
        pool: ArrayList(u16),
        slices: ArrayList(Span),
    },
};

pub const Ref = struct {
    index: u32,

    pub fn is_null(self: Ref) bool {
        return self.index == std.math.maxInt(u32);
    }
    pub fn read(reader: anytype) !Ref {
        return Ref{ .index = try reader.readInt(u32, .little) };
    }
    pub fn write(refe: Ref, writer: anytype) !void {
        try writer.write(u32, refe.index, .little);
    }
};

pub fn ref(index: usize) Ref {
    return .{ .index = @as(u32, @intCast(index)) };
}

pub fn get_null_ref(self: StringPool) Ref {
    _ = self;
    return .{ .index = std.math.maxInt(u32) };
}

const Header = struct {
    header: ResourceChunk.Header,
    string_count: u32,
    style_count: ?u32,
    flags: Flags,
    strings_start: u32,
    styles_start: ?u32,

    const Flags = packed struct(u32) {
        sorted: bool,
        _unused1: u7 = 0,
        utf8: bool,
        _unused2: u23 = 0,
    };

    fn read(reader: anytype, chunk_header: ResourceChunk.Header) !Header {
        return Header{
            .header = chunk_header,
            .string_count = try reader.readInt(u32, .little),
            .style_count = try reader.readInt(u32, .little),
            .flags = @as(Flags, @bitCast(try reader.readInt(u32, .little))),
            .strings_start = try reader.readInt(u32, .little),
            .styles_start = try reader.readInt(u32, .little),
        };
    }

    pub fn write(header: Header, writer: anytype) !void {
        try ResourceChunk.Header.write(writer);
        try writer.writeInt(u32, header.string_count, .little);
        try writer.writeInt(u32, header.style_count, .little);
        try writer.writeInt(u32, @as(u32, @bitCast(header.flags)), .little);
        try writer.writeInt(u32, header.strings_start, .little);
        try writer.writeInt(u32, header.styles_start, .little);
    }
};

pub fn get_len(self: StringPool) usize {
    return switch (self.data) {
        inline else => |t| t.slices.items.len,
    };
}

pub fn insert(self: *StringPool, allocator: std.mem.Allocator, string: []const u8) !Ref {
    if (self.data != .Utf8) return error.WrongEncoding;

    for (self.data.Utf8.slices.items, 0..) |span, i| {
        const str = self.data.Utf8.pool.items[span.start..span.end];
        if (std.mem.eql(u8, str, string)) {
            return Ref{ .index = @as(u32, @intCast(i)) };
        }
    }

    const span = .{
        .start = self.data.Utf8.pool.items.len,
        .end = self.data.Utf8.pool.items.len + string.len,
    };
    try self.data.Utf8.pool.appendSlice(allocator, string);
    const index = self.data.Utf8.slices.items.len;
    try self.data.Utf8.slices.append(allocator, span);
    return Ref{ .index = @as(u32, @intCast(index)) };
}

pub fn getUtf16(self: StringPool, refe: Ref) ?[]const u16 {
    return self.getUtf16Raw(refe.index);
}

pub fn getUtf8(self: StringPool, refe: Ref) ?[]const u8 {
    return self.getUtf8Raw(refe.index);
}

pub fn getUtf16Raw(self: StringPool, index: u32) ?[]const u16 {
    if (self.data != .Utf16 or index == std.math.maxInt(u32)) return null;
    const span = self.data.Utf16.slices.items[index];
    return self.data.Utf16.pool.items[span.start..span.end];
}

pub fn getUtf8Raw(self: StringPool, index: u32) ?[]const u8 {
    if (self.data != .Utf8 or index == std.math.maxInt(u32)) return null;
    const span = self.data.Utf8.slices.items[index];
    return self.data.Utf8.pool.items[span.start..span.end];
}

const FullRef = struct {
    pool: StringPool,
    ref: Ref,
};

/// Print the given `utf8` string
fn format(
    full_ref: FullRef,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    null_ref: {
        switch (full_ref.pool.data) {
            .Utf8 => {
                const str = full_ref.pool.getUtf8(full_ref.ref) orelse break :null_ref;
                try writer.print("{s}", .{str});
                return;
            },
            .Utf16 => {
                const formatter = std.unicode.fmtUtf16le(full_ref.pool.getUtf16(full_ref.ref) orelse break :null_ref);
                try writer.print("{}", .{formatter});
                return;
            },
        }
    }
    _ = try writer.writeAll("[NULL]");
}

pub fn get_formatter(self: StringPool, refe: Ref) ?std.fmt.Formatter(format) {
    if (refe.is_null()) return null;
    return .{ .data = .{ .pool = self, .ref = refe } };
}

pub fn readAlloc(seek: anytype, reader: anytype, pos: usize, chunk_header: ResourceChunk.Header, alloc: std.mem.Allocator) !StringPool {
    const header = try Header.read(reader, chunk_header);

    const data: Data = data: {
        if (header.flags.utf8) {
            const buf_size = (header.header.size - header.header.header_size);
            var string_buf = try ArrayList(u8).initCapacity(alloc, buf_size);

            const string_offset = try alloc.alloc(usize, header.string_count);
            defer alloc.free(string_offset);

            // Create slices from offsets
            try seek.seekTo(pos + header.header.header_size);
            for (string_offset) |*offset| {
                offset.* = try reader.readInt(u32, .little);
            }

            // Copy UTF8 buffer into memory
            for (0..string_buf.capacity) |_| {
                string_buf.appendAssumeCapacity(try reader.readInt(u8, .little));
            }

            // Construct slices
            var string_pool = try ArrayList(Span).initCapacity(alloc, header.string_count);
            for (string_offset) |offset| {
                const buf_index = offset;
                const len: usize = string_buf.items[buf_index];
                const add_index: usize = 1;
                string_pool.appendAssumeCapacity(.{
                    .start = buf_index + add_index,
                    .end = buf_index + add_index + len,
                });
            }
            break :data .{
                .Utf8 = .{
                    .pool = string_buf,
                    .slices = string_pool,
                },
            };
        } else {
            const buf_size = (header.header.size - header.header.header_size) / 2;
            var string_buf = try ArrayList(u16).initCapacity(alloc, buf_size);

            const string_offset = try alloc.alloc(usize, header.string_count);
            defer alloc.free(string_offset);

            // Create slices from offsets
            try seek.seekTo(pos + header.header.header_size);
            for (string_offset) |*offset| {
                offset.* = try reader.readInt(u32, .little);
            }

            // Copy UTF16 buffer into memory
            for (0..string_buf.capacity) |_| {
                string_buf.appendAssumeCapacity(try reader.readInt(u16, .little));
            }

            // Construct slices
            var string_pool = try ArrayList(Span).initCapacity(alloc, header.string_count);
            for (string_offset) |offset| {
                const buf_index = offset / 2;
                var len: usize = string_buf.items[buf_index];
                var add_index: usize = 1;
                if (len > 32767) {
                    len = (len & 0b0111_1111) << 16;
                    len += string_buf.items[buf_index + add_index];
                    add_index += 1;
                }
                string_pool.appendAssumeCapacity(.{
                    .start = buf_index + add_index,
                    .end = buf_index + add_index + len,
                });
            }
            break :data .{ .Utf16 = .{
                .pool = string_buf,
                .slices = string_pool,
            } };
        }
    };

    return StringPool{
        .data = data,
    };
}

pub fn read(seek: anytype, reader: anytype, header: Header, string_buf: []u16, string_pool: [][]const u16) !void {
    // Copy UTF16 buffer into memory
    try seek.seekTo(8 + header.strings_start);
    for (string_buf) |*char| {
        char.* = try reader.readInt(u16, .little);
    }
    // Create slices from offsets
    try seek.seekTo(8 + header.header.header_size);
    for (string_pool) |*string| {
        const offset = try reader.readInt(u32, .little);
        std.debug.assert(offset % 2 == 0);
        const index = offset / 2;
        const len: usize = string_buf[index];
        if (len > 32767) {
            len = (len & 0b0111_1111) << 16;
            index += 1;
            len += string_buf[index];
        }
        string.* = string_buf[index + 1 .. index + 1 + len];
    }
}

const Span = struct {
    start: usize,
    end: usize,
};

const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const ResourceChunk = @import("ResourceChunk.zig");
