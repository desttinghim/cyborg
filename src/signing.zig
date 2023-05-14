//! This file implements signing and verification of Android APKs as described at the
//! [Android Source APK Signature Scheme v2 page (as of 2023-04-16)][https://source.android.com/docs/security/features/apksigning/v2]

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
            const Attribute = struct {
                id: ID,
                value: []const u8,

                const ID = enum(u32) { _ };
            };
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

/// Splits an APK into chunks for signing/verifying.
pub fn splitAPK(ally: std.mem.Allocator, mmapped_file: []const u8, signing_pos: usize, central_directory_pos: usize, end_of_cd_pos: usize) ![][]const u8 {
    const section1 = mmapped_file[0..signing_pos];
    // const section2 = mmapped_file[signing_pos..central_directory_pos];
    const section3 = mmapped_file[central_directory_pos..end_of_cd_pos];
    const section4 = mmapped_file[end_of_cd_pos..];

    std.debug.assert(section1.len != 0);
    // std.debug.assert(section2.len != 0);
    std.debug.assert(section3.len != 0);
    std.debug.assert(section4.len != 0);

    const MB = 2 << 20;
    const section1_count = ((section1.len - 1) / MB) + 1;
    // const section2_count = ((section2.len - 1) / MB) + 1;
    const section3_count = ((section3.len - 1) / MB) + 1;
    const section4_count = ((section4.len - 1) / MB) + 1;

    const total_count = section1_count + section3_count + section4_count;

    var chunks = std.ArrayListUnmanaged([]const u8){};
    try chunks.ensureTotalCapacity(ally, total_count);

    // Split ZIP entries into 1 mb chunks
    {
        var count: usize = 0;
        while (count < section1_count) : (count += 1) {
            const end = @min((count + 1) * MB, section1.len);
            chunks.appendAssumeCapacity(section1[count * MB .. end]);
        }
    }
    // Split Central Directory into 1 mb chunks
    {
        var count: usize = 0;
        while (count < section3_count) : (count += 1) {
            const end = @min((count + 1) * MB, section3.len);
            chunks.appendAssumeCapacity(section3[count * MB .. end]);
        }
    }
    // Split End of Central Directory into 1 mb chunks
    {
        var count: usize = 0;
        while (count < section4_count) : (count += 1) {
            const end = @min((count + 1) * MB, section4.len);
            chunks.appendAssumeCapacity(section4[count * MB .. end]);
        }
    }

    return chunks.toOwnedSlice(ally);
}

const Signing = @This();

signing_block_offset: u64,
central_directory_offset: u64,
end_of_central_directory_offset: u64,

signing_block: []const u8,

pub fn update_eocd_directory_offset(signing: Signing, mmapped_file: []u8) void {
    std.debug.assert(signing.signing_block_offset < std.math.maxInt(u32));
    const pos = @intCast(u32, signing.signing_block_offset);
    const eocd = mmapped_file[signing.end_of_central_directory_offset..];
    std.mem.writeInt(u32, eocd[16..20], pos, .Little);
}

/// Locates the signing block and verifies that the:
/// - two size fields of the APK signing Block contain the same value
/// - ZIP central directory is immediately followed by the ZIP end of central directory record
/// - ZIP end of central directory record is not followed by more data
///
/// # Parameters
/// - mmapped_file: the contents of the APK file as a byte slice
///
/// # Return
/// Returns an instance of the Signing struct
pub fn get_offsets(alloc: std.mem.Allocator, mmapped_file: []const u8) !Signing {
    var fixed_buffer_stream = std.io.FixedBufferStream([]const u8){ .buffer = mmapped_file, .pos = 0 };
    var stream_source = std.io.StreamSource{ .const_buffer = fixed_buffer_stream };

    // TODO: change zig-archive to allow operating without a buffer
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);
    try archive_reader.load();

    const signing_block = try get_signing_block_offset(&stream_source, archive_reader.directory_offset);

    const expected_eocd_start = archive_reader.directory_offset + archive_reader.directory_size;

    // TODO: verify central directory immediately follows ZIP eocd
    // if (!std.mem.eql(u8, mmapped_file[expected_eocd_start..][0..4], &std.mem.toBytes(archive.formats.zip.internal.EndOfCentralDirectoryRecord.signature))) {
    //     return error.EOCDDoesNotImmediatelyFollowCentralDirectory;
    // }

    // TODO: verify eocd is end of file. Is the comment field allowed to contain data?

    return Signing{
        .signing_block_offset = signing_block,
        .central_directory_offset = archive_reader.directory_offset,
        .end_of_central_directory_offset = expected_eocd_start,
        .signing_block = mmapped_file[signing_block..archive_reader.directory_offset],
    };
}

