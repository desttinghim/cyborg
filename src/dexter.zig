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

    const TokenTag = enum {
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
    var token_tags = try std.ArrayListUnmanaged(TokenTag).initCapacity(alloc, std.math.maxInt(u16));
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
                    '$' => tokenize_state = .Register,
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
        field: struct { dex.AccessFlags, ?Dalvik.TypeValue },
        method: struct { dex.AccessFlags, std.ArrayListUnmanaged(Dalvik.TypeValue) },
        instruction: u32,
    };

    var state: ParseState = .top;
    var module = Dalvik{ .classes = .{} };
    var current_class: ?*Dalvik.Class = null;
    var current_method: ?*Dalvik.Method = null;
    var current_instruction: ?*Dalvik.Instruction = null;

    try stdout.writer().print("Token count: {}\nTag count: {}\n", .{ token_indices.items.len, token_tags.items.len });

    for (token_indices.items, token_tags.items) |index, tag| {
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
        // try stdout.writer().print("{s}\t{s}\n", .{ @tagName(tag), string });
        switch (state) {
            .top => {
                switch (tag) {
                    .Instruction => unknown: {
                        const which = std.meta.stringToEnum(Dalvik.Instruction.Tag, string) orelse break :unknown;
                        // try stdout.writer().print("Instruction is {}\n", .{which});
                        current_instruction = try current_method.?.code.addOne(alloc);
                        switch (which) {
                            .@"return-void" => {
                                current_instruction.?.* = .@"return-void";
                            },
                            inline else => |instr| {
                                current_instruction.?.* = @unionInit(Dalvik.Instruction, @tagName(instr), undefined);
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
                        try stdout.writer().print("{s}\t{s}\n", .{ @tagName(tag), string });
                    },
                }
            },
            .class => {
                current_class = try module.classes.addOne(alloc);
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
                        state = .top;
                    } else {
                        const t = try Dalvik.TypeValue.read(string);
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
                    if (Dalvik.TypeValue.read(string)) |value| {
                        try data.*[1].append(alloc, value);
                    } else |_| {
                        if (data.*[1].items.len >= 1) {
                            const method = try current_class.?.methods.addOne(alloc);
                            method.name = string;
                            method.access_flags = data.*[0];
                            method.return_type = data.*[1].items[0];
                            method.code = .{};
                            if (data.*[1].items.len >= 2) {
                                const slice = try alloc.dupe(Dalvik.TypeValue, data.*[1].items[1..]);
                                method.parameters = std.ArrayListUnmanaged(Dalvik.TypeValue).fromOwnedSlice(slice);
                            } else {
                                method.parameters = .{};
                            }
                            current_method = method;
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
                                value.*.method = string;
                            },
                            3...6 => {
                                // std.log.info("{s}", .{string});
                                std.debug.assert(string[0] == 'v');
                                value.*.registers[token_count.* - 3] = try std.fmt.parseInt(u4, string[1..], 10);
                                if (token_count.* == 6) state = .top;
                            },
                            else => unreachable,
                        }
                    },
                }
            },
        } // switch (state)
    } // for (token_indices.items, token_tags.items)

    try stdout.writer().print("Token parsing complete, parse state:  {}\n", .{state});

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

