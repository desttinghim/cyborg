const XMLTree = @This();

pub const Builder = struct {
    allocator: std.mem.Allocator,
    xml_tree: XMLTree,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .allocator = allocator,
            .xml_tree = .{
                .string_pool = StringPool{ .data = .{ .Utf8 = .{ .pool = .{}, .slices = .{} } } },
                .nodes = .{},
                .attributes = .{},
            },
        };
    }

    pub const Attribute_b = struct {
        namespace: ?[:0]const u8,
        name: [:0]const u8,
        value: [:0]const u8,
    };

    const ElementOptions = struct {
        id: ?[]const u8 = null,
        class: ?[]const u8 = null,
        style: ?[]const u8 = null,
        line_number: ?u32 = null,
        namespace: ?[]const u8,
    };

    pub fn startElement(self: *Builder, name: []const u8, attributes: []const Attribute_b, opt: ElementOptions) !void {
        const comment_ref = try self.xml_tree.string_pool.insert(self.allocator, "comment");
        const namespace_ref = if (opt.namespace) |namespace|
            try self.xml_tree.string_pool.insert(self.allocator, (namespace))
        else
            self.xml_tree.string_pool.get_null_ref();
        const name_ref = try self.xml_tree.string_pool.insert(self.allocator, (name));
        const node_id = self.xml_tree.nodes.items.len;
        for (attributes) |attr| {
            // TODO:
            const attr_name_ref = try self.xml_tree.string_pool.insert(self.allocator, (attr.name));
            const attr_namespace_ref = if (attr.namespace) |namespace|
                try self.xml_tree.string_pool.insert(self.allocator, (namespace))
            else
                self.xml_tree.string_pool.get_null_ref();
            const attr_value_ref = try self.xml_tree.string_pool.insert(self.allocator, attr.value);
            try self.xml_tree.attributes.append(self.allocator, .{
                .node = node_id,
                .namespace = attr_namespace_ref,
                .name = attr_name_ref,
                .raw_value = attr_value_ref,
                .typed_value = .{
                    .datatype = .String,
                    .data = attr_value_ref.index,
                    .string_pool = null,
                },
            });
        }
        try self.xml_tree.nodes.append(self.allocator, .{
            .line_number = opt.line_number orelse 0,
            .comment = comment_ref,
            .extended = .{ .Attribute = .{
                .name = name_ref,
                .namespace = namespace_ref,
                .start = 0,
                .size = 0,
                .count = 0,
                .id_index = 0,
                .class_index = 0,
                .style_index = 0,
            } },
        });
    }
    pub fn endElement(self: *Builder, name: []const u8, opt: ElementOptions) !void {
        const comment_ref = try self.xml_tree.string_pool.insert(self.allocator, "comment");
        const namespace_ref = if (opt.namespace) |namespace|
            try self.xml_tree.string_pool.insert(self.allocator, (namespace))
        else
            self.xml_tree.string_pool.get_null_ref();
        const name_ref = try self.xml_tree.string_pool.insert(self.allocator, (name));
        try self.xml_tree.nodes.append(self.allocator, .{
            .line_number = 0,
            .comment = comment_ref,
            .extended = .{ .EndElement = .{
                .name = name_ref,
                .namespace = namespace_ref,
            } },
        });
    }

    pub fn startNamespace(self: *Builder, uri: []const u8, prefix: []const u8) !void {
        const comment_ref = try self.xml_tree.string_pool.insert(self.allocator, "comment");
        const uri_ref = try self.xml_tree.string_pool.insert(self.allocator, (uri));
        const prefix_ref = try self.xml_tree.string_pool.insert(self.allocator, (prefix));
        try self.xml_tree.nodes.append(self.allocator, .{
            .line_number = 0,
            .comment = comment_ref,
            .extended = .{ .Namespace = .{
                .uri = uri_ref,
                .prefix = prefix_ref,
            } },
        });
    }
    pub fn endNamespace(self: *Builder) !void {
        _ = self;
    }

    pub fn insertCData(self: *Builder) !void {
        _ = self;
    }
};

