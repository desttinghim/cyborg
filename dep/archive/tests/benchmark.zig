const std = @import("std");
const builtin = @import("builtin");

const alloc = std.heap.page_allocator;

pub fn Benchmark(
    comptime datasets: anytype,
    comptime runtime_sec: comptime_int,
) type {
    return struct {
        const Self = @This();

        measurements: [datasets.len]std.ArrayListUnmanaged(f64) = .{.{}} ** datasets.len,
        sizes: [datasets.len]usize = .{0} ** datasets.len,

        timer: std.time.Timer = undefined,
        iteration: usize = 0,

        pub fn run(self: *Self) bool {
            if (self.iteration == 0) {
                self.timer = std.time.Timer.start() catch unreachable;
            }

            self.iteration += 1;

            if (self.timer.read() >= runtime_sec * std.time.ns_per_s)
                return false;

            return true;
        }

        pub fn add(self: *Self, comptime field: []const u8, measurement: u64) void {
            self.measurements[indexOf(field)]
                .append(alloc, @as(f64, @floatFromInt(measurement))) catch @panic("oom");
        }

        pub fn setSize(self: *Self, comptime field: []const u8, size: usize) void {
            self.sizes[indexOf(field)] = size;
        }

        fn indexOf(comptime field: []const u8) comptime_int {
            inline for (datasets, 0..) |dataset, i| {
                if (std.mem.eql(u8, dataset, field)) return i;
            }

            unreachable;
        }

        pub fn min(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var val: f64 = std.math.inf(f64);

            for (items) |measurement| {
                if (measurement < val) val = measurement;
            }

            return val;
        }

        pub fn max(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var val: f64 = -std.math.inf(f64);

            for (items) |measurement| {
                if (measurement > val) val = measurement;
            }

            return val;
        }

        pub fn sum(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var this_sum: f64 = 0.0;

            for (items) |measurement| {
                this_sum += measurement;
            }

            return this_sum;
        }

        pub fn mean(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            return self.sum(field) / @as(f64, @floatFromInt(items.len));
        }

        pub fn median(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            std.sort.insertion(f64, items, {}, comptime std.sort.asc(f64));

            if (items.len % 2 == 0) {
                return (items[items.len / 2] + items[items.len / 2 - 1]) / 2;
            } else {
                return items[items.len / 2];
            }
        }

        pub fn stddev(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var sum_sq: f64 = 0.0;

            for (items) |measurement| {
                sum_sq += measurement * measurement;
            }

            const avg = self.mean(field);

            return std.math.sqrt(sum_sq / @as(f64, @floatFromInt(items.len)) - avg * avg);
        }

        pub fn confidence(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            const dev = self.stddev(field);

            return 2.58 * dev / std.math.sqrt(@as(f64, @floatFromInt(items.len)));
        }

        pub fn meanSpeed(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var this_sum: f64 = 0.0;

            for (items) |measurement| {
                this_sum += @as(f64, @floatFromInt(self.sizes[indexOf(field)])) / (measurement / 1e9);
            }

            return this_sum / @as(f64, @floatFromInt(items.len));
        }

        pub fn stddevSpeed(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            var sum_sq: f64 = 0.0;

            for (items) |measurement| {
                const speed = @as(f64, @floatFromInt(self.sizes[indexOf(field)])) / (measurement / 1e9);

                sum_sq += speed * speed;
            }

            const avg = self.meanSpeed(field);

            return std.math.sqrt(sum_sq / @as(f64, @floatFromInt(items.len)) - avg * avg);
        }

        pub fn confidenceSpeed(self: Self, comptime field: []const u8) f64 {
            const items = self.measurements[indexOf(field)].items;

            const dev = self.stddevSpeed(field);

            return 2.58 * dev / std.math.sqrt(@as(f64, @floatFromInt(items.len)));
        }

        pub fn reportSingle(self: Self, comptime field: []const u8) void {
            std.debug.print(
                \\{s} ({d} samples):
                \\  min: {}
                \\  max: {}
                \\  mean: {} ± {}
                \\  median: {}
                \\  stddev: {}
                \\  speed: {} ± {}
                \\
                \\
            , .{
                field,
                self.iteration,
                Nanoseconds{ .data = self.min(field) },
                Nanoseconds{ .data = self.max(field) },
                Nanoseconds{ .data = self.mean(field) },
                Nanoseconds{ .data = self.confidence(field) },
                Nanoseconds{ .data = self.median(field) },
                Nanoseconds{ .data = self.stddev(field) },
                BytesPerSecond{ .data = self.meanSpeed(field) },
                BytesPerSecond{ .data = self.confidenceSpeed(field) },
            });
        }

        pub fn report(self: Self) void {
            inline for (datasets) |dataset| {
                self.reportSingle(dataset);
            }
        }
    };
}

fn formatBytesPerSecond(
    data: f64,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    if (data > 1024 * 1024 * 1024) {
        try writer.print("{d:.3} GB/s", .{data / (1024 * 1024 * 1024)});
    } else if (data > 1024 * 1024) {
        try writer.print("{d:.3} MB/s", .{data / (1024 * 1024)});
    } else if (data > 1024) {
        try writer.print("{d:.3} KB/s", .{data / (1024)});
    } else {
        try writer.print("{d:.3} B/s", .{data});
    }
}

const BytesPerSecond = std.fmt.Formatter(formatBytesPerSecond);

fn formatNanoseconds(
    data: f64,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    if (data > std.time.ns_per_min) {
        try writer.print("{d:.3} min", .{data / std.time.ns_per_min});
    } else if (data > std.time.ns_per_s) {
        try writer.print("{d:.3} s", .{data / std.time.ns_per_s});
    } else if (data > std.time.ns_per_ms) {
        try writer.print("{d:.3} ms", .{data / std.time.ns_per_ms});
    } else if (data > std.time.ns_per_us) {
        try writer.print("{d:.3} us", .{data / std.time.ns_per_us});
    } else {
        try writer.print("{d:.3} ns", .{data});
    }
}

const Nanoseconds = std.fmt.Formatter(formatNanoseconds);