const Dalvik = struct {
    classes: std.ArrayListUnmanaged(Class),

    const Instruction = union(Tag) {
        // nop,
        // move: struct { Register, Register },
        // @"move-wide": struct { Register, Register },
        // @"move-object": Register,
        // @"move-result": Register,
        // @"move-result-wide": Register,
        @"move-result-object": Register,
        // @"move-exception": Register,
        @"return-void",
        // @"return": Register,
        // @"return-wide": Register,
        @"return-object": Register,
        // @"const": struct { Register, Literal },
        // @"monitor-enter": Register,
        // @"monitor-exit": Register,
        // @"check-cast": struct { Register, Literal },
        // @"instance-of": struct { Register, Register, Literal },
        // @"array-length": struct { Register, Register },
        // @"new-instance": struct { Register, Literal },
        // @"new-array": struct { Register, Register, Literal },
        // @"filled-new-array",
        // @"filled-new-array/range",
        // @"filled-array-data",
        // throw: struct { Register },
        // goto: struct { Literal },
        // @"packed-switch",
        // @"sparse-switch",
        // @"cmpl-float": struct { Register, Register, Register },
        // @"cmpg-float": struct { Register, Register, Register },
        // @"cmpl-double": struct { Register, Register, Register },
        // @"cmpg-double": struct { Register, Register, Register },
        // @"cmp-long": struct { Register, Register, Register },
        // @"if-eq": struct { Register, Register, Literal },
        // @"if-ne": struct { Register, Register, Literal },
        // @"if-lt": struct { Register, Register, Literal },
        // @"if-ge": struct { Register, Register, Literal },
        // @"if-gt": struct { Register, Register, Literal },
        // @"if-le": struct { Register, Register, Literal },
        // @"ifz-eq": struct { Register, Literal },
        // @"ifz-ne": struct { Register, Literal },
        // @"ifz-lt": struct { Register, Literal },
        // @"ifz-ge": struct { Register, Literal },
        // @"ifz-gt": struct { Register, Literal },
        // @"ifz-le": struct { Register, Literal },
        // aget,
        // @"aget-wide",
        // @"aget-object",
        // @"aget-boolean",
        // @"aget-byte",
        // @"aget-char",
        // @"aget-short",
        // aput,
        // @"aput-wide",
        // @"aput-object",
        // @"aput-boolean",
        // @"aput-byte",
        // @"aput-char",
        // @"aput-short",
        // iget: vAvBcCCCC,
        // @"iget-wide": vAvBcCCCC,
        // @"iget-object": vAvBcCCCC,
        // @"iget-boolean": vAvBcCCCC,
        // @"iget-byte": vAvBcCCCC,
        // @"iget-char": vAvBcCCCC,
        // @"iget-short": vAvBcCCCC,
        // iput: vAvBcCCCC,
        @"iput-wide": struct {
            a: Register,
            b: Register,
            field: []const u8,
        },
        // @"iput-object": vAvBcCCCC,
        // @"iput-boolean": vAvBcCCCC,
        // @"iput-byte": vAvBcCCCC,
        // @"iput-char": vAvBcCCCC,
        // @"iput-short": vAvBcCCCC,
        // sget: vAAcBBBB,
        // @"sget-wide": vAAcBBBB,
        // @"sget-object": vAAcBBBB,
        // @"sget-boolean": vAAcBBBB,
        // @"sget-byte": vAAcBBBB,
        // @"sget-char": vAAcBBBB,
        // @"sget-short": vAAcBBBB,
        // sput: vAAcBBBB,
        // @"sput-wide",
        // @"sput-object",
        // @"sput-boolean",
        // @"sput-byte",
        // @"sput-char": vAAcBBBB,
        // @"sput-short",
        // @"invoke-virtual",
        // @"invoke-super",
        @"invoke-direct": struct {
            argument_count: u4,
            method: []const u8,
            registers: [5]u4 = [_]u4{ 0, 0, 0, 0, 0 },
        },
        // @"invoke-static",
        // @"invoke-interface",
        // @"invoke-virtual/range",
        // @"invoke-super/range",
        // @"invoke-direct/range",
        // @"invoke-static/range",
        // @"invoke-interface/range",
        // @"neg-int": vAvB,
        // @"not-int",
        // @"neg-long",
        // @"not-long",
        // @"neg-float",
        // @"neg-double",
        // @"int-to-long",
        // @"int-to-float",
        // @"int-to-double",
        // @"long-to-int",
        // @"long-to-float",
        // @"long-to-double",
        // @"float-to-int",
        // @"float-to-long",
        // @"float-to-double",
        // @"double-to-int",
        // @"double-to-long",
        // @"double-to-float",
        // @"int-to-byte",
        // @"int-to-char",
        // @"int-to-short",
        // @"add-int",
        // @"sub-int": vAAvBBvCC,
        // @"mul-int",
        // @"div-int",
        // @"rem-int": vAAvBBvCC,
        // @"and-int",
        // @"or-int",
        // @"xor-int",
        // @"shl-int",
        // @"shr-int",
        // @"ushr-int",
        // @"add-long",
        // @"sub-long",
        // @"mul-long",
        // @"div-long",
        // @"rem-long",
        // @"and-long",
        // @"or-long",
        // @"xor-long",
        // @"shl-long",
        // @"shr-long",
        // @"ushr-long",
        // @"add-float",
        // @"sub-float",
        // @"mul-float",
        // @"div-float",
        // @"rem-float",
        // @"add-double",
        // @"sub-double",
        // @"mul-double",
        // @"div-double",
        // @"rem-double",
        // @"add-int/2addr",
        // @"sub-int/2addr",
        // @"mul-int/2addr",
        // @"div-int/2addr",
        // @"rem-int/2addr",
        // @"and-int/2addr",
        // @"or-int/2addr",
        // @"xor-int/2addr",
        // @"shl-int/2addr",
        // @"shr-int/2addr",
        // @"ushr-int/2addr",
        // @"add-long/2addr",
        // @"sub-long/2addr",
        // @"mul-long/2addr",
        // @"div-long/2addr",
        // @"rem-long/2addr",
        // @"and-long/2addr",
        // @"or-long/2addr",
        // @"xor-long/2addr",
        // @"shl-long/2addr",
        // @"shr-long/2addr",
        // @"ushr-long/2addr",
        // @"add-float/2addr",
        // @"sub-float/2addr",
        // @"mul-float/2addr",
        // @"div-float/2addr",
        // @"rem-float/2addr",
        // @"add-double/2addr",
        // @"sub-double/2addr",
        // @"mul-double/2addr",
        // @"div-double/2addr",
        // @"rem-double/2addr",
        // @"add-int/lit16",
        // @"sub-int/lit16",
        // @"mul-int/lit16",
        // @"div-int/lit16",
        // @"rem-int/lit16",
        // @"and-int/lit16",
        // @"or-int/lit16",
        // @"xor-int/lit16",
        // @"add-int/lit8",
        // @"sub-int/lit8",
        // @"mul-int/lit8",
        // @"div-int/lit8",
        // @"rem-int/lit8",
        // @"and-int/lit8",
        // @"or-int/lit8",
        // @"xor-int/lit8",
        // @"shl-int/lit8",
        // @"shr-int/lit8",
        // @"ushr-int/lit8",
        // @"invoke-polymorphic",
        // @"invoke-polymorphic/range",
        // @"invoke-custom",
        // @"invoke-custom/range",
        // @"const-method-handle",
        // @"const-method-type",

        const Tag = enum {
            @"move-result-object",
            @"return-void",
            @"return-object",
            @"iput-wide",
            @"invoke-direct",
        };
        const Register = u16;
        const Literal = union(enum) {
            uint: u64,
            int: i64,
            string: []const u8,
            class: []const u8,
        };
    };

    const Type = union(enum) {
        /// Only valid for method return types
        void,

        boolean,
        byte,
        short,
        char,
        int,
        long,
        float,
        double,
        object: []const u8,
    };
    const TypeValue = struct {
        /// The type of the value
        t: Type,
        /// if 0, it is NOT an array
        array_dimensions: u8,

        pub fn read(string: []const u8) !TypeValue {
            var index: usize = 0;
            var bracket_count: u8 = 0;
            while (index < string.len) : (index += 1) {
                if (string[index] != '[') {
                    break;
                }
                bracket_count += 1;
            }
            const t: Type = switch (string[index]) {
                'V' => .void,
                'Z' => .boolean,
                'B' => .byte,
                'S' => .short,
                'C' => .char,
                'I' => .int,
                'J' => .long,
                'F' => .float,
                'D' => .double,
                'L' => .{ .object = string[index..] },
                else => return error.InvalidType,
            };
            return .{
                .t = t,
                .array_dimensions = bracket_count,
            };
        }

        pub fn format(type_value: TypeValue, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            if (type_value.array_dimensions != 0) {
                try writer.writeByteNTimes('[', type_value.array_dimensions);
            }
            switch (type_value.t) {
                .void => try writer.writeByte('V'),
                .boolean => try writer.writeByte('Z'),
                .byte => try writer.writeByte('B'),
                .short => try writer.writeByte('S'),
                .char => try writer.writeByte('C'),
                .int => try writer.writeByte('I'),
                .long => try writer.writeByte('J'),
                .float => try writer.writeByte('F'),
                .double => try writer.writeByte('D'),
                .object => |value| try writer.writeAll(value),
            }
        }
    };
    const Class = struct {
        access_flags: dex.AccessFlags,
        name: []const u8,
        extends: ?[]const u8 = null,
        fields: std.ArrayListUnmanaged(Field),
        methods: std.ArrayListUnmanaged(Method),
    };
    const Field = struct {
        access_flags: dex.AccessFlags,
        name: []const u8,
        type: TypeValue,
    };
    const Method = struct {
        access_flags: dex.AccessFlags,
        name: []const u8,
        parameters: std.ArrayListUnmanaged(TypeValue),
        return_type: TypeValue,
        code: std.ArrayListUnmanaged(Instruction),
    };
};

const std = @import("std");
const dex = @import("dex.zig");
