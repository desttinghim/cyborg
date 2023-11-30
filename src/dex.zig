//! The DEX executable file format.

const std = @import("std");

pub const Operation = union(Tag) {
    nop: u8,
    move: vAvB,
    @"move/from16": vAAvBBBB,
    @"move/16": vAAAAvBBBB,
    @"move-wide": vAvB,
    @"move-wide/from16": vAAvBBBB,
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
    @"cmpl-float": vAAvBBvCC,
    @"cmpg-float": vAAvBBvCC,
    @"cmpl-double": vAAvBBvCC,
    @"cmpg-double": vAAvBBvCC,
    @"cmp-long": vAAvBBvCC,
    @"if-eq",
    @"if-ne",
    @"if-lt",
    @"if-ge",
    @"if-gt",
    @"if-le",
    @"ifz-eq": vAApBBBB,
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
    iget: vAvBcCCCC,
    @"iget-wide": vAvBcCCCC,
    @"iget-object": vAvBcCCCC,
    @"iget-boolean": vAvBcCCCC,
    @"iget-byte": vAvBcCCCC,
    @"iget-char": vAvBcCCCC,
    @"iget-short": vAvBcCCCC,
    iput: vAvBcCCCC,
    @"iput-wide": vAvBcCCCC,
    @"iput-object": vAvBcCCCC,
    @"iput-boolean": vAvBcCCCC,
    @"iput-byte": vAvBcCCCC,
    @"iput-char": vAvBcCCCC,
    @"iput-short": vAvBcCCCC,
    sget: vAAcBBBB,
    @"sget-wide": vAAcBBBB,
    @"sget-object": vAAcBBBB,
    @"sget-boolean": vAAcBBBB,
    @"sget-byte": vAAcBBBB,
    @"sget-char": vAAcBBBB,
    @"sget-short": vAAcBBBB,
    sput: vAAcBBBB,
    @"sput-wide",
    @"sput-object",
    @"sput-boolean",
    @"sput-byte",
    @"sput-char": vAAcBBBB,
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
    @"neg-int": vAvB,
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
    @"sub-int": vAAvBBvCC,
    @"mul-int",
    @"div-int",
    @"rem-int": vAAvBBvCC,
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
        @"move-wide" = 0x04,
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
    pub const vAAcBBBB = vAAvBBBB;
    pub const vAApBBBB = vAAvBBBB;
    pub const vAAAAvBBBB = struct { u16, u16 };
    pub const vAA = struct { u8 };
    pub const vAlitB = struct { u4, u4 };
    pub const vAAlitBBBB = struct { u8, u16 };
    pub const vAAlitBBBBBBBB = struct { u8, u32 };
    pub const vAAlitBBBBBBBBBBBBBBBB = struct { u8, u32 };
    pub const vAAcBBBBBBBB = struct { u8, u32 };
    pub const vAvBcCCCC = struct { u8, u8, u16 };
    pub const vAvBBBBvCvDvEvFvG = struct { u4, u16, u4, u4, u4, u4, u4 };
    pub const vAAvBBBBvCCCC = struct { u8, u16, u16 };
    pub const vAAvBBvCC = struct { u8, u8, u8 };

    pub fn format(operation: Operation, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        switch (operation) {
            .nop => |byte| {
                const psuedo_opcode = switch (byte) {
                    0x1 => "(packed-switch)",
                    0x2 => "(sparse-switch)",
                    0x3 => "(fill-array-data)",
                    else => "",
                };
                try writer.print("{s:<20} {x:>4} {s:<20}", .{ @tagName(operation), byte, psuedo_opcode });
            },
            .move => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"move/16" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"move-wide" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"move-wide/from16" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"move-wide/16" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"move-result-object" => |args| {
                try writer.print("{s:<20} {}", .{ @tagName(operation), args[0] });
            },
            .@"return-object" => |args| {
                try writer.print("{s:<20} {}", .{ @tagName(operation), args[0] });
            },
            .@"cmpg-double" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"ifz-eq" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"iput-wide" => |args| {
                try writer.print("{s:<20} {} {} {}", .{ @tagName(operation), args[0], args[1], args[2] });
            },
            .@"sget-object" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"sget-byte" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
            },
            .@"sput-char" => |args| {
                try writer.print("{s:<20} {} {}", .{ @tagName(operation), args[0], args[1] });
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
            .@"sub-int" => |args| {
                try writer.print("{s:<20} {} {} {}", .{ @tagName(operation), args[0], args[1], args[2] });
            },
            .@"rem-int" => |args| {
                try writer.print("{s:<20} {} {} {}", .{ @tagName(operation), args[0], args[1], args[2] });
            },
            else => |tag| {
                try writer.print("{s:<20}", .{@tagName(tag)});
            },
        }
    }

    pub fn read(reader: anytype) !Operation {
        const op = try reader.readEnum(Tag, .little); // 1 byte
        const byte = try reader.readByte();
        switch (op) {
            .nop => {
                return .{ .nop = byte };
            },
            .move => {
                const a: u4 = @truncate(byte & 0xF);
                const b: u4 = @truncate((byte & 0xF0) >> 4);
                return .{ .move = .{ a, b } };
            },
            .@"move/16" => {
                const a = try reader.readInt(u16, .little);
                const b = try reader.readInt(u16, .little);
                return .{ .@"move/16" = .{ a, b } };
            },
            .@"move/from16" => {
                const b = try reader.readInt(u16, .little);
                return .{ .@"move/from16" = .{ byte, b } };
            },
            .@"move-wide" => {
                const a: u4 = @truncate(byte & 0xF);
                const b: u4 = @truncate((byte & 0xF0) >> 4);
                return .{ .@"move-wide" = .{ a, b } };
            },
            .@"move-wide/from16" => {
                const b = try reader.readInt(u16, .little);
                return .{ .@"move-wide/from16" = .{ byte, b } };
            },
            .@"move-result-object" => {
                return .{ .@"move-result-object" = .{byte} };
            },
            .@"return-void" => {
                return .@"return-void";
            },
            .@"return-object" => {
                return .{ .@"return-object" = .{byte} };
            },
            .@"cmpg-double" => {
                const a = byte;
                const b = try reader.readInt(u8, .little);
                const c = try reader.readInt(u8, .little);
                return .{ .@"cmpg-double" = .{ a, b, c } };
            },
            .@"ifz-eq" => {
                const a = try reader.readInt(u8, .little);
                const b = try reader.readInt(u16, .little);
                return .{ .@"ifz-eq" = .{ a, b } };
            },
            .@"iget-byte" => {
                const a: u4 = @truncate(byte & 0xF);
                const b: u4 = @truncate((byte & 0xF0) >> 4);
                const c = try reader.readInt(u16, .little);
                return .{ .@"iget-byte" = .{ a, b, c } };
            },
            .@"iput-wide" => {
                const a: u4 = @truncate(byte & 0xF);
                const b: u4 = @truncate((byte & 0xF0) >> 4);
                const c = try reader.readInt(u16, .little);
                return .{ .@"iput-wide" = .{ a, b, c } };
            },
            .@"sget-object" => {
                const b = try reader.readInt(u16, .little);
                return .{ .@"sget-object" = .{ byte, b } };
            },
            .@"sget-byte" => {
                const b = try reader.readInt(u16, .little);
                return .{ .@"sget-byte" = .{ byte, b } };
            },
            .@"sput-char" => {
                const b = try reader.readInt(u16, .little);
                return .{ .@"sput-char" = .{ byte, b } };
            },
            .@"invoke-direct" => {
                const a: u4 = @truncate((byte & 0xF0) >> 4);
                const g: u4 = @truncate((byte & 0xF));
                const b: u16 = try reader.readInt(u16, .little);
                const third = try reader.readInt(u16, .little);
                const c: u4 = @truncate(third);
                const d: u4 = @truncate(third >> 4);
                const e: u4 = @truncate(third >> 8);
                const f: u4 = @truncate(third >> 12);
                return .{ .@"invoke-direct" = .{ a, b, c, d, e, f, g } };
            },
            .@"neg-int" => {
                const a: u4 = @truncate(byte & 0xF);
                const b: u4 = @truncate((byte & 0xF0) >> 4);
                return .{ .@"neg-int" = .{ a, b } };
            },
            .@"sub-int" => {
                const b = try reader.readInt(u8, .little);
                const c = try reader.readInt(u8, .little);
                return .{ .@"sub-int" = .{ byte, b, c } };
            },
            .@"rem-int" => {
                const b = try reader.readInt(u8, .little);
                const c = try reader.readInt(u8, .little);
                return .{ .@"rem-int" = .{ byte, b, c } };
            },
            else => {
                std.log.err("Unimplemented operation {}", .{op});
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

/// Container type for working with the DEX file format
/// See `Dalvik.Module` for an in-memory representation that allows
pub const Dex = struct {
    /// The DEX file read into memory that we will be querying
    file_buffer: []const u8,
    /// The header of the file parsed into a struct. Contains offsets and sizes for the
    /// many constant pools in the Dalvik EXecutable format.
    header: HeaderItem,

    /// Caller owns `file_buffer` memory. The lifetime of `file_buffer` should match or exceed
    /// the lifetime of the `Dex` struct.
    pub fn initFromSlice(file_buffer: []const u8) !Dex {
        // Verify the passed file is a valid DEX file by parsing the header
        const header = try HeaderItem.parse(file_buffer);
        return Dex{
            .file_buffer = file_buffer,
            .header = header,
        };
    }

    /// Caller owns memory stored in `file_buffer`.
    /// Add `defer allocator.free(dex.file_buffer);` to your code to clean up properly.
    pub fn initFromReader(allocator: std.mem.Allocator, reader: anytype) !Dex {
        const file = try reader.readAllAlloc(allocator, std.math.maxInt(u32));
        errdefer allocator.free(file);

        return try initFromSlice(file);
    }

    pub const CreateOptions = struct {
        endian: std.builtin.Endian = .little,
    };
    /// Writes a new DEX file into memory from the passed `Dalvik.Module`.
    // pub fn createFromModule(allocator: std.mem.Allocator, module: dalvik.Module, opt: CreateOptions) !Dex {
    //     var size_estimate: usize = 0;

    //     // ArrayList of data section, to be constructed
    //     var data = std.ArrayList(u8).init(allocator);
    //     errdefer data.deinit();
    //     const data_writer = data.writer();

    //     // Construct string pool and string id list. String data is in the data section,
    //     // while string ids are in the string_id section.
    //     const string_data_offset = data.items.len;
    //     var string_data_offsets = std.StringArrayHashMap(u32).init(allocator);
    //     errdefer string_data_offset.deinit();
    //     var string_iter = module.getStringIterator();
    //     while (string_iter.next()) |string| {
    //         const current_offset = data.items.len;
    //         // Save offset into arrayhashmap and assert that the current string
    //         // does not already exist.
    //         try string_data_offsets.putNoClobber(string, current_offset);

    //         const count = try std.unicode.utf8CountCodepoints();
    //         // Write the length of the string in unicode codepoints
    //         // TODO: the DEX file spec says the count is in utf16 codepoints, what
    //         // does this mean?
    //         try std.leb.writeULEB128(data_writer, count);
    //         // Write the string itself
    //         try data.appendSlice(string);
    //     }

    //     // Construct type id list
    //     const type_offset = data.items.len;
    //     var type_offsets = std.AutoArrayHashMap(dalvik.TypeValue, u32).init(allocator);
    //     errdefer type_offsets.deinit();
    //     var type_iter = module.getTypeIterator();
    //     while (type_iter.next()) |t| {
    //         const current_offset = data.items.len;
    //         type_offsets.putNoClobber(t, current_offset);

    //         const string = try t.getString(allocator);
    //         defer allocator.free(string);
    //         const string_index = string_data_offset.getIndex(string) orelse return error.MissingTypeString;

    //         try data_writer.writeInt(u32, string_index, opt.endian);
    //     }

    //     // Construct proto list
    //     var proto_offsets = std.AutoArrayHashMap(dalvik.Method, u32).init(allocator);
    //     errdefer proto_offsets.deinit();

    //     // Construct field id list
    //     var field_offsets = std.AutoArrayHashMap(dalvik.Field, u32).init(allocator);
    //     errdefer field_offsets.deinit();

    //     // Construct method id list
    //     var method_offsets = std.AutoArrayHashMap(dalvik.Method, u32).init(allocator);
    //     errdefer method_offsets.deinit();

    //     // Construct class definition list
    //     var class_offsets = std.AutoArrayHashMap(dalvik.Class, u32).init(allocator);
    //     errdefer class_offsets.deinit();

    //     // Construct call site id list
    //     // TODO: WTF is a call site in a DEX file?
    //     var call_site_offsets = std.AutoArrayHashMap(dalvik.CallSite, u32).init(allocator);
    //     errdefer call_site_offsets.deinit();

    //     // Construct method handle list
    //     // TODO: WTF is a method handle in a DEX file?
    //     var method_handle_offsets = std.AutoArrayHashMap(dalvik.MethodHandle, u32).init(allocator);
    //     errdefer method_handle_offsets.deinit();

    //     // Construct map
    //     const map_offset = data.items.len;
    //     var map = std.ArrayList(MapItem).init(allocator);
    //     {
    //         // Should be 12 items long and in order
    //         // 1. Header
    //         try map.append(.{
    //             .type = .header_item,
    //             .size = 1,
    //             .offset = 0,
    //         });
    //         size_estimate += 0x70;

    //         // 2. String ids
    //         try map.append(.{
    //             .type = .string_id_item,
    //             .size = string_data_offsets.count(),
    //             .offset = size_estimate,
    //         });
    //         size_estimate += 0x04 * string_data_offsets.count();

    //         // 3. Type ids
    //         try map.append(.{
    //             .type = .type_id_item,
    //             .size = type_offsets.count(),
    //             .offset = size_estimate,
    //         });
    //         size_estimate += 0x04 * string_data_offsets.count();

    //         // 4. Proto ids
    //         try map.append(.{
    //             .type = .proto_id_item,
    //             .size = proto_offsets.count(),
    //             .offset = size_estimate,
    //         });
    //         size_estimate += 0x0c * proto_offsets.count();

    //         // 5. Field ids
    //         try map.append(.{
    //             .type = .field_id_item,
    //             .size = field_offsets.count(),
    //             .offset = size_estimate,
    //         });
    //         size_estimate += 0x0c * field_offsets.count();

    //         // 6. Method ids
    //         try map.append(.{
    //             .type = .method_id_item,
    //             .size = method_offsets.count(),
    //             .offset = size_estimate,
    //         });
    //         size_estimate += 0x0c * method_offsets.count();

    //         // 7. Class definitions
    //         try map.append(.{
    //             .type = .method_id_item,
    //             .size = method_offsets.count(),
    //             .offset = size_estimate,
    //         });
    //         size_estimate += 0x0c * method_offsets.count();

    //         // 8. Call site ids
    //         // 9. Method handles
    //         // 10. Map list
    //         // 11. Type list
    //         // 12. Annotation set ref list
    //         // 13. Annotation set item
    //     }

    //     // Construct constant pools
    //     var constant_pools = std.ArrayList(u8).init(allocator);
    //     errdefer constant_pools.deinit();
    //     const pool_writer = constant_pools.writer();

    //     // Write magic bytes
    //     // Reserve space for checksum, save slice
    //     // Reserve space for SHA1 signature, save slice
    //     // Write header size (defined to be a constant 0x70)
    //     // Write endian constant

    //     // Linking: size and offset (0 size if none)

    //     return Dex{
    //         .file_buffer = file_buffer,
    //         .header = header,
    //     };
    // }

    pub fn getString(dex: Dex, id: u32) ![]const u8 {
        if (id >= dex.header.string_ids_size) return error.StringIdOutOfBounds;
        const id_offset = dex.header.string_ids_off + (id * 4);
        const string_offset = std.mem.readInt(u32, dex.file_buffer[id_offset..][0..4], dex.header.endian_tag);
        const to_read = dex.file_buffer[string_offset..];
        var fbs = std.io.fixedBufferStream(to_read);
        const reader = fbs.reader();
        const stored_codepoints = try std.leb.readULEB128(u32, reader);
        const pos = fbs.getPos() catch unreachable;
        const data = std.mem.sliceTo(to_read[pos..], 0);

        // Assert that the number of stored codepoints equals the utf8 codepoint count
        const codepoints = try std.unicode.utf8CountCodepoints(data);
        if (stored_codepoints != codepoints) {
            std.log.err("stored codepoints: {}, calculated codepoints: {}", .{
                stored_codepoints,
                codepoints,
            });
            return error.MismatchedCodepointCount;
        }

        return data;
    }

    pub fn getType(dex: Dex, id: u32) !u32 {
        const offset = dex.header.type_ids_off + (id * 0x04);
        if (offset > dex.file_buffer.len) return error.OutOfBounds;
        const type_slice = dex.file_buffer[offset..][0..4];
        const string_index = std.mem.readInt(u32, type_slice, dex.header.endian_tag);
        return string_index;
    }

    pub fn getTypeString(dex: Dex, id: u32) ![]const u8 {
        return try dex.getString(try dex.getType(id));
    }

    pub fn getProto(dex: Dex, id: u32) !ProtoIdItem {
        const offset = dex.header.proto_ids_off + (id * (3 * 4));
        if (offset >= dex.file_buffer.len) return error.OutOfBounds;

        const proto_slice = dex.file_buffer[offset..][0..0xc];

        const shorty_idx = std.mem.readInt(u32, proto_slice[0..4], dex.header.endian_tag);
        const return_type_idx = std.mem.readInt(u32, proto_slice[4..8], dex.header.endian_tag);
        const parameters_off = std.mem.readInt(u32, proto_slice[8..12], dex.header.endian_tag);
        return ProtoIdItem{
            .shorty_idx = shorty_idx,
            .return_type_idx = return_type_idx,
            .parameters_off = parameters_off,
        };
    }

    pub const TypeListIterator = struct {
        dex: *const Dex,
        /// Offset from the beginning of the file to the
        /// TypeList data. Does not include the size uleb128 size that
        /// precedes encoded arrays.
        offset: u32,
        size: u32,
        index: u32,
        /// Returns an index into the type list
        pub fn next(iter: *TypeListIterator) ?u32 {
            if (iter.index >= iter.size) return null;
            const offset = iter.offset + 4 + iter.index * 2;
            const slice = iter.dex.file_buffer[offset..][0..2];
            const t = std.mem.readInt(u16, slice, iter.dex.header.endian_tag);
            iter.index += 1;
            return t;
        }
    };
    pub fn typeListIterator(dex: *const Dex, type_list_offset: u32) !?TypeListIterator {
        if (type_list_offset == 0) return null;
        if (type_list_offset > dex.file_buffer.len) return error.OutOfBounds;
        const to_read = dex.file_buffer[type_list_offset..][0..4];
        const size = std.mem.readInt(u32, to_read, dex.header.endian_tag);

        return .{
            .dex = dex,
            .offset = type_list_offset,
            .index = 0,
            .size = size,
        };
    }

    pub fn getField(dex: Dex, field_id: u32) !FieldIdItem {
        if (field_id > dex.header.field_ids_size) return error.OutOfBounds;
        const offset = dex.header.field_ids_off + field_id * 8;
        if (offset > dex.file_buffer.len) return error.OutOfBounds;
        const slice = dex.file_buffer[offset..][0..8];
        return .{
            .class_idx = std.mem.readInt(u16, slice[0..2], dex.header.endian_tag),
            .type_idx = std.mem.readInt(u16, slice[2..][0..2], dex.header.endian_tag),
            .name_idx = std.mem.readInt(u32, slice[4..][0..4], dex.header.endian_tag),
        };
    }

    pub fn getMethod(dex: Dex, method_id: u32) !MethodIdItem {
        if (method_id > dex.header.method_ids_size) return error.OutOfBounds;
        const offset = dex.header.method_ids_off + method_id * 8;
        if (offset > dex.file_buffer.len) return error.OutOfBounds;
        const slice = dex.file_buffer[offset..][0..8];
        return .{
            .class_idx = std.mem.readInt(u16, slice[0..2], dex.header.endian_tag),
            .proto_idx = std.mem.readInt(u16, slice[2..][0..2], dex.header.endian_tag),
            .name_idx = std.mem.readInt(u32, slice[4..][0..4], dex.header.endian_tag),
        };
    }

    pub fn getClassDef(dex: Dex, class_def: u32) !ClassDefItem {
        if (class_def > dex.header.class_defs_size) return error.OutOfBounds;
        const offset = dex.header.class_defs_off + class_def * 8;
        if (offset > dex.file_buffer.len) return error.OutOfBounds;
        const slice = dex.file_buffer[offset..][0..32];
        return .{
            .class_idx = std.mem.readInt(u32, slice[0..4], dex.header.endian_tag),
            .access_flags = @bitCast(std.mem.readInt(u32, slice[4..][0..4], dex.header.endian_tag)),
            .superclass_idx = std.mem.readInt(u32, slice[8..][0..4], dex.header.endian_tag),
            .interfaces_off = std.mem.readInt(u32, slice[12..][0..4], dex.header.endian_tag),
            .source_file_idx = std.mem.readInt(u32, slice[16..][0..4], dex.header.endian_tag),
            .annotations_off = std.mem.readInt(u32, slice[20..][0..4], dex.header.endian_tag),
            .class_data_off = std.mem.readInt(u32, slice[24..][0..4], dex.header.endian_tag),
            .static_values_off = std.mem.readInt(u32, slice[28..][0..4], dex.header.endian_tag),
        };
    }

    // pub fn getMethod(dex: Dex, method_id: usize) MethodIdItem {}

    pub const MapIterator = struct {
        dex: *const Dex,
        list_size: usize,
        index: usize,
        pub fn next(iter: *MapIterator) ?MapItem {
            if (iter.index >= iter.list_size) return null;
            const offset = iter.dex.header.map_off + 4 + (iter.index * 12);
            iter.index += 1;
            return MapItem.fromSlice(iter.dex.file_buffer[offset..][0..12], iter.dex.header.endian_tag);
        }
    };
    pub fn mapIterator(dex: *const Dex) MapIterator {
        const offset = dex.header.map_off;
        const size_slice = dex.file_buffer[offset..][0..4];
        const list_size = std.mem.readInt(u32, size_slice, dex.header.endian_tag);
        return .{
            .dex = dex,
            .list_size = list_size,
            .index = 0,
        };
    }

    pub const StringIterator = struct {
        dex: *const Dex,
        index: u32,
        pub fn next(iter: *StringIterator) ?[]const u8 {
            if (iter.index >= iter.dex.header.string_ids_size) return null;
            const string = iter.dex.getString(iter.index) catch return null;
            iter.index += 1;
            return string;
        }
    };
    pub fn stringIterator(dex: *const Dex) StringIterator {
        return .{
            .dex = dex,
            .index = 0,
        };
    }

    pub const TypeIterator = struct {
        dex: *const Dex,
        index: u32,
        /// Returns an index into the string pool. The type is encoded in the string.
        pub fn next(iter: *TypeIterator) ?u32 {
            if (iter.index >= iter.dex.header.type_ids_size) return null;
            const t = iter.dex.getType(iter.index) catch return null;
            iter.index += 1;
            return t;
        }
    };
    pub fn typeIterator(dex: *const Dex) TypeIterator {
        return .{
            .dex = dex,
            .index = 0,
        };
    }

    pub const ProtoIterator = struct {
        dex: *const Dex,
        index: u32,
        pub fn next(iter: *ProtoIterator) ?ProtoIdItem {
            if (iter.index >= iter.dex.header.proto_ids_size) return null;
            const proto = iter.dex.getProto(iter.index) catch return null;
            iter.index += 1;
            return proto;
        }
    };
    pub fn protoIterator(dex: *const Dex) ProtoIterator {
        return .{
            .dex = dex,
            .index = 0,
        };
    }

    pub const FieldIterator = struct {
        dex: *const Dex,
        index: u32,
        pub fn next(iter: *FieldIterator) ?FieldIdItem {
            if (iter.index >= iter.dex.header.field_ids_size) return null;
            const field = iter.dex.getField(iter.index) catch return null;
            iter.index += 1;
            return field;
        }
    };
    pub fn fieldIterator(dex: *const Dex) FieldIterator {
        return .{
            .dex = dex,
            .index = 0,
        };
    }

    pub const MethodIterator = struct {
        dex: *const Dex,
        index: u32,
        pub fn next(iter: *MethodIterator) ?MethodIdItem {
            if (iter.index >= iter.dex.header.method_ids_size) return null;
            const method = iter.dex.getMethod(iter.index) catch return null;
            iter.index += 1;
            return method;
        }
    };
    pub fn methodIterator(dex: *const Dex) MethodIterator {
        return .{
            .dex = dex,
            .index = 0,
        };
    }

    pub const ClassDefIterator = struct {
        dex: *const Dex,
        index: u32,
        pub fn next(iter: *ClassDefIterator) ?ClassDefItem {
            if (iter.index >= iter.dex.header.class_defs_size) return null;
            const class_def = iter.dex.getClassDef(iter.index) catch return null;
            iter.index += 1;
            return class_def;
        }
    };
    pub fn classDefIterator(dex: *const Dex) ClassDefIterator {
        return .{
            .dex = dex,
            .index = 0,
        };
    }

    // pub fn writeFieldString(dex: Dex, writer: anytype, field_id: u32) !void {
    //     const id = dex.field_ids.items[field_id];
    //     const class_str = try dex.getString(dex.string_ids.items[dex.type_ids.items[id.class_idx].descriptor_idx]);
    //     const type_str = try dex.getString(dex.string_ids.items[dex.type_ids.items[id.type_idx].descriptor_idx]);
    //     const name_str = try dex.getString(dex.string_ids.items[id.name_idx]);
    //     try std.fmt.format(writer, "{s}.{s}: {s}\n", .{ class_str.data, name_str.data, type_str.data });
    // }

    // pub fn writeMethodString(dex: Dex, alloc: std.mem.Allocator, writer: anytype, method_id: u32) !void {
    //     const id = dex.method_ids.items[method_id];
    //     const class_str = try dex.getString(dex.string_ids.items[dex.type_ids.items[id.class_idx].descriptor_idx]);
    //     const name_str = try dex.getString(dex.string_ids.items[id.name_idx]);
    //     const prototype = try dex.getPrototype(dex.proto_ids.items[id.proto_idx], alloc);
    //     try std.fmt.format(writer, "{s}.{s}(", .{ class_str.data, name_str.data });
    //     if (prototype.parameters) |parameters| {
    //         for (try dex.getTypeStringList(parameters, alloc)) |type_string| {
    //             try std.fmt.format(writer, "{s}", .{type_string.data});
    //         }
    //     }
    //     try std.fmt.format(writer, "){s}\n", .{prototype.return_type.data});
    // }
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

pub const AccessFlags = packed struct(u32) {
    // Byte 1
    Public: bool = false,
    Private: bool = false,
    Protected: bool = false,
    Static: bool = false,
    Final: bool = false,
    Synchronized: bool = false,
    /// Volatile for fields, bridge for methods
    VolatileOrBridge: bool = false,
    /// Transient for fields, varargs for methods
    TransientOrVarargs: bool = false,

    // Byte 2
    Native: bool = false,
    Interface: bool = false,
    Abstract: bool = false,
    Strict: bool = false,
    Synthetic: bool = false,
    Annotation: bool = false,
    Enum: bool = false,
    _unused: bool = false,

    // Byte 3 & 4
    Constructor: bool = false,
    DeclaredSynchronized: bool = false,
    _unused2: u14 = 0,

    pub fn format(access_flags: AccessFlags, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (access_flags.Public) _ = try writer.write("public ");
        if (access_flags.Private) _ = try writer.write("private ");
        if (access_flags.Protected) _ = try writer.write("protected ");
        if (access_flags.Static) _ = try writer.write("static ");
        if (access_flags.Final) _ = try writer.write("final ");
        if (access_flags.Synchronized) _ = try writer.write("synchronized ");
        if (access_flags.VolatileOrBridge) _ = try writer.write("volatile/bridge ");
        if (access_flags.TransientOrVarargs) _ = try writer.write("transient/varargs ");
        if (access_flags.Native) _ = try writer.write("native ");
        if (access_flags.Interface) _ = try writer.write("interface ");
        if (access_flags.Abstract) _ = try writer.write("abstract ");
        if (access_flags.Strict) _ = try writer.write("strict ");
        if (access_flags.Synthetic) _ = try writer.write("synthetic ");
        if (access_flags.Annotation) _ = try writer.write("annotation ");
        if (access_flags.Enum) _ = try writer.write("enum ");
        if (access_flags.Constructor) _ = try writer.write("constructor ");
        if (access_flags.DeclaredSynchronized) _ = try writer.write("declared synchronized ");
    }

    const FlagEnum = enum {
        public,
        private,
        protected,
        static,
        final,
        synchronized,
        @"volatile",
        bridge,
        transient,
        varargs,
        native,
        interface,
        abstract,
        strict,
        synthetic,
        annotation,
        @"enum",
        constructor,
        DeclaredSynchronized,
    };

    /// Takes an AccessFlags struct and a single token as input, and returns the AccessFlags
    /// struct with the additional flag from the parsed the token. Returns an error if the
    /// token is not a valid access flag.
    pub fn addFromString(access_flags: AccessFlags, string: []const u8) !AccessFlags {
        var updated = access_flags;
        var buffer: [256]u8 = undefined;
        const lower_string = std.ascii.lowerString(&buffer, string);
        var flag = std.meta.stringToEnum(FlagEnum, lower_string) orelse return error.NotAnAccessFlag;

        switch (flag) {
            .public => updated.Public = true,
            .private => updated.Private = true,
            .protected => updated.Protected = true,
            .static => updated.Static = true,
            .final => updated.Final = true,
            .synchronized => updated.Synchronized = true,
            .@"volatile", .bridge => updated.VolatileOrBridge = true,
            .transient, .varargs => updated.TransientOrVarargs = true,
            .native => updated.Native = true,
            .interface => updated.Interface = true,
            .abstract => updated.Abstract = true,
            .strict => updated.Strict = true,
            .synthetic => updated.Synthetic = true,
            .annotation => updated.Annotation = true,
            .@"enum" => updated.Enum = true,
            .constructor => updated.Constructor = true,
            .DeclaredSynchronized => updated.DeclaredSynchronized = true,
        }

        return updated;
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
    size: u32,
    values: []EncodedValue,
};

const EncodedAnnotation = struct {
    type_idx: u32,
    size: u32,
    size: u32,
    elements: []AnnotationElement,
};

const AnnotationElement = struct {
    name_idx: u32,
    value: EncodedValue,
};

const HeaderItem = struct {
    /// Dex file format version
    version: Version,
    /// adler32 checksum of the rest of the file (everything but magic and this field); used to detect file corruption
    checksum: u32,
    /// SHA-1 signature (hash) of the rest of the file (everything but magic, checksum, and this field); used to uniquely identify files
    signature: []const u8,
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

    pub const HeaderError = error{
        InvalidMagicBytes,
        UnknownFormatVersion,
        InvalidEndianTag,
        InvalidChecksum,
        InvalidSignature,
    };

    pub fn parse(slice: []const u8) !HeaderItem {
        if (!std.mem.eql(u8, DEX_FILE_MAGIC, slice[0..4])) {
            return error.InvalidMagicBytes;
        }
        const version_buf = slice[4..8];
        var version_opt: ?Version = null;
        if (std.mem.eql(u8, version_buf, "035\x00")) {
            version_opt = .@"035";
        } else if (std.mem.eql(u8, version_buf, "036\x00")) {
            version_opt = .@"036";
        } else if (std.mem.eql(u8, version_buf, "037\x00")) {
            version_opt = .@"037";
        } else if (std.mem.eql(u8, version_buf, "038\x00")) {
            version_opt = .@"038";
        } else if (std.mem.eql(u8, version_buf, "039\x00")) {
            version_opt = .@"039";
        } else {
            return error.UnknownFormatVersion;
        }
        const version = version_opt orelse return error.UnknownFormatVersion;
        const read_checksum = std.mem.readInt(u32, slice[8..12], .little);

        // Compute checksum
        const to_checksum = slice[12..];
        const calculated_checksum = std.hash.Adler32.hash(to_checksum);
        if (read_checksum != calculated_checksum) {
            std.log.err("checksum: file {} - calculated {}", .{
                read_checksum,
                calculated_checksum,
            });
            return error.InvalidChecksum;
        }

        const signature = slice[12..32];

        // Compute SHA1 signature
        const to_hash = to_checksum[20..];
        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(to_hash, &hash, .{});
        if (!std.mem.eql(u8, &hash, signature)) {
            std.log.err("File hash\t{}\n\texpected\t{}", .{
                std.fmt.fmtSliceHexUpper(&hash),
                std.fmt.fmtSliceHexUpper(signature),
            });
            return error.InvalidSignature;
        }

        const file_size = std.mem.readInt(u32, slice[32..36], .little);
        const header_size = std.mem.readInt(u32, slice[36..40], .little);
        const endianness: Endianness = @enumFromInt(std.mem.readInt(u32, slice[40..44], .little));
        const endian_tag: std.builtin.Endian = switch (endianness) {
            .Endian => .little,
            .ReverseEndian => .big,
            _ => return error.InvalidEndianTag,
        };
        const link_size = std.mem.readInt(u32, slice[44..48], endian_tag);
        const link_off = std.mem.readInt(u32, slice[48..52], endian_tag);
        const map_off = std.mem.readInt(u32, slice[52..56], endian_tag);
        const string_ids_size = std.mem.readInt(u32, slice[56..60], endian_tag);
        const string_ids_off = std.mem.readInt(u32, slice[60..64], endian_tag);
        const type_ids_size = std.mem.readInt(u32, slice[64..68], endian_tag);
        const type_ids_off = std.mem.readInt(u32, slice[68..72], endian_tag);
        const proto_ids_size = std.mem.readInt(u32, slice[72..76], endian_tag);
        const proto_ids_off = std.mem.readInt(u32, slice[76..80], endian_tag);
        const field_ids_size = std.mem.readInt(u32, slice[80..84], endian_tag);
        const field_ids_off = std.mem.readInt(u32, slice[84..88], endian_tag);
        const method_ids_size = std.mem.readInt(u32, slice[88..92], endian_tag);
        const method_ids_off = std.mem.readInt(u32, slice[92..96], endian_tag);
        const class_defs_size = std.mem.readInt(u32, slice[96..100], endian_tag);
        const class_defs_off = std.mem.readInt(u32, slice[100..104], endian_tag);
        const data_size = std.mem.readInt(u32, slice[104..108], endian_tag);
        const data_off = std.mem.readInt(u32, slice[108..112], endian_tag);
        return .{
            .version = version,
            .checksum = read_checksum,
            .signature = signature,
            .file_size = file_size,
            .header_size = header_size,
            .endian_tag = endian_tag,
            .link_size = link_size,
            .link_off = link_off,
            .map_off = map_off,
            .string_ids_size = string_ids_size,
            .string_ids_off = string_ids_off,
            .type_ids_size = type_ids_size,
            .type_ids_off = type_ids_off,
            .proto_ids_size = proto_ids_size,
            .proto_ids_off = proto_ids_off,
            .field_ids_size = field_ids_size,
            .field_ids_off = field_ids_off,
            .method_ids_size = method_ids_size,
            .method_ids_off = method_ids_off,
            .class_defs_size = class_defs_size,
            .class_defs_off = class_defs_off,
            .data_size = data_size,
            .data_off = data_off,
        };
    }

    pub fn read(seek: anytype, reader: anytype) !HeaderItem {
        _ = seek;
        var header: HeaderItem = undefined;
        var magic_buf: [4]u8 = undefined;

        if (try reader.read(&magic_buf) != header.magic.len) return error.UnexpectedEOF;
        if (!std.mem.eql(u8, &magic_buf, DEX_FILE_MAGIC[0..])) {
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
    size: u32,
    offset: u32,

    pub fn fromSlice(slice: []const u8, endian: std.builtin.Endian) MapItem {
        std.debug.assert(slice.len == 12);
        return .{
            .type = @enumFromInt(std.mem.readInt(u16, slice[0..2], endian)),
            .size = std.mem.readInt(u32, slice[4..8], endian),
            .offset = std.mem.readInt(u32, slice[8..12], endian),
        };
    }

    pub fn read(reader: anytype) !MapItem {
        const t = try reader.readEnum(TypeCode, .little);
        _ = try reader.readInt(u16, .little); // Read the unused bytes
        const size = try reader.readInt(u32, .little);
        const offset = try reader.readInt(u32, .little);
        return MapItem{
            .type = t,
            .size = size,
            .offset = offset,
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
    utf16_size: u32,
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
    static_fields: std.ArrayListUnmanaged(EncodedField),
    instance_fields: std.ArrayListUnmanaged(EncodedField),
    direct_methods: std.ArrayListUnmanaged(EncodedMethod),
    virtual_methods: std.ArrayListUnmanaged(EncodedMethod),

    pub fn read(alloc: std.mem.Allocator, reader: anytype) !ClassDataItem {
        const static_fields_size = try std.leb.readULEB128(u32, reader);
        const instance_fields_size = try std.leb.readULEB128(u32, reader);
        const direct_methods_size = try std.leb.readULEB128(u32, reader);
        const virtual_methods_size = try std.leb.readULEB128(u32, reader);

        var static_fields = try std.ArrayListUnmanaged(EncodedField).initCapacity(alloc, static_fields_size);
        var instance_fields = try std.ArrayListUnmanaged(EncodedField).initCapacity(alloc, instance_fields_size);
        var direct_methods = try std.ArrayListUnmanaged(EncodedMethod).initCapacity(alloc, direct_methods_size);
        var virtual_methods = try std.ArrayListUnmanaged(EncodedMethod).initCapacity(alloc, virtual_methods_size);

        for (0..static_fields_size) |_| {
            static_fields.appendAssumeCapacity(try EncodedField.read(reader));
        }
        for (0..instance_fields_size) |_| {
            instance_fields.appendAssumeCapacity(try EncodedField.read(reader));
        }
        for (0..direct_methods_size) |_| {
            direct_methods.appendAssumeCapacity(try EncodedMethod.read(reader));
        }
        for (0..virtual_methods_size) |_| {
            virtual_methods.appendAssumeCapacity(try EncodedMethod.read(reader));
        }

        return .{
            .static_fields = static_fields,
            .instance_fields = instance_fields,
            .direct_methods = direct_methods,
            .virtual_methods = virtual_methods,
        };
    }
};

const EncodedField = struct {
    /// Index into field_ids, encoded as difference from last item
    field_idx_diff: u32,
    access_flags: AccessFlags,

    pub fn read(reader: anytype) !EncodedField {
        const field_idx = try std.leb.readULEB128(u32, reader);
        const access_flags: AccessFlags = @bitCast(try std.leb.readULEB128(u32, reader));
        return .{
            .field_idx_diff = field_idx,
            .access_flags = access_flags,
        };
    }
};

const EncodedMethod = struct {
    /// Index into method_ids, encoded as difference from last item
    method_idx_diff: u32,
    access_flags: AccessFlags,
    code_off: u32,

    pub fn read(reader: anytype) !EncodedMethod {
        const method_idx = try std.leb.readULEB128(u32, reader);
        const access_flags: AccessFlags = @bitCast(try std.leb.readULEB128(u32, reader));
        const code_off = try std.leb.readULEB128(u32, reader);
        return .{
            .method_idx_diff = method_idx,
            .access_flags = access_flags,
            .code_off = code_off,
        };
    }
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

    pub fn deinit(code_item: CodeItem, allocator: std.mem.Allocator) void {
        allocator.free(code_item.insns);
        const tries = code_item.tries orelse return;
        allocator.free(tries);
    }

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
    size: u32,
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
    size: i32,
    handlers: []EncodedTypeAddrPair,
    catch_all_addr: ?u32,

    pub fn read(reader: anytype, allocator: std.mem.Allocator) !EncodedCatchHandler {
        const size = try std.leb.readILEB128(i32, reader);
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
    type_idx: u32,
    addr: u32,

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
    line_start: u32,
    parameters_size: u32,
    parameter_names: []u32,
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
    flags: []u32,
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
