const std = @import("std");

const CRC_Magic = 0xdebb20e3;

pub const GeneralFlags = packed struct(u16) {
    encrypted_file: bool,
    compression1: bool,
    compression2: bool,
    data_descriptor: bool,
    enhanced_deflation: bool,
    compressed_patched_data: bool,
    strong_encryption: bool,
    _unused: u4,
    lang_encoding: bool,
    _reserved: u1,
    mask_header_values: bool,
    _reserved2: u2,

    pub fn read(reader: anytype) !GeneralFlags {
        return @bitCast(GeneralFlags, try reader.readInt(u16, .Little));
    }
};

pub const CompressionMethod = enum(u16) {
    None = 0,
    Shrunk = 1,
    ReducedFactor1 = 2,
    ReducedFactor2 = 3,
    ReducedFactor3 = 4,
    ReducedFactor4 = 5,
    Imploded = 6,
    _reserved = 7,
    Deflated = 8,
    EnhancedDeflated = 9,
    PKWareDCLImploded = 10,
    _reserved2 = 11,
    Bzip2 = 12,
    Lzma = 14,
    IbmTerse = 18,
    IbmLz77 = 19,
    PPMdversionIrevision1 = 98,

    pub fn read(reader: anytype) !CompressionMethod {
        const i = try reader.readInt(u16, .Little);
        return std.meta.intToEnum(CompressionMethod, i) catch |e| {
            std.log.debug("Invalid Compression Method value: {}", .{i});
            return e;
        };
    }
};

pub const DosTime = packed struct(u16) {
    seconds: u5,
    minute: u5,
    hour: u6,

    pub fn read(reader: anytype) !DosTime {
        return @bitCast(DosTime, try reader.readInt(u16, .Little));
    }
};

pub const DosDate = packed struct(u16) {
    day: u4,
    month: u4,
    years: u8,

    pub fn read(reader: anytype) !DosDate {
        return @bitCast(DosDate, try reader.readInt(u16, .Little));
    }
};

pub const LocalFileHeader = struct {
    const SIGNATURE = "PK\x03\x04";
    signature: [4]u8,
    version: Version,
    flags: GeneralFlags,
    compression: CompressionMethod,
    last_modified_time: DosTime,
    last_modified_date: DosDate,
    crc_32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    filename_length: u16,
    extra_field_length: u16,

    pub fn readHeader(reader: anytype, cd: CentralDirectoryFileHeader) !LocalFileHeader {
        _ = cd;
        var file_header: LocalFileHeader = undefined;
        std.debug.assert(try reader.read(&file_header.signature) == 4);
        std.debug.assert(std.mem.eql(u8, SIGNATURE, &file_header.signature));
        file_header.version = try Version.read(reader);
        file_header.flags = try GeneralFlags.read(reader);
        file_header.compression = try CompressionMethod.read(reader);
        file_header.last_modified_time = try DosTime.read(reader);
        file_header.last_modified_date = try DosDate.read(reader);
        file_header.crc_32 = try reader.readInt(u32, .Little);
        file_header.compressed_size = try reader.readInt(u32, .Little);
        file_header.uncompressed_size = try reader.readInt(u32, .Little);
        file_header.filename_length = try reader.readInt(u16, .Little);
        file_header.extra_field_length = try reader.readInt(u16, .Little);

        try reader.skipBytes(file_header.filename_length, .{});

        return file_header;
    }
};

pub const System = enum(u8) {
    MSDOS = 0,
    Amiga = 1,
    OpenVMS = 2,
    Unix = 3,
    VM_CMS = 4,
    AtariST = 5,
    OS2HPFS = 6,
    Macintosh = 7,
    ZSystem = 8,
    CPM = 9,
    WindowsNTFS = 10,
    MVS = 11,
    VSE = 12,
    AcornRISC = 13,
    VFAT = 14,
    altMVS = 15,
    BeOS = 16,
    Tandem = 17,
    OS400 = 18,
    OSX_Darwin = 19,
};

pub const Version = packed struct(u16) {
    version: u8,
    system: System,

    pub fn read(reader: anytype) !Version {
        return @bitCast(Version, try reader.readInt(u16, .Little));
    }
};

pub const InternalFileAttr = packed struct(u16) {
    ascii: bool,
    _reserved: bool,
    do_control_record_precede_logical_record: bool,
    _unused: u13,

    pub fn read(reader: anytype) !InternalFileAttr {
        return @bitCast(InternalFileAttr, try reader.readInt(u16, .Little));
    }
};

pub const CentralDirectoryFileHeader = struct {
    const SIGNATURE = "PK\x01\x02";
    pos: usize,
    signature: [4]u8,
    version_madeby: Version,
    version_needed: Version,
    flags: GeneralFlags,
    compression: CompressionMethod,
    last_modified_time: DosTime,
    last_modified_date: DosDate,
    crc_32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    filename_length: u16,
    extra_field_length: u16,
    file_comment_length: u16,
    disk_number: u16,
    internal_file_attr: InternalFileAttr,
    external_file_attr: u32,
    relative_offset: u32,
    filename: []u8,
    extra_field: []u8,
    file_comment: []u8,

    pub fn read(alloc: std.mem.Allocator, reader: anytype, pos: usize) !CentralDirectoryFileHeader {
        var file_header: CentralDirectoryFileHeader = undefined;
        file_header.pos = pos;
        std.debug.assert(try reader.read(&file_header.signature) == 4);
        std.debug.assert(std.mem.eql(u8, SIGNATURE, &file_header.signature));
        file_header.version_madeby = try Version.read(reader);
        file_header.version_needed = try Version.read(reader);
        file_header.flags = try GeneralFlags.read(reader);
        file_header.compression = try CompressionMethod.read(reader);
        file_header.last_modified_time = try DosTime.read(reader);
        file_header.last_modified_date = try DosDate.read(reader);
        file_header.crc_32 = try reader.readInt(u32, .Little);
        file_header.compressed_size = try reader.readInt(u32, .Little);
        file_header.uncompressed_size = try reader.readInt(u32, .Little);
        file_header.filename_length = try reader.readInt(u16, .Little);
        file_header.extra_field_length = try reader.readInt(u16, .Little);
        file_header.file_comment_length = try reader.readInt(u16, .Little);
        file_header.disk_number = try reader.readInt(u16, .Little);
        file_header.internal_file_attr = try InternalFileAttr.read(reader);
        file_header.external_file_attr = try reader.readInt(u32, .Little);
        file_header.relative_offset = try reader.readInt(u32, .Little);

        file_header.filename = try alloc.alloc(u8, file_header.filename_length);
        _ = try reader.read(file_header.filename);
        file_header.extra_field = try alloc.alloc(u8, file_header.extra_field_length);
        _ = try reader.read(file_header.extra_field);
        file_header.file_comment = try alloc.alloc(u8, file_header.file_comment_length);
        _ = try reader.read(file_header.file_comment);
        return file_header;
    }
};

