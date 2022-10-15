const std = @import("std");

const Pool = std.AutoArrayHashMap([]const u8, void);

pub const Document = struct {
    namespaces: []const Namespace,
    root: Node,
};

pub const Namespace = struct {
    prefix: []const u8,
    uri: []const u8,

    pub fn addToPool(namespace: Namespace, pool: Pool) !usize {
        try pool.put(namespace.prefix);
        try pool.put(namespace.uri);
        return 1;
    }
};

pub const Node = union(enum) {
    Element: Element,
    CData: CData,

    pub fn addToPool(node: *Node, pool: Pool) !usize {
        return switch (node) {
            .Element => |el| try el.addToPool(pool),
            .CData => |cdata| try cdata.addToPool(pool),
        };
    }
};

pub const Attribute = struct {
    namespace: ?[]const u8 = null,
    name: []const u8,
    value: Value,

    pub fn addToPool(attr: Attribute, pool: Pool) !usize {
        if (attr.namespace) |ns| _ = ns.addToPool();
        try pool.put(attr.name);
        try pool.put(attr.value);
        return 1;
    }
};

pub const Element = struct {
    namespace: ?[]const u8 = null,
    name: []const u8,
    attributes: []Attribute = &.{},
    children: []Node = &.{},

    pub fn addToPool(el: Element, pool: Pool) !usize {
        if (el.namespace) |ns| _ = ns.addToPool();
        try pool.put(el.name);
        for (el.attributes) |attribute| {
            try attribute.addToPool(pool);
        }
        for (el.children) |child| {
            try child.addToPool(pool);
        }
        return el.children.len + 1;
    }
};

pub const CData = struct {
    value: Value,

    pub fn addToPool(cdata: CData, pool: Pool) !void {
        try cdata.value.addToPool(pool);
    }
};

const Value = union(enum) {
    Null: enum { Undefined, Empty },
    Reference: u32,
    Attribute: Attribute,
    String: []const u8,
    Float: f32,
    Dimension: union(enum) {
        Pixels: u32,
        DeviceIndependentPixels: u32,
        ScaledDeviceIndependentPixels: u32,
        Points: u32,
        Inches: u32,
        Millimeters: u32,
        Fraction: u32,
    },
    Fraction: struct {
        value: u32,
        unit: enum {
            Basic,
            Parent,
        },
        radix: enum {
            r23p0,
            r16p7,
            r8p15,
        },
    },
    Int: union(enum) {
        Dec: u32,
        Hex: u32,
        Bool: bool,
        Color: union(enum) {
            ARGB8: struct {
                r: u8,
                g: u8,
                b: u8,
                a: u8,
            },
            RGB8: struct {
                r: u8,
                g: u8,
                b: u8,
            },
            ARGB4: struct {
                r: u4,
                g: u4,
                b: u4,
                a: u4,
            },
            RGB4: struct {
                r: u4,
                g: u4,
                b: u4,
            },
        },
    },

    pub fn addToPool(value: Value, pool: Pool) !void {
        switch (value) {
            .String => |str| try pool.put(str),
            else => {},
        }
    }
};

test "manifest" {
    const ns_android = Namespace{
        .prefix = "android",
        .uri = "http://schemas.android.com/apk/res/android",
    };
    _ = Element{ .namespace = &ns_android, .name = "manifest", .attributes = &.{
        .{ .name = "compileSdkVersion", .value = .{ .Int = .{ .Dec = 30 } } },
        .{ .name = "compileSdkVersionCodename", .value = .{ .Int = .{ .Dec = 11 } } },
        .{ .name = "package", .value = .{ .Int = .{ .Dec = 11 } } },
        .{ .name = "platformBuildVersionCode", .value = .{ .Int = .{ .Dec = 30 } } },
        .{ .name = "platformBuildVersionName", .value = .{ .Int = .{ .Dec = 11 } } },
    }, .children = &.{
        Element{
            .name = "uses-sdk",
            .attributes = &.{
                .{ .name = "targetSdkVersion", .value = .{ .Int = .{ .Dec = 30 } } },
            },
        },
        Element{
            .name = "uses-permission",
            .attributes = &.{
                .{ .name = "name", .value = .{ .String = "android.permission.SET_RELEASE_APP" } },
            },
        },
        Element{
            .name = "application",
            .attributes = &.{
                .{ .name = "label", .value = .{ .Reference = 0 } },
                .{ .name = "icon", .value = .{ .Reference = 0 } },
                .{ .name = "hasCode", .value = .{ .Int = .{ .Bool = false } } },
                .{ .name = "debuggable", .value = .{ .Int = .{ .Bool = true } } },
            },
            .children = &.{
                Element{
                    .name = "activity",
                    .attributes = &.{
                        .{ .name = "name", .value = .{ .String = "android.app.NativeActivity" } },
                        .{ .name = "configChanges", .value = .{ .Int = .{ .Hex = 0 } } },
                    },
                    .children = &.{
                        Element{
                            .name = "meta-data",
                            .attributes = &.{
                                .{ .name = "name", .value = .{ .String = "android.app.lib_name" } },
                                .{ .name = "value", .value = .{ .Reference = 0 } },
                            },
                        },
                        Element{
                            .name = "intent-filter",
                            .children = &.{
                                Element{
                                    .name = "action",
                                    .attributes = &.{
                                        .{ .name = "name", .value = .{ .String = "android.intent.action.MAIN" } },
                                    },
                                },
                                Element{
                                    .name = "category",
                                    .attributes = &.{
                                        .{ .name = "name", .value = .{ .String = "android.intent.category.LAUNCHER" } },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    } };
}

// /// Builder
// const AXML = struct {
//     elements: std.ArrayList(Element),
//     pub fn init(alloc: std.mem.Allocator) AXML {
//         return AXML{};
//     }
// };

// test "building xml tree" {
//     const std = @import("std");
//     const testing = std.testing;

//     var arena = std.heap.ArenaAllocator(testing.allocator);
//     const alloc = arena.allocator();
//     var tree = AXML.init(alloc);
//     const android = Namespace{ .prefix = "android", .uri = "http://schemas.android.com/apk/res/android" };
//     const root = tree.root(AXML.namespace(android));
//     tree.addChild(root, AXML.el(null, "manifest", .{
//         .{ android, "compileSdkVersion", AXML.int(30) },
//         .{ android, "compileSdkVersionCode", AXML.int(11) },
//         .{ android, "package", AXML.string("net.random_projects.zig_android_template") },
//         .{ android, "platformBuildVersionCode", AXML.int(30) },
//         .{ android, "platformBuildVersionName", AXML.int(11) },
//     }));
// }
