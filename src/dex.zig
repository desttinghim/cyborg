//! The DEX executable file format.

const std = @import("std");

pub const Operation = union(Tag) {
    nop,
    move: vAvB,
    @"move/from16": vAvB,
    @"move/16": vAvB,
    @"move/wide": vAvB,
    @"move-wide/from16": vAvB,
    @"move-wide/16": vAvB,
    @"move-object": vAvB,
    @"move-object/from16": vAvB,
    @"move-object/16": vAvB,
    @"move-result",
    @"move-result-wide",
    @"move-result-object": vAA,
    @"move-exception",
    @"return-void",
    @"return",
    @"return-wide",
    @"return-object": vAA,
    @"const/4",
    @"const/16",
    @"const",
    @"const/high16",
    @"const-wide/16",
    @"const-wide/32",
    @"const-wide",
    @"const-wide/high16",
    @"const-string",
    @"const-string/jumbo",
    @"const-class",
    @"monitor-enter",
    @"monitor-exit",
    @"check-cast",
    @"instance-of",
    @"array-length",
    @"new-instance",
    @"new-array",
    @"filled-new-array",
    @"filled-new-array/range",
    @"filled-array-data",
    throw,
    goto,
    @"goto/16",
    @"goto/32",
    @"packed-switch",
    @"sparse-switch",
    @"cmpl-float",
    @"cmpg-float",
    @"cmpl-double",
    @"cmpg-double",
    @"cmp-long",
    @"if-eq",
    @"if-ne",
    @"if-lt",
    @"if-ge",
    @"if-gt",
    @"if-le",
    @"ifz-eq",
    @"ifz-ne",
    @"ifz-lt",
    @"ifz-ge",
    @"ifz-gt",
    @"ifz-le",
    aget,
    @"aget-wide",
    @"aget-object",
    @"aget-boolean",
    @"aget-byte",
    @"aget-char",
    @"aget-short",
    aput,
    @"aput-wide",
    @"aput-object",
    @"aput-boolean",
    @"aput-byte",
    @"aput-char",
    @"aput-short",
    iget,
    @"iget-wide",
    @"iget-object",
    @"iget-boolean",
    @"iget-byte",
    @"iget-char",
    @"iget-short",
    iput,
    @"iput-wide",
    @"iput-object",
    @"iput-boolean",
    @"iput-byte",
    @"iput-char",
    @"iput-short",
    sget,
    @"sget-wide",
    @"sget-object",
    @"sget-boolean",
    @"sget-byte",
    @"sget-char",
    @"sget-short",
    sput,
    @"sput-wide",
    @"sput-object",
    @"sput-boolean",
    @"sput-byte",
    @"sput-char",
    @"sput-short",
    @"invoke-virtual",
    @"invoke-super",
    @"invoke-direct": vAvBBBBvCvDvEvFvG,
    @"invoke-static",
    @"invoke-interface",
    @"invoke-virtual/range",
    @"invoke-super/range",
    @"invoke-direct/range",
    @"invoke-static/range",
    @"invoke-interface/range",
    @"neg-int",
    @"not-int",
    @"neg-long",
    @"not-long",
    @"neg-float",
    @"neg-double",
    @"int-to-long",
    @"int-to-float",
    @"int-to-double",
    @"long-to-int",
    @"long-to-float",
    @"long-to-double",
    @"float-to-int",
    @"float-to-long",
    @"float-to-double",
    @"double-to-int",
    @"double-to-long",
    @"double-to-float",
    @"int-to-byte",
    @"int-to-char",
    @"int-to-short",
    @"add-int",
    @"sub-int",
    @"mul-int",
    @"div-int",
    @"rem-int",
    @"and-int",
    @"or-int",
    @"xor-int",
    @"shl-int",
    @"shr-int",
    @"ushr-int",
    @"add-long",
    @"sub-long",
    @"mul-long",
    @"div-long",
    @"rem-long",
    @"and-long",
    @"or-long",
    @"xor-long",
    @"shl-long",
    @"shr-long",
    @"ushr-long",
    @"add-float",
    @"sub-float",
    @"mul-float",
    @"div-float",
    @"rem-float",
    @"add-double",
    @"sub-double",
    @"mul-double",
    @"div-double",
    @"rem-double",
    @"add-int/2addr",
    @"sub-int/2addr",
    @"mul-int/2addr",
    @"div-int/2addr",
    @"rem-int/2addr",
    @"and-int/2addr",
    @"or-int/2addr",
    @"xor-int/2addr",
    @"shl-int/2addr",
    @"shr-int/2addr",
    @"ushr-int/2addr",
    @"add-long/2addr",
    @"sub-long/2addr",
    @"mul-long/2addr",
    @"div-long/2addr",
    @"rem-long/2addr",
    @"and-long/2addr",
    @"or-long/2addr",
    @"xor-long/2addr",
    @"shl-long/2addr",
    @"shr-long/2addr",
    @"ushr-long/2addr",
    @"add-float/2addr",
    @"sub-float/2addr",
    @"mul-float/2addr",
    @"div-float/2addr",
    @"rem-float/2addr",
    @"add-double/2addr",
    @"sub-double/2addr",
    @"mul-double/2addr",
    @"div-double/2addr",
    @"rem-double/2addr",
    @"add-int/lit16",
    @"sub-int/lit16",
    @"mul-int/lit16",
    @"div-int/lit16",
    @"rem-int/lit16",
    @"and-int/lit16",
    @"or-int/lit16",
    @"xor-int/lit16",
    @"add-int/lit8",
    @"sub-int/lit8",
    @"mul-int/lit8",
    @"div-int/lit8",
    @"rem-int/lit8",
    @"and-int/lit8",
    @"or-int/lit8",
    @"xor-int/lit8",
    @"shl-int/lit8",
    @"shr-int/lit8",
    @"ushr-int/lit8",
    @"invoke-polymorphic",
    @"invoke-polymorphic/range",
    @"invoke-custom",
    @"invoke-custom/range",
    @"const-method-handle",
    @"const-method-type",
    pub const Tag = enum(u8) {
        /// Waste cycles
        nop = 0x00,
        /// Move the contents of one non-object register to another.
        /// move vA, vB
        /// A: destination register (4 bits)
        /// B: source register (4 bits)
        move = 0x01,
        /// Move the contents of one non-object register to another.
        /// move/from16 vAA, vBBBB
        /// A: destination register (8 bits)
        /// B: source register (16 bits)
        @"move/from16" = 0x02,
        /// Move the contents of one non-object register to another.
        /// move/16 vAAAA, vBBBB
        /// A: destination register (16 bits)
        /// B: source register (16 bits)
        @"move/16" = 0x03,
        /// Move the contents of one register pair to another.
        /// NOTE: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
        /// move-wide vA, vB
        /// A: destination register pair (4 bits)
        /// B: source register pair (4 bits)
        @"move/wide" = 0x04,
        /// Move the contents of one register pair to another.
        /// NOTE: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
        /// move-wide/from16 vAA, vBBBB
        /// A: destination register pair (8 bits)
        /// B: source register pair (16 bits)
        @"move-wide/from16" = 0x05,
        /// Move the contents of one register pair to another.
        /// NOTE: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
        /// move-wide/16 vAAAA, vBBBB
        /// A: destination register pair (8 bits)
        /// B: source register pair (16 bits)
        @"move-wide/16" = 0x06,
        /// Move the contents of one object-bearing register to another.
        /// move-object vA, vB
        /// A: destination register (4 bits)
        /// B: source register (4 bits)
        @"move-object" = 0x07,
        /// Move the contents of one object-bearing register to another.
        /// move-object/from16 vAA, vBBBB
        /// A: destination register (8 bits)
        /// B: source register (16 bits)
        @"move-object/from16" = 0x08,
        /// Move the contents of one object-bearing register to another.
        /// move-object/16 vAAAA, vBBBB
        /// A: destination register (16 bits)
        /// B: source register (16 bits)
        @"move-object/16" = 0x09,
        /// Move the single-word non-object result of the most recent `invoke-kind` into the indicated register. This must be done as the instruction immediately after an `invoke-kind` whose (single-word, non-object) result is not to be ignored; anywhere else is invalid.
        /// move-result vAA
        /// A: destination register (8 bits)
        @"move-result" = 0x0a,
        /// Move the double-word result of the most recent `invoke-kind` into the indicated register. This must be done as the instruction immediately after an `invoke-kind` whose (double-word) result is not to be ignored; anywhere else is invalid.
        /// move-result-wide vAA
        /// A: destination register pair (8 bits)
        @"move-result-wide" = 0x0b,
        /// Move the object result of the most recent `invoke-kind` into the indicated register. This must be done as the instruction immediately after an `invoke-kind` or `filled-new-array` whose (object) result is not to be ignored; anywhere else is invalid.
        /// move-result-object vAA
        /// A: destination register (8 bits)
        @"move-result-object" = 0x0c,
        /// Save a just-caught exception into the given register. This must be the first instruction of any exception handler whose caught exception is not to be ignored, and this instruction must only ever occur as the first instruction of an exception handler; anywhere else is invalid.
        /// move-exception vAA
        /// A: destination register (8 bits)
        @"move-exception" = 0x0d,
        /// Return `void` from a method.
        /// return-void
        @"return-void" = 0x0e,
        /// Return from a single-width (32-bit) non-object value-returning method.
        /// return vAA
        /// A: return value register (8 bits)
        @"return" = 0x0f,
        /// Return from a double-width (64-bit) value-returning method.
        /// return-wide vAA
        /// A: return value register pair (8 bits)
        @"return-wide" = 0x10,
        /// Return from an object-returning method.
        /// return-object vAA
        /// A: return value register (8 bits)
        @"return-object" = 0x11,
        /// Move the given literal value (sign-extended to 32 bits) into the specified register.
        /// const/4 vA, #+B
        /// A: destination register (4 bits)
        /// B: signed int (4 bits)
        @"const/4" = 0x12,
        /// Move the given literal value (sign-extended to 32 bits) into the specified register.
        /// const/16 vAA, #+BBBB
        /// A: destination register (8 bits)
        /// B: signed int (16 bits)
        @"const/16" = 0x13,
        /// Move the given literal value into the specified register.
        /// const vAA, #+BBBBBBBB
        /// A: destination register (8 bits)
        /// B: arbitrary 32-bit constant
        @"const" = 0x14,
        /// Move the given literal value (right-zero extended to 32 bits) into the specified register.
        /// const/high16 vAA, #+BBBB_0000
        /// A: destination register (8 bits)
        /// B: signed int (16 bits)
        @"const/high16" = 0x15,
        /// Move the given literal value (sign extended to 64 bits) into the specified register.
        /// const-wide/high16 vAA, #+BBBB_0000
        /// A: destination register (8 bits)
        /// B: signed int (16 bits)
        @"const-wide/16" = 0x16,
        /// Move the given literal value (sign extended to 64 bits) into the specified register.
        /// const-wide/32 vAA, #+BBBB_BBBB
        /// A: destination register (8 bits)
        /// B: signed int (32 bits)
        @"const-wide/32" = 0x17,
        /// Move the given literal value into the specified register-pair.
        /// const-wide vAA, #+BBBB_BBBB_BBBB_BBBB
        /// A: destination register (8 bits)
        /// B: arbitrary double-width (64-bit) constant
        @"const-wide" = 0x18,
        /// Move the given literal value (right-zero extended to 64 bits) into the specified register-pair.
        /// const-wide/high16 vAA, #+BBBB_0000_0000_0000
        /// A: destination register (8 bits)
        /// B: signed int (16 bits)
        @"const-wide/high16" = 0x19,
        /// Move a reference to the string specified by the given index into the specified register
        /// const-string vAA, string@BBBB
        /// A: destination register (8 bits)
        /// B: string index
        @"const-string" = 0x1a,
        /// Move a reference to the string specified by the given index into the specified register
        /// const-string/jumbo vAA, string@BBBB_BBBB
        /// A: destination register (8 bits)
        /// B: string index
        @"const-string/jumbo" = 0x1b,
        /// Move a reference to the class specified by the given index into the specified register. In the case where the indicated type is primitive, this will store a reference to the primitive type's degenerate class.
        /// const-class vAA, type@BBBB_BBBB
        /// A: destination register (8 bits)
        /// B: type index
        @"const-class" = 0x1c,
        /// Acquire the monitor for the indicated object.
        /// monitor-enter vAA
        /// A: reference-bearing register (8 bits)
        @"monitor-enter" = 0x1d,
        @"monitor-exit" = 0x1e,
        @"check-cast" = 0x1f,
        @"instance-of" = 0x20,
        @"array-length" = 0x21,
        @"new-instance" = 0x22,
        @"new-array" = 0x23,
        @"filled-new-array" = 0x24,
        @"filled-new-array/range" = 0x25,
        @"filled-array-data" = 0x26,
        throw = 0x27,
        goto = 0x28,
        @"goto/16" = 0x29,
        @"goto/32" = 0x2a,
        @"packed-switch" = 0x2b,
        @"sparse-switch" = 0x2c,
        //
        @"cmpl-float" = 0x2d,
        @"cmpg-float" = 0x2e,
        @"cmpl-double" = 0x2f,
        @"cmpg-double" = 0x30,
        @"cmp-long" = 0x31,
        //
        @"if-eq" = 0x32,
        @"if-ne" = 0x33,
        @"if-lt" = 0x34,
        @"if-ge" = 0x35,
        @"if-gt" = 0x36,
        @"if-le" = 0x37,
        //
        @"ifz-eq" = 0x38,
        @"ifz-ne" = 0x39,
        @"ifz-lt" = 0x3a,
        @"ifz-ge" = 0x3b,
        @"ifz-gt" = 0x3c,
        @"ifz-le" = 0x3d,
        // Array operations
        aget = 0x44,
        @"aget-wide" = 0x45,
        @"aget-object" = 0x46,
        @"aget-boolean" = 0x47,
        @"aget-byte" = 0x48,
        @"aget-char" = 0x49,
        @"aget-short" = 0x4a,
        aput = 0x4b,
        @"aput-wide" = 0x4c,
        @"aput-object" = 0x4d,
        @"aput-boolean" = 0x4e,
        @"aput-byte" = 0x4f,
        @"aput-char" = 0x50,
        @"aput-short" = 0x51,
        // Instance operations
        iget = 0x52,
        @"iget-wide" = 0x53,
        @"iget-object" = 0x54,
        @"iget-boolean" = 0x55,
        @"iget-byte" = 0x56,
        @"iget-char" = 0x57,
        @"iget-short" = 0x58,
        iput = 0x59,
        @"iput-wide" = 0x5a,
        @"iput-object" = 0x5b,
        @"iput-boolean" = 0x5c,
        @"iput-byte" = 0x5d,
        @"iput-char" = 0x5e,
        @"iput-short" = 0x5f,
        // Static operations
        sget = 0x60,
        @"sget-wide" = 0x61,
        @"sget-object" = 0x62,
        @"sget-boolean" = 0x63,
        @"sget-byte" = 0x64,
        @"sget-char" = 0x65,
        @"sget-short" = 0x66,
        sput = 0x67,
        @"sput-wide" = 0x68,
        @"sput-object" = 0x69,
        @"sput-boolean" = 0x6a,
        @"sput-byte" = 0x6b,
        @"sput-char" = 0x6c,
        @"sput-short" = 0x6d,
        // Invoke
        @"invoke-virtual" = 0x6e,
        @"invoke-super" = 0x6f,
        @"invoke-direct" = 0x70,
        @"invoke-static" = 0x71,
        @"invoke-interface" = 0x72,
        // 0x73 - Unused
        // Invoke/range
        @"invoke-virtual/range" = 0x74,
        @"invoke-super/range" = 0x75,
        @"invoke-direct/range" = 0x76,
        @"invoke-static/range" = 0x77,
        @"invoke-interface/range" = 0x78,
        // Unary operations
        @"neg-int" = 0x7b,
        @"not-int" = 0x7c,
        @"neg-long" = 0x7d,
        @"not-long" = 0x7e,
        @"neg-float" = 0x7f,
        // 0x79..0x7a - unused
        @"neg-double" = 0x80,
        @"int-to-long" = 0x81,
        @"int-to-float" = 0x82,
        @"int-to-double" = 0x83,
        @"long-to-int" = 0x84,
        @"long-to-float" = 0x85,
        @"long-to-double" = 0x86,
        @"float-to-int" = 0x87,
        @"float-to-long" = 0x88,
        @"float-to-double" = 0x89,
        @"double-to-int" = 0x8a,
        @"double-to-long" = 0x8b,
        @"double-to-float" = 0x8c,
        @"int-to-byte" = 0x8d,
        @"int-to-char" = 0x8e,
        @"int-to-short" = 0x8f,
        // Binary operations
        @"add-int" = 0x90,
        @"sub-int" = 0x91,
        @"mul-int" = 0x92,
        @"div-int" = 0x93,
        @"rem-int" = 0x94,
        @"and-int" = 0x95,
        @"or-int" = 0x96,
        @"xor-int" = 0x97,
        @"shl-int" = 0x98,
        @"shr-int" = 0x99,
        @"ushr-int" = 0x9a,
        @"add-long" = 0x9b,
        @"sub-long" = 0x9c,
        @"mul-long" = 0x9d,
        @"div-long" = 0x9e,
        @"rem-long" = 0x9f,
        @"and-long" = 0xa0,
        @"or-long" = 0xa1,
        @"xor-long" = 0xa2,
        @"shl-long" = 0xa3,
        @"shr-long" = 0xa4,
        @"ushr-long" = 0xa5,
        @"add-float" = 0xa6,
        @"sub-float" = 0xa7,
        @"mul-float" = 0xa8,
        @"div-float" = 0xa9,
        @"rem-float" = 0xaa,
        @"add-double" = 0xab,
        @"sub-double" = 0xac,
        @"mul-double" = 0xad,
        @"div-double" = 0xae,
        @"rem-double" = 0xaf,
        // Binary operations to address
        @"add-int/2addr" = 0xb0,
        @"sub-int/2addr" = 0xb1,
        @"mul-int/2addr" = 0xb2,
        @"div-int/2addr" = 0xb3,
        @"rem-int/2addr" = 0xb4,
        @"and-int/2addr" = 0xb5,
        @"or-int/2addr" = 0xb6,
        @"xor-int/2addr" = 0xb7,
        @"shl-int/2addr" = 0xb8,
        @"shr-int/2addr" = 0xb9,
        @"ushr-int/2addr" = 0xba,
        @"add-long/2addr" = 0xbb,
        @"sub-long/2addr" = 0xbc,
        @"mul-long/2addr" = 0xbd,
        @"div-long/2addr" = 0xbe,
        @"rem-long/2addr" = 0xbf,
        @"and-long/2addr" = 0xc0,
        @"or-long/2addr" = 0xc1,
        @"xor-long/2addr" = 0xc2,
        @"shl-long/2addr" = 0xc3,
        @"shr-long/2addr" = 0xc4,
        @"ushr-long/2addr" = 0xc5,
        @"add-float/2addr" = 0xc6,
        @"sub-float/2addr" = 0xc7,
        @"mul-float/2addr" = 0xc8,
        @"div-float/2addr" = 0xc9,
        @"rem-float/2addr" = 0xca,
        @"add-double/2addr" = 0xcb,
        @"sub-double/2addr" = 0xcc,
        @"mul-double/2addr" = 0xcd,
        @"div-double/2addr" = 0xce,
        @"rem-double/2addr" = 0xcf,
        // Binary operations with 16-bit literal value
        @"add-int/lit16" = 0xd0,
        @"sub-int/lit16" = 0xd1,
        @"mul-int/lit16" = 0xd2,
        @"div-int/lit16" = 0xd3,
        @"rem-int/lit16" = 0xd4,
        @"and-int/lit16" = 0xd5,
        @"or-int/lit16" = 0xd6,
        @"xor-int/lit16" = 0xd7,
        // Binary operations with 8-bit literal value
        @"add-int/lit8" = 0xd8,
        @"sub-int/lit8" = 0xd9,
        @"mul-int/lit8" = 0xda,
        @"div-int/lit8" = 0xdb,
        @"rem-int/lit8" = 0xdc,
        @"and-int/lit8" = 0xdd,
        @"or-int/lit8" = 0xde,
        @"xor-int/lit8" = 0xdf,
        @"shl-int/lit8" = 0xe0,
        @"shr-int/lit8" = 0xe1,
        @"ushr-int/lit8" = 0xe2,
        // e3..f9 - unused
        @"invoke-polymorphic" = 0xfa,
        @"invoke-polymorphic/range" = 0xfb,
        @"invoke-custom" = 0xfc,
        @"invoke-custom/range" = 0xfd,
        @"const-method-handle" = 0xfe,
        @"const-method-type" = 0xff,
    };
    pub const vAvB = struct { u4, u4 };
    pub const vAAvBBBB = struct { u8, u16 };
    pub const vAAAAvBBBB = struct { u16, u16 };
    pub const vAA = struct { u8 };
    pub const vAlitB = struct { u4, u4 };
    pub const vAAlitBBBB = struct { u8, u16 };
    pub const vAAlitBBBBBBBB = struct { u8, u32 };
    pub const vAAlitBBBBBBBBBBBBBBBB = struct { u8, u32 };
    pub const vAAcBBBB = struct { u8, u16 };
    pub const vAAcBBBBBBBB = struct { u8, u32 };
    pub const vAvBcCCCC = struct { u8, u8, u16 };
    pub const vAvBBBBvCvDvEvFvG = struct { u4, u16, u4, u4, u4, u4, u4 };
    pub const vAAvBBBBvCCCC = struct { u8, u16, u16 };

    pub fn format(operation: Operation, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        switch (operation) {
            .@"move-result-object" => |args| {
                try writer.print("{s:<20} {}", .{ @tagName(operation), args[0] });
            },
            .@"return-object" => |args| {
                try writer.print("{s:<20} {}", .{ @tagName(operation), args[0] });
            },
            .@"invoke-direct" => |args| {
                try writer.print("{s:<20} {} {} {} {} {} {}", .{
                    @tagName(operation),
                    args[0],
                    args[1],
                    args[2],
                    args[3],
                    args[4],
                    args[5],
                });
            },
            else => |tag| {
                try writer.print("{s:<20}", .{@tagName(tag)});
            },
        }
    }

    pub fn read(reader: anytype) !Operation {
        const op = try reader.readEnum(Tag, .little); // 1 byte
        switch (op) {
            .@"move-result-object" => {
                const a = try reader.readInt(u8, .little);
                return .{ .@"move-result-object" = .{a} };
            },
            .@"return-object" => {
                const a = try reader.readInt(u8, .little);
                return .{ .@"return-object" = .{a} };
            },
            .@"invoke-direct" => {
                const hi = try reader.readInt(u8, .little);
                const a: u4 = @truncate((hi & 0xF0) >> 4);
                const g: u4 = @truncate((hi & 0xF));
                const b: u16 = try reader.readInt(u16, .little);
                const third = try reader.readInt(u16, .little);
                const c: u4 = @truncate(third);
                const d: u4 = @truncate(third >> 4);
                const e: u4 = @truncate(third >> 8);
                const f: u4 = @truncate(third >> 12);
                return .{ .@"invoke-direct" = .{ a, b, c, d, e, f, g } };
            },
            else => {
                return error.Unimplemented;
            },
        }
    }
};

