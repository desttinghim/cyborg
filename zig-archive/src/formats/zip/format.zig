const std = @import("std");

const mem = std.mem;

// Add more methods as they're supported
pub const CompressionMethod = enum(u16) {
    none = 0,
    deflated = 8,
    enhanced_deflated,
    _,
};

const Crc32Poly = @as(std.hash.crc.Polynomial, @enumFromInt(0xEDB88320));
pub const Crc32 = std.hash.crc.Crc32WithPoly(Crc32Poly);

pub const Version = struct {
    pub const Vendor = enum(u8) {
        dos = 0,
        amiga,
        openvms,
        unix,
        vm,
        atari,
        os2_hpfs,
        macintosh,
        z_system,
        cp_m,
        ntfs,
        mvs,
        vse,
        acorn,
        vfat,
        alt_mvs,
        beos,
        tandem,
        os400,
        osx,
        _,
    };

    vendor: Vendor,
    major: u8,
    minor: u8,

    pub fn read(entry: u16) Version {
        var ver: Version = undefined;

        ver.major = @as(u8, @truncate(entry)) / 10;
        ver.minor = @as(u8, @truncate(entry)) % 10;
        ver.vendor = @as(Vendor, @enumFromInt(@as(u8, @truncate(entry >> 8))));

        return ver;
    }

    pub fn write(self: Version) u16 {
        const version = @as(u16, self.major * 10 + self.minor);
        const vendor = @as(u16, @intFromEnum(self.vendor)) << 8;

        return version | vendor;
    }

    pub fn check(self: Version) bool {
        if (self.major < 4) {
            return true;
        } else if (self.major == 4 and self.minor <= 5) {
            return true;
        } else {
            return false;
        }
    }
};

pub const GeneralPurposeBitFlag = packed struct {
    encrypted: bool,
    compression1: u1,
    compression2: u1,
    data_descriptor: bool,
    enhanced_deflation: u1,
    compressed_patched: bool,
    strong_encryption: bool,
    __7_reserved: u1,
    __8_reserved: u1,
    __9_reserved: u1,
    __10_reserved: u1,
    is_utf8: bool,
    __12_reserved: u1,
    mask_headers: bool,
    __14_reserved: u1,
    __15_reserved: u1,

    pub fn read(entry: u16) GeneralPurposeBitFlag {
        return @as(GeneralPurposeBitFlag, @bitCast(entry));
    }

    pub fn write(self: GeneralPurposeBitFlag) u16 {
        return @as(u16, @bitCast(self));
    }
};

pub const DosTimestamp = struct {
    second: u6,
    minute: u6,
    hour: u5,
    day: u5,
    month: u4,
    year: u12,

    pub fn read(entry: [2]u16) DosTimestamp {
        var self: DosTimestamp = undefined;

        self.second = @as(u6, @as(u5, @truncate(entry[0]))) << 1;
        self.minute = @as(u6, @truncate(entry[0] >> 5));
        self.hour = @as(u5, @truncate(entry[0] >> 11));

        self.day = @as(u5, @truncate(entry[1]));
        self.month = @as(u4, @truncate(entry[1] >> 5));
        self.year = @as(u12, @as(u7, @truncate(entry[1] >> 9))) + 1980;

        return self;
    }

    pub fn write(self: DosTimestamp) [2]u16 {
        var buf: [2]u8 = undefined;

        const second = @as(u16, @as(u5, @truncate(self.second >> 1)));
        const minute = @as(u16, @as(u5, @truncate(self.minute)) << 5);
        const hour = @as(u16, @as(u5, @truncate(self.hour)) << 11);

        buf[0] = second | minute | hour;

        const day = self.day;
        const month = self.month << 5;
        const year = (self.year - 1980) << 11;

        buf[1] = day | month | year;

        return buf;
    }
};

