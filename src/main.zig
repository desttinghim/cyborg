const std = @import("std");
const testing = std.testing;

pub const dex = @import("dex.zig");
pub const zip = @import("zip.zig");
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

    var end_record = try zip.findEndRecord(file);

    const records = try alloc.alloc(zip.CentralDirectoryFileHeader, end_record.record_count);
    var zip_dir = try end_record.readDirectory(file, records);

    var sum: usize = 0;
    for (zip_dir.directory_headers) |file_record| {
        sum += file_record.getVariableSize();
    }

    const buffer = try alloc.alloc(u8, sum);
    defer alloc.free(buffer);

    var remaining = buffer;

    for (zip_dir.directory_headers) |*file_record| {
        remaining = remaining[try file_record.readName(file, remaining)..];
        remaining = remaining[try file_record.readExtra(file, remaining)..];
        remaining = remaining[try file_record.readComment(file, remaining)..];
        try std.fmt.format(stdout.writer(), "{s:10}{:>10.2}{:>10.2}{:>5} {s}\t{s}\n", .{
            @tagName(file_record.compression),
            std.fmt.fmtIntSizeBin(file_record.compressed_size),
            std.fmt.fmtIntSizeBin(file_record.uncompressed_size),
            file_record.extra_field_length,
            file_record.filename.?,
            file_record.file_comment.?,
        });
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

    var document = try binxml.readAlloc(file, arena_alloc);

    var indent: usize = 0;

    for (document.resource_nodes) |node| {
        var iloop: usize = 0;
        while (iloop < indent) : (iloop += 1) {
            try std.fmt.format(stdout, "\t", .{});
        }
        // try std.fmt.format(stdout.writer(), "{s}\n\t", .{
        //     @tagName(node.header.type),
        // });
        switch (node.extended) {
            .CData => |cdata| {
                const data = try document.string_pool.getAlloc(arena_alloc, file, cdata.data) orelse &[_]u16{ 'E', 'N', 'D' };

                try std.fmt.format(stdout.writer(), "{}", .{
                    std.unicode.fmtUtf16le(data),
                });
            },
            .Namespace => |namespace| {
                if (node.header.type == .XmlEndNamespace) {
                    indent -= 1;
                } else {
                    indent += 1;
                    const prefix = try document.string_pool.getAlloc(arena_alloc, file, namespace.prefix) orelse &[_]u16{ 'E', 'N', 'D' };
                    const uri = try document.string_pool.getAlloc(arena_alloc, file, namespace.uri) orelse &[_]u16{ 'E', 'N', 'D' };

                    try std.fmt.format(stdout.writer(), "xmlns:{}={}", .{
                        std.unicode.fmtUtf16le(prefix),
                        std.unicode.fmtUtf16le(uri),
                    });
                }
            },
            .EndElement => |end| {
                // if (try document.string_pool.getAlloc(arena_alloc, file, end.namespace)) |ns| {
                //     try std.fmt.format(stdout.writer(), "{}:", .{std.unicode.fmtUtf16le(ns)});
                // }
                // if (try document.string_pool.getAlloc(arena_alloc, file, end.name)) |name| {
                //     try std.fmt.format(stdout.writer(), "{}", .{std.unicode.fmtUtf16le(name)});
                // }
                _ = end;
                indent -= 1;
            },
            .Attribute => |attribute| {
                {
                    if (try document.string_pool.getAlloc(arena_alloc, file, attribute.namespace)) |ns| {
                        try std.fmt.format(stdout.writer(), "{}:", .{std.unicode.fmtUtf16le(ns)});
                    }
                    if (try document.string_pool.getAlloc(arena_alloc, file, attribute.name)) |name| {
                        try std.fmt.format(stdout.writer(), "{}", .{std.unicode.fmtUtf16le(name)});
                    }
                }
                if (attribute.list) |list| {
                    for (list) |attr| {
                        try std.fmt.format(stdout, "\n", .{});
                        var iloop2: usize = 0;
                        while (iloop2 < indent + 1) : (iloop2 += 1) {
                            try std.fmt.format(stdout, "\t", .{});
                        }
                        // if (try document.string_pool.getAlloc(arena_alloc, file, attr.namespace)) |ns| {
                        //     try std.fmt.format(stdout.writer(), "\n\t{}/", .{std.unicode.fmtUtf16le(ns)});
                        // }
                        if (try document.string_pool.getAlloc(arena_alloc, file, attr.name)) |name| {
                            try std.fmt.format(stdout.writer(), "{}", .{std.unicode.fmtUtf16le(name)});
                        }
                        if (try document.string_pool.getAlloc(arena_alloc, file, attr.raw_value)) |raw| {
                            try std.fmt.format(stdout.writer(), "={}", .{std.unicode.fmtUtf16le(raw)});
                        } else {
                            try std.fmt.format(stdout.writer(), "={s}", .{
                                @tagName(attr.typed_value.datatype),
                            });
                        }
                    }
                }
                indent += 1;
            },
        }
        try std.fmt.format(stdout.writer(), "\n", .{});
    }
}
