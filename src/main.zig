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

    try std.fmt.format(stdout, "{any}\n", .{end_record});

    var zip_dir = try end_record.parseDirectory(file, try alloc.alloc(zip.CentralDirectoryFileHeader, end_record.record_count));
    for (zip_dir.directory_headers) |d| {
        try std.fmt.format(stdout, "{any}\n", .{d});
    }
}
