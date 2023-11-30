const std = @import("std");
const testing = std.testing;
const archive = @import("archive");

// const c = @import("c.zig");
pub const dex = @import("dex.zig");
pub const binxml = @import("binxml.zig");
pub const signing = @import("signing.zig");
pub const dexter = @import("dexter.zig");

comptime {
    _ = dexter;
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const usage =
    \\USAGE: zandroid <subcommand>
    \\SUBCOMMANDS:
    \\  zip     <file>                  Reads a zip file and lists the contents
    \\  zip     <file> <filename>       Reads the contents of a file from a zip file
    \\  align   <file>                  Aligns a zip file
    \\  verify  <file>                  Verifies the signature of an APK file
    \\  sign    <file>                  Signs an APK file
    \\  binxml  <file>                  Reads an Android binary XML file
    \\  xml     <file>                  Converts an XML file to an Android binary XML file
    \\  apk     <file>                  Reads the AndroidManifest.xml in the indicated apk
    \\  dex     <file>                  Reads a Dalvik EXecutable file
    \\
;

const Subcommand = enum {
    zip,
    // xml,
    binxml,
    apk,
    dex,
    @"align",
    sign,
    verify,
    // pkg,
};

pub fn main() !void {
    const stdout = std.io.getStdOut();
    run(stdout) catch |err| {
        switch (err) {
            else => |e| {
                _ = try stdout.write("Error! ");
                _ = try stdout.write(@errorName(e));
                _ = try stdout.write("\n");
            },
        }
        _ = try stdout.write(usage);
    };
}

pub fn run(stdout: std.fs.File) !void {
    const alloc = gpa.allocator();
    const args = try std.process.argsAlloc(alloc);

    if (args.len < 2) {
        return error.MissingSubcommand;
    }

    const cmd = std.meta.stringToEnum(Subcommand, args[1]) orelse return error.InvalidSubcommand;

    switch (cmd) {
        .zip => try readZip(alloc, args, stdout),
        .binxml => try readBinXml(alloc, args, stdout),
        // .xml => try readXml(alloc, args, stdout),
        .apk => try readApk(alloc, args, stdout),
        .dex => try readDex(alloc, args, stdout),
        .@"align" => try alignZip(alloc, args, stdout),
        .sign => try signZip(alloc, args, stdout),
        .verify => try verifyAPK(alloc, args, stdout),
        // .pkg => try writePackage(alloc, args, stdout),
    }
}

// pub fn print_attributes(stdout: std.fs.File, doc: c.xmlDocPtr, node: *c.xmlNode) !void {
//     var cur_attribute = node.properties;
//     _ = doc;
//     while (cur_attribute) |attribute| : (cur_attribute = attribute.*.next) {
//         const attr_name = attribute.*.name;
//         const attr_value = c.xmlGetProp(node, attr_name);
//         defer c.xmlFree.?(attr_value);
//         try std.fmt.format(stdout.writer(), " {s}={s}", .{ attr_name, attr_value });
//     }
// }

// const XMLReaderType = enum(c_int) {
//     None = c.XML_READER_TYPE_NONE,
//     Element = c.XML_READER_TYPE_ELEMENT,
//     Attribute = c.XML_READER_TYPE_ATTRIBUTE,
//     Text = c.XML_READER_TYPE_TEXT,
//     CData,
//     EntityReference,
//     Entity,
//     ProcessingInstruction,
//     Comment,
//     Document,
//     DocumentType,
//     DocumentFragment,
//     Notation,
//     Whitespace,
//     SignificantWhitespace = c.XML_READER_TYPE_SIGNIFICANT_WHITESPACE,
//     EndElement = c.XML_READER_TYPE_END_ELEMENT,
//     EndEntity,
//     XMLDeclaration,
// };
//
// pub fn print_node(stdout: std.fs.File, reader: c.xmlTextReaderPtr) !void {
//     var name: [*:0]const u8 = c.xmlTextReaderConstName(reader) orelse "--";
//     var t = c.xmlTextReaderNodeType(reader);
//     try stdout.writer().print("{:<5} {s: <25} {s: <20} {:<10} {:<10}", .{
//         c.xmlTextReaderDepth(reader),
//         @tagName(@as(XMLReaderType, @enumFromInt(t))),
//         name,
//         c.xmlTextReaderIsEmptyElement(reader),
//         c.xmlTextReaderHasValue(reader),
//     });
//
//     if (c.xmlTextReaderConstValue(reader)) |value| {
//         try stdout.writer().print("{s}\n", .{value});
//     } else {
//         _ = try stdout.writer().write("\n");
//     }
// }
//
// pub fn readXml(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
//     var reader = c.xmlNewTextReaderFilename(args[2].ptr);
//     if (reader == null) {
//         try std.fmt.format(stdout.writer(), "error: could not open file {s}\n", .{args[2]});
//         return error.XMLReaderInit;
//     }
//     defer {
//         c.xmlFreeTextReader(reader);
//         c.xmlCleanupParser();
//     }
//
//     var builder = binxml.XMLTree.Builder.init(alloc);
//
//     var attributes = std.ArrayList(binxml.XMLTree.Builder.Attribute_b).init(alloc);
//     defer attributes.deinit();
//
//     var ret = c.xmlTextReaderRead(reader);
//     while (ret == 1) : (ret = c.xmlTextReaderRead(reader)) {
//         // try print_node(stdout, reader);
//         var node_type = @as(XMLReaderType, @enumFromInt(c.xmlTextReaderNodeType(reader)));
//         const line_number = @as(u32, @intCast(c.xmlTextReaderGetParserLineNumber(reader)));
//         try attributes.resize(0); // clear list
//         switch (node_type) {
//             .Element => {
//                 const name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingNameForElement);
//                 const namespace = if (c.xmlTextReaderConstNamespaceUri(reader)) |namespace| std.mem.span(namespace) else null;
//                 const is_empty = c.xmlTextReaderIsEmptyElement(reader) == 1;
//
//                 if (c.xmlTextReaderHasAttributes(reader) == 1) {
//                     const count = @as(usize, @intCast(c.xmlTextReaderAttributeCount(reader)));
//                     for (0..count) |i| {
//                         if (c.xmlTextReaderMoveToAttributeNo(reader, @as(c_int, @intCast(i))) != 1) continue;
//                         const attr_ns = if (c.xmlTextReaderConstNamespaceUri(reader)) |ns| std.mem.span(ns) else null;
//                         const attr_name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingAttributeName);
//                         const value = std.mem.span(c.xmlTextReaderConstValue(reader) orelse return error.MissingAttributeValue);
//                         if (c.xmlTextReaderIsNamespaceDecl(reader) == 1) {
//                             try builder.startNamespace(attr_name, value);
//                             continue;
//                         }
//                         try attributes.append(.{
//                             .namespace = attr_ns,
//                             .name = attr_name,
//                             .value = value,
//                         });
//                     }
//                 }
//
//                 try builder.startElement(name, attributes.items, .{
//                     .namespace = (namespace),
//                     .line_number = line_number,
//                 });
//                 if (is_empty) {
//                     try builder.endElement(name, .{
//                         .namespace = namespace,
//                         .line_number = line_number,
//                     });
//                     // try stdout.writer().print("{}", .{builder.xml_tree.nodes.getLast()});
//                 }
//             },
//             .EndElement => {
//                 const name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingNameForEndElement);
//                 const namespace = if (c.xmlTextReaderConstNamespaceUri(reader)) |namespace| std.mem.span(namespace) else null;
//                 try builder.endElement(name, .{
//                     .namespace = namespace,
//                     .line_number = line_number,
//                 });
//                 // try stdout.writer().print("{}", .{builder.xml_tree.nodes.getLast()});
//             },
//             // .CData => builder.insertCData(.{}),
//             else => {},
//         }
//     }
//
//     try print_xml_tree(builder.xml_tree, stdout);
// }

pub fn readZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var stream_source = std.io.StreamSource{ .file = file };
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);

    try archive_reader.load();

    for (archive_reader.directory.items, 0..) |cd_record, i| {
        _ = cd_record;
        const header = archive_reader.getHeader(i);
        _ = try stdout.write(header.filename);
        _ = try stdout.write("\n");
    }
}

