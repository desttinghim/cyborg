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

const std = @import("std");
