//! The DEX executable file format.

const std = @import("std");

const Ops = enum(u16) {
    /// Waste cycles
    nop = 0x00_10,
    /// Move the contents of one non-object register to another.
    /// move vA, vB
    /// A: destination register (4 bits)
    /// B: source register (4 bits)
    move = 0x01_12,
    /// Move the contents of one non-object register to another.
    /// move/from16 vAA, vBBBB
    /// A: destination register (8 bits)
    /// B: source register (16 bits)
    move_from16 = 0x02_22,
    /// Move the contents of one non-object register to another.
    /// move/16 vAAAA, vBBBB
    /// A: destination register (16 bits)
    /// B: source register (16 bits)
    move_16 = 0x03_32,
    /// Move the contents of one register pair to another.
    /// NOTE: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
    /// move-wide vA, vB
    /// A: destination register pair (4 bits)
    /// B: source register pair (4 bits)
    move_wide = 0x04_12,
    /// Move the contents of one register pair to another.
    /// NOTE: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
    /// move-wide/from16 vAA, vBBBB
    /// A: destination register pair (8 bits)
    /// B: source register pair (16 bits)
    move_wide_from16 = 0x05_22,
    /// Move the contents of one register pair to another.
    /// NOTE: It is legal to move from vN to either vN-1 or vN+1, so implementations must arrange for both halves of a register pair to be read before anything is written.
    /// move-wide/16 vAAAA, vBBBB
    /// A: destination register pair (8 bits)
    /// B: source register pair (16 bits)
    move_wide_16 = 0x06_32,
    /// Move the contents of one object-bearing register to another.
    /// move-object vA, vB
    /// A: destination register (4 bits)
    /// B: source register (4 bits)
    move_object = 0x07_12,
    /// Move the contents of one object-bearing register to another.
    /// move-object/from16 vAA, vBBBB
    /// A: destination register (8 bits)
    /// B: source register (16 bits)
    move_object_from16 = 0x08_22,
    /// Move the contents of one object-bearing register to another.
    /// move-object/16 vAAAA, vBBBB
    /// A: destination register (16 bits)
    /// B: source register (16 bits)
    move_object_16 = 0x09_32,
    /// Move the single-word non-object result of the most recent `invoke-kind` into the indicated register. This must be done as the instruction immediately after an `invoke-kind` whose (single-word, non-object) result is not to be ignored; anywhere else is invalid.
    /// move-result vAA
    /// A: destination register (8 bits)
    move_result = 0x0a_11,
    /// Move the double-word result of the most recent `invoke-kind` into the indicated register. This must be done as the instruction immediately after an `invoke-kind` whose (double-word) result is not to be ignored; anywhere else is invalid.
    /// move-result-wide vAA
    /// A: destination register pair (8 bits)
    move_result_wide = 0x0b_11,
    /// Move the object result of the most recent `invoke-kind` into the indicated register. This must be done as the instruction immediately after an `invoke-kind` or `filled-new-array` whose (object) result is not to be ignored; anywhere else is invalid.
    /// move-result-object vAA
    /// A: destination register (8 bits)
    move_result_object = 0x0c_11,
    /// Save a just-caught exception into the given register. This must be the first instruction of any exception handler whose caught exception is not to be ignored, and this instruction must only ever occur as the first instruction of an exception handler; anywhere else is invalid.
    /// move-exception vAA
    /// A: destination register (8 bits)
    move_exception = 0x0d_11,
    /// Return `void` from a method.
    /// return-void
    return_void = 0x0e_10,
    /// Return from a single-width (32-bit) non-object value-returning method.
    /// return vAA
    /// A: return value register (8 bits)
    @"return" = 0x0f_11,
    /// Return from a double-width (64-bit) value-returning method.
    /// return-wide vAA
    /// A: return value register pair (8 bits)
    return_wide = 0x10_11,
    /// Return from an object-returning method.
    /// return-object vAA
    /// A: return value register (8 bits)
    return_object = 0x11_11,
    /// Move the given literal value (sign-extended to 32 bits) into the specified register.
    /// const/4 vA, #+B
    /// A: destination register (4 bits)
    /// B: signed int (4 bits)
    const_4 = 0x12_11,
    /// Move the given literal value (sign-extended to 32 bits) into the specified register.
    /// const/16 vAA, #+BBBB
    /// A: destination register (8 bits)
    /// B: signed int (16 bits)
    const_16 = 0x13_21,
    /// Move the given literal value into the specified register.
    /// const vAA, #+BBBBBBBB
    /// A: destination register (8 bits)
    /// B: arbitrary 32-bit constant
    @"const" = 0x14_31,
    /// Move the given literal value (right-zero extended to 32 bits) into the specified register.
    /// const/high16 vAA, #+BBBB_0000
    /// A: destination register (8 bits)
    /// B: signed int (16 bits)
    const_high16 = 0x15_21,
    /// Move the given literal value (sign extended to 64 bits) into the specified register.
    /// const-wide/high16 vAA, #+BBBB_0000
    /// A: destination register (8 bits)
    /// B: signed int (16 bits)
    const_wide_16 = 0x16_21,
    /// Move the given literal value (sign extended to 64 bits) into the specified register.
    /// const-wide/32 vAA, #+BBBB_BBBB
    /// A: destination register (8 bits)
    /// B: signed int (32 bits)
    const_wide_32 = 0x17_31,
    /// Move the given literal value into the specified register-pair.
    /// const-wide vAA, #+BBBB_BBBB_BBBB_BBBB
    /// A: destination register (8 bits)
    /// B: arbitrary double-width (64-bit) constant
    const_wide = 0x18_51,
    /// Move the given literal value (right-zero extended to 64 bits) into the specified register-pair.
    /// const-wide/high16 vAA, #+BBBB_0000_0000_0000
    /// A: destination register (8 bits)
    /// B: signed int (16 bits)
    const_wide_high16 = 0x19_21,
    /// Move a reference to the string specified by the given index into the specified register
    /// const-string vAA, string@BBBB
    /// A: destination register (8 bits)
    /// B: string index
    const_string = 0x1a_21,
    /// Move a reference to the string specified by the given index into the specified register
    /// const-string/jumbo vAA, string@BBBB_BBBB
    /// A: destination register (8 bits)
    /// B: string index
    const_string_jumbo = 0x1b_31,
    /// Move a reference to the class specified by the given index into the specified register. In the case where the indicated type is primitive, this will store a reference to the primitive type's degenerate class.
    /// const-class vAA, type@BBBB_BBBB
    /// A: destination register (8 bits)
    /// B: type index
    const_class = 0x1b_31,
    /// Acquire the monitor for the indicated object.
    /// monitor-enter vAA
    /// A: reference-bearing register (8 bits)
    monitor_enter = 0x1d_11,
    monitor_exit = 0x1e_11,
    check_cast = 0x1f_21,
    instance_of = 0x20_22,
    array_length = 0x21_12,
    new_instance = 0x22_21,
    new_array = 0x23_22,
    filled_new_array = 0x24_35,
    filled_new_array_range = 0x25_30,
    filled_array_data = 0x26_31,
    throw = 0x27_11,
    goto = 0x28_10,
    goto_16 = 0x29_20,
    goto_32 = 0x2a_30,
    packed_switch = 0x2b_31,
    sparse_switch = 0x2c_31,
    //
    cmpl_float = 0x2d_23,
    cmpg_float = 0x2e_23,
    cmpl_double = 0x2f_23,
    cmpg_double = 0x30_23,
    cmp_long = 0x31_23,
    //
    if_eq = 0x32_22,
    if_ne = 0x33_22,
    if_lt = 0x34_22,
    if_ge = 0x35_22,
    if_gt = 0x36_22,
    if_le = 0x37_22,
    //
    ifz_eq = 0x38_21,
    ifz_ne = 0x39_21,
    ifz_lt = 0x3a_21,
    ifz_ge = 0x3b_21,
    ifz_gt = 0x3c_21,
    ifz_le = 0x3d_21,
    // Array operations
    aget = 0x44_23,
    aget_wide = 0x45_23,
    aget_object = 0x46_23,
    aget_boolean = 0x47_23,
    aget_byte = 0x48_23,
    aget_char = 0x49_23,
    aget_short = 0x4a_23,
    aput = 0x4b_23,
    aput_wide = 0x4c_23,
    aput_object = 0x4d_23,
    aput_boolean = 0x4e_23,
    aput_byte = 0x4f_23,
    aput_char = 0x50_23,
    aput_short = 0x51_23,
    // Instance operations
    iget = 0x52_22,
    iget_wide = 0x53_22,
    iget_object = 0x54_22,
    iget_boolean = 0x55_22,
    iget_byte = 0x56_22,
    iget_char = 0x57_22,
    iget_short = 0x58_22,
    iput = 0x59_22,
    iput_wide = 0x5a_22,
    iput_object = 0x5b_22,
    iput_boolean = 0x5c_22,
    iput_byte = 0x5d_22,
    iput_char = 0x5e_22,
    iput_short = 0x5f_22,
    // Static operations
    sget = 0x52_22,
    sget_wide = 0x53_22,
    sget_object = 0x54_22,
    sget_boolean = 0x55_22,
    sget_byte = 0x56_22,
    sget_char = 0x57_22,
    sget_short = 0x58_22,
    sput = 0x59_22,
    sput_wide = 0x5a_22,
    sput_object = 0x5b_22,
    sput_boolean = 0x5c_22,
    sput_byte = 0x5d_22,
    sput_char = 0x5e_22,
    sput_short = 0x5f_22,
    // Invoke
    invoke_virtual = 0x6e_35,
    invoke_super = 0x6f_35,
    invoke_direct = 0x70_35,
    invoke_static = 0x71_35,
    invoke_interface = 0x72_35,
    // Invoke/range
    invoke_virtual_range = 0x6e_30,
    invoke_super_range = 0x6f_30,
    invoke_direct_range = 0x70_30,
    invoke_static_range = 0x71_30,
    invoke_interface_range = 0x72_30,
    // Unary operations
    neg_int = 0x7b_10,
    not_int = 0x7c_10,
    neg_long = 0x7d_10,
    not_long = 0x7e_10,
    neg_float = 0x7f_10,
    neg_double = 0x80_10,
    int_to_long = 0x81_10,
    int_to_float = 0x82_10,
    int_to_double = 0x83_10,
    long_to_int = 0x84_10,
    long_to_float = 0x85_10,
    long_to_double = 0x86_10,
    float_to_int = 0x87_10,
    float_to_long = 0x88_10,
    float_to_double = 0x89_10,
    double_to_int = 0x8a_10,
    double_to_long = 0x8b_10,
    double_to_float = 0x8c_10,
    int_to_byte = 0x8d_10,
    int_to_char = 0x8e_10,
    int_to_short = 0x8f_10,
    // Binary operations
    add_int = 0x90_23,
    sub_int = 0x91_23,
    mul_int = 0x92_23,
    div_int = 0x93_23,
    rem_int = 0x94_23,
    and_int = 0x95_23,
    or_int = 0x96_23,
    xor_int = 0x97_23,
    shl_int = 0x98_23,
    shr_int = 0x99_23,
    ushr_int = 0x9a_23,
    add_long = 0x9b_23,
    sub_long = 0x9c_23,
    mul_long = 0x9d_23,
    div_long = 0x9e_23,
    rem_long = 0x9f_23,
    and_long = 0xa0_23,
    or_long = 0xa1_23,
    xor_long = 0xa2_23,
    shl_long = 0xa3_23,
    shr_long = 0xa4_23,
    ushr_long = 0xa5_23,
    add_float = 0xa6_23,
    sub_float = 0xa7_23,
    mul_float = 0xa8_23,
    div_float = 0xa9_23,
    rem_float = 0xaa_23,
    add_double = 0xab_23,
    sub_double = 0xac_23,
    mul_double = 0xad_23,
    div_double = 0xae_23,
    rem_double = 0xaf_23,
    // Binary operations to address
    add_int_2addr = 0xb0_12,
    sub_int_2addr = 0xb1_12,
    mul_int_2addr = 0xb2_12,
    div_int_2addr = 0xb3_12,
    rem_int_2addr = 0xb4_12,
    and_int_2addr = 0xb5_12,
    or_int_2addr = 0xb6_12,
    xor_int_2addr = 0xb7_12,
    shl_int_2addr = 0xb8_12,
    shr_int_2addr = 0xbb_12,
    ushr_int_2addr = 0xba_12,
    add_long_2addr = 0xbb_12,
    sub_long_2addr = 0xbc_12,
    mul_long_2addr = 0xbd_12,
    div_long_2addr = 0xbe_12,
    rem_long_2addr = 0xbf_12,
    and_long_2addr = 0xc0_12,
    or_long_2addr = 0xc1_12,
    xor_long = 0xc2_12,
    shl_long_2addr = 0xc3_12,
    shr_long_2addr = 0xc4_12,
    ushr_long_2addr = 0xc5_12,
    add_float_2addr = 0xc6_12,
    sub_float_2addr = 0xc7_12,
    mul_float_2addr = 0xc8_12,
    div_float_2addr = 0xc9_12,
    rem_float_2addr = 0xca_12,
    add_double_2addr = 0xcb_12,
    sub_double_2addr = 0xcc_12,
    mul_double_2addr = 0xcd_12,
    div_double_2addr = 0xce_12,
    rem_double_2addr = 0xcf_12,
    // Binary operations with 16-bit literal value
    add_int_lit16 = 0xd0_12,
    sub_int_lit16 = 0xd1_12,
    mul_int_lit16 = 0xd2_12,
    div_int_lit16 = 0xd3_12,
    rem_int_lit16 = 0xd4_12,
    and_int_lit16 = 0xd5_12,
    or_int_lit16 = 0xd6_12,
    xor_int_lit16 = 0xd7_12,
    // Binary operations with 8-bit literal value
    add_int_lit8 = 0xd8_12,
    sub_int_lit8 = 0xd9_12,
    mul_int_lit8 = 0xda_12,
    div_int_lit8 = 0xdb_12,
    rem_int_lit8 = 0xdc_12,
    and_int_lit8 = 0xdd_12,
    or_int_lit8 = 0xde_12,
    xor_int_lit8 = 0xdf_12,
    shl_int_lit8 = 0xe0_12,
    shr_int_lit8 = 0xe1_12,
    ushr_int_lit8 = 0xe2_12,
    invoke_polymorphic = 0xfa_45,
    invoke_polymorphic_range = 0xfb_40,
    invoke_custom = 0xfc_35,
    invoke_custom_range = 0xfd_30,
    const_method_handle = 0xfe_21,
    const_method_type = 0xff_21,
    _,
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

/// Little-Endian Base 128
/// DEX only uses values up to 32-bit
const Leb128 = struct {
    pub fn readS128(reader: anytype) !sleb128 {
        _ = reader;
    }
    pub fn readU128(reader: anytype) !uleb128 {
        _ = reader;
    }
    pub fn readU128p1(reader: anytype) !uleb128p1 {
        _ = reader;
    }
};

/// DEX file layout
pub const Dex = struct {
    /// the header
    header: HeaderItem,
    /// string identifiers list. These are identifiers for all the strings used by this file, either for internal naming (e.g. type descriptors) or as constant objects referred to by code. This list must be sorted by string contents, using UTF-16 code point values (not in a locale-sensitive manner), and it must not contain any duplicate entries.
    string_ids: []StringIdItem,
    type_ids: []TypeIdItem,
    proto_ids: []ProtoIdItem,
    field_ids: []FieldIdItem,
    method_ids: []MethodIdItem,
    class_defs: []ClassDefItem,
    call_site_ids: []CallSiteIdItem,
    method_handles: []MethodHandleItem,
    data: []u8,
    link_data: []u8,
    map_list: MapList,

    pub fn readAlloc(seek: anytype, reader: anytype, allocator: std.mem.Allocator) !Dex {
        var dex: Dex = undefined;

        // Read the header
        dex.header = try HeaderItem.read(seek, reader);

        // Read the string id list
        try seek.seekTo(dex.header.string_ids_off);
        dex.string_ids = try allocator.alloc(StringIdItem, dex.header.string_ids_size);
        for (dex.string_ids) |*id| {
            id.* = try StringIdItem.read(reader);
        }

        // Read the type id list
        try seek.seekTo(dex.header.type_ids_off);
        dex.type_ids = try allocator.alloc(TypeIdItem, dex.header.type_ids_size);
        for (dex.type_ids) |*id| {
            id.* = try TypeIdItem.read(reader);
        }

        // Read the proto id list
        try seek.seekTo(dex.header.proto_ids_off);
        dex.proto_ids = try allocator.alloc(ProtoIdItem, dex.header.proto_ids_size);
        for (dex.proto_ids) |*id| {
            id.* = try ProtoIdItem.read(reader);
        }

        // Read the field id list
        try seek.seekTo(dex.header.field_ids_off);
        dex.field_ids = try allocator.alloc(FieldIdItem, dex.header.field_ids_size);
        for (dex.field_ids) |*id| {
            id.* = try FieldIdItem.read(reader);
        }

        // Read the method id list
        try seek.seekTo(dex.header.method_ids_off);
        dex.method_ids = try allocator.alloc(MethodIdItem, dex.header.method_ids_size);
        for (dex.method_ids) |*id| {
            id.* = try MethodIdItem.read(reader);
        }

        // Read the class def list
        try seek.seekTo(dex.header.class_defs_off);
        dex.class_defs = try allocator.alloc(ClassDefItem, dex.header.class_defs_size);
        for (dex.class_defs) |*def| {
            def.* = try ClassDefItem.read(reader);
        }

        // TODO?
        // dex.call_site_ids = ;
        // dex.method_handles = ;

        // Read data into buffer
        try seek.seekTo(dex.header.data_off);
        dex.data = try allocator.alloc(u8, dex.header.data_size);
        const amount = try reader.read(dex.data);
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
        var fbs = std.io.fixedBufferStream(dex.data[offset..]);
        const reader = fbs.reader();
        const codepoints = try std.leb.readULEB128(u32, reader);
        const data = std.mem.sliceTo(dex.data[offset..], 0);
        return StringDataItem{
            .utf16_size = codepoints,
            .data = data,
        };
    }

    pub fn getTypeString(dex: Dex, id: TypeIdItem) !StringDataItem {
        const descriptor_idx = id.descriptor_idx;
        if (descriptor_idx > dex.string_ids.len) return error.TypeStringOutOfBounds;
        return dex.getString(dex.string_ids[descriptor_idx]);
    }

    pub fn getPrototype(dex: Dex, id: ProtoIdItem, allocator: std.mem.Allocator) !Prototype {
        const parameters = if (id.parameters_off == 0) null else parameters: {
            const offset = id.parameters_off - dex.header.data_off;
            var fbs = std.io.fixedBufferStream(dex.data[offset..]);
            const reader = fbs.reader();
            break :parameters try TypeList.read(reader, allocator);
        };
        return Prototype{
            .shorty = try dex.getString(dex.string_ids[id.shorty_idx]),
            .return_type = try dex.getTypeString(dex.type_ids[id.return_type_idx]),
            .parameters = parameters,
        };
    }

    pub fn getTypeStringList(dex: Dex, type_list: TypeList, allocator: std.mem.Allocator) ![]StringDataItem {
        var string_list = try allocator.alloc(StringDataItem, type_list.size);
        for (type_list.list) |type_item, i| {
            string_list[i] = try dex.getTypeString(dex.type_ids[type_item.type_idx]);
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
        header.checksum = try reader.readInt(u32, .Little);

        if (try reader.read(&header.signature) != header.signature.len) return error.UnexpectedEOF;

        header.file_size = try reader.readInt(u32, .Little);
        header.header_size = try reader.readInt(u32, .Little);
        if (header.header_size != 0x70) return error.UnexpectedHeaderSize;
        header.endian_tag = if (try reader.readEnum(Endianness, .Little) == .Endian) .Little else .Big;
        header.link_size = try reader.readInt(u32, .Little);
        header.link_off = try reader.readInt(u32, .Little);
        header.map_off = try reader.readInt(u32, .Little);
        header.string_ids_size = try reader.readInt(u32, .Little);
        header.string_ids_off = try reader.readInt(u32, .Little);
        header.type_ids_size = try reader.readInt(u32, .Little);
        header.type_ids_off = try reader.readInt(u32, .Little);
        header.proto_ids_size = try reader.readInt(u32, .Little);
        header.proto_ids_off = try reader.readInt(u32, .Little);
        header.field_ids_size = try reader.readInt(u32, .Little);
        header.field_ids_off = try reader.readInt(u32, .Little);
        header.method_ids_size = try reader.readInt(u32, .Little);
        header.method_ids_off = try reader.readInt(u32, .Little);
        header.class_defs_size = try reader.readInt(u32, .Little);
        header.class_defs_off = try reader.readInt(u32, .Little);
        header.data_size = try reader.readInt(u32, .Little);
        header.data_off = try reader.readInt(u32, .Little);

        return header;
    }
};

const MapList = struct {
    size: u32,
    list: []MapItem,

    pub fn read(header: HeaderItem, seek: anytype, reader: anytype, allocator: std.mem.Allocator) !MapList {
        try seek.seekTo(header.map_off);
        const size = try reader.readInt(u32, .Little);
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
            .type = try reader.readEnum(TypeCode, .Little),
            ._unused = try reader.readInt(u16, .Little),
            .size = try reader.readInt(u32, .Little),
            .offset = try reader.readInt(u32, .Little),
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
            .string_data_off = try reader.readInt(u32, .Little),
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
            .descriptor_idx = try reader.readInt(u32, .Little),
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
            .shorty_idx = try reader.readInt(u32, .Little),
            .return_type_idx = try reader.readInt(u32, .Little),
            .parameters_off = try reader.readInt(u32, .Little),
        };
    }
};

const FieldIdItem = struct {
    class_idx: u16,
    type_idx: u16,
    name_idx: u32,
    pub fn read(reader: anytype) !@This() {
        return @This(){
            .class_idx = try reader.readInt(u16, .Little),
            .type_idx = try reader.readInt(u16, .Little),
            .name_idx = try reader.readInt(u32, .Little),
        };
    }
};

const MethodIdItem = struct {
    class_idx: u16,
    proto_idx: u16,
    name_idx: u32,

    pub fn read(reader: anytype) !@This() {
        return @This(){
            .class_idx = try reader.readInt(u16, .Little),
            .proto_idx = try reader.readInt(u16, .Little),
            .name_idx = try reader.readInt(u32, .Little),
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
            .class_idx = try reader.readInt(u32, .Little),
            .access_flags = @bitCast(AccessFlags, try reader.readInt(u32, .Little)),
            .superclass_idx = try reader.readInt(u32, .Little),
            .interfaces_off = try reader.readInt(u32, .Little),
            .source_file_idx = try reader.readInt(u32, .Little),
            .annotations_off = try reader.readInt(u32, .Little),
            .class_data_off = try reader.readInt(u32, .Little),
            .static_values_off = try reader.readInt(u32, .Little),
        };
    }
};

const CallSiteIdItem = struct {
    call_site_off: u32,
    pub fn read(reader: anytype) !@This() {
        return @This(){
            .call_site_off = try reader.readInt(u32, .Little),
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
        const size = try reader.readInt(u32, .Little);
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
            .type_idx = try reader.readInt(u16, .Little),
        };
    }
};

const CodeItem = struct {
    registers_size: u16,
    ins_size: u16,
    outs_size: u16,
    tries_size: u16,
    debug_info_off: u32,
    insns_size: u32,
    insns: []u16,
    padding: ?u16,
    tries: ?[]TryItem,
    handlers: ?EncodedCatchHandlerList,
};

const TryItem = struct {
    start_addr: u32,
    insn_count: u16,
    handler_off: u16,
};

const EncodedCatchHandlerList = struct {
    size: uleb128,
    list: []EncodedCatchHandler,
};

const EncodedCatchHandler = struct {
    size: sleb128,
    handlers: EncodedTypeAddrPair,
    catch_all_addr: ?uleb128,
};

const EncodedTypeAddrPair = struct {
    type_idx: uleb128,
    addr: uleb128,
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
