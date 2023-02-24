//! A single value in Android's binary xml format.

const Value = @This();

const DataType = enum(u8) {
    Null = 0x00,
    Reference = 0x01,
    Attribute = 0x02,
    String = 0x03,
    Float = 0x04,
    Dimension = 0x05,
    Fraction = 0x06,
    DynReference = 0x07,
    DynAttribute = 0x08,
    IntDec = 0x10,
    IntHex = 0x11,
    IntBool = 0x12,
    IntColorARGB8 = 0x1c,
    IntColorRGB8 = 0x1d,
    IntColorARGB4 = 0x1e,
    IntColorRGB4 = 0x1f,
};

const DimensionUnit = enum(u4) {
    Pixels = 0x0,
    DeviceIndependentPixels = 0x1,
    ScaledDeviceIndependentPixels = 0x2,
    Points = 0x3,
    Inches = 0x4,
    Millimeters = 0x5,
    Fraction = 0x6,
};

const FractionUnit = packed struct(u8) {
    unit: enum(u1) {
        Basic,
        Parent,
    },
    radix: enum(u3) {
        r23p0 = 0,
        r16p7 = 1,
        r8p15 = 2,
        r0p23 = 3,
    },
};

const NullType = enum(u1) {
    Undefined = 0,
    Empty = 1,
};

size: u16,
res0: u8,
datatype: DataType,
data: u32,

// Runtime
string_pool: ?*const StringPool,

pub fn read(reader: anytype, string_pool: ?*StringPool) !Value {
    var value = Value{
        .size = try reader.readInt(u16, .Little),
        .res0 = try reader.readInt(u8, .Little),
        .datatype = @intToEnum(DataType, try reader.readInt(u8, .Little)),
        .data = try reader.readInt(u32, .Little),
        .string_pool = string_pool,
    };
    return value;
}

pub fn write(value: Value, writer: anytype) !void {
    try writer.writeInt(u16, @enumToInt(value.size), .Little);
    try writer.writeInt(u8, value.res0, .Little);
    try writer.writeInt(u8, @enumToInt(value.datatype), .Little);
    try writer.writeInt(u32, value.data, .Little);
}

pub fn format(value: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    _ = fmt;
    switch (value.datatype) {
        .Null => {
            if (value.data == 0) {
                _ = try writer.write("undefined");
            } else {
                _ = try writer.write("empty");
            }
        },
        .Reference => {
            try std.fmt.format(writer, "reference to {x}", .{value.data});
        },
        .Attribute => {
            try std.fmt.format(writer, "attribute id {}", .{value.data});
        },
        .String => {
            if (value.string_pool) |string_pool| {
                if (string_pool.getUtf16Raw(value.data)) |str| {
                    try std.fmt.format(writer, "\"{}\"", .{std.unicode.fmtUtf16le(str)});
                } else if (string_pool.getUtf8Raw(value.data)) |str| {
                    try std.fmt.format(writer, "\"{s}\"", .{str});
                } else {
                    try std.fmt.format(writer, "empty string {}", .{value.data});
                }
            } else {
                try std.fmt.format(writer, "string id {}", .{value.data});
            }
        },
        .Float => {
            const float = @bitCast(f32, value.data);
            try std.fmt.format(writer, "float {}", .{float});
        },
        .Dimension => {
            try std.fmt.format(writer, "dimension {x}", .{value.data});
        },
        .Fraction => {
            try std.fmt.format(writer, "fraction {x}", .{value.data});
        },
        .DynReference => {
            try std.fmt.format(writer, "dynamic reference {x}", .{value.data});
        },
        .DynAttribute => {
            try std.fmt.format(writer, "dynamic attribute {x}", .{value.data});
        },
        .IntDec => {
            try std.fmt.format(writer, "integer decimal: {}", .{value.data});
        },
        .IntHex => {
            try std.fmt.format(writer, "integer hex: {x}", .{value.data});
        },
        .IntBool => {
            const bool_value = if (value.data == 0) "false" else "true";
            try std.fmt.format(writer, "int bool: {} ({s})", .{ value.data, bool_value });
        },
        .IntColorARGB8 => {
            try std.fmt.format(writer, "argb8 color: {x}", .{value.data});
        },
        .IntColorRGB8 => {
            try std.fmt.format(writer, "rgb8 color: {x}", .{value.data});
        },
        .IntColorARGB4 => {
            try std.fmt.format(writer, "argb4 color: {x}", .{value.data});
        },
        .IntColorRGB4 => {
            try std.fmt.format(writer, "rgb4 color: {x}", .{value.data});
        },
    }
}

const std = @import("std");
const StringPool = @import("StringPool.zig");
