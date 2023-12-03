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
        signed_data: SignedData,
        signatures: std.ArrayListUnmanaged(Signature),
        public_key: []const u8,

        pub fn deinit(signer: *Signer) void {
            signer.signed_data.deinit();
            for (signer.signatures.items) |signature| {
                signature.deinit();
            }
            signer.signatures.clearAndFree();
            signer.alloc.free(signer.public_key.certificate.buffer);
        }

        pub const SignedData = struct {
            alloc: std.mem.Allocator,
            digests: std.ArrayListUnmanaged(Digest),
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

            const Digest = struct {
                algorithm: Algorithm,
                data: []const u8,
            };

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

            pub fn deinit(signature: *Signature) void {
                signature.alloc.free(signature.signature);
            }
        };

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
    };
};

pub fn verify(ally: std.mem.Allocator, apk_contents: []const u8) void {
    const signing_block = try get_offsets(ally, apk_contents);

    // TODO: Implement V4
    // if (try signing_block.locate_entry(.V4)) |v4_block| {
    //     return;
    // }

    // TODO: Implement V3.1
    // if (try signing_block.locate_entry(.V3_1)) |v3_1_block| {
    //     return;
    // }

    // TODO: Implement V3
    // if (try signing_block.locate_entry(.V3)) |v3_block| {
    //     return;
    // }

    if (try signing_block.locate_entry(.V2)) |v2_block| {
        try verify_v2(ally, apk_contents, v2_block, default_algorithm_try_order);
        return;
    }
}

/// Splits an APK into chunks for signing/verifying.
pub fn splitAPK(ally: std.mem.Allocator, mmapped_file: []const u8, signing_pos: usize, central_directory_pos: usize, end_of_cd_pos: usize) ![][]const u8 {
    const spos = signing_pos;
    const cdpos = central_directory_pos;
    const section1 = mmapped_file[0..spos]; // -8 to account for second signing block size field
    // const section2 = mmapped_file[signing_pos..central_directory_pos];
    const section3 = mmapped_file[cdpos..end_of_cd_pos];
    const section4 = mmapped_file[end_of_cd_pos..];

    std.debug.assert(section1.len != 0);
    // std.debug.assert(section2.len != 0);
    std.debug.assert(section3.len != 0);
    std.debug.assert(section4.len != 0);

    const MB = 1024 * 1024; // 2 << 20;
    const section1_count = try std.math.divCeil(usize, section1.len, MB);
    // const section2_count = std.math.divCeil(usize, section2.len, MB);
    const section3_count = try std.math.divCeil(usize, section3.len, MB);
    const section4_count = try std.math.divCeil(usize, section4.len, MB);

    const total_count = section1_count + section3_count + section4_count;

    var chunks = std.ArrayListUnmanaged([]const u8){};
    try chunks.ensureTotalCapacity(ally, total_count);

    // Split ZIP entries into 1 mb chunks
    {
        var count: usize = 0;
        while (count < section1_count) : (count += 1) {
            const end = @min((count + 1) * MB, section1.len);
            const chunk = section1[count * MB .. end];
            std.debug.assert(chunk.len <= MB);
            chunks.appendAssumeCapacity(chunk);
        }
    }
    // Split Central Directory into 1 mb chunks
    {
        var count: usize = 0;
        while (count < section3_count) : (count += 1) {
            const end = @min((count + 1) * MB, section3.len);
            const chunk = section3[count * MB .. end];
            std.debug.assert(chunk.len <= MB);
            chunks.appendAssumeCapacity(chunk);
        }
    }
    // Split End of Central Directory into 1 mb chunks
    {
        var count: usize = 0;
        while (count < section4_count) : (count += 1) {
            const end = @min((count + 1) * MB, section4.len);
            const chunk = section4[count * MB .. end];
            std.debug.assert(chunk.len <= MB);
            chunks.appendAssumeCapacity(chunk);
        }
    }

    return chunks.toOwnedSlice(ally);
}

const Signing = @This();

signing_block_offset: u64,
central_directory_offset: u64,
end_of_central_directory_offset: u64,

signing_block: []const u8,

