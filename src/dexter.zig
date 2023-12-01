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

    const outfile_arg = outfile_arg_opt orelse @panic("Output filename is somehow missing - this is a bug with dexter, and should never happen");

    std.debug.print("assembling input {s}{s} to output {s}{s}\n", .{ infile_arg.name, infile_arg.extension, outfile_arg.name, outfile_arg.extension });

    const filepath = try std.fs.realpathAlloc(alloc, args[1]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});
    defer file.close();

    const file_map = try std.os.mmap(null, try file.getEndPos(), std.os.PROT.WRITE, std.os.MAP.PRIVATE, file.handle, 0);
    defer std.os.munmap(file_map);

    const tokens = try tokenize(alloc, file_map);
    try stdout.writer().print("Token count: {}\nTag count: {}\n", .{
        tokens.indices.items.len,
        tokens.tags.items.len,
    });

    for (tokens.indices.items, tokens.tags.items) |index, tag| {
        try stdout.writer().print("{}: {}\n", .{
            index,
            tag,
        });
    }

    const module = try parseTokens(alloc, file_map, tokens);
    for (module.classes.items) |class| {
        if (class.extends) |extends| {
            try stdout.writer().print("\nclass {s} extends {s}\n", .{ class.name, extends });
        } else {
            try stdout.writer().print("\nclass {s}\n", .{class.name});
        }

        for (class.fields.items) |field| {
            try stdout.writer().print("\t{} {} {s}\n", .{ field.access_flags, field.type, field.name });
        }

        for (class.methods.items) |method| {
            try stdout.writer().print("\t{} {} {s}\n", .{ method.access_flags, method.return_type, method.name });
        }
    }

    // Lower to dex file
    // dex.Dex.createFromModule(alloc, )
    try stdout.writer().print("\nPrinting Strings:\n", .{});
    var string_iter = module.getStringIterator();
    while (string_iter.next()) |string| {
        try stdout.writer().print("{s}\n", .{string.*});
    }

    try stdout.writer().print("\nPrinting Types:\n", .{});
    var type_iter = module.getTypeIterator();
    while (type_iter.next()) |t| {
        try stdout.writer().print("{s}\n", .{t.*});
    }
}

