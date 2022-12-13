const std = @import("std");
const manifest = @import("manifest.zig");

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

    pub fn init(t: Type) ResourceChunk {
        const header_size: u16 = switch (t) {
            .Null => 8,
            .StringPool => 20,
            .Table => 0,
            .Xml => 0,

            .XmlStartNamespace,
            .XmlEndNamespace,
            .XmlStartElement,
            .XmlEndElement,
            .XmlCData,
            => 16,

            .XmlResourceMap => 8,

            .TablePackage => 0,
            .TableType => 0,
            .TableTypeSpec => 0,
            .TableLibrary => 0,
        };
        const size: u32 = switch (t) {
            .XmlStartNamespace,
            .XmlEndNamespace,
            .XmlEndElement,
            .XmlCData,
            => header_size + 8,
            .XmlStartElement => header_size + 24,
            else => header_size,
        };
        return ResourceChunk{
            .type = t,
            .header_size = header_size,
            .size = size,
        };
    }

    pub fn read(reader: anytype) !ResourceChunk {
        return ResourceChunk{
            .type = @intToEnum(Type, try reader.readInt(u16, .Little)),
            .header_size = try reader.readInt(u16, .Little),
            .size = try reader.readInt(u32, .Little),
        };
    }

    pub fn write(header: ResourceChunk, writer: anytype) !void {
        try writer.writeInt(u16, @enumToInt(header.type), .Little);
        try writer.writeInt(u16, @enumToInt(header.header_size), .Little);
        try writer.writeInt(u32, @enumToInt(header.size), .Little);
    }
};

const Value = struct {
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

    fn read(reader: anytype) !Value {
        var value = Value{
            .size = try reader.readInt(u16, .Little),
            .res0 = try reader.readInt(u8, .Little),
            .datatype = @intToEnum(DataType, try reader.readInt(u8, .Little)),
            .data = try reader.readInt(u32, .Little),
        };
        return value;
    }

    pub fn write(value: Value, writer: anytype) !void {
        try writer.writeInt(u16, @enumToInt(value.size), .Little);
        try writer.writeInt(u8, value.res0, .Little);
        try writer.writeInt(u8, @enumToInt(value.datatype), .Little);
        try writer.writeInt(u32, value.data, .Little);
    }
};

