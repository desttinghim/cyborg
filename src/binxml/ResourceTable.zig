const ResourceTable = @This();

string_pool: StringPool,
packages: ArrayList(Package),

pub fn readAlloc(seek: anytype, reader: anytype, starting_pos: usize, chunk_header: ResourceChunk.Header, alloc: std.mem.Allocator) !ResourceTable {
    const header = try Header.read(reader, chunk_header);

    var string_pool: StringPool = undefined;

    var packages = try ArrayList(ResourceTable.Package).initCapacity(alloc, header.package_count);
    errdefer packages.clearAndFree(alloc);

    var pos: usize = try seek.getPos();
    var package_header = try ResourceChunk.Header.read(reader);

    while (true) {
        switch (package_header.type) {
            .StringPool => {
                string_pool = try StringPool.readAlloc(seek, reader, pos, package_header, alloc);
            },
            .TablePackage => {
                const table_package_type = try Package.read(seek, reader, pos, package_header, alloc);
                packages.appendAssumeCapacity(table_package_type);
            },
            else => {
                return error.InvalidChunkType;
            },
        }
        if (pos + package_header.size >= starting_pos + header.header.size) {
            break;
        }
        try seek.seekTo(pos + package_header.size);
        pos = try seek.getPos();
        package_header = try ResourceChunk.Header.read(reader);
    }

    return ResourceTable{
        .packages = packages,
        .string_pool = string_pool,
    };
}

const Header = struct {
    header: ResourceChunk.Header,
    package_count: u32,

    fn read(reader: anytype, header: ResourceChunk.Header) !Header {
        return Header{
            .header = header,
            .package_count = try reader.readInt(u32, .Little),
        };
    }
};

const Package = struct {
    header: ResourceChunk.Header,
    id: u32,
    /// Actual name of package
    name: []const u16,
    /// Offset to StringPool.Header defining the resource type symbol table. If zero, this package is inheriting
    /// from another base package.
    type_strings: u32,
    /// Last index into type_strings that is for public use by others
    last_public_type: u32,
    /// Offset to a ResStringPool_header defining the resource key symbol table.
    key_strings: u32,
    /// Last index into keyStrings that is for public use by others
    last_public_key: u32,
    type_id_offset: u32,

    // Runtime values
    type_string_pool: StringPool,
    key_string_pool: StringPool,
    type_spec: ArrayList(TypeSpec),
    table_type: ArrayList(TableType),

    fn read(seek: anytype, reader: anytype, starting_pos: usize, header: ResourceChunk.Header, alloc: std.mem.Allocator) !Package {
        var package: Package = undefined;

        package.header = header;
        package.id = try reader.readInt(u32, .Little);
        var name: [127:0]u16 = undefined;
        var index: usize = 0;
        name[index] = try reader.readInt(u16, .Little);
        while (name[index] != 0) {
            index += 1;
            name[index] = try reader.readInt(u16, .Little);
        }
        package.name = try alloc.dupe(u16, name[0..index]);
        package.type_strings = try reader.readInt(u32, .Little);
        package.last_public_type = try reader.readInt(u32, .Little);
        package.key_strings = try reader.readInt(u32, .Little);
        package.last_public_key = try reader.readInt(u32, .Little);
        package.type_id_offset = try reader.readInt(u32, .Little);

        var type_specs = ArrayList(TypeSpec){};
        var table_types = ArrayList(TableType){};

        var type_string_pool: ?StringPool = null;
        var key_string_pool: ?StringPool = null;

        var pos = starting_pos;
        try seek.seekTo(pos + header.header_size);
        pos = try seek.getPos();
        var package_header = try ResourceChunk.Header.read(reader);
        while (true) {
            switch (package_header.type) {
                .StringPool => {
                    if (type_string_pool == null) {
                        type_string_pool = try StringPool.readAlloc(seek, reader, pos, package_header, alloc);
                    } else if (key_string_pool == null) {
                        key_string_pool = try StringPool.readAlloc(seek, reader, pos, package_header, alloc);
                    } else {
                        return error.TooManyStringPools;
                    }
                },
                .TableTypeSpec => {
                    const table_spec_type = try ResourceTable.TypeSpec.read(reader, package_header, alloc);
                    try type_specs.append(alloc, table_spec_type);
                },
                .TableType => {
                    const table_type = try ResourceTable.TableType.read(seek, reader, pos, package_header, alloc);
                    try table_types.append(alloc, table_type);
                },
                else => {
                    std.log.info("Found {s} while parsing package", .{@tagName(package_header.type)});
                    return error.InvalidChunkType;
                },
            }
            if (pos + package_header.size >= starting_pos + header.size) {
                break;
            }
            try seek.seekTo(pos + package_header.size);
            pos = try seek.getPos();
            package_header = try ResourceChunk.Header.read(reader);
        }
        package.type_string_pool = type_string_pool orelse return error.MissingTypeStringPool;
        package.key_string_pool = key_string_pool orelse return error.MissingKeyStringPool;
        package.type_spec = type_specs;
        package.table_type = table_types;

        return package;
    }
};