const Tokens = struct {
    indices: std.ArrayListUnmanaged(u32),
    tags: std.ArrayListUnmanaged(Tag),
    const Tag = enum {
        String,
        Literal,
        Directive,
        Label,
        Instruction,
        Register,
    };
};
pub fn tokenize(alloc: std.mem.Allocator, file_map: []const u8) !Tokens {
    const TokenizeState = enum {
        Whitespace,
        Comment,
        String,
        Literal,
        Directive,
        Label,
        Instruction,
        Register,
    };

    var labels = std.StringHashMap(usize).init(alloc);
    _ = labels;
    var tokenize_state: TokenizeState = .Whitespace;
    var token_indices = try std.ArrayListUnmanaged(u32).initCapacity(alloc, std.math.maxInt(u16));
    var token_tags = try std.ArrayListUnmanaged(Tokens.Tag).initCapacity(alloc, std.math.maxInt(u16));
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
                    '.' => tokenize_state = .Directive,
                    'v' => tokenize_state = .Register,
                    else => tokenize_state = .Instruction,
                }
            },
            .Literal, .Directive, .Label, .Instruction, .Register => {
                if (index >= file_map.len - 1) tokenize_state = .Whitespace;
                switch (byte) {
                    ' ', '\n', '\t' => tokenize_state = .Whitespace,
                    ';' => tokenize_state = .Whitespace,
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
                .Directive => {
                    token_indices.appendAssumeCapacity(token_start);
                    token_tags.appendAssumeCapacity(.Directive);
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
    return .{
        .indices = token_indices,
        .tags = token_tags,
    };
}

pub fn parseTokens(alloc: std.mem.Allocator, file_map: []const u8, tokens: Tokens) !dalvik.Module {
    // # Parsing
    // Takes the token list and tries to construct a dex file from them.
    // This is the code that will ensure type checking and construct a string pool
    const Directive = enum {
        class,
        extends,
        field,
        method,
    };

    const ParseState = union(enum) {
        top,
        class,
        extends,
        field: struct { dex.AccessFlags, ?dalvik.Module.TypeValue },
        method: struct { dex.AccessFlags, std.ArrayListUnmanaged(dalvik.Module.TypeValue) },
        instruction: u32,
    };

    var state: ParseState = .top;
    var module = dalvik.Module.init(alloc);
    var current_class: ?*dalvik.Module.Class = null;
    var current_class_t: ?dalvik.Module.TypeValue = null;
    var current_method: ?*dalvik.Module.Method = null;
    var current_instruction: ?*dalvik.Module.Instruction = null;

    for (tokens.indices.items, tokens.tags.items) |index, tag| {
        var end = index + 1;
        var char: u8 = file_map[end];
        while (true) : (char = file_map[end]) {
            const is_whitespace = char == ' ' or char == '\n' or char == '\t';
            const is_end_string = char == '"';
            const is_end_label = char == ':';
            const is_eof = end == file_map.len - 1;
            if (tag == .String) {
                if (is_end_string) break;
            } else if (tag == .Label) {
                if (is_end_label or is_whitespace) break;
            } else if (is_whitespace) {
                break;
            } else if (is_eof) {
                break;
            }
            end += 1;
        }
        const string = file_map[index..end];
        switch (state) {
            .top => {
                switch (tag) {
                    .Instruction => unknown: {
                        const which = std.meta.stringToEnum(dalvik.Module.Instruction.Tag, string) orelse break :unknown;
                        current_instruction = try current_method.?.code.addOne(alloc);
                        switch (which) {
                            .@"return-void" => {
                                current_instruction.?.* = .@"return-void";
                            },
                            inline else => |instr| {
                                current_instruction.?.* = @unionInit(dalvik.Module.Instruction, @tagName(instr), undefined);
                                state = .{ .instruction = 0 };
                            },
                        }
                    },
                    .Directive => {
                        const which = std.meta.stringToEnum(Directive, string[1..]) orelse return error.UnknownDirective;
                        switch (which) {
                            inline .class,
                            .extends,
                            => |directive_tag| state = @unionInit(ParseState, @tagName(directive_tag), {}),
                            .field => state = .{ .field = .{ .{}, null } },
                            .method => state = .{ .method = .{ .{}, .{} } },
                        }
                    },
                    else => {
                        std.log.info("{s}\t{s}\n", .{ @tagName(tag), string });
                    },
                }
            },
            .class => {
                current_class = try module.classes.addOne(alloc);
                current_class_t = try dalvik.Module.TypeValue.read(string);
                try module.addType(current_class_t.?);
                current_class.?.* = .{
                    .fields = .{},
                    .methods = .{},
                    .access_flags = .{},
                    .name = string,
                };
                state = .top;
            },
            .extends => {
                current_class.?.extends = string;
                state = .top;
            },
            .field => |data| {
                const updated = data[0].addFromString(string) catch {
                    if (data[1]) |t| {
                        const field_struct = try current_class.?.fields.addOne(alloc);
                        field_struct.access_flags = data[0];
                        field_struct.type = t;
                        field_struct.name = string;
                        try module.addField(current_class_t.?, field_struct);
                        state = .top;
                    } else {
                        const t = try dalvik.Module.TypeValue.read(string);
                        state = .{ .field = .{ data[0], t } };
                    }
                    continue;
                };
                state = .{ .field = .{ updated, data[1] } };
            },
            .method => |*data| {
                if (data.*[0].addFromString(string)) |value| {
                    data.*[0] = value;
                } else |_| {
                    if (dalvik.Module.TypeValue.read(string)) |value| {
                        try data.*[1].append(alloc, value);
                    } else |_| {
                        if (data.*[1].items.len >= 1) {
                            const method = try current_class.?.methods.addOne(alloc);
                            method.name = string;
                            method.access_flags = data.*[0];
                            method.return_type = data.*[1].items[0];
                            method.code = .{};
                            if (data.*[1].items.len >= 2) {
                                const slice = try alloc.dupe(dalvik.Module.TypeValue, data.*[1].items[1..]);
                                method.parameters = std.ArrayListUnmanaged(dalvik.Module.TypeValue).fromOwnedSlice(slice);
                            } else {
                                method.parameters = .{};
                            }
                            try method.calculateShorty(&module);
                            current_method = method;
                            try module.addMethod(current_class_t.?, method);
                            state = .top;
                            data.*[1].deinit(alloc);
                        } else {
                            return error.MissingReturnType;
                        }
                    }
                }
            },
            .instruction => |*token_count| {
                switch (current_instruction.?.*) {
                    .@"return-void" => {
                        unreachable;
                    },
                    .@"return-object" => |*value| {
                        std.debug.assert(string[0] == 'v');
                        value.* = try std.fmt.parseInt(u16, string[1..], 10);
                        state = .top;
                    },
                    .@"move-result-object" => |*value| {
                        std.debug.assert(string[0] == 'v');
                        value.* = try std.fmt.parseInt(u16, string[1..], 10);
                        state = .top;
                    },
                    .@"iput-wide" => |*value| {
                        token_count.* += 1;
                        switch (token_count.*) {
                            1 => {
                                std.debug.assert(string[0] == 'v');
                                value.*.a = try std.fmt.parseInt(u16, string[1..], 10);
                            },
                            2 => {
                                std.debug.assert(string[0] == 'v');
                                value.*.b = try std.fmt.parseInt(u16, string[1..], 10);
                            },
                            3 => {
                                const t = try dalvik.Module.TypeValue.read(string);
                                value.*.class = t;
                            },
                            4 => {
                                value.*.field = string;
                                state = .top;
                            },
                            else => unreachable,
                        }
                    },
                    .@"invoke-direct" => |*value| {
                        token_count.* += 1;
                        switch (token_count.*) {
                            1 => {
                                value.*.argument_count = try std.fmt.parseInt(u4, string, 10);
                            },
                            2 => {
                                const t = try dalvik.Module.TypeValue.read(string);
                                value.*.class = t;
                            },
                            3 => {
                                value.*.method = string;
                            },
                            4...7 => {
                                // std.log.info("{s}", .{string});
                                std.debug.assert(string[0] == 'v');
                                value.*.registers[token_count.* - 3] = try std.fmt.parseInt(u4, string[1..], 10);
                                if (token_count.* == 7) state = .top;
                            },
                            else => unreachable,
                        }
                    },
                }
            },
        } // switch (state)
    } // for (token_indices.items, token_tags.items)

    return module;
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

test "NativeInvocationHandler" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const file = @embedFile("./NativeInvocationHandler.dexasm");
    const tokens = try tokenize(arena.allocator(), file);
    const module = try parseTokens(arena.allocator(), file, tokens);

    try std.testing.expectEqual(@as(usize, 1), module.classes.items.len);
    const class = module.classes.items[0];
    try std.testing.expectEqual(dex.AccessFlags{}, class.access_flags);
    try std.testing.expectEqualStrings("NativeInvocationHandler", class.name);
    try std.testing.expectEqualStrings("java.lang.Object", class.extends.?);

    try std.testing.expectEqual(@as(usize, 1), class.fields.items.len);
    const field = class.fields.items[0];
    try std.testing.expectEqual(dex.AccessFlags{ .Private = true }, field.access_flags);
    try std.testing.expectEqual(dalvik.Module.TypeValue{ .t = .long }, field.type);
    try std.testing.expectEqualStrings("ptr", field.name);

    try std.testing.expectEqual(@as(usize, 3), class.methods.items.len);
    const methods = class.methods.items;
    try std.testing.expectEqual(dex.AccessFlags{
        .Public = true,
        .Constructor = true,
    }, methods[0].access_flags);
    try std.testing.expectEqual(dalvik.Module.TypeValue{ .t = .void }, methods[0].return_type);
    try std.testing.expectEqualSlices(
        dalvik.Module.TypeValue,
        &[_]dalvik.Module.TypeValue{.{ .t = .long }},
        methods[0].parameters.items,
    );
    try std.testing.expectEqualStrings("<init>", methods[0].name);
}

const std = @import("std");
const dex = @import("dex.zig");
const dalvik = @import("dalvik.zig");
