//! A single value in Android's binary xml format.

const Value = @This();

const DataType = enum(u8) {
    /// Data is Undefined or Empty, encoded as 0 or 1 respectively
    Null = 0x00,
    /// Data is a reference to another resource table entry
    Reference = 0x01,
    /// Data is an attribute resource identifier
    Attribute = 0x02,
    /// Data is an index into containing resource's global string pool
    String = 0x03,
    /// Data is a single-precision floating point number (f32)
    Float = 0x04,
    /// Data encodes a dimension
    Dimension = 0x05,
    /// Data encodes a fraction
    Fraction = 0x06,
    /// Data is a dynamic resource table reference - must be resolved before using like a Reference
    DynReference = 0x07,
    /// Data is a attribute resource identifier which needs to be resolved before use
    DynAttribute = 0x08,
    /// Data is a raw integer value in decimal form
    IntDec = 0x10,
    /// Data is a raw integer value in hexadecimal form
    IntHex = 0x11,
    /// Data is true or false, encoded as 1 or 0 respectively
    IntBool = 0x12,
    /// Data is a raw integer value in the form of #aarrggbb
    IntColorARGB8 = 0x1c,
    /// Data is a raw integer value in the form of #rrggbb
    IntColorRGB8 = 0x1d,
    /// Data is a raw integer value in the form of #argb
    IntColorARGB4 = 0x1e,
    /// Data is a raw integer value in the form of #rgb
    IntColorRGB4 = 0x1f,
};

const Data = union(enum) {
    Null: NullType,
    Reference: u32,
    Attribute: u32,
    DynReference: u32,
    DynAttribute: u32,
    String: StringPool.Ref,
    Float: f32,
    Dimension: struct {
        unit: DimensionUnit,
        radix: Radix,
        value: i24,
    },
    Fraction: struct {
        unit: FractionUnit,
        radix: Radix,
        value: i24,
    },
    Int: union(enum) {
        Dec: u32,
        Hex: u32,
        Bool: bool,
        Color: union(enum) {
            ARGB8: struct {
                r: u8,
                g: u8,
                b: u8,
                a: u8,
            },
            RGB8: struct {
                r: u8,
                g: u8,
                b: u8,
            },
            ARGB4: struct {
                r: u4,
                g: u4,
                b: u4,
                a: u4,
            },
            RGB4: struct {
                r: u4,
                g: u4,
                b: u4,
            },
        },
    },
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

const FractionUnit = enum(u1) {
    Basic,
    Parent,
};
const Radix = enum(u2) {
    r23p0 = 0,
    r16p7 = 1,
    r8p15 = 2,
    r0p23 = 3,
};

const NullType = enum(u1) {
    Undefined = 0,
    Empty = 1,
};

data: Data,

// Runtime
string_pool: ?*const StringPool,

pub fn read(reader: anytype, string_pool: ?*StringPool) !Value {
    // Read number of bytes in the structure
    const size = try reader.readInt(u16, .Little);
    _ = size;
    // Padding, should always be 0
    const res0 = try reader.readInt(u8, .Little);
    _ = res0;
    const datatype = @as(DataType, @enumFromInt(try reader.readInt(u8, .Little)));
    // const raw_data = try reader.readInt(u32, .Little);
    const data: Data = switch (datatype) {
        .Null => .{ .Null = @as(NullType, @enumFromInt(try reader.readInt(u32, .Little))) },
        .Reference => .{ .Reference = try reader.readInt(u32, .Little) },
        .Attribute => .{ .Attribute = try reader.readInt(u32, .Little) },
        .String => .{ .String = StringPool.Ref{ .index = try reader.readInt(u32, .Little) } },
        .Float => .{ .Float = @as(f32, @bitCast(try reader.readInt(u32, .Little))) },
        .Dimension => .{ .Dimension = dimension: {
            const description = try reader.readByte();
            var unit = @as(DimensionUnit, @enumFromInt(@as(u4, @truncate(description))));
            var radix = @as(Radix, @enumFromInt(@as(u4, @truncate(description >> 4))));
            var value = try reader.readInt(i24, .Little);
            break :dimension .{
                .unit = unit,
                .radix = radix,
                .value = value,
            };
        } },
        .Fraction => .{ .Fraction = fraction: {
            const description = try reader.readByte();
            var unit = @as(FractionUnit, @enumFromInt(@as(u4, @truncate(description))));
            var radix = @as(Radix, @enumFromInt(@as(u4, @truncate(description >> 4))));
            var value = try reader.readInt(i24, .Little);
            break :fraction .{
                .unit = unit,
                .radix = radix,
                .value = value,
            };
        } },
        .DynReference => .{ .DynReference = try reader.readInt(u32, .Little) },
        .DynAttribute => .{ .DynAttribute = try reader.readInt(u32, .Little) },
        .IntBool => .{ .Int = .{ .Bool = try reader.readInt(u32, .Little) == 1 } },
        .IntDec,
        .IntHex,
        .IntColorARGB8,
        .IntColorRGB8,
        .IntColorARGB4,
        .IntColorRGB4,
        => integer: {
            // TODO: preserve type
            const value = try reader.readInt(u32, .Little);
            break :integer .{ .Int = .{ .Dec = value } };
        },
    };
    return .{
        // .datatype = datatype,
        .data = data,
        .string_pool = string_pool,
    };
}

pub fn write(value: Value, writer: anytype) !void {
    try writer.writeInt(u16, @intFromEnum(value.size), .Little);
    try writer.writeInt(u8, value.res0, .Little);
    try writer.writeInt(u8, @intFromEnum(value.datatype), .Little);
    try writer.writeInt(u32, value.data, .Little);
}

pub fn format(value: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    _ = fmt;
    switch (value.data) {
        .Null => |data| {
            try std.fmt.format(writer, "{s}", .{@tagName(data)});
        },
        .Reference => |ref| {
            try std.fmt.format(writer, "reference to {x}", .{ref});
        },
        .Attribute => |attr| {
            try std.fmt.format(writer, "attribute id {}", .{attr});
        },
        .String => |string| {
            if (value.string_pool) |string_pool| {
                if (string_pool.get_formatter(string)) |str| {
                    try std.fmt.format(writer, "\"{}\"", .{str});
                } else {
                    try std.fmt.format(writer, "empty string {}", .{value.data});
                }
            } else {
                try std.fmt.format(writer, "string id {}", .{value.data});
            }
        },
        .Float => |float| {
            try std.fmt.format(writer, "float {}", .{float});
        },
        .Dimension => |dimension| {
            try std.fmt.format(writer, "dimension {}", .{dimension});
        },
        .Fraction => |fraction| {
            try std.fmt.format(writer, "fraction {}", .{fraction});
        },
        .DynReference => |ref| {
            try std.fmt.format(writer, "dynamic reference {x}", .{ref});
        },
        .DynAttribute => |attr| {
            try std.fmt.format(writer, "dynamic attribute {x}", .{attr});
        },
        .Int => |int| switch (int) {
            .Dec => |dec| {
                try std.fmt.format(writer, "integer decimal: {}", .{dec});
            },
            .Hex => |hex| {
                try std.fmt.format(writer, "integer hex: {x}", .{hex});
            },
            .Bool => |bint| {
                try std.fmt.format(writer, "int bool: {}", .{bint});
            },
            .Color => |color| {
                try std.fmt.format(writer, "color: {}", .{color});
            },
        },
    }
}

const std = @import("std");
const StringPool = @import("StringPool.zig");
