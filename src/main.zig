const std = @import("std");
const testing = std.testing;

pub const dex = @import("dex.zig");
pub const zip = @import("zip.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const alloc = gpa.allocator();
    const args = try std.process.argsAlloc(alloc);
    const stdout = std.io.getStdOut().writer();
    if (args.len < 2) {
        try std.fmt.format(stdout, "USAGE:\nzandroid FILE.zip\n", .{});
        return;
    }

    const filepath = try std.fs.realpathAlloc(alloc, args[1]);
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
        try std.fmt.format(stdout, "{s:10}{:>10.2}{:>10.2}{:>5} {s}\t{s}\n", .{
            @tagName(file_record.compression),
            std.fmt.fmtIntSizeBin(file_record.compressed_size),
            std.fmt.fmtIntSizeBin(file_record.uncompressed_size),
            file_record.extra_field_length,
            file_record.filename.?,
            file_record.file_comment.?,
        });
    }
}
