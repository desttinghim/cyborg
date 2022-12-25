const std = @import("std");
const testing = std.testing;
const archive = @import("archive");

const c = @import("c.zig");
pub const dex = @import("dex.zig");
pub const binxml = @import("binxml.zig");
pub const manifest = @import("manifest.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const usage =
    \\USAGE: zandroid <subcommand>
    \\SUBCOMMANDS:
    \\  zip <file>                  Reads a zip file and lists the contents
    \\  zip <file> <filename>       Reads the contents of a file from a zip file
    \\  xml <file>                  Reads an Android binary XML file
    \\  apk <file>                  Reads the AndroidManifest.xml in the indicated apk
    \\  dex <file>                  Reads a Dalvik EXecutable file
    // \\  pkg <manifest> <out>        Creates an APK from a manifest.json
    \\
;

const Subcommand = enum {
    zip,
    xml,
    binxml,
    apk,
    dex,
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

pub fn print_element_names(stdout: std.fs.File, doc: c.xmlDocPtr, a_node: ?*c.xmlNode, depth: usize) !void {
    var cur_node = a_node;
    while (cur_node) |node| : (cur_node = node.next) {
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            _ = try stdout.writer().write("\t");
        }
        switch (node.type) {
            c.XML_ELEMENT_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Element, name: {s}", .{node.name});
                try print_attributes(stdout, doc, node);
                _ = try stdout.writer().write("\n");
            },
            c.XML_ATTRIBUTE_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Attribute, name: {s}\n", .{node.name});
            },
            c.XML_TEXT_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Text, name: {s}\n", .{node.name});
            },
            c.XML_CDATA_SECTION_NODE => {
                try std.fmt.format(stdout.writer(), "node type: CDATA, name: {s}\n", .{node.name});
            },
            c.XML_ENTITY_REF_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Entity Ref, name: {s}\n", .{node.name});
            },
            c.XML_ENTITY_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Entity, name: {s}\n", .{node.name});
            },
            c.XML_PI_NODE => {
                try std.fmt.format(stdout.writer(), "node type: PI, name: {s}\n", .{node.name});
            },
            c.XML_COMMENT_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Comment, name: {s}\n", .{node.name});
            },
            c.XML_DOCUMENT_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Document, name: {s}\n", .{node.name});
            },
            c.XML_DOCUMENT_TYPE_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Document Type, name: {s}\n", .{node.name});
            },
            c.XML_DOCUMENT_FRAG_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Document Frag, name: {s}\n", .{node.name});
            },
            c.XML_NOTATION_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Notation, name: {s}\n", .{node.name});
            },
            c.XML_HTML_DOCUMENT_NODE => {
                try std.fmt.format(stdout.writer(), "node type: Html Document, name: {s}\n", .{node.name});
            },
            c.XML_DTD_NODE => {
                try std.fmt.format(stdout.writer(), "node type: DTD, name: {s}\n", .{node.name});
            },
            c.XML_ELEMENT_DECL => {
                try std.fmt.format(stdout.writer(), "node type: Element Decl, name: {s}\n", .{node.name});
            },
            c.XML_ATTRIBUTE_DECL => {
                try std.fmt.format(stdout.writer(), "node type: Attribute Decl, name: {s}\n", .{node.name});
            },
            c.XML_ENTITY_DECL => {
                try std.fmt.format(stdout.writer(), "node type: Entity Decl, name: {s}\n", .{node.name});
            },
            c.XML_NAMESPACE_DECL => {
                try std.fmt.format(stdout.writer(), "node type: Namespace Decl, name: {s}\n", .{node.name});
            },
            c.XML_XINCLUDE_START => {
                try std.fmt.format(stdout.writer(), "node type: XInclude Start, name: {s}\n", .{node.name});
            },
            c.XML_XINCLUDE_END => {
                try std.fmt.format(stdout.writer(), "node type: XInclude End, name: {s}\n", .{node.name});
            },
            else => {
                try std.fmt.format(stdout.writer(), "Unknown node type, name: {s}\n", .{node.name});
            },
        }
        try print_element_names(stdout, doc, node.children, depth + 1);
    }
}

pub fn readXml(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    // const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    // const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    // const dir = try std.fs.openDirAbsolute(dirpath, .{});
    // const file = try dir.openFile(filepath, .{});
    _ = alloc;

    // c.LIBXML_TEST_VERSION;

    var xml_doc = c.xmlReadFile(args[2].ptr, null, 0);
    defer {
        c.xmlFreeDoc(xml_doc);
        c.xmlCleanupParser();
    }
    if (xml_doc == null) {
        try std.fmt.format(stdout.writer(), "error: could not parse file {s}\n", .{args[2]});
    }

    var root_element = c.xmlDocGetRootElement(xml_doc);
    try print_element_names(stdout, xml_doc, root_element, 0);
}