pub fn signZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    _ = stdout;
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var stream_source = std.io.StreamSource{ .file = file };
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);

    try archive_reader.load();

    // TODO: parse signing options

    // TODO: Read zip archive into memory

    // TODO: Sign with specified options

    // TODO: Write new zip file with signing block added
}

pub fn verifyAPK(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    const apk_map = try std.os.mmap(null, try file.getEndPos(), std.os.PROT.WRITE, std.os.MAP.PRIVATE, file.handle, 0);
    defer std.os.munmap(apk_map);

    const signing_block = try signing.get_offsets(alloc, apk_map);

    const v2_block = signing_block.locate_entry(signing.SigningEntry.Tag.V2) catch return error.MissingV2;

    // TODO: verify signatures before parsing signed data
    const signing_entry = try signing.parse_v2(alloc, v2_block);
    for (signing_entry.V2.items) |signer| {
        try stdout.writer().print(
            \\
            \\Signed Data:
            \\    digests:      {}
            \\    certificates: {}
            \\    attributes:   {}
            \\
        , .{
            signer.signed_data.digests.items.len,
            signer.signed_data.certificates.items.len,
            signer.signed_data.attributes.items.len,
        });

        for (signer.signed_data.digests.items) |digest| {
            try stdout.writer().print("\tLength {}\tAlgorithm {}\n", .{ digest.data.len, digest.algorithm });
            try stdout.writer().print("\t{}\n", .{std.fmt.fmtSliceHexUpper(digest.data)});
        }

        try stdout.writer().print("Signatures: {} items\n", .{
            signer.signatures.items.len,
        });
        for (signer.signatures.items) |signature| {
            try stdout.writer().print("\tAlgorithm: {}\n\tsignature length: {}\n", .{
                signature.algorithm,
                signature.signature.len,
            });
        }

        try stdout.writer().print("Public Key: {}\n", .{
            signer.public_key,
        });
    }

    const signing_block_offset = signing_block.signing_block_offset;
    const directory_offset = signing_block.central_directory_offset;
    const eocd_offset = signing_block.end_of_central_directory_offset; // TODO: get the end of central directory from zig-archive

    // The APK signing algorithm treats the directory offset in the EOCD record
    // as a point to the beginning of the signing block offset. This is necessary
    // because inserting the signing block can move the beginning of the central
    // directory record, which would make the signing block invalid.
    signing_block.update_eocd_directory_offset(apk_map);

    const chunks = try signing.splitAPK(alloc, apk_map, signing_block_offset, directory_offset, eocd_offset);
    try stdout.writer().print("Chunk total: {}\n", .{chunks.len});

    // TODO: use the correct algorithm instead of assuming Sha256
    const Sha256 = std.crypto.hash.sha2.Sha256;

    // Allocate enough memory to store all the digests
    const digest_mem = try alloc.alloc(u8, Sha256.digest_length * chunks.len);
    defer alloc.free(digest_mem);

    // Loop over every chunk and compute its digest
    for (chunks, 0..) |chunk, i| {
        var hash = Sha256.init(.{});

        var size_buf: [4]u8 = undefined;
        var size = @as(u32, @intCast(chunk.len));
        std.mem.writeInt(u32, &size_buf, size, .little);

        hash.update(&.{0xa5}); // Magic value byte
        hash.update(&size_buf); // Size in bytes, le u32
        hash.update(chunk); // Chunk contents

        hash.final(digest_mem[i * Sha256.digest_length ..][0..Sha256.digest_length]);
    }

    // Compute the digest over all chunks
    var hash = Sha256.init(.{});

    var size_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &size_buf, @as(u32, @intCast(chunks.len)), .little);

    hash.update(&.{0x5a}); // Magic value byte for final digest
    hash.update(&size_buf);
    hash.update(digest_mem);
    const final_digest = hash.finalResult();

    // Compare the final digest with the one stored in the signing block
    const digest_is_equal = std.mem.eql(u8, signing_entry.V2.items[0].signed_data.digests.items[0].data, &final_digest);
    try stdout.writer().print("{}\n", .{std.fmt.fmtSliceHexUpper(&final_digest)});
    if (digest_is_equal) {
        try stdout.writer().print("Digest Equal\n", .{});
    } else {
        try stdout.writer().print("ERROR - Digest Value Differs!\n", .{});
    }

    // TODO: Verify the SubjectPublicKeyInfo of the certificate is identical to the public key
}