pub const Instruction = struct {
    const InvokePolymorphicRange = struct {
        count: u8,
        method: u16,
        start_register: u16,
        prototype: u16,

        pub fn read(reader: anytype) !InvokePolymorphicRange {
            const count = try reader.readInt(u8, .little);
            const method = try reader.readInt(u16, .little);
            const start_register = try reader.readInt(u16, .little);
            const prototype = try reader.readInt(u16, .little);
            return .{
                .count = count,
                .method = method,
                .start_register = start_register,
                .prototype = prototype,
            };
        }
    };
};

const PackedSwitchPayload = struct {
    ident: u16 = 0x0100,
    size: u16,
    first_key: i32,
    targets: []i32,
};

const SparseSwitchPayload = struct {
    ident: u16 = 0x0200,
    size: u16,
    keys: []i32,
    targets: []i32,
};

const FillArrayDataPayload = struct {
    ident: u16 = 0x0300,
    element_width: u16,
    size: u32,
    data: []u8,
};

// Data types used in the DEX file format specification
const byte = i8;
const ubyte = u8;
const short = i16;
const ushort = u16;
const int = i32;
const uint = u32;
const long = i64;
const ulong = u64;

const sleb128 = i32;
const uleb128 = u32;
const uleb128p1 = u33;

/// DEX file layout
pub const Dex = struct {
    /// the header
    header: HeaderItem,
    /// string identifiers list. These are identifiers for all the strings used by this file, either for internal naming (e.g. type descriptors) or as constant objects referred to by code. This list must be sorted by string contents, using UTF-16 code point values (not in a locale-sensitive manner), and it must not contain any duplicate entries.
    string_ids: std.ArrayListUnmanaged(StringIdItem),
    type_ids: std.ArrayListUnmanaged(TypeIdItem),
    proto_ids: std.ArrayListUnmanaged(ProtoIdItem),
    field_ids: std.ArrayListUnmanaged(FieldIdItem),
    method_ids: std.ArrayListUnmanaged(MethodIdItem),
    class_defs: std.ArrayListUnmanaged(ClassDefItem),
    call_site_ids: std.ArrayListUnmanaged(CallSiteIdItem),
    method_handles: std.ArrayListUnmanaged(MethodHandleItem),
    data: std.ArrayListUnmanaged(u8),
    link_data: std.ArrayListUnmanaged(u8),
    map_list: MapList,

    pub fn readAlloc(seek: anytype, reader: anytype, allocator: std.mem.Allocator) !Dex {
        var dex: Dex = undefined;

        // Read the header
        dex.header = try HeaderItem.read(seek, reader);

        // Read the string id list
        try seek.seekTo(dex.header.string_ids_off);
        dex.string_ids = try std.ArrayListUnmanaged(StringIdItem).initCapacity(allocator, dex.header.string_ids_size);
        for (0..dex.header.string_ids_size) |_| {
            dex.string_ids.appendAssumeCapacity(try StringIdItem.read(reader));
        }

        // Read the type id list
        try seek.seekTo(dex.header.type_ids_off);
        dex.type_ids = try std.ArrayListUnmanaged(TypeIdItem).initCapacity(allocator, dex.header.type_ids_size);
        for (0..dex.header.type_ids_size) |_| {
            dex.type_ids.appendAssumeCapacity(try TypeIdItem.read(reader));
        }

        // Read the proto id list
        try seek.seekTo(dex.header.proto_ids_off);
        dex.proto_ids = try std.ArrayListUnmanaged(ProtoIdItem).initCapacity(allocator, dex.header.proto_ids_size);
        for (0..dex.header.proto_ids_size) |_| {
            dex.proto_ids.appendAssumeCapacity(try ProtoIdItem.read(reader));
        }

        // Read the field id list
        try seek.seekTo(dex.header.field_ids_off);
        dex.field_ids = try std.ArrayListUnmanaged(FieldIdItem).initCapacity(allocator, dex.header.field_ids_size);
        for (0..dex.header.field_ids_size) |_| {
            dex.field_ids.appendAssumeCapacity(try FieldIdItem.read(reader));
        }

        // Read the method id list
        try seek.seekTo(dex.header.method_ids_off);
        dex.method_ids = try std.ArrayListUnmanaged(MethodIdItem).initCapacity(allocator, dex.header.method_ids_size);
        for (0..dex.header.method_ids_size) |_| {
            dex.method_ids.appendAssumeCapacity(try MethodIdItem.read(reader));
        }

        // Read the class def list
        try seek.seekTo(dex.header.class_defs_off);
        dex.class_defs = try std.ArrayListUnmanaged(ClassDefItem).initCapacity(allocator, dex.header.class_defs_size);
        for (0..dex.header.class_defs_size) |_| {
            dex.class_defs.appendAssumeCapacity(try ClassDefItem.read(reader));
        }

        // TODO?
        // Read the call site ids list
        // NOTE: The call_site list does NOT have an offset specified in the header
        // dex.call_site_ids = try std.ArrayListUnmanaged(CallSiteIdItem).initCapacity(allocator, dex.header.call_site_ids_size);
        // for (0..dex.header.class_defs_size) |_| {
        //     dex.call_site_ids.appendAssumeCapacity(try CallSiteIdItem.read(reader));
        // }
        // dex.call_site_ids = ;
        // dex.method_handles = ;

        // Read data into buffer
        try seek.seekTo(dex.header.data_off);
        dex.data = try std.ArrayListUnmanaged(u8).initCapacity(allocator, dex.header.data_size);
        const data_slice = dex.data.addManyAsSliceAssumeCapacity(dex.header.data_size);
        const amount = try reader.read(data_slice);
        if (amount != dex.header.data_size) {
            std.log.err("read {} bytes into dex.data", .{amount});
            return error.UnexpectedEOF;
        }

        // TODO?
        // dex.link_data = ;

        // Read the file map
        dex.map_list = try MapList.read(dex.header, seek, reader, allocator);

        return dex;
    }

    pub fn getString(dex: Dex, id: StringIdItem) !StringDataItem {
        const offset = id.string_data_off - dex.header.data_off;
        var fbs = std.io.fixedBufferStream(dex.data.items[offset..]);
        const reader = fbs.reader();
        const codepoints = try std.leb.readULEB128(u32, reader);
        const pos = fbs.getPos() catch unreachable;
        const data = std.mem.sliceTo(dex.data.items[offset + pos ..], 0);
        return StringDataItem{
            .utf16_size = codepoints,
            .data = data,
        };
    }

    pub fn getTypeString(dex: Dex, id: TypeIdItem) !StringDataItem {
        const descriptor_idx = id.descriptor_idx;
        if (descriptor_idx > dex.string_ids.items.len) return error.TypeStringOutOfBounds;
        return dex.getString(dex.string_ids.items[descriptor_idx]);
    }

    pub fn getPrototype(dex: Dex, id: ProtoIdItem, allocator: std.mem.Allocator) !Prototype {
        const parameters = if (id.parameters_off == 0) null else parameters: {
            const offset = id.parameters_off - dex.header.data_off;
            var fbs = std.io.fixedBufferStream(dex.data.items[offset..]);
            const reader = fbs.reader();
            break :parameters try TypeList.read(reader, allocator);
        };
        return Prototype{
            .shorty = try dex.getString(dex.string_ids.items[id.shorty_idx]),
            .return_type = try dex.getTypeString(dex.type_ids.items[id.return_type_idx]),
            .parameters = parameters,
        };
    }

    pub fn getTypeStringList(dex: Dex, type_list: TypeList, allocator: std.mem.Allocator) ![]StringDataItem {
        var string_list = try allocator.alloc(StringDataItem, type_list.size);
        for (type_list.list, 0..) |type_item, i| {
            string_list[i] = try dex.getTypeString(dex.type_ids.items[type_item.type_idx]);
        }
        return string_list;
    }
};