/// Updates the EOCD directory offset to point to start of signing block
pub fn update_eocd_directory_offset(signing: Signing, mmapped_file: []u8) void {
    std.debug.assert(signing.signing_block_offset < std.math.maxInt(u32));
    const pos = @as(u32, @intCast(signing.signing_block_offset));
    const eocd = mmapped_file[signing.end_of_central_directory_offset..];
    std.mem.writeInt(u32, eocd[16..20], pos, .little);
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
    const fixed_buffer_stream = std.io.FixedBufferStream([]const u8){ .buffer = mmapped_file, .pos = 0 };
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

    const block_size = try stream_source.reader().readInt(u64, .little);

    const block_start = directory_offset - block_size - 8;

    try stream_source.seekTo(block_start);

    const block_size_2 = try stream_source.reader().readInt(u64, .little);

    if (block_size != block_size_2) return error.BlockSizeMismatch;

    return block_start;
}

/// Within the signing block, finds the entry that corresponds to a given
/// signing scheme version.
///
/// # Parameters
/// - signing_block: A slice of bytes corresponding to the APK signing block
/// - tag: The SigningEntry.Tag value for the desired entry
///
/// # Return
/// Returns a slice corresponding to the signing entry within the signing block
pub fn locate_entry(signing: Signing, tag: SigningEntry.Tag) !?[]const u8 {
    var index: usize = 8; // skip the signing block size
    while (index < signing.signing_block.len) {
        const size = std.mem.readInt(u64, signing.signing_block[index..][0..8], .little);
        if (size > signing.signing_block.len) return error.SigningEntryLengthOutOfBounds;
        const entry_tag = @as(SigningEntry.Tag, @enumFromInt(std.mem.readInt(u32, signing.signing_block[index + 8 ..][0..4], .little)));

        if (entry_tag == tag)
            return signing.signing_block[index + 12 ..][0 .. size - 4];

        index += size + 8;
    }
    return null;
}

// TODO: make this order less arbitrary
pub const default_algorithm_try_order = [_]SigningEntry.Signer.Algorithm{
    .sha256_RSASSA_PSS,
    .sha512_RSASSA_PSS,
    .sha256_RSASSA_PKCS1_v1_5,
    .sha512_RSASSA_PKCS1_v1_5,
    .sha256_ECDSA,
    .sha512_ECDSA,
    .sha256_DSA_PKCS1_v1_5,
};

