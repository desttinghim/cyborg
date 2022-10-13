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
    string_buffer: std.ArrayList(u8),
    string_id: std.ArrayList(InternedString),
    bytes_buffer: std.ArrayList(u8),
    tokens: std.ArrayList(TokenValue),
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

    const string_table_offset = header[2];
    const string_table_count = header[3];

    std.log.debug("string table @ {}, {} entries", .{ string_table_offset, string_table_count });

    var string_offsets = try alloc.alloc(u32, string_table_count);
    for (string_offsets) |*offset| {
        offset.* = try reader.readInt(u32, .Little);
        std.log.debug("offset {}", .{offset.*});
    }

    var string_buffer = std.ArrayList(u8).init(alloc);
    errdefer string_buffer.deinit();
    var string_id = std.ArrayList(InternedString).init(alloc);
    errdefer string_id.deinit();
    var bytes_buffer = std.ArrayList(u8).init(alloc);
    errdefer bytes_buffer.deinit();
    var tokens = std.ArrayList(TokenValue).init(alloc);
    errdefer tokens.deinit();
    while (reader.readByte() catch null) |byte| {
        const event_num: u4 = @intCast(u4, byte & 0x0F);
        const _type_num: u4 = @intCast(u4, byte & 0xF0 >> 4);
        const event = try std.meta.intToEnum(Event, event_num);
        const _type = try std.meta.intToEnum(Type, _type_num);
        const token = Token{ .event = event, .type = _type };
        switch (_type) {
            .Null => {
                try tokens.append(TokenValue{ .token = token, .value = .Null });
            },
            .String => {
                const length = try reader.readInt(u16, .Little);
                const buf = try alloc.alloc(u8, length);
                _ = try reader.read(buf);
                try tokens.append(TokenValue{ .token = token, .value = .{ .String = buf } });
            },
            .StringInterned => {
                var id = try reader.readInt(u16, .Little);
                if (id == 0xFFFF) {
                    const length = try reader.readInt(u16, .Little);
                    const pos = @intCast(u16, string_buffer.items.len);
                    var i: usize = 0;
                    while (i < length) {
                        try string_buffer.append(try reader.readByte());
                    }
                    id = @intCast(u16, string_id.items.len);
                    try string_id.append(.{ .pos = pos, .length = length });
                }
                try tokens.append(TokenValue{ .token = token, .value = .{ .StringInterned = id } });
            },
            .BytesHex => {
                const pos = bytes_buffer.items.len;
                const length = try reader.readInt(u16, .Little);
                var i: usize = 0;
                while (i < length) {
                    try bytes_buffer.append(try reader.readByte());
                }
                try tokens.append(TokenValue{ .token = token, .value = .{ .BytesHex = .{
                    .pos = pos,
                    .length = length,
                } } });
            },
            .BytesBase64 => {
                const pos = bytes_buffer.items.len;
                const length = try reader.readInt(u16, .Little);
                var i: usize = 0;
                while (i < length) {
                    try bytes_buffer.append(try reader.readByte());
                }
                try tokens.append(TokenValue{ .token = token, .value = .{ .BytesBase64 = .{
                    .pos = pos,
                    .length = length,
                } } });
            },
            .Int => {
                try tokens.append(TokenValue{
                    .token = token,
                    .value = .{ .Int = try reader.readInt(u32, .Little) },
                });
            },
            .IntHex => {
                try tokens.append(TokenValue{
                    .token = token,
                    .value = .{ .IntHex = try reader.readInt(u32, .Little) },
                });
            },
            .Long => {
                try tokens.append(TokenValue{
                    .token = token,
                    .value = .{ .Long = try reader.readInt(u64, .Little) },
                });
            },
            .LongHex => {
                try tokens.append(TokenValue{
                    .token = token,
                    .value = .{ .LongHex = try reader.readInt(u64, .Little) },
                });
            },
            .Float => {
                try tokens.append(TokenValue{
                    .token = token,
                    .value = .{ .Float = @bitCast(f32, try reader.readInt(u32, .Little)) },
                });
            },
            .Double => {
                try tokens.append(TokenValue{
                    .token = token,
                    .value = .{ .Double = @bitCast(f64, try reader.readInt(u64, .Little)) },
                });
            },
            .BoolTrue => {
                try tokens.append(TokenValue{
                    .token = token,
                    .value = .BoolTrue,
                });
            },
            .BoolFalse => {
                try tokens.append(TokenValue{
                    .token = token,
                    .value = .BoolFalse,
                });
            },
        }
    }

    return Document{
        .string_buffer = string_buffer,
        .string_id = string_id,
        .bytes_buffer = bytes_buffer,
        .tokens = tokens,
    };
}