const Prototype = struct {
    shorty: StringDataItem,
    return_type: StringDataItem,
    parameters: ?TypeList,
};

/// Magic bytes that identify a DEX file
const DEX_FILE_MAGIC = "dex\n";
const Version = enum(u32) {
    @"039" = 0x03_33_39_00,
    @"038" = 0x03_33_38_00,
    @"037" = 0x03_33_37_00,
    @"036" = 0x03_33_36_00,
    @"035" = 0x03_33_35_00,
};

const Endianness = enum(u32) {
    /// Constant used to identify the endianness of the file
    Endian = 0x12345678,
    /// Constant used to identify the endianness of the file
    ReverseEndian = 0x78563412,
    _,
};
/// Value to represent null indexes
pub const NO_INDEX: u32 = 0xffffffff;

const AccessFlags = packed struct(u32) {
    Public: bool,
    Private: bool,
    Protected: bool,
    Static: bool,
    Final: bool,
    Synchronized: bool,
    Volatile: bool,
    Bridge: bool,
    Transient: bool,
    Varargs: bool,
    Native: bool,
    Interface: bool,
    Abstract: bool,
    Strict: bool,
    Synthetic: bool,
    Annotation: bool,
    Enum: bool,
    _unused: bool,
    Constructor: bool,
    DeclaredSynchronized: bool,
    _unused2: u12,

    pub fn format(access_flags: AccessFlags, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (access_flags.Public) _ = try writer.write("public");
        if (access_flags.Private) _ = try writer.write(" private");
        if (access_flags.Protected) _ = try writer.write(" protected");
        if (access_flags.Static) _ = try writer.write(" static");
        if (access_flags.Final) _ = try writer.write(" final");
        if (access_flags.Synchronized) _ = try writer.write(" synchronized");
        if (access_flags.Volatile) _ = try writer.write(" volatile");
        if (access_flags.Bridge) _ = try writer.write(" bridge");
        if (access_flags.Transient) _ = try writer.write(" transient");
        if (access_flags.Varargs) _ = try writer.write(" varargs");
        if (access_flags.Native) _ = try writer.write(" native");
        if (access_flags.Interface) _ = try writer.write(" interface");
        if (access_flags.Abstract) _ = try writer.write(" abstract");
        if (access_flags.Strict) _ = try writer.write(" strict");
        if (access_flags.Synthetic) _ = try writer.write(" synthetic");
        if (access_flags.Annotation) _ = try writer.write(" annotation");
        if (access_flags.Enum) _ = try writer.write(" enum");
        if (access_flags.Constructor) _ = try writer.write(" constructor");
        if (access_flags.DeclaredSynchronized) _ = try writer.write(" declared synchronized");
    }
};