pub const LocalFileRecord = struct {
    pub const signature = 0x04034b50;
    pub const size = 30;

    signature: u32,
    version: u16,
    flags: GeneralPurposeBitFlag,
    compression_method: CompressionMethod,
    last_mod_time: u16,
    last_mod_date: u16,
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    filename_len: u16,
    extra_len: u16,

    pub fn read(reader: anytype) !LocalFileRecord {
        var self: LocalFileRecord = undefined;

        var buf: [30]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        self.signature = mem.readInt(u32, buf[0..4], .little);
        if (self.signature != signature) return error.InvalidSignature;

        self.version = mem.readInt(u16, buf[4..6], .little);
        self.flags = @as(GeneralPurposeBitFlag, @bitCast(mem.readInt(u16, buf[6..8], .little)));
        self.compression_method = @as(CompressionMethod, @enumFromInt(mem.readInt(u16, buf[8..10], .little)));
        self.last_mod_time = mem.readInt(u16, buf[10..12], .little);
        self.last_mod_date = mem.readInt(u16, buf[12..14], .little);
        self.crc32 = mem.readInt(u32, buf[14..18], .little);
        self.compressed_size = mem.readInt(u32, buf[18..22], .little);
        self.uncompressed_size = mem.readInt(u32, buf[22..26], .little);
        self.filename_len = mem.readInt(u16, buf[26..28], .little);
        self.extra_len = mem.readInt(u16, buf[28..30], .little);

        return self;
    }

    pub fn write(self: LocalFileRecord, writer: anytype) !void {
        try writer.writeInt(u32, signature, .little);

        try writer.writeInt(u16, self.version, .little);
        try writer.writeInt(u16, @as(u16, @bitCast(self.flags)), .little);
        try writer.writeInt(u16, @intFromEnum(self.compression_method), .little);
        try writer.writeInt(u16, self.last_mod_time, .little);
        try writer.writeInt(u16, self.last_mod_date, .little);
        try writer.writeInt(u32, self.crc32, .little);
        try writer.writeInt(u32, self.compressed_size, .little);
        try writer.writeInt(u32, self.uncompressed_size, .little);
        try writer.writeInt(u16, self.filename_len, .little);
        try writer.writeInt(u16, self.extra_len, .little);
    }
};

