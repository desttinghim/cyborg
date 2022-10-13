const std = @import("std");

const Event = enum(u4) {
    DocumentStart = 0,
    DocumentEnd = 1,
    TagStart = 2,
    TagEnd = 3,
    Text = 4,
    CDSect = 5,
    EntityRef = 6,
    IgnorableWhitespace = 7,
    ProcessingInstruction = 8,
    Comment = 9,
    DocDecl = 10,
    Attribute = 0xF,
};

const Type = enum(u4) {
    Null = 1,
    String = 2,
    StringInterned = 3,
    BytesHex = 4,
    BytesBase64 = 5,
    Int = 6,
    IntHex = 7,
    Long = 8,
    LongHex = 9,
    Float = 10,
    Double = 11,
    BoolTrue = 12,
    BoolFalse = 13,
};

const ByteLookup = struct {
    pos: usize,
    length: u16,
};

const TypeValue = union(Type) {
    Null,
    String: []const u8, // Length
    StringInterned: u16, // Id
    BytesHex: ByteLookup,
    BytesBase64: ByteLookup, // Length
    Int: u32,
    IntHex: u32,
    Long: u64,
    LongHex: u64,
    Float: f32,
    Double: f64,
    BoolTrue,
    BoolFalse,
};

const Token = packed struct(u8) {
    event: Event,
    type: Type,
};

const TokenValue = struct {
    token: Token,
    value: TypeValue,
};

const InternedString = struct {
    pos: u16,
    length: u16,
};

pub const Document = struct {
    string_buffer: []const u16,
};

pub fn readAlloc(file: std.fs.File, alloc: std.mem.Allocator) !Document {
    const reader = file.reader();
    var signature: [4]u8 = undefined;
    const count = try reader.read(&signature);
    if (count != 4) return error.UnexpectedEof;

    std.log.debug("magic bytes: {s} {any}", .{ &signature, signature });

    if (!std.mem.eql(u8, &signature, "\x03\x00\x08\x00")) return error.WrongMagicBytes;

    var header: [8]u32 = undefined;
    for (header) |*value| {
        value.* = try reader.readInt(u32, .Little);
        std.log.debug("{}", .{value.*});
    }

    const string_table_end = header[2];
    const string_table_count = header[3];
    const string_table_offset = 0x24 + string_table_count * 4;

    std.log.debug("string table @ {}-{}, {} entries", .{ string_table_offset, string_table_end, string_table_count });
    // try file.seekTo(string_table_offset);
    const string_offsets = try alloc.alloc(u32, string_table_count);
    for (string_offsets) |*offset| {
        offset.* = try reader.readInt(u32, .Little);
    }

    const string_buffer = try alloc.alloc(u16, (string_table_end - string_table_offset) / 2);
    var i: usize = 0;
    var pos: usize = 0;
    while (i < string_table_count) : (i += 1) {
        // std.log.debug("{}", .{try file.getPos()});
        const len = try reader.readInt(u16, .Little);
        const buf = string_buffer[pos..pos + 1 + len];
        pos += len + 1;
        for (buf) |*char| {
            char.* = try reader.readInt(u16, .Little);
        }
        std.log.debug("{s}", .{std.unicode.fmtUtf16le(buf)});
    }

    while (try reader.readInt(u32, .Little) != 0x00100102) {}
    std.log.debug("found start tag at {}", .{try file.getPos()});

    var tag : [5]u32 = undefined;
    for (tag) |*value| {
        value.* = try reader.readInt(u32, .Little);
        std.log.debug("{}", .{value.*});
    }

    return Document{
        .string_buffer = string_buffer,
    };
}
