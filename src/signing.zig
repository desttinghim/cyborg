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
    V2: std.ArrayList(Signer),

    pub fn deinit(entry: *SigningEntry) void {
        switch (entry) {
            inline else => |list| {
                for (list.items) |item| {
                    item.deinit();
                }
                list.deinit();
            },
        }
    }

    pub const Tag = enum(u32) {
        V2 = 0x7109871a,
        _,
    };

    pub const Signer = struct {
        alloc: std.mem.Allocator,
        signed_data: std.ArrayListUnmanaged(SignedData),
        signatures: std.ArrayListUnmanaged(Signature),
        public_key: std.crypto.Certificate.Parsed,

        pub fn deinit(signer: *Signer) void {
            for (signer.signed_data.items) |signed_data| {
                signed_data.deinit();
            }
            for (signer.signatures.items) |signature| {
                signature.deinit();
            }
            signer.signed_data.clearAndFree();
            signer.signatures.clearAndFree();
            signer.alloc.free(signer.public_key.certificate.buffer);
        }

        pub const SignedData = struct {
            alloc: std.mem.Allocator,
            digests: std.ArrayListUnmanaged([]const u8),
            certificates: std.ArrayListUnmanaged(std.crypto.Certificate.Parsed),
            attributes: std.ArrayListUnmanaged(Attribute),

            pub fn deinit(signed_data: *SignedData) void {
                for (signed_data.digests.items) |digest| {
                    signed_data.alloc.free(digest);
                }
                for (signed_data.certificates.items) |certificate| {
                    signed_data.alloc.free(certificate.certificate.Certificate);
                }
                signed_data.digests.clearAndFree(signed_data.alloc);
                signed_data.certificates.clearAndFree(signed_data.alloc);
                signed_data.attributes.clearAndFree(signed_data.alloc);
            }

            const digest_magic = 0x5a;
            const Attribute = struct {};
        };

        pub const Signature = struct {
            algorithm: std.crypto.Certificate.Algorithm,
            signature: []const u8,

            pub fn deinit(signature: *Signature) void {
                signature.alloc.free(signature.signature);
            }
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

pub fn get_signing_blocks(alloc: std.mem.Allocator, stream_source: *std.io.StreamSource, directory_offset: u64) !std.AutoArrayHashMap(SigningEntry.Tag, OffsetSlice) {
    // Verify that the magic bytes are present
    const magic_byte_offset = directory_offset - 16;
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

    const block_start = directory_offset - block_size;

    const block_size_offset_2 = block_start - 8;

    try stream_source.seekTo(block_size_offset_2);

    const block_size_2 = try stream_source.reader().readInt(u64, .Little);

    if (block_size != block_size_2) return error.BlockSizeMismatch;

    // Create the hashmap and add all the signing blocks to it

    var id_value_pairs = std.AutoArrayHashMap(SigningEntry.Tag, OffsetSlice).init(alloc);
    errdefer id_value_pairs.deinit();

    while (try stream_source.getPos() < block_size_offset) {
        const size = try stream_source.reader().readInt(u64, .Little);
        const id = @intToEnum(SigningEntry.Tag, try stream_source.reader().readInt(u32, .Little));
        const pos = try stream_source.getPos();
        if (pos + size - 4 > try stream_source.getEndPos()) return error.LengthTooLarge;

        try id_value_pairs.put(id, .{ .start = pos, .end = pos + size - 4 });

        try stream_source.seekBy(@intCast(i64, size - 4));
    }

    return id_value_pairs;
}

pub fn parse_v2(alloc: std.mem.Allocator, stream_source: *std.io.StreamSource, stream_slice: OffsetSlice) !SigningEntry {
    try stream_source.seekTo(stream_slice.start);

    var signers = std.ArrayList(SigningEntry.Signer).init(alloc);
    errdefer signers.deinit();

    const signer_list_length = try stream_source.reader().readInt(u32, .Little);
    const signer_list_pos = try stream_source.getPos();
    while (try stream_source.getPos() < signer_list_pos + signer_list_length) {
        var signed_data = std.ArrayListUnmanaged(SigningEntry.Signer.SignedData){};
        errdefer signed_data.clearAndFree(alloc);

        const signer_length = try stream_source.reader().readInt(u32, .Little);
        _ = signer_length;
        const signer_pos = try stream_source.getPos();
        _ = signer_pos;

        const signed_data_pos = try stream_source.getPos();
        const signed_data_length = try stream_source.reader().readInt(u32, .Little);

        // Signed Data
        while (try stream_source.getPos() < signed_data_pos + signed_data_length) {
            var digests = std.ArrayListUnmanaged([]const u8){};
            errdefer {
                for (digests.items) |digest| {
                    alloc.free(digest);
                }
                digests.clearAndFree(alloc);
            }

            const digest_chunks_length = try stream_source.reader().readInt(u32, .Little);
            const digest_chunks_pos = try stream_source.getPos();

            const digest_chunk_pos = try stream_source.getPos();
            _ = digest_chunk_pos;
            const digest_chunk_length = try stream_source.reader().readInt(u32, .Little);
            _ = digest_chunk_length;
            const signature_algorithm_id = try stream_source.reader().readInt(u32, .Little);

            while (try stream_source.getPos() < digest_chunks_pos + digest_chunks_length) {
                const digest_pos = try stream_source.getPos();
                _ = digest_pos;
                const digest_length = try stream_source.reader().readInt(u32, .Little);
                switch (signature_algorithm_id) {
                    0x101, 0x102, 0x103, 0x104, 0x201, 0x202, 0x301 => {},
                    else => return error.InvalidSignatureAlgorithm,
                }
                const digest = try alloc.alloc(u8, digest_length);
                try digests.append(alloc, digest);
                try stream_source.seekBy(digest_length);
            }

            var x509_list = std.ArrayListUnmanaged(std.crypto.Certificate.Parsed){};
            errdefer x509_list.clearAndFree(alloc);

            const x509_list_pos = try stream_source.getPos();
            const x509_list_length = try stream_source.reader().readInt(u32, .Little);
            while (try stream_source.getPos() < x509_list_pos + x509_list_length) {
                const x509_pos = try stream_source.getPos();
                _ = x509_pos;
                const x509_length = try stream_source.reader().readInt(u32, .Little);
                var buf: [1024]u8 = undefined;
                std.debug.assert(x509_length == try stream_source.reader().read(buf[0..x509_length]));

                const x509 = buf[0..x509_length];

                var cert = std.crypto.Certificate{
                    .buffer = x509,
                    .index = 0,
                };
                var parsed = try cert.parse();

                try x509_list.append(alloc, parsed);
            }

            var attributes = std.ArrayListUnmanaged(SigningEntry.Signer.SignedData.Attribute){};
            // errdefer attributes.clearAndFree(alloc);

            const attribute_list_pos = try stream_source.getPos();
            const attribute_list_length = try stream_source.reader().readInt(u32, .Little);
            while (try stream_source.getPos() < attribute_list_pos + attribute_list_length) {
                const attribute_pos = try stream_source.getPos();
                _ = attribute_pos;
                const attribute_length = try stream_source.reader().readInt(u32, .Little);
                const attribute_id = try stream_source.reader().readInt(u32, .Little);
                _ = attribute_id;
                try stream_source.seekBy(attribute_length - 4);
            }

            try signed_data.append(alloc, .{
                .alloc = alloc,
                .digests = digests,
                .certificates = x509_list,
                .attributes = attributes,
            });
        }

        var signatures = std.ArrayListUnmanaged(SigningEntry.Signer.Signature){};
        errdefer signatures.deinit(alloc);

        // Signatures
        const signatures_length = try stream_source.reader().readInt(u32, .Little);
        const signatures_pos = try stream_source.getPos();
        while (try stream_source.getPos() < signatures_pos + signatures_length) {
            const signature_length = try stream_source.reader().readInt(u32, .Little);
            const signature_pos = try stream_source.getPos();
            _ = signature_pos;
            const signature_algorithm_id = try stream_source.reader().readInt(u32, .Little);
            _ = signature_algorithm_id;
            const signature_over_data_length = try stream_source.reader().readInt(u32, .Little);
            _ = signature_over_data_length;
            try stream_source.seekBy(signature_length - 8);
        }

        // Public Key
        const public_key_length = try stream_source.reader().readInt(u32, .Little);
        const public_key_pos = try stream_source.getPos();
        _ = public_key_pos;
        const public_key_buffer = try alloc.alloc(u8, public_key_length);
        std.debug.assert(try stream_source.read(public_key_buffer) == public_key_length);
        const public_key_cert = std.crypto.Certificate{
            .buffer = public_key_buffer,
            .index = 0,
        };
        const public_key = try public_key_cert.parse();
        // try stream_source.seekBy(@intCast(i64, public_key_pos + public_key_length));

        try signers.append(.{
            .alloc = alloc,
            .signed_data = signed_data,
            .signatures = signatures,
            .public_key = public_key,
        });
    }

    return SigningEntry{ .V2 = signers };
}

// Imports
const std = @import("std");
const archive = @import("archive");
