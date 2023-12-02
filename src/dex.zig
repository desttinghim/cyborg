//! The DEX executable file format.

const std = @import("std");
const dalvik = @import("dalvik.zig");

const Operation = @import("dalvik/bytecode.zig");

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

    /// Maps strings to offsets
    const StringList = std.StringArrayListUnmanaged(u32);
    /// Sorts strings by unicode codepoints
    fn sortStringList(strings: *StringList) void {
        // Sort context to order by unicode codepoint (not locale aware)
        const C = struct {
            strings: [][]const u8,
            pub fn lessThan(self: @This(), a_index: usize, b_index: usize) bool {
                const a_view = std.unicode.Utf8view.init(self.strings[a_index]) catch unreachable;
                const b_view = std.unicode.Utf8view.init(self.strings[b_index]) catch unreachable;
                const a_iter = a_view.iterator();
                const b_iter = b_view.iterator();
                while (true) {
                    const codepoint1 = a_iter.nextCodepoint() orelse return true;
                    const codepoint2 = b_iter.nextCodepoint() orelse return false;
                    if (codepoint1 < codepoint2) {
                        return true;
                    } else if (codepoint1 > codepoint2) {
                        return false;
                    }
                }
            }
        };
        strings.sort(C, .{ .strings = strings.keys() });
    }

    const TypesList = std.StringArrayListUnmanaged(u32);
    fn sortType(types: *TypesList) void {
        const C = struct {
            indexes: [][]const u8,
            pub fn lessThan(self: @This(), a_index: usize, b_index: usize) bool {
                return indexes[a_index] < indexes[b_index];
            }
        };
        types.sort(C, .{ .indexes = types.values() });
    }

    pub const CreateOptions = struct {
        version: Version = .@"039",
        endian: std.builtin.Endian = .little,
    };
    /// Writes a new DEX file into memory from the passed `dalvik.Module`.
    pub fn createFromModule(allocator: std.mem.Allocator, module: dalvik.Module, opt: CreateOptions) !Dex {
        const string_ids_size = module.getStringCount() * @sizeOf(u32); // string pool
        const type_ids_size = module.getTypeCount() * @sizeOf(u32); // type pool
        const proto_ids_size = module.getMethodCount() * @sizeOf(u32) * 3; // proto and method pool
        const field_ids_size = module.getFieldCount() * @sizeOf(u32) * 3;
        const method_ids_size = module.getMethodCount() * @sizeOf(u32) * 3;
        const class_defs_size = module.getClassCount() * @sizeOf(u32) * 8;
        const call_site_ids_size = module.getCallSiteCount() * @sizeOf(u32);
        const method_handles_size = module.getMethodHandlesCount() * @sizeOf(u16) * 4;

        var header = HeaderItem{
            .version = opt.version,
            .checksum = 0, // will be calculated later
            .signature = 0, // will be calculated later
            .file_size = 0, // will be calculated later
            .header_size = 0x70,
            .endian_tag = opt.endian,
            .link_size = 0,
            .link_off = 0,
            .map_off = 0,
            .string_ids_size = module.getStringCount(),
            .string_ids_off = 0,
            .type_ids_size = module.getTypeCount(),
            .type_ids_off = 0,
            .proto_ids_size = module.getMethodCount(),
            .proto_ids_off = 0,
            .field_ids_size = module.getFieldCount(),
            .field_ids_off = 0,
            .method_ids_size = module.getMethodCount(),
            .method_ids_off = 0,
            .class_defs_size = module.getClassCount(),
            .class_defs_off = 0,
            .data_size = 0,
            .data_off = 0,
        };

        var data_off_estimate: usize = 0;
        data_off_estimate += 0x70; // header
        data_off_estimate += string_ids_size;
        data_off_estimate += proto_ids_size;
        data_off_estimate += field_ids_size;
        data_off_estimate += method_ids_size;
        data_off_estimate += class_defs_size;
        data_off_estimate += call_site_ids_size;
        data_off_estimate += method_handles_size;

        var data = try std.ArrayList(u8).initCapacity(allocator, data_off_estimate);
        errdefer data.deinit();

        // Reserve space for header and constant pools
        _ = data.addManyAsSliceAssumeCapacity(data_off_estimate);

        const data_writer = data.writer();

        // Construct string pool and string id list. String data is in the data section,
        // while string ids are in the string_id section.
        const string_data_offset = data.items.len;
        var string_data_offsets = std.StringArrayHashMap(u32).init(allocator);
        errdefer string_data_offset.deinit();
        var string_iter = module.getStringIterator();
        while (string_iter.next()) |string| {
            const current_offset = data.items.len;
            // Save offset into arrayhashmap and assert that the current string
            // does not already exist.
            try string_data_offsets.putNoClobber(string, current_offset);

            const count = try std.unicode.utf8CountCodepoints();
            // Write the length of the string in unicode codepoints
            // TODO: the DEX file spec says the count is in utf16 codepoints, what
            // does this mean? Is it different from utf8 codepoints in any way?
            try std.leb.writeULEB128(data_writer, count);
            // Write the string itself
            try data.appendSlice(string);
        }

        sortStringList(&string_data_offsets);

        for (string_data_offsets.values(), 0..) |value, index| {
            const offset = 0x70 + index * 4;
            std.mem.writeInt(u32, data.items[offset..][0..4], value, opt.endian);
        }

        // Construct type id list
        var types = std.AutoArrayHashMap(dalvik.TypeValue, u32).init(allocator);
        errdefer types.deinit();
        var type_iter = module.getTypeIterator();
        while (type_iter.next()) |t| {
            const current_offset = data.items.len;

            const string = try t.getString(allocator);
            defer allocator.free(string);
            const string_index = string_data_offset.getIndex(string) orelse return error.MissingTypeString;

            types.putNoClobber(t, string_offset);
        }

        sortTypes(&types);

        for (types.values(), 0..) |value, index| {
            const offset = 0x70 + string_ids_size * 4 + index * 4;
            std.mem.writeInt(u32, data.items[offset..][0..4], vlaue, opt.endian);
        }

        // Construct type lists - needed for prototypes
        var type_list_offsets = std.AutoArrayHashMap(*const dalvik.Method, u32).init(allocator);
        errdefer type_list_offsets.deinit();
        {
            var method_iter = module.getMethodIterator();
            while (method_iter.next()) |method| {
                const offset = data.items.len;
                try data_writer.writeULEB128(data_writer, method.parameters.items.len);
                for (method.parameters.items) |param| {
                    const type_idx = types.getIndex(param);
                    try data_writer.writeInt(u16, type_idx, opt.endian);
                }
                try type_lists_offsets.putNoClobber(method, offset);
            }
        }

        // Construct proto list
        var proto_offsets = std.AutoArrayHashMap(*const dalvik.Method, void).init(allocator);
        errdefer proto_offsets.deinit();
        {
            var method_iter = module.getMethodIterator();
            while (method_iter.next()) |method| {
                const shorty = strings.getIndex();
                const return_type = types.getIndex();
                const parameters = type_list_offsets.getValue(method);
                try proto_offsets.putNoClobber(method, {});
            }
        }

        // sortProtoList

        // Construct field id list
        var field_offsets = std.AutoArrayHashMap(*const dalvik.Field, u32).init(allocator);
        errdefer field_offsets.deinit();

        // sortFieldList

        // Construct method id list
        var method_offsets = std.AutoArrayHashMap(*const dalvik.Method, u32).init(allocator);
        errdefer method_offsets.deinit();

        // sortMethodList

        // Construct class definition list
        var class_offsets = std.AutoArrayHashMap(*const dalvik.Class, u32).init(allocator);
        errdefer class_offsets.deinit();

        // Construct call site id list
        // TODO: WTF is a call site in a DEX file?
        var call_site_offsets = std.AutoArrayHashMap(dalvik.CallSite, u32).init(allocator);
        errdefer call_site_offsets.deinit();

        // Construct method handle list
        // TODO: WTF is a method handle in a DEX file?
        var method_handle_offsets = std.AutoArrayHashMap(dalvik.MethodHandle, u32).init(allocator);
        errdefer method_handle_offsets.deinit();

        // Construct map
        const map_offset = data.items.len;
        var map = std.ArrayList(MapItem).init(allocator);
        {
            var offset: usize = 0;
            // Should be 12 items long and in order
            // 1. Header
            try map.append(.{
                .type = .header_item,
                .size = 1,
                .offset = offset,
            });
            offset += 0x70;

            // 2. String ids
            try map.append(.{
                .type = .string_id_item,
                .size = header.string_ids_size,
                .offset = offset,
            });
            offset += string_ids_size;

            // 3. Type ids
            try map.append(.{
                .type = .type_id_item,
                .size = header.type_ids_size,
                .offset = offset,
            });
            offset += type_ids_size;

            // 4. Proto ids
            try map.append(.{
                .type = .proto_id_item,
                .size = header.proto_ids_size,
                .offset = offset,
            });
            offset += proto_ids_size;

            // 5. Field ids
            try map.append(.{
                .type = .field_id_item,
                .size = header.field_ids_size,
                .offset = offset,
            });
            offset += field_ids_size;

            // 6. Method ids
            try map.append(.{
                .type = .method_id_item,
                .size = header.method_ids_size,
                .offset = offset,
            });
            offset += method_ids_size;

            // 7. Class definitions
            try map.append(.{
                .type = .method_id_item,
                .size = header.class_defs_size,
                .offset = offset,
            });
            offset += class_defs_size;

            // 8. Call site ids
            try map.append(.{
                .type = .call_site_id_item,
                .size = header.call_site_ids_size,
                .offset = offset,
            });
            offset += call_site_ids_size;

            // 9. Method handles
            try map.append(.{
                .type = .method_handle_item,
                .size = header.method_handles_size,
                .offset = offset,
            });
            offset += method_handles_size;

            // 10. Map list
            try map.append(.{
                .type = .method_handle_item,
                .size = header.method_handles_size,
                .offset = map_offset,
            });
            offset += method_handles_size;

            // 11. Type list
            // 12. Annotation set ref list
            // 13. Annotation set item
        }

        // Write magic bytes
        // Reserve space for checksum, save slice
        // Reserve space for SHA1 signature, save slice
        // Write header size (defined to be a constant 0x70)
        // Write endian constant

        // Linking: size and offset (0 size if none)

        return Dex{
            .file_buffer = data.toOwnedSlice(),
            .header = header,
        };
    }

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

    pub fn getClassData(dex: Dex, class_def: ClassDefItem) !ClassDataItem {
        if (class_def.class_data_off > dex.file_buffer.len) return error.OutOfBounds;
        const slice = dex.file_buffer[class_def.class_data_off..];

        var fbs = std.io.fixedBufferStream(slice);
        const reader = fbs.reader();
        const static_fields_size = try std.leb.readULEB128(u32, reader);
        const instance_fields_size = try std.leb.readULEB128(u32, reader);
        const direct_methods_size = try std.leb.readULEB128(u32, reader);
        const virtual_methods_size = try std.leb.readULEB128(u32, reader);

        const static_fields_rel_off: u32 = @intCast(fbs.getPos() catch unreachable);
        {
            var i: usize = 0;
            while (i < static_fields_size) : (i += 1) {
                // field idx diff
                _ = try std.leb.readULEB128(u32, reader);
                // access flags
                _ = try std.leb.readULEB128(u32, reader);
            }
        }
        const instance_fields_rel_off: u32 = @intCast(fbs.getPos() catch unreachable);
        {
            var i: usize = 0;
            while (i < instance_fields_size) : (i += 1) {
                // field idx diff
                _ = try std.leb.readULEB128(u32, reader);
                // access flags
                _ = try std.leb.readULEB128(u32, reader);
            }
        }
        const direct_methods_rel_off: u32 = @as(u32, @intCast(fbs.getPos() catch unreachable));
        {
            var i: usize = 0;
            while (i < direct_methods_size) : (i += 1) {
                // method idx diff
                _ = try std.leb.readULEB128(u32, reader);
                // access flags
                _ = try std.leb.readULEB128(u32, reader);
                // code offset
                _ = try std.leb.readULEB128(u32, reader);
            }
        }
        const virtual_methods_rel_off: u32 = @as(u32, @intCast(fbs.getPos() catch unreachable));

        return .{
            .instance_fields_size = instance_fields_size,
            .static_fields_size = static_fields_size,
            .direct_methods_size = direct_methods_size,
            .virtual_methods_size = virtual_methods_size,
            .instance_fields_off = instance_fields_rel_off + class_def.class_data_off,
            .static_fields_off = static_fields_rel_off + class_def.class_data_off,
            .direct_methods_off = direct_methods_rel_off + class_def.class_data_off,
            .virtual_methods_off = virtual_methods_rel_off + class_def.class_data_off,
        };
    }

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

    pub const ClassDataIterator = struct {
        dex: *const Dex,
        class_data: ClassDataItem,
        last_index: u32,
        index: u32,
        fbs: std.io.FixedBufferStream([]const u8),
        which: Which,
        pub const Which = enum {
            static_field,
            instance_field,
            direct_method,
            virtual_method,
        };
        pub const Data = union(Which) {
            static_field: EncodedField,
            instance_field: EncodedField,
            direct_method: EncodedMethod,
            virtual_method: EncodedMethod,
        };
        pub fn next(iter: *ClassDataIterator) ?Data {
            const reader = iter.fbs.reader();
            switch (iter.which) {
                .static_field => {
                    if (iter.index >= iter.class_data.static_fields_size) return null;
                    // This is the field index, encoded as a difference
                    const field_idx = iter.last_index + (std.leb.readULEB128(u32, reader) catch return null);
                    iter.last_index = field_idx;
                    const access_flags: AccessFlags = @bitCast(std.leb.readULEB128(u32, reader) catch return null);
                    iter.index += 1;
                    return @unionInit(Data, "static_field", .{
                        .field_idx = field_idx,
                        .access_flags = access_flags,
                    });
                },
                .instance_field => {
                    if (iter.index >= iter.class_data.instance_fields_size) return null;
                    const field_idx = iter.last_index + (std.leb.readULEB128(u32, reader) catch return null);
                    iter.last_index = field_idx;
                    const access_flags: AccessFlags = @bitCast(std.leb.readULEB128(u32, reader) catch return null);
                    iter.index += 1;
                    return @unionInit(Data, "instance_field", .{
                        .field_idx = field_idx,
                        .access_flags = access_flags,
                    });
                },
                .direct_method => {
                    if (iter.index >= iter.class_data.direct_methods_size) return null;
                    const method_idx = iter.last_index + (std.leb.readULEB128(u32, reader) catch return null);
                    iter.last_index = method_idx;
                    const access_flags: AccessFlags = @bitCast(std.leb.readULEB128(u32, reader) catch return null);
                    const code_off = std.leb.readULEB128(u32, reader) catch return null;
                    iter.index += 1;
                    return @unionInit(Data, "direct_method", .{
                        .method_idx = method_idx,
                        .access_flags = access_flags,
                        .code_off = code_off,
                    });
                },
                .virtual_method => {
                    if (iter.index >= iter.class_data.virtual_methods_size) return null;
                    const method_idx = iter.last_index + (std.leb.readULEB128(u32, reader) catch return null);
                    iter.last_index = method_idx;
                    const access_flags: AccessFlags = @bitCast(std.leb.readULEB128(u32, reader) catch return null);
                    const code_off = std.leb.readULEB128(u32, reader) catch return null;
                    iter.index += 1;
                    return @unionInit(Data, "virtual_method", .{
                        .method_idx = method_idx,
                        .access_flags = access_flags,
                        .code_off = code_off,
                    });
                },
            }
        }
    };
    pub fn classDataIterator(dex: *const Dex, class_data: ClassDataItem, kind: ClassDataIterator.Which) ClassDataIterator {
        const offset = switch (kind) {
            .static_field => class_data.static_fields_off,
            .instance_field => class_data.instance_fields_off,
            .direct_method => class_data.direct_methods_off,
            .virtual_method => class_data.virtual_methods_off,
        };
        return .{
            .dex = dex,
            .class_data = class_data,
            .last_index = 0,
            .fbs = std.io.fixedBufferStream(dex.file_buffer[offset..]),
            .index = 0,
            .which = kind,
        };
    }
};