pub fn alignZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var stream_source = std.io.StreamSource{ .file = file };
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);

    try archive_reader.load();

    for (archive_reader.directory.items, 0..) |cd_record, i| {
        _ = cd_record;
        const header = archive_reader.getHeader(i);
        _ = try stdout.write(header.filename);
        _ = try stdout.write("\n");
    }
}

pub fn readBinXml(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();

    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var document = try binxml.Document.readAlloc(file.seekableStream(), file.reader(), arena_alloc);

    try printInfo(document, stdout);
}

pub fn readApk(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var stream_source = std.io.StreamSource{ .file = file };
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);

    try archive_reader.load();

    // Read manifest
    const manifest_header = archive_reader.findFile("AndroidManifest.xml") orelse return error.MissingManifest;

    const manifest_string = try archive_reader.extractFileString(manifest_header, alloc, true);
    defer alloc.free(manifest_string);

    var manifest_stream = std.io.FixedBufferStream([]const u8){ .pos = 0, .buffer = manifest_string };
    var document = try binxml.Document.readAlloc(manifest_stream.seekableStream(), manifest_stream.reader(), alloc);

    try printInfo(document, stdout);

    // Read resource table
    const resource_header = archive_reader.findFile("resources.arsc") orelse return error.MissingResourceTable;

    const resource_string = try archive_reader.extractFileString(resource_header, alloc, true);
    defer alloc.free(resource_string);

    var resource_stream = std.io.FixedBufferStream([]const u8){ .pos = 0, .buffer = resource_string };
    var resource_document = try binxml.Document.readAlloc(resource_stream.seekableStream(), resource_stream.reader(), alloc);

    try printInfo(resource_document, stdout);
}