string_pool: StringPool,
nodes: ArrayList(Node),
attributes: ArrayList(Attribute),

pub fn readAlloc(seek: anytype, reader: anytype, starting_pos: usize, chunk_header: ResourceChunk.Header, alloc: std.mem.Allocator) !XMLTree {
    const header = chunk_header;

    var string_pool: StringPool = undefined;

    var pos: usize = try seek.getPos();
    var resource_header = try ResourceChunk.Header.read(reader);

    var nodes = ArrayList(Node){};
    var attributes = ArrayList(Attribute){};

    while (true) {
        switch (resource_header.type) {
            .StringPool => {
                string_pool = try StringPool.readAlloc(seek, reader, pos, resource_header, alloc);
            },
            .XmlStartNamespace,
            .XmlEndElement,
            .XmlEndNamespace,
            => try nodes.append(alloc, try XMLTree.Node.read(reader, resource_header)),
            .XmlStartElement => {
                var node_id = nodes.items.len;
                var node = try XMLTree.Node.read(reader, resource_header);
                try nodes.append(alloc, node);
                var attribute = node.extended.Attribute;
                if (attribute.count > 0) {
                    var i: usize = 0;
                    while (i < attribute.count) : (i += 1) {
                        try attributes.append(
                            alloc,
                            try XMLTree.Attribute.read(reader, node_id),
                        );
                    }
                }
            },
            .XmlResourceMap => {
                std.log.info("skipped resource map", .{});
                // Skip for now
                // TODO
            },
            else => {
                std.log.info("xmltree unexpected chunk {}", .{resource_header});
                return error.InvalidChunkType;
            },
        }
        if (pos + resource_header.size >= starting_pos + header.size) {
            break;
        }
        try seek.seekTo(pos + resource_header.size);
        pos = try seek.getPos();
        resource_header = try ResourceChunk.Header.read(reader);
    }

    return XMLTree{
        .string_pool = string_pool,
        .nodes = nodes,
        .attributes = attributes,
    };
}

const XMLResourceMap = ResourceChunk.Header;

const Node = struct {
    line_number: u32,
    comment: StringPool.Ref,
    extended: NodeExtended,

    fn read(reader: anytype, header: ResourceChunk.Header) !Node {
        return Node{
            .line_number = try reader.readInt(u32, .Little),
            .comment = try StringPool.Ref.read(reader),
            .extended = switch (header.type) {
                .XmlStartNamespace,
                .XmlEndNamespace,
                => .{ .Namespace = try NamespaceExtended.read(reader) },
                .XmlCData => .{ .CData = try CDataExtended.read(reader) },
                .XmlEndElement => .{ .EndElement = try EndElementExtended.read(reader) },
                .XmlStartElement => .{ .Attribute = try AttributeExtended.read(reader) },
                else => {
                    std.log.info("not an xml element, {}", .{header});
                    return error.UnexpectedChunk;
                },
            },
        };
    }

    pub fn write(node: Node, writer: anytype) !void {
        // try node.header.write(writer);
        // TODO: construct + write header
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
            .value = try Value.read(reader, null),
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

    // Runtime values
    node: usize,

    pub fn read(reader: anytype, node: usize) !Attribute {
        return Attribute{
            .namespace = try StringPool.Ref.read(reader),
            .name = try StringPool.Ref.read(reader),
            .raw_value = try StringPool.Ref.read(reader),
            .typed_value = try Value.read(reader, null),
            .node = node,
        };
    }

    pub fn write(attribute: Attribute, writer: anytype) !void {
        try attribute.namespace.write(writer);
        try attribute.name.write(writer);
        try attribute.raw_value.write(writer);
        try attribute.typed_value.write(writer);
    }
};

const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const StringPool = @import("StringPool.zig");
const ResourceChunk = @import("ResourceChunk.zig");
const Value = @import("Value.zig");