pub fn readZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &std.io.StreamSource{ .file = file });

    try archive_reader.load();

    for (archive_reader.directory.items) |cd_record, i| {
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

    for (classes.string_ids) |id, i| {
        const str = try classes.getString(id);
        try std.fmt.format(stdout.writer(), "String {}: {s}\n", .{ i, str.data });
    }

    for (classes.type_ids) |id, i| {
        const str = try classes.getTypeString(id);
        try std.fmt.format(stdout.writer(), "Type Descriptor {}: {s}\n", .{ i, str.data });
    }

    for (classes.proto_ids) |id, i| {
        const prototype = try classes.getPrototype(id, alloc);
        try std.fmt.format(stdout.writer(), "Prototype {}; shorty {s}; (", .{ i, prototype.shorty.data });
        if (prototype.parameters) |parameters| {
            for (try classes.getTypeStringList(parameters, alloc)) |type_string| {
                try std.fmt.format(stdout.writer(), "{s}", .{type_string.data});
            }
        }
        try std.fmt.format(stdout.writer(), "){s}\n", .{prototype.return_type.data});
    }

    for (classes.field_ids) |id, i| {
        const class_str = try classes.getString(classes.string_ids[classes.type_ids[id.class_idx].descriptor_idx]);
        const type_str = try classes.getString(classes.string_ids[classes.type_ids[id.type_idx].descriptor_idx]);
        const name_str = try classes.getString(classes.string_ids[id.name_idx]);
        try std.fmt.format(stdout.writer(), "Field {}, {s}.{s}: {s}", .{ i, class_str.data, name_str.data, type_str.data });
    }

    for (classes.method_ids) |id, i| {
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
    var indent: usize = 0;

    for (document.xml_trees) |xml_tree| {
        for (xml_tree.nodes) |node, node_id| {
            if (node.extended == .Attribute) {
                indent += 1;
            }
            var iloop: usize = 1;
            while (iloop < indent) : (iloop += 1) {
                try std.fmt.format(stdout, "\t", .{});
            }
            switch (node.extended) {
                .CData => |cdata| {
                    const data = xml_tree.string_pool.getUtf16(cdata.data) orelse &[_]u16{};

                    try std.fmt.format(stdout.writer(), "{}", .{
                        std.unicode.fmtUtf16le(data),
                    });
                },
                .Namespace => |namespace| {
                    if (node.header.type == .XmlStartNamespace) {
                        const prefix = xml_tree.string_pool.getUtf16(namespace.prefix) orelse &[_]u16{};
                        const uri = xml_tree.string_pool.getUtf16(namespace.uri) orelse &[_]u16{};

                        try std.fmt.format(stdout.writer(), "xmlns:{}={}", .{
                            std.unicode.fmtUtf16le(prefix),
                            std.unicode.fmtUtf16le(uri),
                        });
                    }
                },
                .EndElement => |end| {
                    const name = xml_tree.string_pool.getUtf16(end.name) orelse &[_]u16{};
                    try std.fmt.format(stdout.writer(), "</{}>", .{std.unicode.fmtUtf16le(name)});
                },
                .Attribute => |attribute| {
                    try std.fmt.format(stdout.writer(), "<", .{});
                    {
                        if (xml_tree.string_pool.getUtf16(attribute.namespace)) |ns| {
                            try std.fmt.format(stdout.writer(), "{}:", .{std.unicode.fmtUtf16le(ns)});
                        }
                        if (xml_tree.string_pool.getUtf16(attribute.name)) |name| {
                            try std.fmt.format(stdout.writer(), "{}", .{std.unicode.fmtUtf16le(name)});
                        }
                    }
                    for (xml_tree.attributes) |*attr| {
                        if (attr.*.node != node_id) continue;
                        try std.fmt.format(stdout, "\n", .{});
                        var iloop2: usize = 1;
                        while (iloop2 < indent + 1) : (iloop2 += 1) {
                            try std.fmt.format(stdout, "\t", .{});
                        }
                        if (xml_tree.string_pool.getUtf16(attr.*.namespace)) |ns| {
                            try std.fmt.format(stdout.writer(), "{}/", .{std.unicode.fmtUtf16le(ns)});
                        }
                        if (xml_tree.string_pool.getUtf16(attr.*.name)) |name| {
                            try std.fmt.format(stdout.writer(), "{}", .{std.unicode.fmtUtf16le(name)});
                        }
                        if (xml_tree.string_pool.getUtf16(attr.*.raw_value)) |raw| {
                            try std.fmt.format(stdout.writer(), "={}", .{std.unicode.fmtUtf16le(raw)});
                        } else {
                            attr.*.typed_value.string_pool = &xml_tree.string_pool;
                            try std.fmt.format(stdout.writer(), "={s}", .{
                                attr.*.typed_value,
                                // @tagName(attr.typed_value.datatype),
                            });
                        }
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

    for (document.tables) |table| {
        for (table.packages) |package| {
            try std.fmt.format(stdout.writer(), "Package {} (ID {})\n", .{ std.unicode.fmtUtf16le(package.name), package.id });
            try std.fmt.format(stdout.writer(), "\tType Strings {}\n\tLast Public Type {}\n\tKey Strings {}\n\tLast Public Key {}\n\tType ID Offset {}\n", .{
                package.type_strings,
                package.last_public_type,
                package.key_strings,
                package.last_public_key,
                package.type_id_offset,
            });
            for (package.type_spec) |type_spec| {
                try std.fmt.format(stdout.writer(), "\tType Spec {}\n", .{type_spec.id});
                for (type_spec.entry_indices) |*entry| {
                    try std.fmt.format(stdout.writer(), "\t\t{}\n", .{entry.*});
                }
            }
            for (package.table_type) |table_type| {
                try std.fmt.format(stdout.writer(), "\tTable Type {}, {}\n", .{ table_type.id, table_type.flags });
                // try std.fmt.format(stdout.writer(), "\t\tConfig: {}\n", .{table_type.config});
                for (table_type.entries) |*entry| {
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
}