const EncodedValue = struct {
    type: u8,
    value: []u8,
};

const ValueType = packed struct(u8) {
    type: u5,
    arg: u3,
};

const ValueFormats = enum(u5) {
    Byte = 0x00,
    Short = 0x02,
    Char = 0x03,
    Int = 0x04,
    Long = 0x06,
    Float = 0x10,
    Double = 0x11,
    MethodType = 0x15,
    MethodHandle = 0x16,
    String = 0x17,
    Type = 0x18,
    Field = 0x19,
    Method = 0x1a,
    Enum = 0x1b,
    Array = 0x1c,
    Annotation = 0x1d,
    Null = 0x1e,
    Boolean = 0x1f,
};

const EncodedArray = struct {
    size: uleb128,
    values: []EncodedValue,
};

const EncodedAnnotation = struct {
    type_idx: uleb128,
    size: uleb128,
    size: uleb128,
    elements: []AnnotationElement,
};

const AnnotationElement = struct {
    name_idx: uleb128,
    value: EncodedValue,
};

const HeaderItem = struct {
    /// Magic value
    magic: [4]u8,
    /// Dex file format version
    version: Version,
    /// adler32 checksum of the rest of the file (everything but magic and this field); used to detect file corruption
    checksum: u32,
    /// SHA-1 signature (hash) of the rest of the file (everything but magic, checksum, and this field); used to uniquely identify files
    signature: [20]u8,
    /// size of the entire file (including the header), in bytes
    file_size: u32,
    /// size of the header (this entire section), in bytes. This allows for at least a limited amount of backwards/forwards compatibility without invalidating the format
    header_size: u32 = 0x70,
    /// endianness tag. Either `ENDIAN_CONSTANT` or `REVERSE_ENDIAN_CONSTANT`
    endian_tag: std.builtin.Endian,
    /// size of the link section, or 0 if this file isn't statically linked
    link_size: u32,
    /// offset from the start of the file to the link section, or 0 if `link_size == 0`. The
    /// offset, if non-zero, should be to an offset into the `link_data` section. The format of
    /// the data pointed at is left unspecified by this document; this header field (and the
    /// previous) are left as hooks for use by runtime implementations
    link_off: u32,
    /// offset from the start of the file to the map item. The offset, which must be non-zero,
    /// should be to an offset into the data section, and the data should be in the format
    /// specified by "`map_list`" below.
    map_off: u32,
    /// count of strings in the string identifiers list
    string_ids_size: u32,
    /// offset from the start of the file to the string identifiers list or `0` if `string_ids_size == 0`
    /// (admittedly a strange edge case). The offset, if non-zero, should be to the
    /// start of the `string_ids` section.
    string_ids_off: u32,
    /// count of the elements in the type identifiers list, at most 65535
    type_ids_size: u32,
    /// offset from the start of the file to the type identifiers list or `0` if `type_ids_size == 0`
    /// (admittedly a strange edge case). The offset, if non-zero, should be to the
    /// start of the `type_ids` section.
    type_ids_off: u32,
    /// count of the elements in the prototype identifiers list, at most 65535
    proto_ids_size: u32,
    /// offset from the start of the file to the prototype list or `0` if `proto_ids_size == 0`
    /// (admittedly a strange edge case). The offset, if non-zero, should be to the
    /// start of the `proto_ids` section.
    proto_ids_off: u32,
    /// count of the elements in the field identifiers list
    field_ids_size: u32,
    /// offset from the start of the file to the field list or `0` if `field_ids_size == 0`.
    /// The offset, if non-zero, should be to the start of the `field_ids` section.
    field_ids_off: u32,
    /// count of the elements in the method identifiers list
    method_ids_size: u32,
    /// offset from the start of the file to the method list or `0` if `method_ids_size == 0`.
    /// The offset, if non-zero, should be to the start of the `method_ids` section.
    method_ids_off: u32,
    /// count of the elements in the class identifiers list
    class_defs_size: u32,
    /// offset from the start of the file to the class list or `0` if `class_ids_size == 0`
    /// (admittedly a strange edge case). The offset, if non-zero, should be to the
    /// start of the `class_defs` section.
    class_defs_off: u32,
    /// Size of the data section in bytes. Must be an even multiple of sizeof(uint).
    data_size: u32,
    /// offset from the start of the file to the start of the data section.
    data_off: u32,

    pub fn read(seek: anytype, reader: anytype) !HeaderItem {
        _ = seek;
        var header: HeaderItem = undefined;

        if (try reader.read(&header.magic) != header.magic.len) return error.UnexpectedEOF;
        if (!std.mem.eql(u8, header.magic[0..], DEX_FILE_MAGIC[0..])) {
            std.log.info("Header magic bytes were 0x{}, expected 0x{}", .{ std.fmt.fmtSliceHexLower(header.magic[0..]), std.fmt.fmtSliceHexLower(DEX_FILE_MAGIC[0..]) });
            return error.InvalidMagicBytes;
        }

        var version_buf: [4]u8 = undefined;
        if (try reader.read(&version_buf) != 4) return error.UnexpectedEOF;
        if (std.mem.eql(u8, &version_buf, "035\x00")) {
            header.version = .@"035";
        } else if (std.mem.eql(u8, &version_buf, "036\x00")) {
            header.version = .@"036";
        } else if (std.mem.eql(u8, &version_buf, "037\x00")) {
            header.version = .@"037";
        } else if (std.mem.eql(u8, &version_buf, "038\x00")) {
            header.version = .@"038";
        } else if (std.mem.eql(u8, &version_buf, "039\x00")) {
            header.version = .@"039";
        } else {
            return error.UnknownFormatVersion;
        }

        // TODO: compute checksum and compare
        header.checksum = try reader.readInt(u32, .little);

        if (try reader.read(&header.signature) != header.signature.len) return error.UnexpectedEOF;

        header.file_size = try reader.readInt(u32, .little);
        header.header_size = try reader.readInt(u32, .little);
        if (header.header_size != 0x70) return error.UnexpectedHeaderSize;
        header.endian_tag = if (try reader.readEnum(Endianness, .little) == .Endian) .little else .big;
        header.link_size = try reader.readInt(u32, .little);
        header.link_off = try reader.readInt(u32, .little);
        header.map_off = try reader.readInt(u32, .little);
        header.string_ids_size = try reader.readInt(u32, .little);
        header.string_ids_off = try reader.readInt(u32, .little);
        header.type_ids_size = try reader.readInt(u32, .little);
        header.type_ids_off = try reader.readInt(u32, .little);
        header.proto_ids_size = try reader.readInt(u32, .little);
        header.proto_ids_off = try reader.readInt(u32, .little);
        header.field_ids_size = try reader.readInt(u32, .little);
        header.field_ids_off = try reader.readInt(u32, .little);
        header.method_ids_size = try reader.readInt(u32, .little);
        header.method_ids_off = try reader.readInt(u32, .little);
        header.class_defs_size = try reader.readInt(u32, .little);
        header.class_defs_off = try reader.readInt(u32, .little);
        header.data_size = try reader.readInt(u32, .little);
        header.data_off = try reader.readInt(u32, .little);

        return header;
    }
};