/// Given the offset of the Central Directory in a stream, finds the start of APK signing block
/// and verifies that the two size fields contain the same value
fn get_signing_block_offset(stream_source: *std.io.StreamSource, directory_offset: u64) !u64 {
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

    return block_start;
}

/// Updates the EOCD directory offset to point to start of signing block
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

/// Within the signing block, finds the entry that corresponds to a given
/// signing scheme version.
///
/// # Parameters
/// - signing_block: A slice of bytes corresponding to the APK signing block
/// - tag: The SigningEntry.Tag value for the desired entry
///
/// # Return
/// Returns a slice corresponding to the signing entry within the signing block
pub fn locate_entry(signing: Signing, tag: SigningEntry.Tag) ![]const u8 {
    var index: usize = 0;
    while (index < signing.signing_block.len) {
        const size = std.mem.readInt(u64, signing.signing_block[index..][0..8], .Little);
        if (size > signing.signing_block.len) return error.SigningEntryLengthOutOfBounds;
        const entry_tag = @intToEnum(SigningEntry.Tag, std.mem.readInt(u32, signing.signing_block[index + 8 ..][0..4], .Little));

        if (entry_tag == tag)
            return signing.signing_block[index + 12 ..][0 .. size - 4];

        index += size + 8;
    }
    return error.EntryNotFound;
}

