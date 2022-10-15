const std = @import("std");
const testing = std.testing;

pub const dex = @import("dex.zig");
pub const ZIP = @import("zip.zig").ZIP;
pub const binxml = @import("binxml.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const usage =
    \\USAGE: zandroid <subcommand>
    \\SUBCOMMANDS:
    \\  zip <file>      Reads a zip file
    \\  xml <file>      Reads an Android binary XML file
    \\
;

const Subcommand = enum {
    zip,
    xml,
};

pub fn main() !void {
    const alloc = gpa.allocator();
    const args = try std.process.argsAlloc(alloc);
    const stdout = std.io.getStdOut();

    errdefer {
        _ = stdout.write(usage) catch 0;
    }

    if (args.len < 2) {
        return error.MissingSubcommand;
    }

    const cmd = std.meta.stringToEnum(Subcommand, args[1]) orelse return error.InvalidSubcommand;

    switch (cmd) {
        .zip => try readZip(alloc, args, stdout),
        .xml => try readXml(alloc, args, stdout),
    }
}

pub fn readZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var zip = try ZIP.initFromFile(alloc, file);

    if (args.len >= 4) {
        const decompress_file = args[3];
        if (zip.getFileRecord(decompress_file)) |descriptor| {
            try std.fmt.format(stdout.writer(), "{s:10}{:>10.2}{:>10.2}{:>5} {s}\t{s}\n", .{
                @tagName(descriptor.compression),
                std.fmt.fmtIntSizeBin(descriptor.compressed_size),
                std.fmt.fmtIntSizeBin(descriptor.uncompressed_size),
                descriptor.extra_field_length,
                descriptor.filename,
                descriptor.file_comment,
            });
            if (try zip.getFileAlloc(alloc, decompress_file)) |decompressed| {
                try std.fmt.format(stdout.writer(), "{s}", .{decompressed});
            }
        }
    } else {
        for (zip.directory_headers) |file_record| {
            try std.fmt.format(stdout.writer(), "{s:10}{:>10.2}{:>10.2}{:>5} {s}\t{s}\n", .{
                @tagName(file_record.compression),
                std.fmt.fmtIntSizeBin(file_record.compressed_size),
                std.fmt.fmtIntSizeBin(file_record.uncompressed_size),
                file_record.extra_field_length,
                file_record.filename,
                file_record.file_comment,
            });
        }
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

    var document = try binxml.Document.readAlloc(file, arena_alloc);

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
}