/// Attempts to verify a v2 signing entry. The algorithm to use is decided by the `algorithm_try_order`. The first
/// algorithm from the list that is present in the file is used for verification.
///
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
pub fn verify_v2(ally: std.mem.Allocater, apk: []const u8, entry_v2: []const u8, algorithm_try_order: []const SigningEntry.Signer.Algorithm) !void {
    const signer_list_iter = try get_length_prefixed_slice(entry_v2);
    std.debug.assert(signer_list_iter.remaining == null);

    var signer_count: usize = 0;
    var iter = try get_length_prefixed_slice_iter(signer_list_iter.slice);
    while (iter.next()) |signer_slice| {
        signer_count += 1;

        const signed_data_block = try get_length_prefixed_slice(signer_slice);

        // Get public key
        const signature_sequence = try get_length_prefixed_slice(signed_data_block.remaining orelse return error.UnexpectedEndOfStream);
        const public_key_chunk = try get_length_prefixed_slice(signature_sequence.remaining orelse return error.UnexpectedEndOfStream);
        const Element = std.crypto.Certificate.der.Element;
        const PK = struct {
            algo: std.crypto.Certificate.Parsed.PubKeyAlgo,
            data: Element.Slice,
        };
        const public_key: PK = pk: {
            var cert = std.crypto.Certificate{
                .buffer = public_key_chunk.slice,
                .index = 0,
            };
            const pk_info = try Element.parse(public_key_chunk.slice, 0);
            const pk_alg_elem = try Element.parse(public_key_chunk.slice, pk_info.slice.start);
            const pk_alg_tag = try Element.parse(public_key_chunk.slice, pk_alg_elem.slice.start);
            const alg = try std.crypto.Certificate.parseAlgorithmCategory(public_key_chunk.slice, pk_alg_tag);

            const pub_key_algo: std.crypto.Certificate.Parsed.PubKeyAlgo = switch (alg) {
                .X9_62_id_ecPublicKey => curve: {
                    const params_elem = try Element.parse(public_key_chunk.slice, pk_alg_tag.slice.end);
                    const named_curve = try std.crypto.Certificate.parseNamedCurve(public_key_chunk.slice, params_elem);
                    break :curve .{ .X9_62_id_ecPublicKey = named_curve };
                },
                .rsaEncryption => .{ .rsaEncryption = {} },
            };

            const pub_key_elem = try Element.parse(public_key_chunk.slice, pk_alg_elem.slice.end);
            break :pk .{
                .algo = pub_key_algo,
                .data = try cert.parseBitString(pub_key_elem),
            };
        };

        // A. choose strongest algorithm
        const selected_signature = signature: for (algorithm_try_order) |algorithm_try| {
            break :signature get_signer_algorithm(signature_sequence.slice, algorithm_try) orelse continue;
        } else {
            return error.AlgorithmNotInList;
        };

        // B. Verify signature aginst signed data
        switch (selected_signature.algorithm) {
            .sha256_RSASSA_PSS => {
                if (public_key.algo != .rsaEncryption) return error.MismatchedPublicKey;
                const pk_components = try std.crypto.Certificate.rsa.PublicKey.parseDer(public_key_chunk.slice[public_key.data.start..public_key.data.end]);
                const pub_key = try std.crypto.Certificate.rsa.PublicKey.fromBytes(pk_components.exponent, pk_components.modulus);

                const rsa = std.crypto.Certificate.rsa;
                const Sha256 = std.crypto.hash.sha2.Sha256;
                const modulus_len = 256;

                const sig = rsa.PSSSignature.fromBytes(modulus_len, selected_signature.signature);
                _ = try rsa.PSSSignature.verify(modulus_len, sig, signed_data_block.slice, pub_key, Sha256);
            },
            .sha256_ECDSA => {
                switch (public_key.algo.X9_62_id_ecPublicKey) {
                    .secp521r1 => return error.Unsupported,
                    inline else => |named_curve| {
                        const Ecdsa = std.crypto.sign.ecdsa.Ecdsa(named_curve.Curve(), std.crypto.hash.sha2.Sha256);
                        const pub_key = try Ecdsa.PublicKey.fromSec1(public_key_chunk.slice[public_key.data.start..public_key.data.end]);

                        const sig = try Ecdsa.Signature.fromDer(selected_signature.signature);
                        _ = try sig.verify(signed_data_block.slice, pub_key);
                    },
                }
            },
            .sha512_RSASSA_PSS,
            .sha256_RSASSA_PKCS1_v1_5,
            .sha512_RSASSA_PKCS1_v1_5,
            .sha512_ECDSA,
            .sha256_DSA_PKCS1_v1_5,
            => return error.Unimplemented,
        }

        // C. Verify algorithm lists are the same
        const digest_sequence = try get_length_prefixed_slice(signed_data_block.slice);
        var digest_iter = try get_length_prefixed_slice_iter(digest_sequence.slice);
        var signature_iter = get_length_prefixed_slice_iter(signature_sequence) catch return null;
        while (try digest_iter.next()) |digest_chunk| {
            const signature = signature_iter.next();
            const digest_algorithm_id = std.mem.readInt(u32, digest_chunk[0..4], .little);
            const digest_algorithm: SigningEntry.Signer.Algorithm = @enumFromInt(digest_algorithm_id);

            const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .little);
            const signature_algorithm: SigningEntry.Signer.Algorithm = @enumFromInt(signature_algorithm_id);

            if (digest_algorithm != signature_algorithm) return error.MismatchedAlgorithmList;
        }

        _ = apk;
        _ = ally;
        // TODO
        // D. Compute digest
        // const chunks = try signing.splitAPK(ally, apk_map, signing_block_offset, directory_offset, eocd_offset);

        // // TODO: use the correct algorithm instead of assuming Sha256
        // const Sha256 = std.crypto.hash.sha2.Sha256;

        // // Allocate enough memory to store all the digests
        // const digest_mem = try alloc.alloc(u8, Sha256.digest_length * chunks.len);
        // defer alloc.free(digest_mem);

        // // Loop over every chunk and compute its digest
        // for (chunks, 0..) |chunk, i| {
        //     var hash = Sha256.init(.{});

        //     var size_buf: [4]u8 = undefined;
        //     const size = @as(u32, @intCast(chunk.len));
        //     std.mem.writeInt(u32, &size_buf, size, .little);

        //     hash.update(&.{0xa5}); // Magic value byte
        //     hash.update(&size_buf); // Size in bytes, le u32
        //     hash.update(chunk); // Chunk contents

        //     hash.final(digest_mem[i * Sha256.digest_length ..][0..Sha256.digest_length]);
        // }

        // TODO
        // // E. Verify computed digest matches stored digest
        // // Compute the digest over all chunks

        // var hash = Sha256.init(.{});
        // var size_buf: [4]u8 = undefined;
        // std.mem.writeInt(u32, &size_buf, @as(u32, @intCast(chunks.len)), .little);
        // hash.update(&.{0x5a}); // Magic value byte for final digest
        // hash.update(&size_buf);
        // hash.update(digest_mem);
        // const final_digest = hash.finalResult();
        // // Compare the final digest with the one stored in the signing block
        // const digest_is_equal = std.mem.eql(u8, signing_entry.V2.items[0].signed_data.digests.items[0].data, &final_digest);
        // try stdout.writer().print("{}\n", .{std.fmt.fmtSliceHexUpper(&final_digest)});
        // if (digest_is_equal) {
        //     try stdout.writer().print("Digest Equal\n", .{});
        // } else {
        //     try stdout.writer().print("ERROR - Digest Value Differs!\n", .{});
        // }

        // F. Verify SubjectPublicKeyInfo of first certificate is equal to public key
        return error.ImplementationUnfinished;
    }
    if (signer_count == 0) return error.NoSignersFound;
}

