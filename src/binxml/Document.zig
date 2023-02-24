const Document = @This();

xml_trees: ArrayList(XMLTree),
tables: ArrayList(ResourceTable),

pub fn readAlloc(seek: anytype, reader: anytype, alloc: std.mem.Allocator) !Document {
    const file_length = try seek.getEndPos();

    var xml_trees = ArrayList(XMLTree){};
    var tables = ArrayList(ResourceTable){};

    var pos: usize = try seek.getPos();
    var header = try ResourceChunk.read(reader);
    while (true) {
        switch (header.type) {
            .Xml => {
                try xml_trees.append(alloc, try XMLTree.readAlloc(seek, reader, pos, header, alloc));
            },
            .Table => {
                try tables.append(alloc, try ResourceTable.readAlloc(seek, reader, pos, header, alloc));
            },
            .Null => {
                std.log.err("Encountered null chunk {}, {?}", .{ pos, header });
                if (header.header_size == 0) return error.MalformedNullChunk;
            },
            else => {
                std.log.err("Unimplemented chunk type: {s}", .{@tagName(header.type)});
                break;
            },
        }
        if (pos + header.size >= file_length) {
            break;
        }
        try seek.seekTo(pos + header.size);
        pos = try seek.getPos();
        header = try ResourceChunk.read(reader);
    }

    return Document{
        .xml_trees = xml_trees,
        .tables = tables,
    };
}

pub fn write(document: Document, seek: anytype, writer: anytype) !Document {
    // TODO: Rewrite this to reflect updated understanding

    // Write magic bytes
    try writer.write("\x03\x00\x08\x00");

    // Save a spot for the length
    try writer.writeInt(u32, 0, .Little);

    // Write the string pool header
    try document.string_pool_header.write(writer);

    // Write the string offsets
    for (document.string_pool, 0..) |string, i| {
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
    for (document.resources_nodes, 0..) |node, i| {
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
    const file_size = seek.getEndPos();
    try seek.seekTo(4);
    try writer.write(file_size);
}

const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;

const ResourceChunk = @import("ResourceChunk.zig");
const Value = @import("Value.zig");
const StringPool = @import("StringPool.zig");
const XMLTree = @import("XMLTree.zig");
const ResourceTable = @import("ResourceTable.zig");
