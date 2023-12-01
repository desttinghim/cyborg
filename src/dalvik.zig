pub const Module = struct {
    arena: std.heap.ArenaAllocator,
    strings: std.StringHashMapUnmanaged(void),
    types: std.StringHashMapUnmanaged(TypeValue),
    fields: std.StringHashMapUnmanaged(void),
    methods: std.StringHashMapUnmanaged(void),
    classes: std.ArrayListUnmanaged(Class),

    pub fn init(alloc: std.mem.Allocator) Module {
        return .{
            .arena = std.heap.ArenaAllocator.init(alloc),
            .strings = .{},
            .types = .{},
            .fields = .{},
            .methods = .{},
            .classes = .{},
        };
    }

    pub fn deinit(module: *Module) void {
        module.arena.deinit();
    }

    pub fn addString(module: *Module, string: []const u8) !void {
        const alloc = module.arena.allocator();
        try module.strings.put(alloc, string, {});
    }

    pub fn addType(module: *Module, t: TypeValue) !void {
        const alloc = module.arena.allocator();
        const type_string = try std.fmt.allocPrint(alloc, "{}", .{t});
        try module.addString(type_string);
        try module.types.put(alloc, type_string, t);
    }

    pub fn addField(module: *Module, class: TypeValue, field: *const Field) !void {
        const alloc = module.arena.allocator();
        try module.addType(field.type);
        try module.addType(class);
        try module.addString(field.name);
        try module.fields.put(alloc, field.name, {});
    }

    pub fn addMethod(module: *Module, class: TypeValue, method: *const Method) !void {
        const alloc = module.arena.allocator();
        try module.addType(method.return_type);
        try module.addType(class);
        const shorty = try alloc.alloc(u8, 1 + method.parameters.items.len);
        shorty[0] = method.return_type.getShortyChar();
        for (method.parameters.items, 1..) |param, i| {
            try module.addType(param);
            shorty[i] = param.getShortyChar();
        }
        try module.addString(shorty);
        try module.addString(method.name);
        try module.fields.put(alloc, method.name, {});
    }

    pub const Instruction = union(Tag) {
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
            class: TypeValue,
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
            class: TypeValue,
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

        pub const Tag = enum {
            @"move-result-object",
            @"return-void",
            @"return-object",
            @"iput-wide",
            @"invoke-direct",
        };
        pub const Register = u16;
        pub const Literal = union(enum) {
            uint: u64,
            int: i64,
            string: []const u8,
            class: []const u8,
        };
    };

    pub const Type = union(enum) {
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

        pub fn getShortyChar(t: Type) u8 {
            return switch (t) {
                .void => 'V',
                .boolean => 'Z',
                .byte => 'B',
                .short => 'S',
                .char => 'C',
                .int => 'I',
                .long => 'J',
                .float => 'F',
                .double => 'D',
                .object => 'L',
            };
        }
    };
    pub const TypeValue = struct {
        /// The type of the value
        t: Type,
        /// if 0, it is NOT an array
        array_dimensions: u8 = 0,

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

        pub fn getShortyChar(value: TypeValue) u8 {
            if (value.array_dimensions != 0) return 'L';
            return value.t.getShortyChar();
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
    pub const Class = struct {
        access_flags: dex.AccessFlags,
        name: []const u8,
        extends: ?[]const u8 = null,
        fields: std.ArrayListUnmanaged(Field),
        methods: std.ArrayListUnmanaged(Method),
    };
    pub const Field = struct {
        access_flags: dex.AccessFlags,
        name: []const u8,
        type: TypeValue,
    };
    pub const Method = struct {
        access_flags: dex.AccessFlags,
        name: []const u8,
        parameters: std.ArrayListUnmanaged(TypeValue),
        return_type: TypeValue,
        code: std.ArrayListUnmanaged(Instruction),
    };

    pub fn getStringIterator(module: *const Module) std.StringHashMap(void).KeyIterator {
        return module.strings.keyIterator();
    }
};

const std = @import("std");
const dex = @import("dex.zig");