const MapList = struct {
    size: u32,
    list: []MapItem,

    pub fn read(header: HeaderItem, seek: anytype, reader: anytype, allocator: std.mem.Allocator) !MapList {
        try seek.seekTo(header.map_off);
        const size = try reader.readInt(u32, .little);
        var list = try allocator.alloc(MapItem, size);
        errdefer allocator.free(list);
        for (list) |*map_item| {
            map_item.* = try MapItem.read(reader);
        }
        return .{
            .size = size,
            .list = list,
        };
    }
};

const MapItem = struct {
    type: TypeCode,
    _unused: u16,
    size: u32,
    offset: u32,

    pub fn read(reader: anytype) !MapItem {
        return MapItem{
            .type = try reader.readEnum(TypeCode, .little),
            ._unused = try reader.readInt(u16, .little),
            .size = try reader.readInt(u32, .little),
            .offset = try reader.readInt(u32, .little),
        };
    }
};

const TypeCode = enum(u16) {
    header_item = 0x0000,
    string_id_item = 0x0001,
    type_id_item = 0x0002,
    proto_id_item = 0x0003,
    field_id_item = 0x0004,
    method_id_item = 0x0005,
    class_def_item = 0x0006,
    call_site_id_item = 0x0007,
    method_handle_item = 0x0008,
    map_list = 0x1000,
    type_list = 0x1001,
    annotation_set_ref_list = 0x1002,
    annotation_set_item = 0x1003,
    class_data_item = 0x2000,
    code_item = 0x2001,
    string_data_item = 0x2002,
    debug_info_item = 0x2003,
    annotation_item = 0x2004,
    encoded_array_item = 0x2005,
    annotations_directory_item = 0x2006,
    hiddenapi_class_data_item = 0xF000,
};

