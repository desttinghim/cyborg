const std = @import("std");

const Type = enum(u16) {
    Null = 0x0000,
    StringPool = 0x0001,
    Table = 0x0002,
    Xml = 0x0003,

    XmlStartNamespace = 0x0100,
    XmlEndNamespace = 0x0101,
    XmlStartElement = 0x0102,
    XmlEndElement = 0x0103,
    XmlCData = 0x0104,

    XmlResourceMap = 0x0180,

    TablePackage = 0x0200,
    TableType = 0x0201,
    TableTypeSpec = 0x0202,
    TableLibrary = 0x0203,
};

const ResourceChunk = struct {
    type: Type,
    header_size: u16,
    size: u32,

    pub fn read(reader: anytype) !ResourceChunk {
        return ResourceChunk{
            .type = @intToEnum(Type, try reader.readInt(u16, .Little)),
            .header_size = try reader.readInt(u16, .Little),
            .size = try reader.readInt(u32, .Little),
        };
    }
};

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

const Value = struct {
    size: u16,
    res0: u8,
    datatype: DataType,
    data: u32,
};

const TableRef = struct {
    ident: u32,
};

const StringPool = struct {
    const Ref = struct {
        index: u32,
    };

    const Header = struct {
        header: ResourceChunk,
        string_count: u32,
        style_count: u32,
        flags: Flags,
        strings_start: u32,
        styles_start: u32,

        const Flags =
            packed struct(u32) {
            sorted: bool,
            utf8: bool,
            _unused: u30 = 0,
        };

        fn read(reader: anytype) !Header {
            return Header{
                .header = try ResourceChunk.read(reader),
                .string_count = try reader.readInt(u32, .Little),
                .style_count = try reader.readInt(u32, .Little),
                .flags = @bitCast(Flags, try reader.readInt(u32, .Little)),
                .strings_start = try reader.readInt(u32, .Little),
                .styles_start = try reader.readInt(u32, .Little),
            };
        }
    };

    const Span = struct {
        name: Ref,
        first_char: u32,
        last_char: u32,
    };
};

const XMLTree = struct {
    const Header = struct {
        header: ResourceChunk,
    };

    const Node = struct {
        header: ResourceChunk,
        line_number: u32,
        comment: StringPool.Ref,
    };

    const CDataExtended = struct {
        data: StringPool.Ref,
        value: Value,
    };

    const NamespaceExtended = struct {
        prefix: StringPool.Ref,
        uri: StringPool.Ref,
    };

    const EndElementExtended = struct {
        namespace: StringPool.Ref,
        name: StringPool.Ref,
    };

    const AttributeExtended = struct {
        namespace: StringPool.Ref,
        name: StringPool.Ref,
        start: u16,
        size: u16,
        count: u16,
        id_index: u16,
        class_index: u16,
        style_index: u16,
    };

    const Attribute = struct {
        namespace: StringPool.Ref,
        name: StringPool.Ref,
        raw_value: StringPool.Ref,
        typed_value: Value,
    };
};

const ResourceTable = struct {
    const Header = struct {
        header: ResourceChunk,
        package_count: u32,
    };

    const Package = struct {
        header: ResourceChunk,
        id: u32,
        name: [127:0]u16,
        /// Offset to StringPool.Header defining the resource type symbol table.
        type_strings: u32,
        last_public_type: u32,
        key_strings: u32,
        last_public_key: u32,
        type_id_offset: u32,
    };

    const Config = struct {
        size: u32,
        geo: union {
            imsi: u32,
            code: packed struct(u32) {
                mcc: u16,
                mnc: u16,
            },
        },
        locale: union {
            code: packed struct(u32) {
                language: [2]u8,
                country: [2]u8,
            },
            locale: u32,
        },
        screen_type: union {
            details: packed struct(u32) {
                orientation: u8,
                touchscreen: u8,
                density: u16,
            },
            screen_type: u32,
        },
        input: packed struct(u32) {
            keyboard: u8,
            navigation: u8,
            input_flags: u8,
            input_pad: u8,
        },
        screen_size: packed struct(u32) {
            width: u16,
            height: u16,
        },
        version: packed struct(u32) {
            sdk: u16,
            minor: u16,
        },
        screen_config: packed struct(u32) {
            layout: u8,
            ui_mode: u8,
            smallest_screen_width_dp: u16,
        },
        screen_size_dp: packed struct(u32) {
            width: u16,
            height: u16,
        },
        locale_script: [4]u8,
        locale_version: [8]u8,
        screen_config2: packed struct(u32) {
            layout2: u8,
            color_mode: u8,
            _pad: u16,
        },
        locale_script_was_computed: bool,
        locale_numbering_system: [8]u8,
    };

    const TypeSpec = struct {
        header: ResourceChunk,
        id: u8,
        res0: u8,
        res1: u16,
        entry_count: u32,
    };

    const Type = struct {
        header: ResourceChunk,
        id: u8,
        flags: u8,
        reserved: u8,
        entry_count: u32,
        entries_start: u32,
        config: Config,
    };

    const SparseTypeEntry = struct {
        entry: u32,
        idx: u16,
        offset: u16,
    };

    const Entry = struct {
        size: u16,
        flags: u16,
        key: StringPool.Ref,
    };

    const MapEntry = struct {
        parent: TableRef,
        count: u32,
    };

    const Map = struct {
        name: TableRef,
        value: Value,
    };

    const LibHeader = struct {
        header: ResourceChunk,
        count: u32,
    };

    const LibEntry = struct {
        package_id: u32,
        package_name: [127:0]u16,
    };
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

    _ = try reader.readInt(u32, .Little);

    const string_pool = try StringPool.Header.read(reader);

    std.log.debug("{any}", .{string_pool});

    const string_table_end = string_pool.header.size;
    const string_table_count = string_pool.string_count;
    const string_table_offset = string_pool.header.header_size + string_table_count * 4;

    std.log.debug("string table @ {}-{}, {} entries", .{ string_table_offset, string_table_end, string_table_count });

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
        const buf = string_buffer[pos .. pos + 1 + len];
        pos += len + 1;
        for (buf) |*char| {
            char.* = try reader.readInt(u16, .Little);
        }
        std.log.debug("{s}", .{std.unicode.fmtUtf16le(buf)});
    }

    while (try reader.readInt(u32, .Little) != 0x00100102) {}
    std.log.debug("found start tag at {}", .{try file.getPos()});

    var tag: [5]u32 = undefined;
    for (tag) |*value| {
        value.* = try reader.readInt(u32, .Little);
        std.log.debug("{}", .{value.*});
    }

    return Document{
        .string_buffer = string_buffer,
    };
}
