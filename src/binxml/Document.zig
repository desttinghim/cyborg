const Document = @This();

chunks: ArrayList(ResourceChunk.Chunk) = .{},

pub fn readAlloc(seek: anytype, reader: anytype, alloc: std.mem.Allocator) !Document {
    const file_length = try seek.getEndPos();

    var document = Document{};

    var pos: usize = try seek.getPos();
    while (true) {
        const chunk = ResourceChunk.readAlloc(seek, reader, pos, alloc) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        try document.chunks.append(alloc, chunk);
        pos = seek.getPos() catch break;
        if (pos > file_length) break;
    }

    return document;
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
        try writer.writeInt(u32, @as(u32, @intCast((string.len + i) * 2)), .Little);
    }

    // Write the strings
    for (document.string_pool) |string| {
        try writer.writeInt(u16, @as(u16, @intCast(string.len)), .Little);
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

const Builder = struct {
    allocator: std.mem.Allocator,
    document: Document,

    pub fn init(allocator: std.mem.Allocator) void {
        return .{
            .allocator = allocator,
            .document = Document{},
        };
    }

    pub fn createXMLTree(self: *Builder) !XMLTree.Builder {
        self.document.xml_trees.append(self.allocator, .{});
    }
};

test Builder {
    const builder = Builder.init(std.testing.allocator);
    _ = builder;
}

const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;

const ResourceChunk = @import("ResourceChunk.zig");
const Value = @import("Value.zig");
const StringPool = @import("StringPool.zig");
const XMLTree = @import("XMLTree.zig");
const ResourceTable = @import("ResourceTable.zig");
