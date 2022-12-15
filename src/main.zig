const std = @import("std");
const testing = std.testing;
const archive = @import("archive");

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
    // \\  pkg <manifest> <out>        Creates an APK from a manifest.json
    \\
;

const Subcommand = enum {
    zip,
    xml,
    apk,
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
        .xml => try readXml(alloc, args, stdout),
        .apk => try readApk(alloc, args, stdout),
        // .pkg => try writePackage(alloc, args, stdout),
    }
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

pub fn readXml(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
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

    const manifest_header = archive_reader.findFile("AndroidManifest.xml") orelse return error.MissingManifest;

    const manifest_string = try archive_reader.extractFileString(manifest_header, alloc, true);
    defer alloc.free(manifest_string);

    var stream = std.io.FixedBufferStream([]const u8){ .pos = 0, .buffer = manifest_string };
    var document = try binxml.Document.readAlloc(stream.seekableStream(), stream.reader(), alloc);

    try printInfo(document, stdout);
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
                    for (xml_tree.attributes) |attr| {
                        if (attr.node != node_id) continue;
                        try std.fmt.format(stdout, "\n", .{});
                        var iloop2: usize = 1;
                        while (iloop2 < indent + 1) : (iloop2 += 1) {
                            try std.fmt.format(stdout, "\t", .{});
                        }
                        if (xml_tree.string_pool.getUtf16(attr.namespace)) |ns| {
                            try std.fmt.format(stdout.writer(), "{}/", .{std.unicode.fmtUtf16le(ns)});
                        }
                        if (xml_tree.string_pool.getUtf16(attr.name)) |name| {
                            try std.fmt.format(stdout.writer(), "{}", .{std.unicode.fmtUtf16le(name)});
                        }
                        if (xml_tree.string_pool.getUtf16(attr.raw_value)) |raw| {
                            try std.fmt.format(stdout.writer(), "={}", .{std.unicode.fmtUtf16le(raw)});
                        } else {
                            try std.fmt.format(stdout.writer(), "={s}", .{
                                @tagName(attr.typed_value.datatype),
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
                    if (package.key_string_pool.getUtf16(entry.key)) |entry_string| {
                        try std.fmt.format(stdout.writer(), "\t\t{}: {?}\n", .{ std.unicode.fmtUtf16le(entry_string), entry.value });
                    }
                }
            }
        }
    }
}
