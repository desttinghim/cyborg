const std = @import("std");
const testing = std.testing;
const archive = @import("archive");

const c = @import("c.zig");
pub const dex = @import("dex.zig");
pub const binxml = @import("binxml.zig");
pub const signing = @import("signing.zig");

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
    xml,
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
        .xml => try readXml(alloc, args, stdout),
        .apk => try readApk(alloc, args, stdout),
        .dex => try readDex(alloc, args, stdout),
        .@"align" => try alignZip(alloc, args, stdout),
        .sign => try signZip(alloc, args, stdout),
        .verify => try verifyAPK(alloc, args, stdout),
        // .pkg => try writePackage(alloc, args, stdout),
    }
}

pub fn print_attributes(stdout: std.fs.File, doc: c.xmlDocPtr, node: *c.xmlNode) !void {
    var cur_attribute = node.properties;
    _ = doc;
    while (cur_attribute) |attribute| : (cur_attribute = attribute.*.next) {
        const attr_name = attribute.*.name;
        const attr_value = c.xmlGetProp(node, attr_name);
        defer c.xmlFree.?(attr_value);
        try std.fmt.format(stdout.writer(), " {s}={s}", .{ attr_name, attr_value });
    }
}

const XMLReaderType = enum(c_int) {
    None = c.XML_READER_TYPE_NONE,
    Element = c.XML_READER_TYPE_ELEMENT,
    Attribute = c.XML_READER_TYPE_ATTRIBUTE,
    Text = c.XML_READER_TYPE_TEXT,
    CData,
    EntityReference,
    Entity,
    ProcessingInstruction,
    Comment,
    Document,
    DocumentType,
    DocumentFragment,
    Notation,
    Whitespace,
    SignificantWhitespace = c.XML_READER_TYPE_SIGNIFICANT_WHITESPACE,
    EndElement = c.XML_READER_TYPE_END_ELEMENT,
    EndEntity,
    XMLDeclaration,
};

pub fn print_node(stdout: std.fs.File, reader: c.xmlTextReaderPtr) !void {
    var name: [*:0]const u8 = c.xmlTextReaderConstName(reader) orelse "--";
    var t = c.xmlTextReaderNodeType(reader);
    try stdout.writer().print("{:<5} {s: <25} {s: <20} {:<10} {:<10}", .{
        c.xmlTextReaderDepth(reader),
        @tagName(@intToEnum(XMLReaderType, t)),
        name,
        c.xmlTextReaderIsEmptyElement(reader),
        c.xmlTextReaderHasValue(reader),
    });

    if (c.xmlTextReaderConstValue(reader)) |value| {
        try stdout.writer().print("{s}\n", .{value});
    } else {
        _ = try stdout.writer().write("\n");
    }
}

pub fn readXml(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    var reader = c.xmlNewTextReaderFilename(args[2].ptr);
    if (reader == null) {
        try std.fmt.format(stdout.writer(), "error: could not open file {s}\n", .{args[2]});
        return error.XMLReaderInit;
    }
    defer {
        c.xmlFreeTextReader(reader);
        c.xmlCleanupParser();
    }

    var builder = binxml.XMLTree.Builder.init(alloc);

    var attributes = std.ArrayList(binxml.XMLTree.Builder.Attribute_b).init(alloc);
    defer attributes.deinit();

    var ret = c.xmlTextReaderRead(reader);
    while (ret == 1) : (ret = c.xmlTextReaderRead(reader)) {
        // try print_node(stdout, reader);
        var node_type = @intToEnum(XMLReaderType, c.xmlTextReaderNodeType(reader));
        const line_number = @intCast(u32, c.xmlTextReaderGetParserLineNumber(reader));
        try attributes.resize(0); // clear list
        switch (node_type) {
            .Element => {
                const name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingNameForElement);
                const namespace = if (c.xmlTextReaderConstNamespaceUri(reader)) |namespace| std.mem.span(namespace) else null;
                const is_empty = c.xmlTextReaderIsEmptyElement(reader) == 1;

                if (c.xmlTextReaderHasAttributes(reader) == 1) {
                    const count = @intCast(usize, c.xmlTextReaderAttributeCount(reader));
                    for (0..count) |i| {
                        if (c.xmlTextReaderMoveToAttributeNo(reader, @intCast(c_int, i)) != 1) continue;
                        const attr_ns = if (c.xmlTextReaderConstNamespaceUri(reader)) |ns| std.mem.span(ns) else null;
                        const attr_name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingAttributeName);
                        const value = std.mem.span(c.xmlTextReaderConstValue(reader) orelse return error.MissingAttributeValue);
                        if (c.xmlTextReaderIsNamespaceDecl(reader) == 1) {
                            try builder.startNamespace(attr_name, value);
                            continue;
                        }
                        try attributes.append(.{
                            .namespace = attr_ns,
                            .name = attr_name,
                            .value = value,
                        });
                    }
                }

                try builder.startElement(name, attributes.items, .{
                    .namespace = (namespace),
                    .line_number = line_number,
                });
                if (is_empty) {
                    try builder.endElement(name, .{
                        .namespace = namespace,
                        .line_number = line_number,
                    });
                    // try stdout.writer().print("{}", .{builder.xml_tree.nodes.getLast()});
                }
            },
            .EndElement => {
                const name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingNameForEndElement);
                const namespace = if (c.xmlTextReaderConstNamespaceUri(reader)) |namespace| std.mem.span(namespace) else null;
                try builder.endElement(name, .{
                    .namespace = namespace,
                    .line_number = line_number,
                });
                // try stdout.writer().print("{}", .{builder.xml_tree.nodes.getLast()});
            },
            // .CData => builder.insertCData(.{}),
            else => {},
        }
    }

    try print_xml_tree(builder.xml_tree, stdout);
}