const StringIdItem = struct {
    string_data_off: u32,

    pub fn read(reader: anytype) !StringIdItem {
        return StringIdItem{
            .string_data_off = try reader.readInt(u32, .little),
        };
    }
};

const StringDataItem = struct {
    /// size of this string, in UTF-16 code units (which is the "string length" in many systems). That is, this is the decoded length of the string. (The encoded length is implied by the position of the 0 byte)
    utf16_size: uleb128,
    /// a series of MUTF-8 code units (a.k.a. octets, a.k.a. bytes) followed by a byte of value 0.
    data: []u8,
};

const TypeIdItem = struct {
    /// index into the string_ids list for the descriptor string of this type. The string must conform to the syntax for TypeDescriptor, defined above.
    descriptor_idx: u32,
    pub fn read(reader: anytype) !TypeIdItem {
        return TypeIdItem{
            .descriptor_idx = try reader.readInt(u32, .little),
        };
    }
};

const ProtoIdItem = struct {
    /// index into the string_ids list for the short-form descriptor string of this prototype. The string must conform to the syntax for ShortyDescriptor, defined above, and must correspond to the return type and parameters of this item.
    shorty_idx: u32,
    /// index into the type_ids list for the return type of this prototype
    return_type_idx: u32,
    /// offset from the start of the file to the list of the parameter types for this prototype, or 0 if this prototype has no parameters. This offset, if non-zero, should be in the data section, and the data there should be in the format specified by the "type_list" below. Additionally, there should be no reference to the type void in the list.
    parameters_off: u32,

    pub fn read(reader: anytype) !@This() {
        return @This(){
            .shorty_idx = try reader.readInt(u32, .little),
            .return_type_idx = try reader.readInt(u32, .little),
            .parameters_off = try reader.readInt(u32, .little),
        };
    }
};