const StringPool = struct {
    header: Header,
    pool: []u16,
    slices: [][]u16,

    const Ref = struct {
        index: u32,

        pub fn read(reader: anytype) !Ref {
            return Ref{ .index = try reader.readInt(u32, .Little) };
        }
        pub fn write(refe: Ref, writer: anytype) !void {
            try writer.write(u32, refe.index, .Little);
        }
    };

    pub fn ref(index: usize) Ref {
        return .{ .index = @intCast(u32, index) };
    }

    const Header = struct {
        header: ResourceChunk,
        string_count: u32,
        style_count: u32,
        flags: Flags,
        strings_start: u32,
        styles_start: u32,

        const Flags = packed struct(u32) {
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

        pub fn write(header: Header, writer: anytype) !void {
            try ResourceChunk.write(writer);
            try writer.writeInt(u32, header.string_count, .Little);
            try writer.writeInt(u32, header.style_count, .Little);
            try writer.writeInt(u32, @bitCast(u32, header.flags), .Little);
            try writer.writeInt(u32, header.strings_start, .Little);
            try writer.writeInt(u32, header.styles_start, .Little);
        }

        pub fn getAlloc(self: Header, alloc: std.mem.Allocator, file: std.fs.File, refe: Ref) !?[]const u16 {
            if (refe.index == std.math.maxInt(u32)) return null;
            try file.seekTo(8 + self.header.header_size + refe.index * 4);
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

    pub fn readAlloc(file: std.fs.File, chunk_header: ResourceChunk, alloc: std.mem.Allocator) !StringPool {
        const reader = file.reader();
        const header = try Header.read(reader, chunk_header);
        const buf_size = (header.header.size - header.strings_start) / 2;
        const string_buf = try alloc.alloc(u16, buf_size);
        const string_pool = try alloc.alloc([]u16, header.string_count);
        // Copy UTF16 buffer into memory
        try file.seekTo(8 + header.strings_start);
        for (string_buf) |*char| {
            char.* = try reader.readInt(u16, .Little);
        }
        // Create slices from offsets
        try file.seekTo(8 + header.header.header_size);
        for (string_pool) |*string| {
            const offset = try reader.readInt(u32, .Little);
            std.debug.assert(offset % 2 == 0);
            var index = offset / 2;
            var len: usize = string_buf[index];
            if (len > 32767) {
                len = (len & 0b0111_1111) << 16;
                index += 1;
                len += string_buf[index];
            }
            string.* = string_buf[index + 1 .. index + 1 + len];
        }
        return StringPool{
            .header = header,
            .pool = string_buf,
            .slices = string_pool,
        };
    }

    pub fn read(file: std.fs.File, header: Header, string_buf: []u16, string_pool: [][]const u16) !void {
        const reader = file.reader();
        // Copy UTF16 buffer into memory
        try file.seekTo(8 + header.strings_start);
        for (string_buf) |*char| {
            char.* = try reader.readInt(u16, .Little);
        }
        // Create slices from offsets
        try file.seekTo(8 + header.header.header_size);
        for (string_pool) |*string| {
            const offset = try reader.readInt(u32, .Little);
            std.debug.assert(offset % 2 == 0);
            var index = offset / 2;
            var len: usize = string_buf[index];
            if (len > 32767) {
                len = (len & 0b0111_1111) << 16;
                index += 1;
                len += string_buf[index];
            }
            string.* = string_buf[index + 1 .. index + 1 + len];
        }
    }

    // pub fn write(writer: anytype, pool: [][]const u8) !void {
    // }

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
                    .XmlStartNamespace,
                    .XmlEndNamespace,
                    => .{ .Namespace = try NamespaceExtended.read(reader) },
                    .XmlCData => .{ .CData = try CDataExtended.read(reader) },
                    .XmlEndElement => .{ .EndElement = try EndElementExtended.read(reader) },
                    .XmlStartElement => .{ .Attribute = try AttributeExtended.read(reader) },
                    else => @panic("not an xml element"),
                },
            };
        }

        pub fn write(node: Node, writer: anytype) !void {
            try node.header.write(writer);
            try writer.writeInt(u32, node.line_number, .Little);
            try node.comment.write();
            try switch (node.extended) {
                .CData => |cdata| cdata.write(writer),
                .Namespace => |namespace| namespace.write(writer),
                .EndElement => |el| el.write(writer),
                .Attribute => |attr| attr.write(writer),
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
        pub fn read(reader: anytype) !CDataExtended {
            return CDataExtended{
                .data = try StringPool.Ref.read(reader),
                .value = try Value.read(reader),
            };
        }
        pub fn write(cdata: CDataExtended, writer: anytype) !void {
            try cdata.data.write(writer);
            try cdata.value.write(writer);
        }
    };

    const NamespaceExtended = struct {
        prefix: StringPool.Ref,
        uri: StringPool.Ref,

        pub fn read(reader: anytype) !NamespaceExtended {
            return NamespaceExtended{
                .prefix = try StringPool.Ref.read(reader),
                .uri = try StringPool.Ref.read(reader),
            };
        }
        pub fn write(namespace: NamespaceExtended, writer: anytype) !void {
            try namespace.prefix.write(writer);
            try namespace.uri.write(writer);
        }
    };

    const EndElementExtended = struct {
        namespace: StringPool.Ref,
        name: StringPool.Ref,

        pub fn read(reader: anytype) !EndElementExtended {
            return EndElementExtended{
                .namespace = try StringPool.Ref.read(reader),
                .name = try StringPool.Ref.read(reader),
            };
        }
        pub fn write(el: EndElementExtended, writer: anytype) !void {
            try el.namespace.write(writer);
            try el.name.write(writer);
        }
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

        pub fn read(reader: anytype) !AttributeExtended {
            return AttributeExtended{
                .namespace = try StringPool.Ref.read(reader),
                .name = try StringPool.Ref.read(reader),
                .start = try reader.readInt(u16, .Little),
                .size = try reader.readInt(u16, .Little),
                .count = try reader.readInt(u16, .Little),
                .id_index = try reader.readInt(u16, .Little),
                .class_index = try reader.readInt(u16, .Little),
                .style_index = try reader.readInt(u16, .Little),
            };
        }
        pub fn write(el: AttributeExtended, writer: anytype) !void {
            try el.namespace.write(writer);
            try el.name.write(writer);
            try writer.writeInt(u16, el.start, .Little);
            try writer.writeInt(u16, el.size, .Little);
            try writer.writeInt(u16, el.count, .Little);
            try writer.writeInt(u16, el.id_index, .Little);
            try writer.writeInt(u16, el.class_index, .Little);
            try writer.writeInt(u16, el.style_index, .Little);
        }
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

        pub fn write(attribute: Attribute, writer: anytype) !void {
            try attribute.namespace.write(writer);
            try attribute.name.write(writer);
            try attribute.raw_value.write(writer);
            try attribute.typed_value.write(writer);
        }
    };
};

const ResourceTable = struct {
    const Header = struct {
        header: ResourceChunk,
        package_count: u32,

        fn read(reader: anytype, header: ResourceChunk) !Header {
            return Header{
                .header = header,
                .package_count = try reader.readInt(u32, .Little),
            };
        }
    };

    const Package = struct {
        header: ResourceChunk,
        id: u32,
        /// Actual name of package
        name: [127:0]u16,
        /// Offset to StringPool.Header defining the resource type symbol table. If zero, this package is inheriting
        /// from another base package.
        type_strings: u32,
        /// Last index into type_strings that is for public use by others
        last_public_type: u32,
        /// Offset to a ResStringPool_header defining the resource key symbol table.
        key_strings: u32,
        /// Last index into keyStrings that is for public use by others
        last_public_key: u32,
        type_id_offset: u32,

        fn read(reader: anytype, header: ResourceChunk) !Package {
            var package: Package = undefined;

            package.header = header;
            package.id = try reader.readInt(u32, .Little);
            var index: usize = 0;
            package.name[index] = try reader.readInt(u16, .Little);
            while (package.name[index] != 0) {
                index += 1;
                package.name[index] = try reader.readInt(u16, .Little);
            }
            std.log.info("{}", .{
                std.unicode.fmtUtf16le(&package.name),
            });
            package.type_strings = try reader.readInt(u32, .Little);
            package.last_public_type = try reader.readInt(u32, .Little);
            package.key_strings = try reader.readInt(u32, .Little);
            package.last_public_key = try reader.readInt(u32, .Little);
            package.type_id_offset = try reader.readInt(u32, .Little);

            return package;
        }
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
                dir: enum(u2) { Any = 0, LTR = 1, RTL = 2 },
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

    const TableRef = struct {
        ident: u32,
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
    arena: std.heap.ArenaAllocator,
    string_pool: StringPool,
    resource_nodes: []XMLTree.Node,
    resource_header: XMLTree.Header,
    attributes: []Attribute,

    const Attribute = struct {
        node: usize,
        value: XMLTree.Attribute,
    };

    pub fn readXMLAlloc(file: std.fs.File, backing_allocator: std.mem.Allocator) !Document {
        std.log.info("Reading XML file", .{});
        const reader = file.reader();

        var signature: [4]u8 = undefined;
        const count = try reader.read(&signature);
        if (count != 4) return error.UnexpectedEof;

        if (!std.mem.eql(u8, &signature, "\x03\x00\x08\x00")) return error.WrongMagicBytes;

        const file_length = try reader.readInt(u32, .Little);

        return readAlloc(file, backing_allocator, file_length);
    }

    pub fn readResAlloc(file: std.fs.File, backing_allocator: std.mem.Allocator) !Document {
        std.log.info("Reading res file", .{});
        return readAlloc(file, backing_allocator, (try file.metadata()).size());
    }

    pub fn readAlloc(file: std.fs.File, backing_allocator: std.mem.Allocator, file_length: usize) !Document {
        const reader = file.reader();
        var arena = std.heap.ArenaAllocator.init(backing_allocator);
        const alloc = arena.allocator();

        var string_pool: StringPool = undefined;
        var resource_header: XMLTree.Header = undefined;
        var nodes = std.ArrayList(XMLTree.Node).init(alloc);
        defer nodes.deinit();
        var attributes = std.ArrayList(Document.Attribute).init(alloc);
        defer attributes.deinit();

        var pos: usize = try file.getPos();
        var header = try ResourceChunk.read(reader);
        while (true) {
            switch (header.type) {
                .StringPool => {
                    string_pool = try StringPool.readAlloc(file, header, alloc);
                },
                .XmlResourceMap => resource_header = XMLTree.Header{ .header = header },
                .XmlStartNamespace,
                .XmlEndElement,
                .XmlEndNamespace,
                => try nodes.append(try XMLTree.Node.read(reader, header)),
                .XmlStartElement => {
                    var node_id = nodes.items.len;
                    var node = try XMLTree.Node.read(reader, header);
                    try nodes.append(node);
                    var attribute = node.extended.Attribute;
                    if (attribute.count > 0) {
                        var i: usize = 0;
                        while (i < attribute.count) : (i += 1) {
                            try attributes.append(.{
                                .node = node_id,
                                .value = try XMLTree.Attribute.read(reader),
                            });
                        }
                    }
                },
                .Table => {
                    const table = try ResourceTable.Header.read(reader, header);
                    std.log.info("Resource table: {?}", .{table});
                },
                else => {
                    std.log.err("Unimplemented chunk type: {s}", .{@tagName(header.type)});
                    break;
                },
            }
            if (pos + header.size >= file_length) {
                std.log.err("Next chunk outside of file", .{});
                break;
            }
            try file.seekTo(pos + header.size);
            pos = try file.getPos();
            header = try ResourceChunk.read(reader);
        }

        return Document{
            .arena = arena,
            .string_pool = string_pool,
            .resource_nodes = nodes.toOwnedSlice(),
            .resource_header = resource_header,
            .attributes = attributes.toOwnedSlice(),
        };
    }

    pub fn write(document: Document, file: std.fs.File) !Document {
        const writer = file.writer();

        // Write magic bytes
        try writer.write("\x03\x00\x08\x00");

        // Save a spot for the length
        try writer.writeInt(u32, 0, .Little);

        // Write the string pool header
        try document.string_pool_header.write(writer);

        // Write the string offsets
        for (document.string_pool) |string, i| {
            // Add index to account for the length values, and then multiply by 2 to get the byte offset
            try writer.writeInt(u32, @intCast(u32, (string.len + i) * 2), .Little);
        }

        // Write the strings
        for (document.string_pool) |string| {
            try writer.writeInt(u16, @intCast(u16, string.len), .Little);
            for (string) |char| {
                try writer.writeInt(u16, char, .Little);
            }
        }

        // Write the XML resource chunks
        for (document.resources_nodes) |node, i| {
            // Write the header (including the extended bytes)
            try node.write(writer);
            // If the node is the start of an element, write out any attributes it may have
            if (node.extended == .Attribute) {
                for (document.attribute) |attr| {
                    if (attr.node == i) {
                        try attr.value.write(writer);
                    }
                }
            }
        }

        // Backtrack and write the file size
        const file_size = file.getEndPos();
        try file.seekTo(4);
        try writer.write(file_size);
    }

    pub fn getString(document: Document, ref: StringPool.Ref) ?[]const u16 {
        if (ref.index > document.string_pool.slices.len) return null;
        return document.string_pool.slices[ref.index];
    }
};
