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

    const TokenizeState = enum {
        Whitespace,
        Comment,
        String,
        Literal,
        Reference,
        Label,
        Instruction,
        Register,
    };

    const Tag = enum {
        String,
        Literal,
        Reference,
        Label,
        Instruction,
        Register,
    };

    var labels = std.StringHashMap(usize).init(alloc);
    _ = labels;
    var tokenize_state: TokenizeState = .Whitespace;
    var token_indices = try std.ArrayListUnmanaged(u32).initCapacity(alloc, std.math.maxInt(u16));
    var token_tags = try std.ArrayListUnmanaged(Tag).initCapacity(alloc, std.math.maxInt(u16));
    var token_start: u32 = 0;
    var comment_level: u8 = 0;

    for (file_map, 0..) |byte, index| {
        const last_state = tokenize_state;
        switch (tokenize_state) {
            .Whitespace => {
                switch (byte) {
                    ' ', '\n', '\t' => continue,
                    '"' => tokenize_state = .String,
                    '(' => tokenize_state = .Comment,
                    '#' => tokenize_state = .Literal,
                    '@' => tokenize_state = .Label,
                    '.' => tokenize_state = .Reference,
                    '$' => tokenize_state = .Register,
                    else => tokenize_state = .Instruction,
                }
            },
            .Literal, .Reference, .Label, .Instruction, .Register => {
                switch (byte) {
                    ' ', '\n', '\t' => tokenize_state = .Whitespace,
                    ';' => tokenize_state = .Comment,
                    else => continue,
                }
            },
            .String => {
                switch (byte) {
                    '"' => tokenize_state = .Whitespace,
                    else => continue,
                }
            },
            .Comment => { // Supports nesting up to 256 levels
                switch (byte) {
                    '(' => comment_level += 1,
                    ')' => {
                        if (comment_level == 0) {
                            tokenize_state = .Whitespace;
                        } else {
                            comment_level -= 1;
                        }
                    },
                    else => continue,
                }
            },
        }

        if (tokenize_state != last_state) {
            switch (last_state) {
                .Whitespace, .Comment => {}, // ignore
                .String => {
                    token_indices.appendAssumeCapacity(token_start + 1);
                    token_tags.appendAssumeCapacity(.String);
                },
                .Literal => {
                    token_indices.appendAssumeCapacity(token_start);
                    token_tags.appendAssumeCapacity(.Literal);
                },
                .Reference => {
                    token_indices.appendAssumeCapacity(token_start);
                    token_tags.appendAssumeCapacity(.Reference);
                },
                .Label => {
                    token_indices.appendAssumeCapacity(token_start + 1);
                    token_tags.appendAssumeCapacity(.Label);
                },
                .Instruction => {
                    token_indices.appendAssumeCapacity(token_start);
                    token_tags.appendAssumeCapacity(.Instruction);
                },
                .Register => {
                    token_indices.appendAssumeCapacity(token_start);
                    token_tags.appendAssumeCapacity(.Register);
                },
            }
            token_start = @intCast(index);
        }
    }

    for (token_indices.items, token_tags.items) |index, tag| {
        var end = index + 1;
        var char: u8 = file_map[end];
        while (true) : (char = file_map[end]) {
            const is_whitespace = char == ' ' or char == '\n' or char == '\t';
            const is_end_string = char == '"';
            const is_end_label = char == ':';
            if (tag == .String) {
                if (is_end_string) break;
            } else if (tag == .Label) {
                if (is_end_label or is_whitespace) break;
            } else if (is_whitespace) {
                break;
            }
            end += 1;
        }
        const string = file_map[index..end];
        try stdout.writer().print("{s}\t{s}\n", .{ @tagName(tag), string });
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

const std = @import("std");
const dex = @import("dex.zig");