fn get_signer_algorithm(signature_sequence: []const u8, algorithm_find: SigningEntry.Signer.Algorithm) ?SigningEntry.Signer {
    var signature_iter = get_length_prefixed_slice_iter(signature_sequence) catch return null;
    while (signature_iter.next() catch return null) |signature| {
        // Find strongest algorithm
        const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .little);
        const algorithm: SigningEntry.Signer.Algorithm = @enumFromInt(signature_algorithm_id);

        if (algorithm == algorithm_find) {
            const signed_data_sig = get_length_prefixed_slice(signature[4..]) catch return error.UnexpectedEndOfStream;
            return SigningEntry.Signer{
                .algorithm = algorithm,
                .signature = signed_data_sig.slice,
            };
        }
    }
    return null;
}

pub fn parse_v2(alloc: std.mem.Allocator, entry_slice: []const u8) !SigningEntry {
    var signers = std.ArrayList(SigningEntry.Signer).init(alloc);
    errdefer signers.deinit();

    const signer_list_iter = try get_length_prefixed_slice(entry_slice);

    var iter = try get_length_prefixed_slice(signer_list_iter.slice);
    var signer_slice_opt: ?[]const u8 = iter.slice;
    while (signer_slice_opt) |signer_slice| {
        const signed_data_block = try get_length_prefixed_slice(signer_slice);

        var signatures = std.ArrayListUnmanaged(SigningEntry.Signer.Signature){};
        errdefer signatures.deinit(alloc);

        const signature_sequence = try get_length_prefixed_slice(signed_data_block.remaining orelse return error.UnexpectedEndOfStream);
        const public_key_chunk = try get_length_prefixed_slice(signature_sequence.remaining orelse return error.UnexpectedEndOfStream);

        std.log.info("{}", .{std.fmt.fmtSliceHexUpper(public_key_chunk.slice)});

        var certi = std.crypto.Certificate{
            .buffer = public_key_chunk.slice,
            .index = 0,
        };

        const Element = std.crypto.Certificate.der.Element;
        const subject_pk_info = try Element.parse(public_key_chunk.slice, 0);
        std.debug.assert(subject_pk_info.identifier.tag == .sequence);

        const pk_alg_elem = try Element.parse(public_key_chunk.slice, subject_pk_info.slice.start);
        std.debug.assert(pk_alg_elem.identifier.tag == .sequence);

        const pk_alg_tag = try Element.parse(public_key_chunk.slice, pk_alg_elem.slice.start);
        std.debug.assert(pk_alg_tag.identifier.tag == .object_identifier);
        const alg = try std.crypto.Certificate.parseAlgorithmCategory(public_key_chunk.slice, pk_alg_tag);

        const pub_key_algo: std.crypto.Certificate.Parsed.PubKeyAlgo = switch (alg) {
            .X9_62_id_ecPublicKey => curve: {
                const params_elem = try Element.parse(public_key_chunk.slice, pk_alg_tag.slice.end);
                const named_curve = try std.crypto.Certificate.parseNamedCurve(public_key_chunk.slice, params_elem);
                break :curve .{ .X9_62_id_ecPublicKey = named_curve };
            },
            .rsaEncryption => .{ .rsaEncryption = {} },
        };

        const pub_key_elem = try Element.parse(public_key_chunk.slice, pk_alg_elem.slice.end);
        const subject_pk_bitstring = try certi.parseBitString(pub_key_elem);

        var signature_iter = try get_length_prefixed_slice(signature_sequence.slice);
        var signature_opt: ?[]const u8 = signature_iter.slice;
        while (signature_opt) |signature| {
            // Parse signatures
            const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .little);

            const signed_data_sig = get_length_prefixed_slice(signature[4..]) catch return error.UnexpectedEndOfStream;

            std.debug.print("signature algorithm id {x}\n", .{signature_algorithm_id});

            std.debug.print("Signature: {}\n", .{std.fmt.fmtSliceHexUpper(signed_data_sig.slice)});

            // Verify signature/public key over signed data block
            // TODO: don't check every signature, we only need to choose one
            switch (pub_key_algo) {
                .X9_62_id_ecPublicKey => {
                    switch (pub_key_algo.X9_62_id_ecPublicKey) {
                        .secp521r1 => return error.Unsupported,
                        inline else => |named_curve| {
                            const Ecdsa = std.crypto.sign.ecdsa.Ecdsa(named_curve.Curve(), std.crypto.hash.sha2.Sha256);
                            const sig = try Ecdsa.Signature.fromDer(signed_data_sig.slice);
                            const pub_key = try Ecdsa.PublicKey.fromSec1(public_key_chunk.slice[subject_pk_bitstring.start..subject_pk_bitstring.end]);
                            _ = try sig.verify(signed_data_block.slice, pub_key);
                        },
                    }
                },
                .rsaEncryption => {
                    const pk_components = try std.crypto.Certificate.rsa.PublicKey.parseDer(public_key_chunk.slice[subject_pk_bitstring.start..subject_pk_bitstring.end]);
                    const public_key = try std.crypto.Certificate.rsa.PublicKey.fromBytes(pk_components.exponent, pk_components.modulus);

                    const rsa = std.crypto.Certificate.rsa;
                    const Sha256 = std.crypto.hash.sha2.Sha256;
                    const modulus_len = 256;
                    const sig = rsa.PSSSignature.fromBytes(modulus_len, signed_data_sig.slice);

                    _ = try rsa.PSSSignature.verify(modulus_len, sig, signed_data_block.slice, public_key, Sha256);
                },
            }
            try signatures.append(alloc, .{
                .algorithm = @as(SigningEntry.Signer.Algorithm, @enumFromInt(signature_algorithm_id)),
                .signature = signed_data_sig.slice,
            });

            // End of loop
            signature_iter = get_length_prefixed_slice(signature_iter.remaining orelse break) catch break;
            signature_opt = signature_iter.slice;
        }

        // const which_algo = for (algorithm_order) |check_algo| {
        //     for (signatures.items) |sig| {
        //         if (sig.algorithm != check_algo) continue;
        //         switch (algorithm) {
        //             .sha256_ECDSA => {
        //                 const rsa = std.crypto.Certificate.rsa;
        //                 const Sha256 = std.crypto.hash.sha2.Sha256;
        //                 const modulus_len = 256;
        //                 const s = rsa.PSSSignature.fromBytes(modulus_len, signed_data_sig.slice);
        //             },
        //             .sha256_RSASSA_PSS,
        //             .sha512_RSASSA_PSS,
        //             .sha256_RSASSA_PKCS1_v1_5,
        //             .sha512_RSASSA_PKCS1_v1_5,
        //             .sha512_ECDSA,
        //             .sha256_DSA_PKCS1_v1_5,
        //             => return error.Unsupported,
        //             _ => return error.UnknownAlgorithm,
        //         }
        //     }
        // } else {
        //     return error.MissingSignedDataHashAlgorithm;
        // };

        // Parse signed data
        const signed_data = signed_data: {
            const digest_sequence = try get_length_prefixed_slice(signed_data_block.slice);

            var digests = std.ArrayListUnmanaged(SigningEntry.Signer.SignedData.Digest){};
            errdefer digests.deinit(alloc);

            var digest_iter = try get_length_prefixed_slice(digest_sequence.slice);
            var digest_chunk_opt: ?[]const u8 = digest_iter.slice;
            while (digest_chunk_opt) |digest_chunk| {
                const signature_algorithm_id = std.mem.readInt(u32, digest_chunk[0..4], .little);
                const algorithm = @as(SigningEntry.Signer.Algorithm, @enumFromInt(signature_algorithm_id));

                const digest_length = std.mem.readInt(u32, digest_chunk[4..8], .little);
                const digest = digest_chunk[8 .. 8 + digest_length];

                try digests.append(alloc, .{
                    .algorithm = algorithm,
                    .data = digest,
                });

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

            var attributes = std.ArrayListUnmanaged(SigningEntry.Signer.SignedData.Attribute){};
            errdefer attributes.clearAndFree(alloc);

            const attribute_sequence = get_length_prefixed_slice(x509_sequence.remaining orelse return error.UnexpectedEndOfStream) catch |e| {
                std.debug.assert(e == error.SliceTooSmall);
                break :signed_data .{
                    .alloc = alloc,
                    .digests = digests,
                    .certificates = x509_list,
                    .attributes = attributes,
                };
            };

            attribute: {
                var attribute_iter = get_length_prefixed_slice(attribute_sequence.slice) catch break :attribute;
                var attribute_chunk_opt: ?[]const u8 = attribute_iter.slice;
                while (attribute_chunk_opt) |attribute_chunk| {
                    const id = std.mem.readInt(u32, attribute_chunk[0..4], .little);
                    try attributes.append(alloc, .{
                        .id = @as(SigningEntry.Signer.SignedData.Attribute.ID, @enumFromInt(id)),
                        .value = attribute_chunk[4..],
                    });

                    attribute_iter = get_length_prefixed_slice(attribute_iter.remaining orelse break) catch break;
                    attribute_chunk_opt = attribute_iter.slice;
                }
            }

            break :signed_data .{
                .alloc = alloc,
                .digests = digests,
                .certificates = x509_list,
                .attributes = attributes,
            };
        };

        {
            const sdpk = signed_data.certificates.items[0].pubKey();
            std.debug.assert(std.mem.eql(u8, public_key_chunk.slice[subject_pk_bitstring.start..subject_pk_bitstring.end], sdpk));
        }

        // Ensures signed data and signatures have the same list of algorithms
        for (signatures.items, signed_data.digests.items) |signature, digest| {
            if (signature.algorithm != digest.algorithm) return error.MismatchedAlgorithms;
        }

        try signers.append(.{
            .alloc = alloc,
            .signed_data = signed_data,
            .signatures = signatures,
            .public_key = public_key_chunk.slice[subject_pk_bitstring.start..subject_pk_bitstring.end],
        });

        // End of loop
        iter = get_length_prefixed_slice(iter.remaining orelse break) catch break;
        signer_slice_opt = iter.slice;
    }
    return SigningEntry{ .V2 = signers };
}