pub fn readDex(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});
    const file_buffer = try file.readToEndAlloc(alloc, std.math.maxInt(u16));
    defer alloc.free(file_buffer);

    // TODO: remove references to Dex internal fields and instead design an API that will allow
    // querying the file directly _without_ creating a bunch of in-memory structures
    var dexfile = try dex.Dex.initFromSlice(file_buffer);

    // var classes = try dex.Dex.readAlloc(file.seekableStream(), file.reader(), alloc);

    var map_iter = dexfile.mapIterator();
    try std.fmt.format(stdout.writer(), "Map Item Count: {}\n", .{map_iter.list_size});
    while (map_iter.next()) |list_item| {
        try std.fmt.format(stdout.writer(), "Map Item: {}\n", .{list_item});
    }

    var string_iter = dexfile.stringIterator();
    while (string_iter.next()) |string| {
        try std.fmt.format(stdout.writer(), "String: {s}\n", .{string});
    }

    var type_iter = dexfile.typeIterator();
    while (type_iter.next()) |t_id| {
        const t = try dexfile.getString(t_id);
        try std.fmt.format(stdout.writer(), "Type Descriptor: {s}\n", .{t});
    }

    {
        var i: usize = 0;
        var proto_iter = dexfile.protoIterator();
        while (proto_iter.next()) |proto| : (i += 1) {
            const shorty = try dexfile.getString(proto.shorty_idx);
            const t = try dexfile.getTypeString(proto.return_type_idx);
            try std.fmt.format(stdout.writer(), "prototype {}\n", .{proto});
            try std.fmt.format(stdout.writer(), "Prototype {}; shorty {s}; (", .{ i, shorty });
            var param_iter_opt = try dexfile.typeListIterator(proto.parameters_off);
            if (param_iter_opt) |*param_iter| {
                while (param_iter.next()) |param| {
                    const param_str = try dexfile.getTypeString(param);
                    try std.fmt.format(stdout.writer(), "{s}", .{param_str});
                }
            }
            try std.fmt.format(stdout.writer(), "){s}\n", .{t});
        }
    }

    {
        var i: usize = 0;
        var field_iter = dexfile.fieldIterator();
        while (field_iter.next()) |id| : (i += 1) {
            const class_str = try dexfile.getTypeString(id.class_idx);
            const type_str = try dexfile.getTypeString(id.type_idx);
            const name_str = try dexfile.getString(id.name_idx);
            try std.fmt.format(stdout.writer(), "Field {}, {s}.{s}: {s}\n", .{ i, class_str, name_str, type_str });
        }
    }

    // {
    //     var i: usize = 0;
    //     var method_iter = dexfile.methodIterator();
    //     while (method_iter.next()) |id| : (i += 1) {
    //         const class_str = dexfile.getClassString(id.class_idx);
    //         const name_str = dexfile.getString(id.name_idx);
    //         const prototype = dexfile.getPrototypeString(id.proto_idx);
    //         try std.fmt.format(stdout.writer(), "Method {}, {s}.{s}", .{ i, class_str, name_str, prototype_string });
    //     }
    // }

    // {
    //     var i: usize = 0;
    //     var class_iter = dexfile.classIterator();
    //     while (class_iter.next()) |class| : (i += 1) {
    //     }
    // }
    // for (classes.class_defs.items, classes.class_data.items) |def, data| {
    //     const class = try classes.getTypeString(classes.type_ids.items[def.class_idx]);
    //     const superclass = if (def.superclass_idx == dex.NO_INDEX) "null" else (try classes.getTypeString(classes.type_ids.items[def.superclass_idx])).data;
    //     const file_name = if (def.source_file_idx == dex.NO_INDEX) "null" else (try classes.getString(classes.string_ids.items[def.source_file_idx])).data;
    //     try std.fmt.format(stdout.writer(), "{} Class {s} extends {s} defined in {s}\n", .{ def.access_flags, class.data, superclass, file_name });

    //     var static_field_id: u32 = 0;
    //     for (data.static_fields.items, 0..) |field, i| {
    //         static_field_id = if (i == 0) field.field_idx_diff else static_field_id +% field.field_idx_diff;
    //         try stdout.writer().print("\t{} ", .{field.access_flags});
    //         try classes.writeFieldString(stdout.writer(), static_field_id);
    //     }

    //     var instance_field_id: u32 = 0;
    //     for (data.instance_fields.items, 0..) |field, i| {
    //         instance_field_id = if (i == 0) field.field_idx_diff else instance_field_id +% field.field_idx_diff;
    //         try stdout.writer().print("\t{} ", .{field.access_flags});
    //         try classes.writeFieldString(stdout.writer(), instance_field_id);
    //     }

    //     var direct_method_id: u32 = 0;
    //     for (data.direct_methods.items, 0..) |method, i| {
    //         direct_method_id = if (i == 0) method.method_idx_diff else direct_method_id +% method.method_idx_diff;
    //         try stdout.writer().print("\t{} ", .{method.access_flags});
    //         try classes.writeMethodString(alloc, stdout.writer(), direct_method_id);

    //         if (method.code_off == 0) continue;

    //         try file.seekTo(method.code_off);
    //         const code_item = try dex.CodeItem.read(file.reader(), alloc);
    //         defer code_item.deinit(alloc);
    //         try stdout.writer().print("{}\n", .{code_item});
    //     }

    //     var virtual_method_id: u32 = 0;
    //     for (data.virtual_methods.items, 0..) |method, i| {
    //         virtual_method_id = if (i == 0) method.method_idx_diff else virtual_method_id +% method.method_idx_diff;
    //         try stdout.writer().print("\t{} ", .{method.access_flags});
    //         try classes.writeMethodString(alloc, stdout.writer(), virtual_method_id);

    //         if (method.code_off == 0) continue;

    //         try file.seekTo(method.code_off);
    //         const code_item = try dex.CodeItem.read(file.reader(), alloc);
    //         defer code_item.deinit(alloc);
    //         try stdout.writer().print("{}\n", .{code_item});
    //     }
    // }
}