pub fn readZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &std.io.StreamSource{ .file = file });

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

    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &std.io.StreamSource{ .file = file });

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

    var stream_source = std.io.StreamSource{ .file = file };

    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);
    try archive_reader.load();

    var id_value_pairs = try signing.get_signing_blocks(alloc, &stream_source, archive_reader);

    {
        var iter = id_value_pairs.iterator();
        try stdout.writer().print("\nSigning Blocks\n{s:<12}{s:<12}{s:<12}{s:<12}\n", .{ "ID", "Start", "End", "Length" });
        while (iter.next()) |id_value| {
            const start = id_value.value_ptr.start;
            const end = id_value.value_ptr.end;
            try stdout.writer().print("0x{X:<10}0x{X:<10}0x{X:<10}{:<10}\n", .{ id_value.key_ptr.*, start, end, end - start });
        }
        try stdout.writer().print("\n", .{});
    }

    const v2_block = id_value_pairs.get(0x7109871a) orelse return error.MissingV2;
    try stream_source.seekTo(v2_block.start);
    const signer_length = try stream_source.reader().readInt(u32, .Little);
    const signer_pos = try stream_source.getPos();
    try stdout.writer().print("Signer\t\t{}\tlength {}\n", .{ signer_pos, signer_length });
    while (try stream_source.getPos() < signer_pos + signer_length) {
        const signed_data_length = try stream_source.reader().readInt(u32, .Little);
        const signed_data_pos = try stream_source.getPos();
        try stdout.writer().print("signed data\t{}\tlength {}\n", .{ signed_data_pos, signed_data_length });

        // Signed Data
        while (try stream_source.getPos() < signed_data_pos + signed_data_length) {
            const digest_chunks_total_length = try stream_source.reader().readInt(u32, .Little);
            const digest_chunks_total_pos = try stream_source.getPos();
            try stdout.writer().print("Digest Chunks\t{}\tlength {}\n", .{ digest_chunks_total_pos, digest_chunks_total_length });
            // const digest_chunks_length = try stream_source.reader().readInt(u32, .Little);
            // const digest_chunks_pos = try stream_source.getPos();
            // try stdout.writer().print("Digest chunk of length {}; pos {}\n", .{ digest_chunks_length, digest_chunks_pos });
            while (try stream_source.getPos() < digest_chunks_total_pos + digest_chunks_total_length) {
                const digest_chunk_length = try stream_source.reader().readInt(u32, .Little);
                const digest_chunk_pos = try stream_source.getPos();
                const signature_algorithm_id = try stream_source.reader().readInt(u32, .Little);
                const digest_length = try stream_source.reader().readInt(u32, .Little);
                try stdout.writer().print("Digest signature algorithm id {x}; length {}\n", .{ signature_algorithm_id, digest_length });
                try stream_source.seekTo(digest_chunk_pos + digest_chunk_length);
            }

            const x509_list_length = try stream_source.reader().readInt(u32, .Little);
            const x509_list_pos = try stream_source.getPos();
            while (try stream_source.getPos() < x509_list_pos + x509_list_length) {
                const x509_length = try stream_source.reader().readInt(u32, .Little);
                try stdout.writer().print("x509 Certificate of length {}\n", .{x509_length});
                var buf: [1024]u8 = undefined;
                std.debug.assert(x509_length == try stream_source.reader().read(buf[0..x509_length]));
                const hex = std.fmt.fmtSliceHexUpper(buf[0..x509_length]);
                try stdout.writer().print("{s}\n", .{hex});

                const x509 = buf[0..x509_length];

                var cert = std.crypto.Certificate{
                    .buffer = x509,
                    .index = 0,
                };
                var parsed = try cert.parse();
                _ = parsed;
            }

            const attribute_list_length = try stream_source.reader().readInt(u32, .Little);
            const attribute_list_pos = try stream_source.getPos();
            while (try stream_source.getPos() < attribute_list_pos + attribute_list_length) {
                const attribute_length = try stream_source.reader().readInt(u32, .Little);
                const attribute_id = try stream_source.reader().readInt(u32, .Little);
                try stdout.writer().print("Attribute length {}; id: {}\n", .{ attribute_length, attribute_id });
                try stream_source.seekBy(attribute_length - 4);
            }
        }

        // Signatures
        const signatures_length = try stream_source.reader().readInt(u32, .Little);
        const signatures_pos = try stream_source.getPos();
        try stdout.writer().print("Signatures block of length {}\n", .{signatures_length});
        while (try stream_source.getPos() < signatures_pos + signatures_length) {
            const signature_length = try stream_source.reader().readInt(u32, .Little);
            const signature_pos = try stream_source.getPos();
            _ = signature_pos;
            const signature_algorithm_id = try stream_source.reader().readInt(u32, .Little);
            try stdout.writer().print("Signature id {}, length {} \n", .{ signature_algorithm_id, signature_length });
            const signature_over_data_length = try stream_source.reader().readInt(u32, .Little);
            _ = signature_over_data_length;
            try stream_source.seekBy(signature_length - 8);
        }

        // Public Key
        const public_key_length = try stream_source.reader().readInt(u32, .Little);
        const public_key_pos = try stream_source.getPos();
        try stdout.writer().print("Public key block of length {}\n", .{public_key_length});
        try stream_source.seekBy(@intCast(i64, public_key_pos + public_key_length));
    }

    try stdout.writer().print("End of signing block\n", .{});
}