pub fn parse_v2(alloc: std.mem.Allocator, entry_slice: []const u8) !SigningEntry {
    var signers = std.ArrayList(SigningEntry.Signer).init(alloc);
    errdefer signers.deinit();

    const signer_list_iter = try get_length_prefixed_slice(entry_slice);

    var iter: SliceIter = try get_length_prefixed_slice(signer_list_iter.slice);
    var signer_slice_opt: ?[]const u8 = iter.slice;
    while (signer_slice_opt) |signer_slice| {
        var signed_data = std.ArrayListUnmanaged(SigningEntry.Signer.SignedData){};
        errdefer signed_data.deinit(alloc);

        const signed_data_sequence = try get_length_prefixed_slice(signer_slice);
        {
            const digest_sequence = try get_length_prefixed_slice(signed_data_sequence.slice);

            var digests = std.ArrayListUnmanaged([]const u8){};
            errdefer digests.deinit(alloc);

            var digest_iter = try get_length_prefixed_slice(digest_sequence.slice);
            var digest_chunk_opt: ?[]const u8 = digest_iter.slice;
            while (digest_chunk_opt) |digest_chunk| {
                const signature_algorithm_id = std.mem.readInt(u32, digest_chunk[0..4], .Little);
                switch (signature_algorithm_id) {
                    0x101, 0x102, 0x103, 0x104, 0x201, 0x202, 0x301 => {},
                    else => return error.InvalidSignatureAlgorithm,
                }

                const digest_length = std.mem.readInt(u32, digest_chunk[4..8], .Little);
                const digest = digest_chunk[8 .. 8 + digest_length];

                try digests.append(alloc, digest);

                digest_iter = get_length_prefixed_slice(digest_iter.remaining orelse break) catch break;
                digest_chunk_opt = digest_iter.slice;
            }

            const x509_sequence = try get_length_prefixed_slice(digest_sequence.remaining.?);

            var x509_list = std.ArrayListUnmanaged(std.crypto.Certificate.Parsed){};
            errdefer x509_list.clearAndFree(alloc);

            var x509_iter = get_length_prefixed_slice(x509_sequence.slice) catch return error.UnexpectedEndOfStream;
            var x509_chunk_opt: ?[]const u8 = x509_iter.slice;
            while (x509_chunk_opt) |x509_chunk| {
                const cert = std.crypto.Certificate{ .buffer = x509_chunk, .index = 0 };
                const parsed = try cert.parse();
                try x509_list.append(alloc, parsed);

                x509_iter = get_length_prefixed_slice(x509_iter.remaining orelse break) catch break;
                x509_chunk_opt = x509_iter.slice;
            }

            const attribute_sequence = try get_length_prefixed_slice(x509_sequence.remaining.?);

            var attributes = std.ArrayListUnmanaged(SigningEntry.Signer.SignedData.Attribute){};
            errdefer attributes.clearAndFree(alloc);

            attribute: {
                var attribute_iter = get_length_prefixed_slice(attribute_sequence.slice) catch break :attribute;
                var attribute_chunk_opt: ?[]const u8 = attribute_iter.slice;
                while (attribute_chunk_opt) |attribute_chunk| {
                    const id = std.mem.readInt(u32, attribute_chunk[0..4], .Little);
                    try attributes.append(alloc, .{
                        .id = @intToEnum(SigningEntry.Signer.SignedData.Attribute.ID, id),
                        .value = attribute_chunk[4..],
                    });

                    attribute_iter = get_length_prefixed_slice(attribute_iter.remaining orelse break) catch break;
                    attribute_chunk_opt = attribute_iter.slice;
                }
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

        const signature_sequence = try get_length_prefixed_slice(signed_data_sequence.remaining orelse return error.UnexpectedEndOfStream);
        {
            var signature_iter = try get_length_prefixed_slice(signature_sequence.slice);
            var signature_opt: ?[]const u8 = signature_iter.slice;
            while (signature_opt) |signature| {
                const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .Little);

                const signed_data_sig = get_length_prefixed_slice(signature[4..]) catch return error.UnexpectedEndOfStream;

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

        const Element = std.crypto.Certificate.der.Element;
        const subject_pk_info = try Element.parse(public_key_chunk.slice, 0);
        std.debug.assert(subject_pk_info.identifier.tag == .sequence);

        const alg_id = try Element.parse(public_key_chunk.slice, subject_pk_info.slice.start);
        std.debug.assert(alg_id.identifier.tag == .sequence);

        const oid = try Element.parse(public_key_chunk.slice, alg_id.slice.start);
        std.debug.assert(oid.identifier.tag == .object_identifier);
        const alg = try std.crypto.Certificate.parseAlgorithmCategory(public_key_chunk.slice, oid);
        _ = alg;

        const null_val = try Element.parse(public_key_chunk.slice, oid.slice.end);

        const subject_pk = try Element.parse(public_key_chunk.slice, null_val.slice.end);
        const unused_bits = public_key_chunk.slice[subject_pk.slice.start];
        _ = unused_bits;
        const subject_pk_bitstring = public_key_chunk.slice[subject_pk.slice.start + 1 ..];

        const pk_components = try std.crypto.Certificate.rsa.PublicKey.parseDer(subject_pk_bitstring);
        const public_key = try std.crypto.Certificate.rsa.PublicKey.fromBytes(pk_components.exponent, pk_components.modulus, alloc);

        {
            const sdpk = signed_data.items[0].certificates[0][0].pubKey();
            std.debug.assert(std.mem.eql(u8, subject_pk_bitstring, sdpk));
        }

        // TODO: make sure signed data and signatures have the same list of algorithms

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

// Utility functions for working with signing block chunks
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
        return error.OutOfBounds;
    }
    return .{ .slice = new_slice[0..length], .remaining = new_slice[length..] };
}

// Imports
const std = @import("std");
const archive = @import("archive");
