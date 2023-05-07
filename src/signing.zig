//! This file implements signing and verification of Android APKs as described at the
//! [Android Source APK Signature Scheme v2 page (as of 2023-04-16)][https://source.android.com/docs/security/features/apksigning/v2]

const SigningBlock = struct {
    stream_source: std.io.StreamSource,
    buffer: []const u8,
    size_of_block: u64,
    entries: []SigningEntry,
    // size_of_block repeated
    magic: [16]u8 = "APK Sig Block 42",
};

pub const SigningEntry = union(Tag) {
    V2: []Signer,

    pub const Tag = enum(u32) {
        V2 = 0x7109871a,
    };

    pub const Signer = struct {
        signed_data: []SignedData,
        signatures: []Signature,
        public_key: std.crypto.Certificate,

        pub const SignedData = struct {
            digests: [][]const u8,
            certificates: std.crypto.Certificate,
            attributes: []Attribute,

            const digest_magic = 0x5a;
            const Attribute = struct {};
        };

        pub const Signature = struct {
            algorithm: std.crypto.Certificate.Algorithm,
            signature: []const u8,
        };
    };
};

const Sections = struct {
    stream_source: *std.io.StreamSource,
    contents_index: u64,
    signing_block_index: u64,
    central_directory_index: u64,
    end_of_central_directory_index: u64,
};

/// Intermediate data structure for signing/verifying an APK. Each section is split into chunks.
/// Each chunk is 1MB, unless it is the final chunk in a section, in which case it may be smaller.
const Chunks = struct {
    sections: *Sections,
    chunks: []Slice,

    const magic = 0xa5;
    const Slice = struct {
        start: u64,
        end: u64,
    };
};

/// Splits an APK into chunks for signing/verifying.
fn splitAPK(alloc: std.mem.Allocator, file: std.fs.File) Chunks {
    var stream_source = std.io.StreamSource{ .file = file };

    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);
    try archive_reader.load();

    // Verify that the magic bytes are present

    const magic_byte_offset = archive_reader.directory_offset - 16;
    {
        var buf: [16]u8 = undefined;

        try stream_source.seekTo(magic_byte_offset);

        std.debug.assert(try stream_source.read(&buf) == 16);

        if (!std.mem.eql(u8, &buf, "APK Sig Block 42")) return error.MissingSigningBlock;
    }

    // Get the block size

    const block_size_offset = magic_byte_offset - 8;

    try stream_source.seekTo(block_size_offset);

    const block_size = try stream_source.reader().readInt(u64, .Little);

    const block_start = archive_reader.directory_offset - block_size;

    const block_size_offset_2 = block_start - 8;

    try stream_source.seekTo(block_size_offset_2);

    const block_size_2 = try stream_source.reader().readInt(u64, .Little);

    if (block_size != block_size_2) return error.BlockSizeMismatch;
}

/// Verifies that a signed APK is valid.
/// [The following description of the algorithm is copied from the Android Source documentation.][https://source.android.com/docs/security/features/apksigning/v2#v2-verification]
/// 1. Locate the signing block and verify that the
///    a. two size fields of the APK Signing Block contain the same value
///    b. ZIP central directory is immediately followed by the ZIP end of central directory record
///    c. ZIP end of central directory record is not followed by more data
/// 2. Locate the first APK signature scheme v2 block inside the APK signing block. If the v2 block is present,
///    proceed to step 3. Otherwise, fallback to verifying the APK using v1 scheme.
/// 3. For each signer in the APK Signature Scheme v2 Block:
///    a. Choose the strongest supported `signature algorithm ID` from `signatures`. The strength ordering is up
///       to each implementation/platform version
///    b. Verify the corresponding `signature` from `signatures` against `signed data` using `public key`. (It
///       is now safe to parse `signed data`.)
///    c. Verify that the ordered list of signature algorithm IDs in `digests` and `signatures` is identical.
///       (This is to prevent signature stripping/addition.)
///    d. (Compute the digest of the APK contents)[https://source.android.com/docs/security/features/apksigning/v2#integrity-protected-contents]
///       using the same digest algorithm as the digest algorithm used by the signature algorithm.
///    e. Verify that the computed digest is identical to the corresponding `digest` from `digests`
///    f. Verify that `SubjectPublicKeyInfo` of the first `certificate` of `certificates` is identical to `public key`.
/// 4. Verification succeeds if at least one `signer` was found and step 3 succeeded for each found `signer`.
pub fn verify() void {}

pub const OffsetSlice = struct { start: u64, end: u64 };

pub fn get_signing_blocks(alloc: std.mem.Allocator, stream_source: *std.io.StreamSource, archive_reader: archive.formats.zip.reader.ArchiveReader) !std.AutoArrayHashMap(u32, OffsetSlice) {
    // Verify that the magic bytes are present
    const magic_byte_offset = archive_reader.directory_offset - 16;
    {
        var buf: [16]u8 = undefined;

        try stream_source.seekTo(magic_byte_offset);

        std.debug.assert(try stream_source.read(&buf) == 16);

        if (!std.mem.eql(u8, &buf, "APK Sig Block 42")) return error.MissingSigningBlock;
    }

    // Get the block size

    const block_size_offset = magic_byte_offset - 8;

    try stream_source.seekTo(block_size_offset);

    const block_size = try stream_source.reader().readInt(u64, .Little);

    const block_start = archive_reader.directory_offset - block_size;

    const block_size_offset_2 = block_start - 8;

    try stream_source.seekTo(block_size_offset_2);

    const block_size_2 = try stream_source.reader().readInt(u64, .Little);

    if (block_size != block_size_2) return error.BlockSizeMismatch;

    // Create the hashmap and add all the signing blocks to it

    var id_value_pairs = std.AutoArrayHashMap(u32, OffsetSlice).init(alloc);
    errdefer id_value_pairs.deinit();

    while (try stream_source.getPos() < block_size_offset) {
        const size = try stream_source.reader().readInt(u64, .Little);
        const id = try stream_source.reader().readInt(u32, .Little);
        const pos = try stream_source.getPos();
        if (pos + size - 4 > try stream_source.getEndPos()) return error.LengthTooLarge;

        try id_value_pairs.put(id, .{ .start = pos, .end = pos + size - 4 });

        try stream_source.seekBy(@intCast(i64, size - 4));
    }

    return id_value_pairs;
}

// Imports
const std = @import("std");
const archive = @import("archive");
