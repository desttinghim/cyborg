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
        public_key: std.crypto.Certificate.rsa.PublicKey,

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
            algorithm: Algorithm,
            signature: []const u8,

            pub const Algorithm = enum(u32) {
                // 0x0101—RSASSA-PSS with SHA2-256 digest, SHA2-256 MGF1, 32 bytes of salt, trailer: 0xbc
                sha256_RSASSA_PSS = 0x0101,
                // 0x0102—RSASSA-PSS with SHA2-512 digest, SHA2-512 MGF1, 64 bytes of salt, trailer: 0xbc
                sha512_RSASSA_PSS = 0x0102,
                // 0x0103—RSASSA-PKCS1-v1_5 with SHA2-256 digest. This is for build systems which require deterministic signatures.
                sha256_RSASSA_PKCS1_v1_5 = 0x0103,
                // 0x0104—RSASSA-PKCS1-v1_5 with SHA2-512 digest. This is for build systems which require deterministic signatures.
                sha512_RSASSA_PKCS1_v1_5 = 0x0104,
                // 0x0201—ECDSA with SHA2-256 digest
                sha256_ECDSA = 0x0201,
                // 0x0202—ECDSA with SHA2-512 digest
                sha512_ECDSA = 0x0202,
                // 0x0301—DSA with SHA2-256 digest
                sha256_DSA_PKCS1_v1_5 = 0x0301,
                _,
            };

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

pub const OffsetSlice = struct { position: u64, slice: []const u8 };

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

        var buffer = try alloc.alloc(u8, size - 4);
        errdefer alloc.free(buffer);
        std.debug.assert(try stream_source.reader().read(buffer) == size - 4);

        try id_value_pairs.put(id, .{ .position = pos, .slice = buffer });

        // try stream_source.seekBy(@intCast(i64, size - 4));
    }

    return id_value_pairs;
}

const SliceIter = struct {
    slice: []const u8,
    remaining: ?[]const u8,
};

pub fn get_length_prefixed_slice(slice: []const u8) !SliceIter {
    if (slice.len <= 4) return error.SliceTooSmall;
    const length = std.mem.readInt(u32, slice[0..4], .Little);
    const new_slice = slice[4..];
    if (length == slice.len) return .{ .slice = new_slice[0..length], .remaining = null };
    if (length > slice.len) {
        std.debug.print("Length of slice {}\tlength of new_slice {}\tprefix {x}\n", .{ slice.len, new_slice.len, length });
        return error.OutOfBounds;
    }
    return .{ .slice = new_slice[0..length], .remaining = new_slice[length..] };
}