const Config = extern struct {
    const Imsi = packed struct(u32) {
        mcc: u16,
        mnc: u16,
    };
    const Locale = packed struct(u32) {
        language: u16,
        country: u16,
    };
    const ScreenType = packed struct(u32) {
        orientation: enum(u8) { Any = 0, Port = 1, Land = 2, Square = 3 },
        touchscreen: enum(u8) { Any = 0, NoTouch = 1, Stylus = 2, Finger = 3 },
        density: enum(u16) { Default = 0, Low = 120, Medium = 160, Tv = 213, High = 240, XHigh = 320, XXHigh = 480, XXXHigh = 640, Any = 0xFFFE, None = 0xFFFF },
    };
    const Input = packed struct(u32) {
        keyboard: enum(u8) { Any = 0, NoKeys = 1, Qwerty = 2, _12Key = 3 },
        navigation: enum(u8) { Any = 0, NoNav = 1, Dpad = 2, Trackball = 3, Wheel = 4 },
        input_flags: packed struct(u8) {
            keys_hidden: enum(u2) { Any = 0, No = 1, Yes = 2, Soft = 3 },
            nav_hidden: enum(u2) { Any = 0, No = 1, Yes = 2 },
            _unused: u4,
        },
        input_pad: u8,
    };
    const ScreenSize = packed struct(u32) {
        width: enum(u16) { Any = 0, _ },
        height: enum(u16) { Any = 0, _ },
    };
    const Version = packed struct(u32) {
        sdk: enum(u16) { Any = 0, _ },
        minor: enum(u16) { Any = 0, _ }, // must be 0, meaning is undefined
    };
    const ScreenConfig = packed struct(u32) {
        layout: packed struct(u8) {
            size: enum(u4) { Any = 0, Small = 1, Normal = 2, Large = 3, XLarge = 4 },
            long: enum(u2) { Any = 0, No = 1, Yes = 2 },
            dir: enum(u2) { Any = 0, LTR = 1, RTL = 2 },
        },
        ui_mode: packed struct(u8) {
            type: enum(u4) { Any = 0, Normal = 1, Desk = 2, Car = 3, Television = 4, Appliance = 5, Watch = 6, VrHeadset = 7 },
            night: enum(u2) { Any = 0, No = 1, Yes = 2 },
            _unused: u2,
        },
        smallest_screen_width_dp: u16,
    };
    const ScreenSizeDp = packed struct(u32) {
        width: u16,
        height: u16,
    };
    const ScreenConfig2 = packed struct(u32) {
        layout2: packed struct(u8) {
            round: enum(u2) { Any = 0, No = 1, Yes = 2 },
            _unused: u6,
        },
        color_mode: packed struct(u8) {
            wide_color: enum(u2) { Any = 0, No = 1, Yes = 2 },
            hdr: enum(u2) { Any = 0, No = 1, Yes = 2 },
            _unused: u4,
        },
        _pad: u16,
    };
    size: u32,
    imsi: Imsi,
    locale: Locale,
    screen_type: ScreenType,
    input: Input,
    screen_size: ScreenSize,
    version: Version,
    screen_config: ScreenConfig,
    screen_size_dp: ScreenSizeDp,
    locale_script: [4]u8,
    locale_version: [8]u8,
    screen_config2: ScreenConfig2,
    locale_script_was_computed: bool,
    locale_numbering_system: [8]u8,

    fn read(reader: anytype) !Config {
        var config: Config = undefined;

        config.size = try reader.readInt(u32, .Little);
        std.debug.assert(config.size == @sizeOf(Config));
        config.imsi = @bitCast(Imsi, try reader.readInt(u32, .Little));
        config.locale = @bitCast(Locale, try reader.readInt(u32, .Little));
        config.screen_type = @bitCast(ScreenType, try reader.readInt(u32, .Little));
        config.input = @bitCast(Input, try reader.readInt(u32, .Little));
        config.screen_size = @bitCast(ScreenSize, try reader.readInt(u32, .Little));
        config.version = @bitCast(Version, try reader.readInt(u32, .Little));
        config.screen_config = @bitCast(ScreenConfig, try reader.readInt(u32, .Little));
        config.screen_size_dp = @bitCast(ScreenSizeDp, try reader.readInt(u32, .Little));
        _ = try reader.read(&config.locale_script);
        _ = try reader.read(&config.locale_version);
        config.screen_config2 = @bitCast(ScreenConfig2, try reader.readInt(u32, .Little));

        return config;
    }
};

