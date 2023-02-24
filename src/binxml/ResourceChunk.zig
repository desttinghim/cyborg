//! This represents one chunk in the Android binary xml format.

/// Union of chunk types - only StringPool, Table, and XML are valid top-level chunks. The rest are chuldren of a StringPool, Table, or Xml chunk.
pub const Chunk = union(enum) {
    StringPool: StringPool,
    Table: ResourceTable,
    Xml: XMLTree,
};

/// Enum of all resource chunk tags.
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

pub const Header = struct {
    type: Type,
    header_size: u16,
    size: u32,

    pub fn read(reader: anytype) !Header {
        return Header{
            .type = @intToEnum(Type, try reader.readInt(u16, .Little)),
            .header_size = try reader.readInt(u16, .Little),
            .size = try reader.readInt(u32, .Little),
        };
    }

    pub fn init(t: Type) Chunk {
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
        return Chunk{
            .type = t,
            .header_size = header_size,
            .size = size,
        };
    }
};

pub fn readAlloc(seek: anytype, reader: anytype, pos: usize, alloc: std.mem.Allocator) !Chunk {
    var header = Header{
        .type = @intToEnum(Type, try reader.readInt(u16, .Little)),
        .header_size = try reader.readInt(u16, .Little),
        .size = try reader.readInt(u32, .Little),
    };
    const chunk: Chunk = switch (header.type) {
        // inline .Xml, .Table, .StringPool => |tag| {
        //     @unionInit(Chunk, @tagName(tag), @field(Chunk, @tagName(tag)).read(seek, reader, pos, header, alloc),);
        // },
        .Xml => .{ .Xml = try XMLTree.readAlloc(seek, reader, pos, header, alloc) },
        .Table => .{ .Table = try ResourceTable.readAlloc(seek, reader, pos, header, alloc) },
        .StringPool => .{ .StringPool = try StringPool.readAlloc(seek, reader, pos, header, alloc) },
        else => return error.MissingTopLevelChunk,
    };
    seek.seekTo(pos + header.size) catch {};
    return chunk;
}

// TODO:
// pub fn write(chunk: Chunk, writer: anytype) !void {
//     try writer.writeInt(u16, @enumToInt(header.type), .Little);
//     try writer.writeInt(u16, @enumToInt(header.header_size), .Little);
//     try writer.writeInt(u32, @enumToInt(header.size), .Little);
// }

const std = @import("std");
const Value = @import("Value.zig");
const StringPool = @import("StringPool.zig");
const XMLTree = @import("XMLTree.zig");
const ResourceTable = @import("ResourceTable.zig");