pub fn parse_v2(alloc: std.mem.Allocator, stream_source: *std.io.StreamSource, stream_slice: OffsetSlice) !SigningEntry {
    _ = stream_source;
    // try stream_source.seekTo(stream_slice.start);

    var signers = std.ArrayList(SigningEntry.Signer).init(alloc);
    errdefer signers.deinit();

    // const signer_list_end = std.mem.readInt(u32, stream_slice[0..4], .Little);
    const signer_list_iter = try get_length_prefixed_slice(stream_slice.slice);

    std.debug.print("\tstream_slice {}\tsigner_list {}\n", .{ stream_slice.slice.len, signer_list_iter.slice.len });

    var iter: SliceIter = try get_length_prefixed_slice(signer_list_iter.slice);
    var signer_slice_opt: ?[]const u8 = iter.slice;
    while (signer_slice_opt) |signer_slice| {
        std.debug.print("\tsigner {}\n", .{signer_slice.len});

        var signed_data = std.ArrayListUnmanaged(SigningEntry.Signer.SignedData){};
        errdefer signed_data.deinit(alloc);

        const signed_data_sequence = try get_length_prefixed_slice(signer_slice);
        std.debug.print("\tsigned data {}\n", .{signed_data_sequence.slice.len});
        signed_data: {
            const digest_sequence = try get_length_prefixed_slice(signed_data_sequence.slice);
            std.debug.print("\t\tdigest_sequence {}\n", .{digest_sequence.slice.len});

            var digest_iter = try get_length_prefixed_slice(digest_sequence.slice);
            var digest_chunk_opt: ?[]const u8 = digest_iter.slice;
            while (digest_chunk_opt) |digest_chunk| {
                const signature_algorithm_id = std.mem.readInt(u32, digest_chunk[0..4], .Little);
                switch (signature_algorithm_id) {
                    0x101, 0x102, 0x103, 0x104, 0x201, 0x202, 0x301 => {},
                    else => return error.InvalidSignatureAlgorithm,
                }
                std.debug.print("\t\t\tdigest_chunk {}\tsignature algorithm id 0x{x}\n", .{ digest_chunk.len, signature_algorithm_id });

                digest_iter = get_length_prefixed_slice(digest_iter.remaining orelse break) catch break;
                digest_chunk_opt = digest_iter.slice;
            }

            const x509_sequence = try get_length_prefixed_slice(digest_sequence.remaining.?);
            std.debug.print("\t\tx509 list {}\n", .{x509_sequence.slice.len});

            var x509_list = std.ArrayListUnmanaged(std.crypto.Certificate.Parsed){};
            errdefer x509_list.clearAndFree(alloc);

            var x509_iter = get_length_prefixed_slice(x509_sequence.slice) catch return error.UnexpectedEndOfStream;
            var x509_chunk_opt: ?[]const u8 = x509_iter.slice;
            while (x509_chunk_opt) |x509_chunk| {
                std.debug.print("\t\t\tx509 {}\n", .{x509_chunk.len});

                const cert = std.crypto.Certificate{ .buffer = x509_chunk, .index = 0 };
                const parsed = try cert.parse();
                try x509_list.append(alloc, parsed);

                x509_iter = get_length_prefixed_slice(x509_iter.remaining orelse break) catch break;
                x509_chunk_opt = x509_iter.slice;
            }

            const attribute_sequence = try get_length_prefixed_slice(x509_sequence.remaining.?);
            std.debug.print("\t\tattribute list {}\n", .{attribute_sequence.slice.len});

            var attribute_iter = get_length_prefixed_slice(attribute_sequence.slice) catch break :signed_data;
            var attribute_chunk_opt: ?[]const u8 = attribute_iter.slice;
            while (attribute_chunk_opt) |attribute_chunk| {
                std.debug.print("\t\t\tattribute {}\n", .{attribute_chunk.len});

                attribute_iter = get_length_prefixed_slice(attribute_iter.remaining orelse break) catch break;
                attribute_chunk_opt = attribute_iter.slice;
            }

            // try signed_data.append(alloc, .{
            //     .alloc = alloc,
            // });
        }

        var signatures = std.ArrayListUnmanaged(SigningEntry.Signer.Signature){};
        errdefer signatures.deinit(alloc);

        const signature_sequence = try get_length_prefixed_slice(signed_data_sequence.remaining orelse return error.UnexpectedEndOfStream);
        std.debug.print("\tsignature_sequence {}\n", .{signature_sequence.slice.len});
        {
            var signature_iter = try get_length_prefixed_slice(signature_sequence.slice);
            var signature_opt: ?[]const u8 = signature_iter.slice;
            while (signature_opt) |signature| {
                const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .Little);
                std.debug.print("\t\t\tsignature {}\tid 0x{X}\n", .{ signature.len, signature_algorithm_id });

                std.debug.print("\t\t\tsignature[4..] {}\n", .{signature[4..].len});

                const signed_data_sig = get_length_prefixed_slice(signature[4..]) catch return error.UnexpectedEndOfStream;
                std.debug.print("\t\t\tsigned data sig {}\n", .{signed_data_sig.slice.len});

                try signatures.append(alloc, .{
                    .algorithm = @intToEnum(SigningEntry.Signer.Signature.Algorithm, signature_algorithm_id),
                    .signature = signed_data_sig.slice,
                });

                // End of loop
                signature_iter = get_length_prefixed_slice(signature_iter.remaining orelse break) catch break;
                signature_opt = signature_iter.slice;
            }
        }

        const public_key_chunk = try get_length_prefixed_slice(signature_sequence.remaining orelse return error.UnexpectedEndOfStream);
        std.debug.print("\tpublic_key {}\n", .{public_key_chunk.slice.len});

        const pk_components = try std.crypto.Certificate.rsa.PublicKey.parseDer(public_key_chunk.slice);
        const public_key = try std.crypto.Certificate.rsa.PublicKey.fromBytes(pk_components.exponent, pk_components.modulus, alloc);

        // var buf: [1024]u8 = undefined;
        // const base64 = std.base64.standard.Encoder.encode(&buf, public_key.slice);
        // std.debug.print("{s}\n", .{(base64)});

        try signers.append(.{
            .alloc = alloc,
            .signed_data = signed_data,
            .signatures = signatures,
            .public_key = public_key,
        });

        // End of loop
        iter = get_length_prefixed_slice(iter.remaining orelse break) catch break;
        signer_slice_opt = iter.slice;
    }
    return SigningEntry{ .V2 = signers };
}

// Imports
const std = @import("std");
const archive = @import("archive");
