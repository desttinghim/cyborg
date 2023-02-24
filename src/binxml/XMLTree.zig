const XMLTree = @This();

header: Header,
string_pool: StringPool,
nodes: ArrayList(Node),
attributes: ArrayList(Attribute),

pub fn readAlloc(seek: anytype, reader: anytype, starting_pos: usize, chunk_header: ResourceChunk, alloc: std.mem.Allocator) !XMLTree {
    const header = chunk_header;

    var string_pool: StringPool = undefined;

    var pos: usize = try seek.getPos();
    var resource_header = try ResourceChunk.read(reader);

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
        resource_header = try ResourceChunk.read(reader);
    }

    return XMLTree{
        .header = header,
        .string_pool = string_pool,
        .nodes = nodes,
        .attributes = attributes,
    };
}

const Header = ResourceChunk;

const XMLResourceMap = ResourceChunk;

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
                else => {
                    std.log.info("not an xml element, {}", .{header});
                    return error.UnexpectedChunk;
                },
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
