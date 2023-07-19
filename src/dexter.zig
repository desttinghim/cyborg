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

    const infile_arg: ParsedName = try parse_file_name(args[1], "dexasm"); // verify our input file's extension is dexasm
    var outfile_arg_opt: ?ParsedName = null;

    if (args.len == 2) {
        // Automatically name the output based on the input when no output file name is given
        outfile_arg_opt = .{ .name = infile_arg.name, .extension = "dex" };
    } else if (args.len == 3) {
        // Parse output filename if given
        outfile_arg_opt = try parse_file_name(args[2], "dex");
    }

    if (outfile_arg_opt == null) @panic("Output filename is somehow missing - this is a bug with dexter, and should never happen");

    try assemble(infile_arg, outfile_arg_opt.?);
}

const ParsedName = struct {
    name: []const u8,
    extension: []const u8,
};

fn parse_file_name(infile_name: []const u8, expected_extension: []const u8) !ParsedName {
    var tokens = std.mem.tokenizeScalar(u8, infile_name, '.');
    const name = tokens.next() orelse return error.MissingExtension;
    const extension = tokens.next() orelse return error.MissingExtension;

    if (!std.mem.eql(u8, expected_extension, extension)) {
        return error.InvalidExtension;
    }

    return .{
        .name = name,
        .extension = extension,
    };
}

pub fn assemble(infile_arg: ParsedName, outfile_arg: ParsedName) !void {
    std.debug.print("assembling input {s}.{s} to output {s}.{s}\n", .{ infile_arg.name, infile_arg.extension, outfile_arg.name, outfile_arg.extension });
}
