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

    fn read(reader: anytype) !Value {
        var value = Value{
            .size = try reader.readInt(u16, .Little),
            .res0 = try reader.readInt(u8, .Little),
            .datatype = @intToEnum(DataType, try reader.readInt(u8, .Little)),
            .data = try reader.readInt(u32, .Little),
        };
        // try reader.skipBytes(value.size - @sizeOf(Value), .{});
        return value;
    }
};

const TableRef = struct {
    ident: u32,
};

const StringPool = struct {
    const Ref = struct {
        index: u32,

        pub fn read(reader: anytype) !Ref {
            return Ref{ .index = try reader.readInt(u32, .Little) };
        }
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

        fn read(reader: anytype, header: ResourceChunk) !Header {
            return Header{
                .header = header,
                .string_count = try reader.readInt(u32, .Little),
                .style_count = try reader.readInt(u32, .Little),
                .flags = @bitCast(Flags, try reader.readInt(u32, .Little)),
                .strings_start = try reader.readInt(u32, .Little),
                .styles_start = try reader.readInt(u32, .Little),
            };
        }

        pub fn getAlloc(self: Header, alloc: std.mem.Allocator, file: std.fs.File, ref: Ref) !?[]const u16 {
            if (ref.index == std.math.maxInt(u32)) return null;
            try file.seekTo(8 + self.header.header_size + ref.index * 4);
            const reader = file.reader();
            const offset = try reader.readInt(u32, .Little);
            try file.seekTo(8 + self.strings_start + offset);
            var length: u32 = try reader.readInt(u16, .Little);
            if (length > 32767) {
                length = (length & 0b0111_1111) << 16;
                length += try reader.readInt(u16, .Little);
            }
            const mem = try alloc.alloc(u16, length);
            for (mem) |*char| {
                char.* = try reader.readInt(u16, .Little);
            }
            return mem;
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
        extended: NodeExtended,

        fn read(reader: anytype, header: ResourceChunk) !Node {
            return Node{
                .header = header,
                .line_number = try reader.readInt(u32, .Little),
                .comment = try StringPool.Ref.read(reader),
                .extended = switch (header.type) {
                    .XmlCData => .{ .CData = .{
                        .data = try StringPool.Ref.read(reader),
                        .value = try Value.read(reader),
                    } },
                    .XmlStartNamespace,
                    .XmlEndNamespace,
                    => .{ .Namespace = .{
                        .prefix = try StringPool.Ref.read(reader),
                        .uri = try StringPool.Ref.read(reader),
                    } },
                    .XmlEndElement => .{ .EndElement = .{
                        .namespace = try StringPool.Ref.read(reader),
                        .name = try StringPool.Ref.read(reader),
                    } },
                    .XmlStartElement => .{ .Attribute = .{
                        .namespace = try StringPool.Ref.read(reader),
                        .name = try StringPool.Ref.read(reader),
                        .start = try reader.readInt(u16, .Little),
                        .size = try reader.readInt(u16, .Little),
                        .count = try reader.readInt(u16, .Little),
                        .id_index = try reader.readInt(u16, .Little),
                        .class_index = try reader.readInt(u16, .Little),
                        .style_index = try reader.readInt(u16, .Little),
                    } },
                    else => @panic("not an xml element"),
                },
            };
        }
    };

    const NodeExtended = union(enum) {
        CData: CDataExtended,
        Namespace: NamespaceExtended,
        EndElement: EndElementExtended,
        Attribute: AttributeExtended,
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
        list: ?[]Attribute = null,
    };

    const Attribute = struct {
        namespace: StringPool.Ref,
        name: StringPool.Ref,
        raw_value: StringPool.Ref,
        typed_value: Value,

        pub fn read(reader: anytype) !Attribute {
            return Attribute{
                .namespace = try StringPool.Ref.read(reader),
                .name = try StringPool.Ref.read(reader),
                .raw_value = try StringPool.Ref.read(reader),
                .typed_value = try Value.read(reader),
            };
        }
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
        imsi: packed struct(u32) {
            mcc: u16,
            mnc: u16,
        },
        locale: packed struct(u32) {
            language: [2]u8,
            country: [2]u8,
        },
        screen_type: packed struct(u32) {
            orientation: enum(u8) { Any = 0, Port = 1, Land = 2, Square = 3 },
            touchscreen: enum(u8) { Any = 0, NoTouch = 1, Stylus = 2, Finger = 3 },
            density: enum(u16) { Default = 0, Low = 120, Medium = 160, Tv = 213, High = 240, XHigh = 320, XXHigh = 480, XXXHigh = 640, Any = 0xFFFE, None = 0xFFFF },
        },
        input: packed struct(u32) {
            keyboard: enum(u8) { Any = 0, NoKeys = 1, Qwerty = 2, _12Key = 3 },
            navigation: enum(u8) { Any = 0, NoNav = 1, Dpad = 2, Trackball = 3, Wheel = 4 },
            input_flags: packed struct(u8) {
                keys_hidden: enum(u2) { Any = 0, No = 1, Yes = 2, Soft = 3 },
                nav_hidden: enum(u2) { Any = 0, No = 1, Yes = 2 },
                _unused: u4,
            },
            input_pad: u8,
        },
        screen_size: packed struct(u32) {
            width: enum(u16) { Any = 0, _ },
            height: enum(u16) { Any = 0, _ },
        },
        version: packed struct(u32) {
            sdk: enum(u16) { Any = 0, _ },
            minor: enum(u16) { Any = 0, _ }, // must be 0, meaning is undefined
        },
        screen_config: packed struct(u32) {
            layout: packed struct(u8) {
                size: enum(u4) { Any = 0, Small = 1, Normal = 2, Large = 3, XLarge = 4 },
                long: enum(u2) { Any = 0, No = 1, Yes = 2 },
                dir: enum(u2) { Any = 0, LTR = 1, RTL = 2 }, // TODO
            },
            ui_mode: packed struct(u8) {
                type: enum(u4) { Any = 0, Normal = 1, Desk = 2, Car = 3, Television = 4, Appliance = 5, Watch = 6, VrHeadset = 7 },
                night: enum(u2) { Any = 0, No = 1, Yes = 2 },
                _unused: u2,
            },
            smallest_screen_width_dp: u16,
        },
        screen_size_dp: packed struct(u32) {
            width: u16,
            height: u16,
        },
        locale_script: [4]u8,
        locale_version: [8]u8,
        screen_config2: packed struct(u32) {
            layout2: packed struct(u8) {
                round: enum(u2) { Any = 0, No = 1, Yes = 2 },
                _unused: u6,
            },
            color_mode: packed struct(u8) {
                wide_color: enum(u2) { Any = 0, No = 1, Yes = 2 },
                hdr: enum(u2) { Any = 0, No = 1, Yes = 2 },
                _unused: u4,
            },
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
    string_pool: StringPool.Header,
    resource_map: XMLTree.Header,
    resource_nodes: []XMLTree.Node,
};

pub fn readAlloc(file: std.fs.File, alloc: std.mem.Allocator) !Document {
    const reader = file.reader();
    var signature: [4]u8 = undefined;
    const count = try reader.read(&signature);
    if (count != 4) return error.UnexpectedEof;

    if (!std.mem.eql(u8, &signature, "\x03\x00\x08\x00")) return error.WrongMagicBytes;

    const file_length = try reader.readInt(u32, .Little);

    var string_pool: StringPool.Header = undefined;
    var resource_map: XMLTree.Header = undefined;
    var nodes = std.ArrayList(XMLTree.Node).init(alloc);
    defer nodes.deinit();

    var pos: usize = try file.getPos();
    var header = try ResourceChunk.read(reader);
    while (true) {
        switch (header.type) {
            .StringPool => string_pool = try StringPool.Header.read(reader, header),
            .XmlResourceMap => resource_map = XMLTree.Header{ .header = header },
            .XmlStartNamespace,
            .XmlEndElement,
            .XmlEndNamespace,
            => try nodes.append(try XMLTree.Node.read(reader, header)),
            .XmlStartElement => {
                var node = try XMLTree.Node.read(reader, header);
                var attribute = node.extended.Attribute;
                if (attribute.count > 0) {
                    var attrs = try alloc.alloc(XMLTree.Attribute, attribute.count);
                    for (attrs) |*attr| {
                        attr.* = try XMLTree.Attribute.read(reader);
                    }
                    node.extended.Attribute.list = attrs;
                }
                try nodes.append(node);
            },
            else => break,
        }
        if (pos + header.size >= file_length) break;
        try file.seekTo(pos + header.size);
        pos = try file.getPos();
        header = try ResourceChunk.read(reader);
    }

    return Document{
        .string_pool = string_pool,
        .resource_map = resource_map,
        .resource_nodes = nodes.toOwnedSlice(),
    };
}