const FieldIdItem = struct {
    class_idx: u16,
    type_idx: u16,
    name_idx: u32,
    pub fn read(reader: anytype) !@This() {
        return @This(){
            .class_idx = try reader.readInt(u16, .little),
            .type_idx = try reader.readInt(u16, .little),
            .name_idx = try reader.readInt(u32, .little),
        };
    }
};

const MethodIdItem = struct {
    class_idx: u16,
    proto_idx: u16,
    name_idx: u32,

    pub fn read(reader: anytype) !@This() {
        return @This(){
            .class_idx = try reader.readInt(u16, .little),
            .proto_idx = try reader.readInt(u16, .little),
            .name_idx = try reader.readInt(u32, .little),
        };
    }
};

const ClassDefItem = struct {
    class_idx: u32,
    access_flags: AccessFlags,
    superclass_idx: u32,
    interfaces_off: u32,
    source_file_idx: u32,
    annotations_off: u32,
    class_data_off: u32,
    static_values_off: u32,

    pub fn read(reader: anytype) !@This() {
        return @This(){
            .class_idx = try reader.readInt(u32, .little),
            .access_flags = @as(AccessFlags, @bitCast(try reader.readInt(u32, .little))),
            .superclass_idx = try reader.readInt(u32, .little),
            .interfaces_off = try reader.readInt(u32, .little),
            .source_file_idx = try reader.readInt(u32, .little),
            .annotations_off = try reader.readInt(u32, .little),
            .class_data_off = try reader.readInt(u32, .little),
            .static_values_off = try reader.readInt(u32, .little),
        };
    }
};

const CallSiteIdItem = struct {
    call_site_off: u32,
    pub fn read(reader: anytype) !@This() {
        return @This(){
            .call_site_off = try reader.readInt(u32, .little),
        };
    }
};

/// Appears in the data section
///
/// alignment: none (byte aligned)
///
/// The call_site_item is an encoded_array_item whose elements correspond to the arguments provided to a bootstrap linker method. The first three arguments are:
///
/// 1. A method handle representing the bootstrap linker method (VALUE_METHOD_HANDLE)
/// 2. A method name that the bootstrap linker should resolve (VALUE_STRING).
/// 3. A method type corresponding to the type of the method name to be resolved (VALUE_METHOD_TYPE)
///
/// Any additional arguments are constant values passed to the bootstrap linker method. These arguments are passed in order and without any type conversion.
///
/// The method handle representing the bootstrap linker method must have return type `java.lang.invoke.CallSite`. The first three parameter types are:
/// 1. `java.lang.invoke.Lookup`
/// 2. `java.lang.String`
/// 3. `java.lang.invoke.MethodType`
///
/// The parameter types of any additional arguments are determined from their constant values.
const CallSiteItem = struct {};

const MethodHandleItem = struct {
    /// type of the method handle; see table below
    method_handle_type: u16,
    _unused: u16,
    /// Field or method id depending on whether the method handle type is an accessor or a method invoker
    field_or_method_id: u16,
    _unused2: u16,
};

const MethodHandleTypeCode = enum(u16) {
    StaticPut = 0x00,
    StaticGet = 0x01,
    InstancePut = 0x02,
    InstanceGet = 0x03,
    InvokeStatic = 0x04,
    InvokeInstance = 0x05,
    InvokeConstructor = 0x06,
    InvokeDirect = 0x07,
    InvokeInterface = 0x08,
};

const ClassDataItem = struct {
    static_fields_size: uleb128,
    instance_fields_size: uleb128,
    direct_methods_size: uleb128,
    virtual_methods_size: uleb128,
    static_fields: []EncodedField,
    instance_fields: []EncodedField,
    direct_methods: []EncodedMethod,
    virtual_methods: []EncodedMethod,
};

const EncodedField = struct {
    field_idx_off: uleb128,
    access_flags: uleb128,
};

const EncodedMethod = struct {
    method_idx_diff: uleb128,
    access_flags: uleb128,
    code_off: uleb128,
};

const TypeList = struct {
    size: u32,
    list: []TypeItem,

    pub fn read(reader: anytype, allocator: std.mem.Allocator) !TypeList {
        const size = try reader.readInt(u32, .little);
        var list = try allocator.alloc(TypeItem, size);
        errdefer allocator.free(list);
        for (list) |*type_item| {
            type_item.* = try TypeItem.read(reader);
        }
        return .{
            .size = size,
            .list = list,
        };
    }
};