pub const CentralDirectoryRecord = struct {
    pub const signature = 0x02014b50;

    version_made: u16,
    version_needed: u16,
    flags: GeneralPurposeBitFlag,
    compression_method: CompressionMethod,
    last_mod_time: u16,
    last_mod_date: u16,
    crc32: u32,
    compressed_size: u64,
    uncompressed_size: u64,
    filename_len: u16,
    extra_len: u16 = 0,
    comment_len: u16 = 0,
    disk_number_start: u16 = 0,
    internal_attributes: u16 = 0,
    external_attributes: u32 = 0,
    local_offset: u64,

    filename_idx: usize,

    pub fn read(reader: anytype) !CentralDirectoryRecord {
        const sig = try reader.readInt(u32, .little);
        if (sig != signature) return error.InvalidSignature;

        var record: CentralDirectoryRecord = undefined;

        var buf: [42]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        record.version_made = mem.readInt(u16, buf[0..2], .little);
        record.version_needed = mem.readInt(u16, buf[2..4], .little);
        record.flags = @as(GeneralPurposeBitFlag, @bitCast(mem.readInt(u16, buf[4..6], .little)));
        record.compression_method = @as(CompressionMethod, @enumFromInt(mem.readInt(u16, buf[6..8], .little)));
        record.last_mod_time = mem.readInt(u16, buf[8..10], .little);
        record.last_mod_date = mem.readInt(u16, buf[10..12], .little);
        record.crc32 = mem.readInt(u32, buf[12..16], .little);
        record.compressed_size = mem.readInt(u32, buf[16..20], .little);
        record.uncompressed_size = mem.readInt(u32, buf[20..24], .little);
        record.filename_len = mem.readInt(u16, buf[24..26], .little);
        record.extra_len = mem.readInt(u16, buf[26..28], .little);
        record.comment_len = mem.readInt(u16, buf[28..30], .little);
        record.disk_number_start = mem.readInt(u16, buf[30..32], .little);
        record.internal_attributes = mem.readInt(u16, buf[32..34], .little);
        record.external_attributes = mem.readInt(u32, buf[34..38], .little);
        record.local_offset = mem.readInt(u32, buf[38..42], .little);

        return record;
    }

    pub fn write(self: CentralDirectoryRecord, writer: anytype) !void {
        try writer.writeInt(u32, signature, .little);

        try writer.writeInt(u16, self.version_made, .little);
        try writer.writeInt(u16, self.version_needed, .little);
        try writer.writeInt(u16, @as(u16, @bitCast(self.flags)), .little);
        try writer.writeInt(u16, @intFromEnum(self.compression_method), .little);
        try writer.writeInt(u16, self.last_mod_time, .little);
        try writer.writeInt(u16, self.last_mod_date, .little);
        try writer.writeInt(u32, self.crc32, .little);
        try writer.writeInt(u32, @as(u32, @truncate(self.compressed_size)), .little);
        try writer.writeInt(u32, @as(u32, @truncate(self.uncompressed_size)), .little);
        try writer.writeInt(u16, self.filename_len, .little);
        try writer.writeInt(u16, self.extra_len, .little);
        try writer.writeInt(u16, self.comment_len, .little);
        try writer.writeInt(u16, self.disk_number_start, .little);
        try writer.writeInt(u16, self.internal_attributes, .little);
        try writer.writeInt(u32, self.external_attributes, .little);
        try writer.writeInt(u32, @as(u32, @truncate(self.local_offset)), .little);
    }

    pub fn needs64(self: CentralDirectoryRecord) bool {
        return self.compressed_size == 0xffffffff or
            self.uncompressed_size == 0xffffffff or
            self.local_offset == 0xffffffff;
    }
};

pub const EndOfCentralDirectory64Record = struct {
    pub const signature = 0x06064b50;

    size: u64,
    version_made: u16,
    version_needed: u16,
    disk_number: u32 = 0,
    disk_central: u32 = 0,
    num_entries_disk: u64,
    num_entries_total: u64,
    directory_size: u64,
    directory_offset: u64,

    pub fn read(reader: anytype) !EndOfCentralDirectory64Record {
        const sig = try reader.readInt(u32, .little);
        if (sig != signature) return error.InvalidSignature;

        var record: EndOfCentralDirectory64Record = undefined;

        var buf: [52]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        record.size = mem.readInt(u64, buf[0..8], .little);
        record.version_made = mem.readInt(u16, buf[8..10], .little);
        record.version_needed = mem.readInt(u16, buf[10..12], .little);
        record.disk_number = mem.readInt(u32, buf[12..16], .little);
        record.disk_central = mem.readInt(u32, buf[16..20], .little);
        record.num_entries_disk = mem.readInt(u64, buf[20..28], .little);
        record.num_entries_total = mem.readInt(u64, buf[28..36], .little);
        record.directory_size = mem.readInt(u64, buf[36..44], .little);
        record.directory_offset = mem.readInt(u64, buf[44..52], .little);

        return record;
    }

    pub fn write(self: EndOfCentralDirectory64Record, writer: anytype) !void {
        try writer.writeInt(u32, signature, .little);
        try writer.writeInt(u64, self.size, .little);
        try writer.writeInt(u16, self.version_made, .little);
        try writer.writeInt(u16, self.version_needed, .little);
        try writer.writeInt(u32, self.disk_number, .little);
        try writer.writeInt(u32, self.disk_central, .little);
        try writer.writeInt(u64, self.num_entries_disk, .little);
        try writer.writeInt(u64, self.num_entries_total, .little);
        try writer.writeInt(u64, self.directory_size, .little);
        try writer.writeInt(u64, self.directory_offset, .little);
    }
};

