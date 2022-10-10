//! The DEX executable file format.

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
const Dex = struct {
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
};

/// Magic bytes that identify a DEX file
const DEX_FILE_MAGIC: [8]u8 = "dex\n039\x00";
/// Constant used to identify the endianness of the file
const ENDIAN_CONSTANT: u32 = 0x12345678;
/// Constant used to identify the endianness of the file
const REVERSE_ENDIAN_CONSTANT: u32 = 0x78563412;
/// Value to represent null indexes
const NO_INDEX: u32 = 0xffffffff;

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
    magic: [8]u8 = DEX_FILE_MAGIC,
    /// adler32 checksum of the rest of the file (everything but magic and this field); used to detect file corruption
    checksum: u32,
    /// SHA-1 signature (hash) of the rest of the file (everything but magic, checksum, and this field); used to uniquely identify files
    signature: [20]u8,
    /// size of the entire file (including the header), in bytes
    file_size: u32,
    /// size of the header (this entire section), in bytes. This allows for at least a limited amount of backwards/forwards compatibility without invalidating the format
    header_size: u32 = 0x70,
    /// endianness tag. Either `ENDIAN_CONSTANT` or `REVERSE_ENDIAN_CONSTANT`
    endian_tag: u32 = ENDIAN_CONSTANT,
    /// size of the link section, or 0 if this file isn't statically linked
    link_size: u32,
    /// offset from
    link_off: u32,
    map_off: u32,
    string_ids_size: u32,
    string_ids_off: u32,
    type_ids_size: u32,
    type_ids_off: u32,
    proto_ids_off: u32,
    field_ids_size: u32,
    fields_ids_off: u32,
    method_ids_size: u32,
    method_ids_off: u32,
    class_defs_size: u32,
    class_defs_off: u32,
    data_size: u32,
    data_off: u32,
};

const MapList = struct {
    size: u32,
    list: []MapItem,
};

const MapItem = struct {
    type: TypeCode,
    _unused: u16,
    size: u32,
    offset: u32,
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
};

const ProtoIdItem = struct {
    /// index into the string_ids list for the short-form descriptor string of this prototype. The string must conform to the syntax for ShortyDescriptor, defined above, and must correspond to the return type and parameters of this item.
    shorty_idx: u32,
    /// index into the type_ids list for the return type of this prototype
    return_type_idx: u32,
    /// offset from the start of the file to the list of the parameter types for this prototype, or 0 if this prototype has no parameters. This offset, if non-zero, should be in the data section, and the data there should be in the format specified by the "type_list" below. Additionally, there should be no reference to the type void in the list.
    parameters_off: u32,
};

const FieldIdItem = struct {
    class_idx: u16,
    type_idx: u16,
    name_idx: u32,
};

const MethodIdItem = struct {
    class_idx: u16,
    proto_idx: u16,
    name_idx: u32,
};

const ClassDefItem = struct {
    class_idx: u32,
    access_flags: u32,
    superclass_idx: u32,
    interfaces_off: u32,
    interfaces_off: u32,
    source_file_idx: u32,
    annotations_off: u32,
    class_data_off: u32,
    static_values_off: u32,
};

const CallSiteIdItem = struct {
    call_site_off: u32,
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
};

const TypeItem = struct {
    type_idx: u16,
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

const ParamaterAnnotation = struct {
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