// Utility functions for working with signing block chunks
const SplitSlice = struct {
    slice: []const u8,
    remaining: ?[]const u8,
};

pub fn get_length_prefixed_slice(slice: []const u8) !SplitSlice {
    if (slice.len <= 4) return error.SliceTooSmall;
    const length = std.mem.readInt(u32, slice[0..4], .little);
    const new_slice = slice[4..];
    if (length == slice.len) return .{ .slice = new_slice[0..length], .remaining = null };
    if (length > slice.len) {
        return error.OutOfBounds;
    }
    return .{ .slice = new_slice[0..length], .remaining = new_slice[length..] };
}

const SliceIter = struct {
    slice: ?[]const u8,
    remaining: ?[]const u8,

    pub fn next(iter: *SliceIter) !?[]const u8 {
        const to_return = iter.slice;
        if (iter.remaining) |remaining| {
            iter.* = get_length_prefixed_slice_iter(remaining) catch .{
                .slice = null,
                .remaining = null,
            };
        } else {
            iter.slice = null;
        }
        return to_return;
    }
};

pub fn get_length_prefixed_slice_iter(slice: []const u8) !SliceIter {
    if (slice.len <= 4) return error.SliceTooSmall;
    const length = std.mem.readInt(u32, slice[0..4], .little);
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