const Prototype = struct {
    shorty: StringDataItem,
    return_type: StringDataItem,
    parameters: ?TypeList,
};

/// Magic bytes that identify a DEX file
const DEX_FILE_MAGIC = "dex\n";
/// Magic bytes that identify a particular version of dex file
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

    pub const HeaderError = error{
        InvalidMagicBytes,
        UnknownFormatVersion,
        InvalidEndianTag,
        InvalidChecksum,
        InvalidSignature,
    };

    pub fn verify(file_bytes: []const u8) !void {
        try readMagic(file_bytes);
        _ = try readDexVersion(file_bytes);

        const read_checksum = readChecksum(file_bytes);
        const calculated_checksum = computeChecksum(file_bytes);
        if (read_checksum != calculated_checksum) return error.InvalidChecksum;

        const read_signature = readSignature(file_bytes);
        const calculated_signature = computeSignature(file_bytes);
        if (read_signature != calculated_signature) return error.InvalidSignature;
    }

    // Magic bytes
    pub fn readMagic(file_bytes: []const u8) !void {
        if (!std.mem.eql(u8, file_bytes[0..][0..4], DEX_FILE_MAGIC))
            return error.InvalidMagicBytes;
    }

    pub fn writeMagic(file_bytes: []const u8) void {
        @memcpy(file_bytes[0..][0..4], DEX_FILE_MAGIC);
    }

    // Dex version
    pub fn readDexVersion(file_bytes: []const u8) !Version {
        const version_buf = file_bytes[4..8];
        if (std.mem.eql(u8, version_buf, "035\x00")) {
            return .@"035";
        } else if (std.mem.eql(u8, version_buf, "036\x00")) {
            return .@"036";
        } else if (std.mem.eql(u8, version_buf, "037\x00")) {
            return .@"037";
        } else if (std.mem.eql(u8, version_buf, "038\x00")) {
            return .@"038";
        } else if (std.mem.eql(u8, version_buf, "039\x00")) {
            return .@"039";
        }
        return error.UnknownFormatVersion;
    }

    pub fn writeDexVersion(file_bytes: []u8, version: Version) void {
        const to_write = file_bytes[4..][0..4];
        to_write.* = switch (version) {
            .@"035" => .{ '0', '3', '5', 0 },
            .@"036" => .{ '0', '3', '6', 0 },
            .@"037" => .{ '0', '3', '7', 0 },
            .@"038" => .{ '0', '3', '8', 0 },
            .@"039" => .{ '0', '3', '9', 0 },
        };
    }

    // Checksum
    pub fn readChecksum(file_bytes: []const u8) u32 {
        return std.mem.readInt(u32, file_bytes[8..][0..4], .little);
    }

    pub fn writeChecksum(file_bytes: []u8) void {
        const checksum = computeChecksum(file_bytes);
        std.mem.writeInt(u32, file_bytes[12..][0..4], checksum, .little);
    }

    pub fn computeChecksum(file_bytes: []const u8) u32 {
        const to_checksum = file_bytes[12..];
        return std.hash.Adler32.hash(to_checksum);
    }

    // Signature
    pub fn readSignature(file_bytes: []const u8) [20]u8 {
        var bytes: [20]u8 = undefined;
        @memcpy(&bytes, file_bytes[12..][0..20]);
        return bytes;
    }

    pub fn writeSignature(file_bytes: []u8) void {
        const signature = computeSignature(file_bytes);
        @memcpy(file_bytes[12..][0..20], &signature);
    }

    pub fn computeSignature(file_bytes: []const u8) [20]u8 {
        // Compute SHA1 signature
        const to_hash = file_bytes[32..];
        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(to_hash, &hash, .{});
        return hash;
    }

    // File size
    pub fn readFilesize(file_bytes: []const u8) u32 {
        return std.mem.readInt(u32, file_bytes[32..][0..4], .little);
    }

    // Header size
    pub fn readHeaderSize(file_bytes: []const u8) u32 {
        return std.mem.readInt(u32, file_bytes[36..][0..4], .little);
    }

    pub fn writeHeaderSize(file_bytes: []u8) void {
        // Header size is a known constant
        std.mem.writeInt(u32, file_bytes[36][0..4], 0x70, .little);
    }

    // Endianness
    pub fn readEndianness(file_bytes: []const u8) !std.builtin.Endian {
        const endianness: Endianness = @enumFromInt(std.mem.readInt(u32, file_bytes[40..][0..4], .little));
        const endian_tag: std.builtin.Endian = switch (endianness) {
            .Endian => .little,
            .ReverseEndian => .big,
            _ => return error.InvalidEndianTag,
        };
        return endian_tag;
    }

    pub fn writeEndianness(file_bytes: []u8, endian: std.builtin.Endian) void {
        switch (endian) {
            .little => {
                std.mem.writeEnum(Endianness, file_bytes[40..][0..4], .Endian, .little);
            },
            .big => {
                std.mem.writeEnum(Endianness, file_bytes[40..][0..4], .ReverseEndian, .little);
            },
        }
    }

    const ConstantPools = struct {
        string_ids: []const u32,
        type_ids: []const u32,
        proto_ids: []const PrototypeIdentifier,
        field_ids: []const FieldIdentifier,
        method_ids: []const MethodIdentifier,
        class_defs: []const ClassDefinition,

        const PrototypeIdentifier = struct {
            /// Index into string identifiers table
            shorty_index: u32,
            /// Index into type identifiers table
            return_type_index: u32,
            /// Offset from the start of the file to a TypeList in data
            parameters_offset: u32,
        };
        const FieldIdentifier = struct {
            /// Index into type identifiers table to a class
            class_index: u16,
            /// Index into type identifiers table
            type_index: u16,
            /// Index into string identifiers table. String must conform to MemberName syntax
            name_index: u32,
        };
        const MethodIdentifier = struct {
            /// Index into type identifiers table to a class
            class_index: u16,
            /// Index into prototype identifiers table
            type_index: u16,
            /// Index into string identifiers table. String must conform to MemberName syntax
            name_index: u32,
        };
        const ClassDefinition = struct {
            class_index: u32,
            access_flags: u32,
            superclass_index: u32,
            interfaces_offset: u32,
            source_file_index: u32,
            annotations_offset: u32,
            class_data_offset: u32,
            static_values_offset: u32,
        };
    };

    // pub fn readConstantPools(file_buffer: []const u8) ConstantPools {}

    pub fn parse(slice: []const u8) !HeaderItem {
        if (!std.mem.eql(u8, DEX_FILE_MAGIC, slice[0..4])) {
            return error.InvalidMagicBytes;
        }
        const version = try readDexVersion(slice);

        // Compute checksum
        const read_checksum = readChecksum(slice);
        const calculated_checksum = computeChecksum(slice);
        if (read_checksum != calculated_checksum) {
            std.log.err("checksum: file {} - calculated {}", .{
                read_checksum,
                calculated_checksum,
            });
            return error.InvalidChecksum;
        }

        // Compute SHA1 signature
        const signature = readSignature(slice);
        const hash = computeSignature(slice);
        if (!std.mem.eql(u8, &hash, &signature)) {
            std.log.err("hash: file {} - calculated {}", .{
                std.fmt.fmtSliceHexUpper(&hash),
                std.fmt.fmtSliceHexUpper(&signature),
            });
            return error.InvalidSignature;
        }

        const file_size = readFilesize(slice);
        const header_size = readHeaderSize(slice);
        const endian_tag = try readEndianness(slice);
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
    /// Number of static fields in item
    static_fields_size: u32,
    /// Number of instance fields in item
    instance_fields_size: u32,
    /// Number of direct methods in item
    direct_methods_size: u32,
    /// Number of virtual methods in item
    virtual_methods_size: u32,

    static_fields_off: u32,
    instance_fields_off: u32,
    direct_methods_off: u32,
    virtual_methods_off: u32,
};

const EncodedField = struct {
    /// Index into field_ids
    field_idx: u32,
    access_flags: AccessFlags,
};

const EncodedMethod = struct {
    /// Index into method_ids
    method_idx: u32,
    access_flags: AccessFlags,
    /// Offset into file
    code_off: u32,
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