pub fn alignZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &std.io.StreamSource{ .file = file });

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

    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &std.io.StreamSource{ .file = file });

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

    var classes = try dex.Dex.readAlloc(file.seekableStream(), file.reader(), alloc);

    for (classes.map_list.list) |list_item| {
        try std.fmt.format(stdout.writer(), "{}\n", .{list_item});
    }

    for (classes.string_ids, 0..) |id, i| {
        const str = try classes.getString(id);
        try std.fmt.format(stdout.writer(), "String {}: {s}\n", .{ i, str.data });
    }

    for (classes.type_ids, 0..) |id, i| {
        const str = try classes.getTypeString(id);
        try std.fmt.format(stdout.writer(), "Type Descriptor {}: {s}\n", .{ i, str.data });
    }

    for (classes.proto_ids, 0..) |id, i| {
        const prototype = try classes.getPrototype(id, alloc);
        try std.fmt.format(stdout.writer(), "Prototype {}; shorty {s}; (", .{ i, prototype.shorty.data });
        if (prototype.parameters) |parameters| {
            for (try classes.getTypeStringList(parameters, alloc)) |type_string| {
                try std.fmt.format(stdout.writer(), "{s}", .{type_string.data});
            }
        }
        try std.fmt.format(stdout.writer(), "){s}\n", .{prototype.return_type.data});
    }

    for (classes.field_ids, 0..) |id, i| {
        const class_str = try classes.getString(classes.string_ids[classes.type_ids[id.class_idx].descriptor_idx]);
        const type_str = try classes.getString(classes.string_ids[classes.type_ids[id.type_idx].descriptor_idx]);
        const name_str = try classes.getString(classes.string_ids[id.name_idx]);
        try std.fmt.format(stdout.writer(), "Field {}, {s}.{s}: {s}", .{ i, class_str.data, name_str.data, type_str.data });
    }

    for (classes.method_ids, 0..) |id, i| {
        const class_str = try classes.getString(classes.string_ids[classes.type_ids[id.class_idx].descriptor_idx]);
        const name_str = try classes.getString(classes.string_ids[id.name_idx]);
        const prototype = try classes.getPrototype(classes.proto_ids[id.proto_idx], alloc);
        try std.fmt.format(stdout.writer(), "Method {}, {s}.{s}(", .{ i, class_str.data, name_str.data });
        if (prototype.parameters) |parameters| {
            for (try classes.getTypeStringList(parameters, alloc)) |type_string| {
                try std.fmt.format(stdout.writer(), "{s}", .{type_string.data});
            }
        }
        try std.fmt.format(stdout.writer(), "){s}\n", .{prototype.return_type.data});
    }

    for (classes.class_defs) |def| {
        const class = try classes.getTypeString(classes.type_ids[def.class_idx]);
        const superclass = if (def.superclass_idx == dex.NO_INDEX) "null" else (try classes.getTypeString(classes.type_ids[def.superclass_idx])).data;
        const file_name = try classes.getString(classes.string_ids[def.source_file_idx]);
        try std.fmt.format(stdout.writer(), "{} Class {s} extends {s} defined in {s}\n", .{ def.access_flags, class.data, superclass, file_name.data });
    }
}

fn printInfo(document: binxml.Document, stdout: std.fs.File) !void {
    for (document.chunks.items) |chunk| {
        switch (chunk) {
            .Xml => |xml_tree| try print_xml_tree(xml_tree, stdout),
            .Table => |table| try print_table(table, stdout),
            .StringPool => |string_pool| {
                try std.fmt.format(stdout, "String Pool chunk:\n", .{});
                for (0..string_pool.get_len()) |index| {
                    const i = @intCast(u32, index);
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