fn printInfo(document: binxml.Document, stdout: std.fs.File) !void {
    for (document.chunks.items) |chunk| {
        switch (chunk) {
            .Xml => |xml_tree| try print_xml_tree(xml_tree, stdout),
            .Table => |table| try print_table(table, stdout),
            .StringPool => |string_pool| {
                try std.fmt.format(stdout, "String Pool chunk:\n", .{});
                for (0..string_pool.get_len()) |index| {
                    const i = @as(u32, @intCast(index));
                    if (string_pool.getUtf16Raw(i)) |string| {
                        try std.fmt.format(stdout.writer(), "{}: {}\n", .{ i, std.unicode.fmtUtf16le(string) });
                    } else if (string_pool.getUtf8Raw(i)) |string| {
                        try std.fmt.format(stdout.writer(), "{}: {s}\n", .{ i, string });
                    } else {
                        try std.fmt.format(stdout.writer(), "[Unknown Encoding for string {}] \n", .{i});
                    }
                }
            },
        }
    }
}

fn print_xml_tree(xml_tree: binxml.XMLTree, stdout: std.fs.File) !void {
    var indent: usize = 0;
    for (xml_tree.nodes.items, 0..) |node, node_id| {
        if (node.extended == .Attribute) {
            indent += 1;
        }
        var iloop: usize = 1;
        while (iloop < indent) : (iloop += 1) {
            try std.fmt.format(stdout, "\t", .{});
        }
        switch (node.extended) {
            .CData => |cdata| {
                const data = xml_tree.string_pool.get_formatter(cdata.data).?;

                try std.fmt.format(stdout.writer(), "{}", .{data});
            },
            .Namespace => |namespace| {
                const prefix = xml_tree.string_pool.get_formatter(namespace.prefix).?;
                const uri = xml_tree.string_pool.get_formatter(namespace.uri).?;

                try std.fmt.format(stdout.writer(), "xmlns:{}={}", .{
                    prefix,
                    uri,
                });
            },
            .EndElement => |end| {
                if (xml_tree.string_pool.get_formatter(end.name)) |name| {
                    try std.fmt.format(stdout.writer(), "</{}>", .{name});
                }
            },
            .Attribute => |attribute| {
                try std.fmt.format(stdout.writer(), "<", .{});
                {
                    if (xml_tree.string_pool.get_formatter(attribute.namespace)) |ns| {
                        try std.fmt.format(stdout.writer(), "{}:", .{ns});
                    }
                    if (xml_tree.string_pool.get_formatter(attribute.name)) |name| {
                        try std.fmt.format(stdout.writer(), "{}", .{name});
                    }
                }
                for (xml_tree.attributes.items) |*attr| {
                    if (attr.*.node != node_id) continue;
                    try std.fmt.format(stdout, "\n", .{});
                    var iloop2: usize = 1;
                    while (iloop2 < indent + 1) : (iloop2 += 1) {
                        try std.fmt.format(stdout, "\t", .{});
                    }
                    if (xml_tree.string_pool.get_formatter(attr.*.namespace)) |ns| {
                        try std.fmt.format(stdout.writer(), "{}/", .{ns});
                    }
                    if (xml_tree.string_pool.get_formatter(attr.*.name)) |name| {
                        try std.fmt.format(stdout.writer(), "{}", .{name});
                    }
                    try std.fmt.format(stdout.writer(), "={s}", .{attr.*.typed_value});
                }
                try std.fmt.format(stdout.writer(), ">", .{});
            },
        }
        try std.fmt.format(stdout.writer(), "\n", .{});
        if (node.extended == .EndElement) {
            indent -= 1;
        }
    }
}