pub const EndOfCentralDirectory64Locator = struct {
    pub const signature = 0x07064b50;

    disk_number: u32 = 0,
    offset: u64,
    num_disks: u32 = 1,

    pub fn read(reader: anytype) !EndOfCentralDirectory64Locator {
        // signature is consumed by the search algorithm

        var locator: EndOfCentralDirectory64Locator = undefined;

        var buf: [16]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        locator.disk_number = mem.readInt(u32, buf[0..4], .little);
        locator.offset = mem.readInt(u64, buf[4..12], .little);
        locator.num_disks = mem.readInt(u32, buf[12..16], .little);

        return locator;
    }

    pub fn write(self: EndOfCentralDirectory64Locator, writer: anytype) !void {
        try writer.writeInt(u32, signature, .little);
        try writer.writeInt(u32, self.disk_number, .little);
        try writer.writeInt(u64, self.offset, .little);
        try writer.writeInt(u32, self.num_disks, .little);
    }
};

pub const EndOfCentralDirectoryRecord = struct {
    pub const signature = 0x06054b50;

    disk_number: u16 = 0,
    disk_central: u16 = 0,
    entries_on_disk: u16,
    entries_total: u16,
    directory_size: u32,
    directory_offset: u32,
    comment_length: u16 = 0,

    pub fn read(reader: anytype) !EndOfCentralDirectoryRecord {
        // signature is consumed by the search algorithm

        var record: EndOfCentralDirectoryRecord = undefined;

        var buf: [18]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        record.disk_number = mem.readInt(u16, buf[0..2], .little);
        record.disk_central = mem.readInt(u16, buf[2..4], .little);
        record.entries_on_disk = mem.readInt(u16, buf[4..6], .little);
        record.entries_total = mem.readInt(u16, buf[6..8], .little);
        record.directory_size = mem.readInt(u32, buf[8..12], .little);
        record.directory_offset = mem.readInt(u32, buf[12..16], .little);
        record.comment_length = mem.readInt(u16, buf[16..18], .little);

        return record;
    }

    pub fn write(self: EndOfCentralDirectoryRecord, writer: anytype) !void {
        try writer.writeInt(u32, signature, .little);
        try writer.writeInt(u16, self.disk_number, .little);
        try writer.writeInt(u16, self.disk_central, .little);
        try writer.writeInt(u16, self.entries_on_disk, .little);
        try writer.writeInt(u16, self.entries_total, .little);
        try writer.writeInt(u32, self.directory_size, .little);
        try writer.writeInt(u32, self.directory_offset, .little);
        try writer.writeInt(u16, self.comment_length, .little);
    }

    pub fn needs64(self: EndOfCentralDirectoryRecord) bool {
        return self.directory_size == 0xffffffff or
            self.directory_offset == 0xffffffff or
            self.entries_total == 0xffff;
    }
};

pub const ExtraFieldZip64 = struct {
    uncompressed: ?u64 = null,
    compressed: ?u64 = null,
    offset: ?u64 = null,

    pub fn present(self: ExtraFieldZip64) bool {
        return !(self.uncompressed == null and self.compressed == null and self.offset == null);
    }

    pub fn length(self: ExtraFieldZip64) u16 {
        if (!self.present()) return 0;

        var size: u16 = 4;

        if (self.uncompressed != null) size += 8;
        if (self.compressed != null) size += 8;
        if (self.offset != null) size += 8;

        return size;
    }

    pub fn write(self: ExtraFieldZip64, writer: anytype) !void {
        if (!self.present()) return;

        try writer.writeInt(u16, 0x0001, .little);
        try writer.writeInt(u16, self.length() - 4, .little);

        if (self.uncompressed) |num| {
            try writer.writeInt(u64, num, .little);
        }

        if (self.compressed) |num| {
            try writer.writeInt(u64, num, .little);
        }

        if (self.offset) |num| {
            try writer.writeInt(u64, num, .little);
        }
    }
};