const TypeItem = struct {
    type_idx: u16,

    pub fn read(reader: anytype) !TypeItem {
        return TypeItem{
            .type_idx = try reader.readInt(u16, .little),
        };
    }
};

pub const CodeItem = struct {
    registers_size: u16,
    ins_size: u16,
    outs_size: u16,
    tries_size: u16,
    debug_info_off: u32,
    insns_size: u32,
    insns: []u16,
    tries: ?[]TryItem,
    handlers: ?EncodedCatchHandlerList,

    pub fn format(code_item: CodeItem, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Registers: {}, In: {}, Out: {}, Tries: {}, Debug Info Offset: {}\n", .{
            code_item.registers_size,
            code_item.ins_size,
            code_item.outs_size,
            code_item.tries_size,
            code_item.debug_info_off,
        });
        var stream = std.io.fixedBufferStream(std.mem.sliceAsBytes(code_item.insns));
        const reader = stream.reader();
        while (Operation.read(reader) catch null) |insn| {
            try writer.print("\t{}\n", .{insn});
        }
    }

    pub fn read(reader: anytype, allocator: std.mem.Allocator) !CodeItem {
        const registers_size = try reader.readInt(u16, .little);
        const ins_size = try reader.readInt(u16, .little);
        const outs_size = try reader.readInt(u16, .little);
        const tries_size = try reader.readInt(u16, .little);
        const debug_info_off = try reader.readInt(u32, .little);
        const insns_size = try reader.readInt(u32, .little);
        const insns = try allocator.alloc(u16, insns_size);
        for (insns) |*ins| {
            ins.* = try reader.readInt(u16, .little);
        }
        if (insns_size != 0 and insns_size % 2 != 0) try reader.skipBytes(2, .{});
        const tries = tries: {
            if (tries_size != 0) {
                const tries = try allocator.alloc(TryItem, tries_size);
                for (tries) |*t| {
                    t.* = try TryItem.read(reader);
                }
                break :tries tries;
            } else {
                break :tries null;
            }
        };
        const handlers = handlers: {
            if (tries_size != 0) {
                break :handlers try EncodedCatchHandlerList.read(reader, allocator);
            } else {
                break :handlers null;
            }
        };

        return .{
            .registers_size = registers_size,
            .ins_size = ins_size,
            .outs_size = outs_size,
            .tries_size = tries_size,
            .debug_info_off = debug_info_off,
            .insns_size = insns_size,
            .insns = insns,
            .tries = tries,
            .handlers = handlers,
        };
    }
};

const TryItem = struct {
    start_addr: u32,
    insn_count: u16,
    handler_off: u16,

    pub fn read(reader: anytype) !TryItem {
        const start_addr = try reader.readInt(u32, .little);
        const insn_count = try reader.readInt(u16, .little);
        const handler_off = try reader.readInt(u16, .little);
        return .{
            .start_addr = start_addr,
            .insn_count = insn_count,
            .handler_off = handler_off,
        };
    }
};

const EncodedCatchHandlerList = struct {
    size: uleb128,
    list: []EncodedCatchHandler,

    pub fn read(reader: anytype, allocator: std.mem.Allocator) !EncodedCatchHandlerList {
        const size = try std.leb.readULEB128(u32, reader);
        const list = try allocator.alloc(EncodedCatchHandler, size);
        for (list) |*handler| {
            handler.* = try EncodedCatchHandler.read(reader, allocator);
        }
        return .{
            .size = size,
            .list = list,
        };
    }
};

const EncodedCatchHandler = struct {
    size: sleb128,
    handlers: []EncodedTypeAddrPair,
    catch_all_addr: ?uleb128,

    pub fn read(reader: anytype, allocator: std.mem.Allocator) !EncodedCatchHandler {
        const size = try std.leb.readILEB128(sleb128, reader);
        const type_addr_pairs = try allocator.alloc(EncodedTypeAddrPair, @intCast(if (size < 0) -size else size));
        for (type_addr_pairs) |*pair| {
            pair.* = try EncodedTypeAddrPair.read(reader);
        }
        const catch_all_addr = if (size < 0) try std.leb.readULEB128(u32, reader) else null;
        return .{
            .size = size,
            .handlers = type_addr_pairs,
            .catch_all_addr = catch_all_addr,
        };
    }
};

const EncodedTypeAddrPair = struct {
    type_idx: uleb128,
    addr: uleb128,

    pub fn read(reader: anytype) !EncodedTypeAddrPair {
        const t = try std.leb.readULEB128(u32, reader);
        const addr = try std.leb.readULEB128(u32, reader);
        return .{
            .type_idx = t,
            .addr = addr,
        };
    }
};

const DebugInfoItem = struct {
    line_start: uleb128,
    parameters_size: uleb128,
    parameter_names: []uleb128p1,
};

const DebugInfoItemBytes = enum(u8) {
    EndSequence = 0x00,
    AdvancePC = 0x01,
    AdvanceLine = 0x02,
    StartLocal = 0x03,
    StartLocalExtended = 0x04,
    EndLocal = 0x05,
    RestartLocal = 0x06,
    SetPrologueEnd = 0x07,
    SetEpilogueBegin = 0x08,
    SetFile = 0x09,
};

const AnnotationsDirectoryItem = struct {
    class_annotations_off: u32,
    fields_size: u32,
    annotated_methods_size: u32,
    annotated_parameters_size: u32,
    field_annotations: ?[]FieldAnnotation,
    method_annotations: ?[]MethodAnnotation,
    parameter_annotations: ?[]ParameterAnnotation,
};

const FieldAnnotation = struct {
    field_idx: u32,
    annotations_off: u32,
};

const MethodAnnotation = struct {
    method_idx: u32,
    annotations_off: u32,
};

const ParameterAnnotation = struct {
    parameter_idx: u32,
    annotations_off: u32,
};

const AnnotationSetRefList = struct {
    size: u32,
    list: []AnnotationSetRefItem,
};

const AnnotationSetRefItem = struct {
    annotations_off: u32,
};

const AnnotationSetItem = struct {
    size: u32,
    entries: []AnnotationOffItem,
};

const AnnotationOffItem = struct {
    annotation_off: u32,
};

const AnnotationItem = struct {
    visibility: Visibility,
    annotation: EncodedAnnotation,
};

const Visibility = enum(u8) {
    Build = 0x00,
    Runtime = 0x01,
    System = 0x02,
};

const EncodedArrayItem = struct {
    value: EncodedArray,
};

const HiddenapiClassDataItem = struct {
    size: u32,
    offsets: []u32,
    flags: []uleb128,
};

const FlagType = enum(u8) {
    Whitelist = 0,
    Greylist = 1,
    Blacklist = 2,
    GreylistMaxO = 3,
    GreylistMaxP = 4,
    GreylistMaxQ = 5,
    GreylistMaxR = 6,
};
