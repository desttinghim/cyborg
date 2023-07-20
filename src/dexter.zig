const std = @import("std");

pub fn main() !void {
    // Setup necessary global state
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer {
        const check = gpa.deinit();
        _ = check;
    }
    const gpa_alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    defer {
        arena.deinit();
    }

    const stdout = std.io.getStdOut();
    _ = stdout;

    // Parse the arguments
    const args = try std.process.argsAlloc(alloc);

    if (args.len < 2) {
        // Assert we have at least one file
        return error.MissingFileArgument;
    }

    const infile_arg: ParsedName = try parse_file_name(args[1], ".dexasm"); // verify our input file's extension is dexasm
    var outfile_arg_opt: ?ParsedName = null;

    if (args.len == 2) {
        // Automatically name the output based on the input when no output file name is given
        const basename = try std.fmt.allocPrint(alloc, "{s}.dex", .{infile_arg.name});
        outfile_arg_opt = try parse_file_name(basename, ".dex");
    } else if (args.len == 3) {
        // Parse output filename if given
        outfile_arg_opt = try parse_file_name(args[2], ".dex");
    }

    if (outfile_arg_opt == null) @panic("Output filename is somehow missing - this is a bug with dexter, and should never happen");

    const outfile_arg = outfile_arg_opt.?;

    std.debug.print("assembling input {s}{s} to output {s}{s}\n", .{ infile_arg.name, infile_arg.extension, outfile_arg.name, outfile_arg.extension });

    const filepath = try std.fs.realpathAlloc(alloc, args[1]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});
    defer file.close();

    const file_map = try std.os.mmap(null, try file.getEndPos(), std.os.PROT.WRITE, std.os.MAP.PRIVATE, file.handle, 0);
    defer std.os.munmap(file_map);

    var line_iter = std.mem.tokenizeSequence(u8, file_map, "\n");
    var instructions = try std.ArrayListUnmanaged(u16).initCapacity(alloc, std.math.maxInt(u8));

    while (line_iter.next()) |line| {
        std.debug.print("{s}\n", .{line});
        var tok_iter = std.mem.tokenizeSequence(u8, line, " ");
        var token = tok_iter.next() orelse continue;
        if (std.mem.eql(u8, ";", token)) continue;
        if (std.mem.eql(u8, "nop", token)) instructions.appendAssumeCapacity(0x0010);
    }

    for (instructions.items, 0..) |instruction, i| {
        std.debug.print("{x:0>4}\t{x:0>4}\n", .{ i, instruction });
    }
}

const ParsedName = struct {
    full: []const u8,
    path: []const u8,
    basename: []const u8,
    name: []const u8,
    extension: []const u8,
};

fn parse_file_name(infile_path: []const u8, expected_extension: []const u8) !ParsedName {
    const path = std.fs.path.dirname(infile_path) orelse "";
    const name = std.fs.path.stem(infile_path);
    const basename = std.fs.path.basename(infile_path);
    const extension = std.fs.path.extension(infile_path);

    if (!std.mem.eql(u8, expected_extension, extension)) {
        std.debug.print("Invalid extension: {s}\n", .{extension});
        return error.InvalidExtension;
    }

    return .{
        .full = infile_path,
        .path = path,
        .basename = basename,
        .name = name,
        .extension = extension,
    };
}
