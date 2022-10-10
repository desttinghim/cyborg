const std = @import("std");
const testing = std.testing;

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