pub const CentralDirectoryEndRecord = struct {
    const SIGNATURE = "PK\x05\x06";
    stream_pos: usize,
    signature: [4]u8,
    disk_number: u16,
    central_directory_disk: u16,
    record_count: u16,
    total_record_count: u16,
    directory_size: u32,
    directory_offset: u32,
    comment_length: u16,
    comment: ?[]u8,

    /// Expects a File
    pub fn findEndRecord(file: anytype) !CentralDirectoryEndRecord {
        var i: usize = 22; // minimum possible record size
        var signature: [4]u8 = undefined;
        try file.seekTo(try file.getEndPos() - i);
        _ = try file.read(&signature);
        if (!std.mem.eql(u8, CentralDirectoryEndRecord.SIGNATURE, &signature)) {
            return error.CouldntRead;
        }
        try file.seekTo(try file.getEndPos() - i);
        var end_record = CentralDirectoryEndRecord.read(file.reader(), i);
        return end_record;
    }

    pub fn read(reader: anytype, pos: usize) !CentralDirectoryEndRecord {
        var end_record: CentralDirectoryEndRecord = undefined;
        end_record.stream_pos = pos;
        _ = try reader.read(&end_record.signature);
        std.debug.assert(std.mem.eql(u8, SIGNATURE, &end_record.signature));
        end_record.disk_number = try reader.readInt(u16, .Little);
        end_record.central_directory_disk = try reader.readInt(u16, .Little);
        end_record.record_count = try reader.readInt(u16, .Little);
        end_record.total_record_count = try reader.readInt(u16, .Little);
        end_record.directory_size = try reader.readInt(u32, .Little);
        end_record.directory_offset = try reader.readInt(u32, .Little);
        end_record.comment_length = try reader.readInt(u16, .Little);
        end_record.comment = null;
        return end_record;
    }

    pub fn readComment(end_record: *CentralDirectoryEndRecord, reader: anytype, buffer: []u8) !usize {
        return reader.read(buffer[0..end_record.comment_length]);
    }
};

pub const ZIP = struct {
    file: std.fs.File,
    directory_headers: []CentralDirectoryFileHeader,
    end_record: CentralDirectoryEndRecord,

    pub fn init(file: std.fs.File) !ZIP {
        return ZIP{
            .file = file,
            .directory_headers = &.{},
            .end_record = CentralDirectoryEndRecord{
                .stream_pos = 0,
                .signature = CentralDirectoryEndRecord.SIGNATURE,
                .disk_number = 0,
                .central_directory_disk = 0,
                .record_count = 0,
                .total_record_count = 0,
                .directory_size = 0,
                .directory_offset = 0,
                .comment_length = 0,
                .comment = null,
            },
        };
    }

    pub fn initFromFile(alloc: std.mem.Allocator, file: std.fs.File) !ZIP {
        var end_record = try CentralDirectoryEndRecord.findEndRecord(file);

        const records = try alloc.alloc(CentralDirectoryFileHeader, end_record.record_count);

        try file.seekTo(end_record.directory_offset);
        const reader = file.reader();
        var i: usize = 0;
        while (i < end_record.record_count) : (i += 1) {
            records[i] = try CentralDirectoryFileHeader.read(alloc, reader, try file.getPos());
        }

        return ZIP{
            .file = file,
            .end_record = end_record,
            .directory_headers = records,
        };
    }

    pub fn getFileRecord(zip: *const ZIP, filename: []const u8) ?CentralDirectoryFileHeader {
        for (zip.directory_headers) |file_record| {
            if (std.mem.eql(u8, file_record.filename, filename)) {
                return file_record;
            }
        }
        return null;
    }

    /// Returns file with filenam
    pub fn getFileAlloc(zip: *ZIP, alloc: std.mem.Allocator, filename: []const u8) !?[]const u8 {
        for (zip.directory_headers) |file_record| {
            if (std.mem.eql(u8, file_record.filename, filename)) {
                const reader = zip.file.reader();
                try zip.file.seekTo(file_record.relative_offset);
                const local_file = try LocalFileHeader.readHeader(reader, file_record);
                const slice = try alloc.alloc(u8, local_file.uncompressed_size);
                switch (local_file.compression) {
                    .None => {
                        _ = try reader.read(slice);
                    },
                    .Deflated => {
                        var decompressor = try std.compress.deflate.decompressor(alloc, reader, null);
                        defer decompressor.deinit();
                        _ = try decompressor.read(slice);
                    },
                    else => return error.UnimplementedCompressionMethod,
                }
                return slice;
            }
        }
        return null;
    }
};