fn print_table(table: binxml.ResourceTable, stdout: std.fs.File) !void {
    for (table.packages.items) |package| {
        try std.fmt.format(stdout.writer(), "Package {} (ID {})\n", .{ std.unicode.fmtUtf16le(package.name), package.id });
        try std.fmt.format(stdout.writer(), "\tType Strings {}\n\tLast Public Type {}\n\tKey Strings {}\n\tLast Public Key {}\n\tType ID Offset {}\n", .{
            package.type_strings,
            package.last_public_type,
            package.key_strings,
            package.last_public_key,
            package.type_id_offset,
        });
        for (package.type_spec.items) |type_spec| {
            try std.fmt.format(stdout.writer(), "\tType Spec {}\n", .{type_spec.id});
            for (type_spec.entry_indices) |*entry| {
                try std.fmt.format(stdout.writer(), "\t\t{}\n", .{entry.*});
            }
        }
        for (package.table_type.items) |table_type| {
            try std.fmt.format(stdout.writer(), "\tTable Type {}, {}\n", .{ table_type.id, table_type.flags });
            // try std.fmt.format(stdout.writer(), "\t\tConfig: {}\n", .{table_type.config});
            for (table_type.entries.items) |*entry| {
                if (entry.*.value) |*value| {
                    value.*.string_pool = &package.key_string_pool;
                }
                if (package.key_string_pool.getUtf16(entry.key)) |entry_string| {
                    try std.fmt.format(stdout.writer(), "\t\t{}: {?}\n", .{ std.unicode.fmtUtf16le(entry_string), entry.value });
                }
            }
        }
    }
}