const TypeSpec = struct {
    id: u8,
    res0: u8,
    res1: u16,
    entry_count: u32,

    entry_indices: []u32,
    // entries: []TableType,

    fn read(reader: anytype, header: ResourceChunk.Header, alloc: std.mem.Allocator) !TypeSpec {
        _ = header;
        var type_spec: TypeSpec = undefined;

        type_spec.id = try reader.readInt(u8, .Little);
        type_spec.res0 = try reader.readInt(u8, .Little);
        type_spec.res1 = try reader.readInt(u16, .Little);
        type_spec.entry_count = try reader.readInt(u32, .Little);

        type_spec.entry_indices = try alloc.alloc(u32, type_spec.entry_count);
        for (type_spec.entry_indices) |*entry| {
            entry.* = try reader.readInt(u32, .Little);
        }
        // type_spec.entries = try alloc.alloc(TableType, type_spec.entry_count);
        // for (type_spec.entries) |*entry| {
        //     const type_header = try ResourceChunk.read(reader);
        //     entry.* = try TableType.read(reader, type_header, alloc);
        // }

        return type_spec;
    }
};

const TableType = struct {
    id: u8,
    flags: u8,
    reserved: u16,
    entry_count: u32,
    entries_start: u32,
    config: Config,
    entry_indices: ArrayList(u32),
    entries: ArrayList(Entry),

    fn read(seek: anytype, reader: anytype, pos: usize, header: ResourceChunk.Header, alloc: std.mem.Allocator) !TableType {
        var table_type: TableType = undefined;

        table_type.id = try reader.readInt(u8, .Little);
        table_type.flags = try reader.readInt(u8, .Little);
        table_type.reserved = try reader.readInt(u16, .Little);
        table_type.entry_count = try reader.readInt(u32, .Little);
        table_type.entries_start = try reader.readInt(u32, .Little);
        table_type.config = try Config.read(reader);

        if (table_type.flags & 0x01 != 0) {
            // Complex flag
        } else {
            try seek.seekTo(pos + header.header_size);
            table_type.entry_indices = try ArrayList(u32).initCapacity(alloc, table_type.entry_count);
            for (0..table_type.entry_indices.capacity) |_| {
                table_type.entry_indices.appendAssumeCapacity(try reader.readInt(u32, .Little));
            }
            try seek.seekTo(pos + table_type.entries_start);
            table_type.entries = try ArrayList(Entry).initCapacity(alloc, table_type.entry_count);
            for (0..table_type.entries.capacity) |_| {
                table_type.entries.appendAssumeCapacity(try Entry.read(reader));
            }
        }

        return table_type;
    }
};

const SparseTypeEntry = struct {
    entry: u32,
    idx: u16,
    offset: u16,
};

const Entry = struct {
    size: u16,
    flags: u16,
    key: StringPool.Ref,
    value: ?Value,

    pub fn read(reader: anytype) !Entry {
        var entry: Entry = undefined;

        entry.size = try reader.readInt(u16, .Little);
        entry.flags = try reader.readInt(u16, .Little);
        entry.key = try StringPool.Ref.read(reader);
        std.debug.assert(entry.flags & 0x0001 == 0);
        entry.value = try Value.read(reader, null);

        return entry;
    }
};

const TableRef = struct {
    ident: u32,
};

const MapEntry = struct {
    parent: TableRef,
    count: u32,
};

const Map = struct {
    name: TableRef,
    value: Value,
};

const LibHeader = struct {
    count: u32,
};

const LibEntry = struct {
    package_id: u32,
    package_name: [127:0]u16,
};

const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const StringPool = @import("StringPool.zig");
const ResourceChunk = @import("ResourceChunk.zig");
const Value = @import("Value.zig");
