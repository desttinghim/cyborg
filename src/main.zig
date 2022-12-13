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
    // \\  pkg <manifest> <out>        Creates an APK from a manifest.json
    \\
;

const Subcommand = enum {
    zip,
    xml,
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

    var document = if (std.mem.endsWith(u8, filepath, "arsc"))
        try binxml.Document.readResAlloc(file, arena_alloc)
    else
        try binxml.Document.readXMLAlloc(file, arena_alloc);

    var indent: usize = 0;

    for (document.resource_nodes) |node, node_id| {
        if (node.extended == .Attribute) {
            indent += 1;
        }
        var iloop: usize = 1;
        while (iloop < indent) : (iloop += 1) {
            try std.fmt.format(stdout, "\t", .{});
        }
        switch (node.extended) {
            .CData => |cdata| {
                const data = document.getString(cdata.data) orelse &[_]u16{};

                try std.fmt.format(stdout.writer(), "{}", .{
                    std.unicode.fmtUtf16le(data),
                });
            },
            .Namespace => |namespace| {
                if (node.header.type == .XmlStartNamespace) {
                    const prefix = document.getString(namespace.prefix) orelse &[_]u16{};
                    const uri = document.getString(namespace.uri) orelse &[_]u16{};

                    try std.fmt.format(stdout.writer(), "xmlns:{}={}", .{
                        std.unicode.fmtUtf16le(prefix),
                        std.unicode.fmtUtf16le(uri),
                    });
                }
            },
            .EndElement => |end| {
                const name = document.getString(end.name) orelse &[_]u16{};
                try std.fmt.format(stdout.writer(), "</{}>", .{std.unicode.fmtUtf16le(name)});
            },
            .Attribute => |attribute| {
                try std.fmt.format(stdout.writer(), "<", .{});
                {
                    if (document.getString(attribute.namespace)) |ns| {
                        try std.fmt.format(stdout.writer(), "{}:", .{std.unicode.fmtUtf16le(ns)});
                    }
                    if (document.getString(attribute.name)) |name| {
                        try std.fmt.format(stdout.writer(), "{}", .{std.unicode.fmtUtf16le(name)});
                    }
                }
                for (document.attributes) |attr| {
                    if (attr.node != node_id) continue;
                    try std.fmt.format(stdout, "\n", .{});
                    var iloop2: usize = 1;
                    while (iloop2 < indent + 1) : (iloop2 += 1) {
                        try std.fmt.format(stdout, "\t", .{});
                    }
                    if (document.getString(attr.value.namespace)) |ns| {
                        try std.fmt.format(stdout.writer(), "{}/", .{std.unicode.fmtUtf16le(ns)});
                    }
                    if (document.getString(attr.value.name)) |name| {
                        try std.fmt.format(stdout.writer(), "{}", .{std.unicode.fmtUtf16le(name)});
                    }
                    if (document.getString(attr.value.raw_value)) |raw| {
                        try std.fmt.format(stdout.writer(), "={}", .{std.unicode.fmtUtf16le(raw)});
                    } else {
                        try std.fmt.format(stdout.writer(), "={s}", .{
                            @tagName(attr.value.typed_value.datatype),
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

    for (document.packages) |package| {
        try std.fmt.format(stdout.writer(), "Package {} (ID {})\n", .{ std.unicode.fmtUtf16le(package.name), package.id });
        try std.fmt.format(stdout.writer(), "\tType Strings {}\n\tLast Public Type {}\n\tKey Strings {}\n\tLast Public Key {}\n\tType ID Offset {}\n", .{
            package.type_strings,
            package.last_public_type,
            package.key_strings,
            package.last_public_key,
            package.type_id_offset,
        });
    }
}

// pub fn writePackage(backing_alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
//     // Create an arena allocator
//     var arena = std.heap.ArenaAllocator.init(backing_alloc);
//     const alloc = arena.allocator();
//     defer arena.deinit();

//     // Open the manifest.json
//     const manifest_data = manifest: {
//         const filepath = try std.fs.realpathAlloc(alloc, args[2]);
//         const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
//         const dir = try std.fs.openDirAbsolute(dirpath, .{});
//         const file = try dir.openFile(filepath, .{});
//         defer file.close();
//         const data = try file.readToEndAlloc(alloc, 4 * 1024 * 1024);
//         break :manifest data;
//     };

//     // Read the manifest and convert it to Android's binary XML format
//     var tokens = std.json.TokenStream.init(manifest_data);
//     const document = std.json.parse(manifest.Document, &tokens, .{ .allocator = alloc }) catch |e| {
//         try std.fmt.format(stdout.writer(), "{s}\n", .{@errorName(e)});
//         return;
//     };
//     defer std.json.parseFree(manifest.Document, document, .{ .allocator = alloc });

//     const bindoc = try binxml.Document.serialize(alloc, document);
//     _ = bindoc;

//     // Create files
//     // var records = std.ArrayList().initCapacity(
//     //     alloc,
//     // );

//     // Create the zip file
//     // const zip = zip: {
//     //     const outpath = try std.fs.realpathAlloc(alloc, args[3]);
//     //     const dirpath = std.fs.path.dirname(outpath) orelse return error.NonexistentDirectory;
//     //     const dir = try std.fs.openDirAbsolute(dirpath, .{});
//     //     break :zip try dir.openFile(outpath, .{});
//     // };

//     // try ZIP.serialize(alloc, document);
// }
