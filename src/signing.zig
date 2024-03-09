//! This file implements signing and verification of Android APKs as described at the
//! [Android Source APK Signature Scheme v2 page (as of 2023-04-16)][https://source.android.com/docs/security/features/apksigning/v2]

// Re-exports
pub const pem = @import("signing/pem.zig");

comptime {
    _ = @import("signing/test.zig");
}

pub const SigningEntry = union(Tag) {
    V2: std.ArrayList(Signer),

    pub fn deinit(entry: *SigningEntry) void {
        switch (entry.*) {
            inline .V2 => |*list| {
                for (list.items) |*item| {
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
            for (signer.signatures.items) |*signature| {
                signature.deinit(signer.alloc);
            }
            signer.signatures.clearAndFree(signer.alloc);
            signer.alloc.free(signer.public_key);
        }

        pub const SignedData = struct {
            alloc: std.mem.Allocator,
            digests: std.ArrayListUnmanaged(Digest),
            certificates: std.ArrayListUnmanaged(std.crypto.Certificate.Parsed),
            attributes: std.ArrayListUnmanaged(Attribute),

            pub fn deinit(signed_data: *SignedData) void {
                for (signed_data.digests.items) |digest| {
                    signed_data.alloc.free(digest.data);
                }
                for (signed_data.certificates.items) |certificate| {
                    signed_data.alloc.free(certificate.certificate.buffer);
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

            pub fn deinit(signature: *Signature, alloc: std.mem.Allocator) void {
                alloc.free(signature.signature);
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

const Hash = enum { sha256, sha512 };

/// Parses an APK and returns a context for adding signatures
pub fn getV2SigningContext(ally: std.mem.Allocator, apk_contents: []u8, comptime which_hash: Hash) !SigningContext {
    const fixed_buffer_stream = std.io.FixedBufferStream([]const u8){ .buffer = apk_contents, .pos = 0 };
    var stream_source = std.io.StreamSource{ .const_buffer = fixed_buffer_stream };

    // TODO: change zig-archive to allow operating without a buffer
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(ally, &stream_source);
    defer archive_reader.deinit();
    try archive_reader.load();

    const expected_eocd_start = archive_reader.directory_offset + archive_reader.directory_size;

    const offsets = SigningOffsets{
        .signing_block_offset = archive_reader.directory_offset,
        .central_directory_offset = archive_reader.directory_offset,
        .end_of_central_directory_offset = expected_eocd_start,
        .signing_block = undefined,
        .apk_contents = apk_contents,
    };

    const chunks = try offsets.splitAPK(ally);

    const Sha = switch (which_hash) {
        .sha256 => std.crypto.hash.sha2.Sha256,
        .sha512 => std.crypto.hash.sha2.Sha512,
    };
    const digest_mem = try ally.alloc(u8, Sha.digest_length * chunks.len);

    // Loop over every chunk and compute its digest
    for (chunks, 0..) |chunk, i| {
        var hash = Sha.init(.{});

        var size_buf: [4]u8 = undefined;
        const size = @as(u32, @intCast(chunk.len));
        std.mem.writeInt(u32, &size_buf, size, .little);

        hash.update(&.{0xa5}); // Magic value byte
        hash.update(&size_buf); // Size in bytes, le u32
        hash.update(chunk); // Chunk contents

        hash.final(digest_mem[i * Sha.digest_length ..][0..Sha.digest_length]);
    }

    // Compute the digest over all chunks
    var hash = Sha.init(.{});
    var size_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &size_buf, @as(u32, @intCast(chunks.len)), .little);
    hash.update(&.{0x5a}); // Magic value byte for final digest
    hash.update(&size_buf);
    hash.update(digest_mem);
    const final_digest = try ally.dupe(u8, &hash.finalResult());

    return .{
        .offsets = offsets,
        .v2_signers = .{},
        .hash = which_hash,
        .digest_buffer = digest_mem,
        .final_digest = final_digest,
        .chunks = chunks,
    };
}

pub const SigningContext = struct {
    offsets: SigningOffsets,
    v2_signers: std.ArrayListUnmanaged([]const u8) = .{},
    hash: Hash,
    digest_buffer: []const u8,
    final_digest: []const u8,
    chunks: [][]const u8,

    pub fn deinit(ctx: *SigningContext, ally: std.mem.Allocator) void {
        ally.free(ctx.digest_buffer);
        ally.free(ctx.final_digest);
        for (ctx.v2_signers.items) |signer| {
            ally.free(signer);
        }
        ctx.v2_signers.deinit(ally);
        ally.free(ctx.chunks);
    }

    pub fn writeSignedAPKAlloc(context: SigningContext, ally: std.mem.Allocator) ![]u8 {
        std.debug.assert(context.v2_signers.items.len != 0);
        var v2_total_length: usize = 0;
        for (context.v2_signers.items) |signer| {
            v2_total_length += signer.len;
        }

        const signing_block_length_prefix_size = 8;
        const signing_block_tag_size = 4;
        const magic_string_size = 16;
        const signing_block_length =
            signing_block_length_prefix_size +
            (signing_block_length_prefix_size + signing_block_tag_size + v2_total_length) +
            signing_block_length_prefix_size + magic_string_size;
        const signed_apk_length = context.offsets.apk_contents.len + signing_block_length;
        const signed_apk = try ally.alloc(u8, signed_apk_length);

        const sign_block_offset = context.offsets.signing_block_offset;
        const cd_offset = context.offsets.central_directory_offset;
        const eocd_offset = context.offsets.end_of_central_directory_offset;
        const cd_size = eocd_offset - cd_offset;
        const eocd_size = context.offsets.apk_contents.len - eocd_offset;

        @memcpy(signed_apk[0..][0..sign_block_offset], context.offsets.apk_contents[0..][0..sign_block_offset]);
        @memcpy(signed_apk[cd_offset + signing_block_length ..][0..cd_size], context.offsets.apk_contents[cd_offset..][0..cd_size]);
        @memcpy(signed_apk[eocd_offset + signing_block_length ..][0..eocd_size], context.offsets.apk_contents[eocd_offset..][0..eocd_size]);

        // update eocd directory offset
        const new_cd_offset: u32 = @intCast(cd_offset + signing_block_length);
        const eocd = signed_apk[eocd_offset + signing_block_length ..];
        std.mem.writeInt(u32, eocd[16..20], new_cd_offset, .little);

        const signing_block = signed_apk[context.offsets.signing_block_offset..][0..signing_block_length];

        std.debug.assert(signing_block.len == signing_block_length);

        std.mem.writeInt(u64, signing_block[0..][0..8], signing_block_length - 8, .little); // size of block
        std.mem.writeInt(u64, signing_block[8..][0..8], v2_total_length + 4, .little); // length of v2 block
        std.mem.writeInt(u32, signing_block[16..][0..4], @intFromEnum(SigningEntry.Tag.V2), .little); // v2 block id
        // std.mem.writeInt(u32, signing_block[20..][0..4], @intCast(v2_total_length), .little); // v2 total length

        var current_index: usize = 20;
        for (context.v2_signers.items) |signer| {
            @memcpy(signing_block[current_index..][0..signer.len], signer);
            current_index += signer.len;
        }

        std.mem.writeInt(u64, signing_block[current_index..][0..8], signing_block_length - 8, .little); // size of block
        current_index += 8;

        @memcpy(signing_block[current_index..][0..16], "APK Sig Block 42");

        return signed_apk;
    }
};

/// Returns the calculated size of the signed data.
/// - Length of the signed data: 4 bytes
/// - Length of the digest list: 4 bytes
/// - Each digest:
///   - Length of the digest item: 4 bytes
///   - signature algorithm id for the digest: 4 bytes
///   - Length of the digest: 4 bytes
///   - Digest: 32 or 64 bytes, depending on hash
/// - Length of the certificate list: 4 bytes
/// - Each certificate:
///   - Length of the certificate: 4 bytes
///   - Certificate: variable size
/// - Length of attribute list: 4 bytes
/// - Each attribute:
///   - Length of attribute: 4 bytes
///   - ID: 4 bytes
///   - Value: variable length
fn calculateSizeOfSignedData(final_digest: []const u8, public_certificates: []const std.crypto.Certificate.Parsed, private_keys: []const pem.PrivateKeyInfo) usize {
    std.debug.assert(public_certificates.len > 0);

    const data_length = 4;
    const digest_list_length = 4;
    const digest_item_length = 4;
    const digest_algo = 4;
    const digest_length = 4;
    const digests_length: u32 = @as(u32, @intCast((digest_item_length + digest_algo + digest_length + final_digest.len) * private_keys.len));

    const certificate_list_length = 4;
    var certificates_length: u32 = 0;
    for (public_certificates) |certificate| {
        const certificate_length = 4;
        certificates_length += certificate_length + @as(u32, @intCast(certificate.certificate.buffer.len));
    }

    const attributes_list_length = 4;
    const attributes_length = 0;

    return data_length + digest_list_length + digests_length + certificate_list_length + certificates_length + attributes_list_length + attributes_length;
}

fn writeSignedData(hash: Hash, final_digest: []const u8, buffer: []u8, public_certificates: []const std.crypto.Certificate.Parsed, private_keys: []const pem.PrivateKeyInfo) void {
    std.debug.assert(buffer.len == calculateSizeOfSignedData(final_digest, public_certificates, private_keys));

    const digests_length: u32 = @as(u32, @intCast((4 + 4 + 4 + final_digest.len) * private_keys.len));
    var certificates_length: u32 = 0;
    for (public_certificates) |certificate| {
        certificates_length += 4 + @as(u32, @intCast(certificate.certificate.buffer.len));
    }
    const attributes_length = 0;

    var left_to_write = buffer[0..];

    // Write total size of signed data
    std.mem.writeInt(u32, left_to_write[0..4], @intCast(buffer.len - 4), .little);
    left_to_write = left_to_write[4..];

    // Write size of digest sequence
    std.mem.writeInt(u32, left_to_write[0..4], digests_length, .little);
    left_to_write = left_to_write[4..];

    for (private_keys) |private_key| {
        // Write length
        std.mem.writeInt(u32, left_to_write[0..4], @intCast(final_digest.len + 8), .little);
        left_to_write = left_to_write[4..];

        const algorithm: SigningEntry.Signer.Algorithm = switch (hash) {
            inline .sha256 => switch (private_key.algorithm) {
                inline .rsaEncryption => .sha256_RSASSA_PSS,
                inline .X9_62_id_ecPublicKey => .sha256_ECDSA,
            },
            inline .sha512 => switch (private_key.algorithm) {
                inline .rsaEncryption => .sha512_RSASSA_PSS,
                inline .X9_62_id_ecPublicKey => .sha512_ECDSA,
            },
        };

        std.mem.writeInt(u32, left_to_write[0..4], @intFromEnum(algorithm), .little);
        left_to_write = left_to_write[4..];

        std.mem.writeInt(u32, left_to_write[0..4], @intCast(final_digest.len), .little);
        left_to_write = left_to_write[4..];

        @memcpy(left_to_write[0..final_digest.len], final_digest);
        left_to_write = left_to_write[final_digest.len..];
    }

    // Write size of certificates sequence
    std.mem.writeInt(u32, left_to_write[0..4], certificates_length, .little);
    left_to_write = left_to_write[4..];

    for (public_certificates) |certificate| {
        const cert = certificate.certificate;
        std.mem.writeInt(u32, left_to_write[0..4], @intCast(cert.buffer.len), .little);
        left_to_write = left_to_write[4..];

        @memcpy(left_to_write[0..cert.buffer.len], cert.buffer);
        left_to_write = left_to_write[cert.buffer.len..];
    }

    // Write size of attributes length - for now, hard-coded to zero
    // TODO: attributes
    std.mem.writeInt(u32, left_to_write[0..4], attributes_length, .little);
    left_to_write = left_to_write[4..];

    std.debug.assert(left_to_write.len == 0);
}

test writeSignedData {
    const hash = std.crypto.hash.sha2.Sha256;

    try std.testing.expectEqual(@as(usize, 32), hash.digest_length);

    const ally = std.testing.allocator;
    const digest = [_]u8{0} ** hash.digest_length;

    const cert_bytes = try pem.decodeCertificateAlloc(.Certificate, ally, test_file.PEM) orelse unreachable;
    defer ally.free(cert_bytes);

    const enc_key_bytes = try pem.decodeCertificateAlloc(.EncryptedPrivateKey, ally, test_file.PEM) orelse unreachable;
    defer ally.free(enc_key_bytes);

    const enc_key = try pem.EncryptedPrivateKeyInfo.init(enc_key_bytes);
    const key = try enc_key.decryptAlloc(ally, test_file.PEM_password);
    defer ally.free(key.binary_buf);

    const unparsed_cert = std.crypto.Certificate{ .buffer = cert_bytes, .index = 0 };
    const cert = try unparsed_cert.parse();

    const size = calculateSizeOfSignedData(&digest, &.{cert}, &.{key});

    try std.testing.expectEqual(@as(usize, 367), size);

    const buffer = try ally.alloc(u8, size);
    defer ally.free(buffer);

    writeSignedData(.sha256, &digest, buffer, &.{cert}, &.{key});

    // try std.testing.expectEqualSlices(u8, &[_]u8{}, buffer);
}

fn calculateSizeOfSignatures(hash: Hash, private_keys: []const pem.PrivateKeyInfo) usize {
    var size: usize = 4; // list length prefix
    for (private_keys) |private_key| {
        var el_size: usize = 0;
        el_size += 4; // signature length prefix
        el_size += 4; // algorithm id
        el_size += 4; // signature bytes length prefix
        // TODO: size of signature (will vary based on algorithm id)

        el_size += switch (hash) {
            inline .sha256 => switch (private_key.algorithm) {
                inline .rsaEncryption => 0, // .sha256_RSASSA_PSS,
                inline .X9_62_id_ecPublicKey => 64, //.sha256_ECDSA,
            },
            inline .sha512 => switch (private_key.algorithm) {
                inline .rsaEncryption => 0, // .sha512_RSASSA_PSS,
                inline .X9_62_id_ecPublicKey => 64, // .sha512_ECDSA,
            },
        };
        size += el_size;

        if (hash == .sha256 and private_key.algorithm == .X9_62_id_ecPublicKey)
            std.debug.assert(el_size == 76);
    }
    return size;
}

fn writeSignatures(hash: Hash, buffer: []u8, signed_data: []const u8, private_keys: []const pem.PrivateKeyInfo) !void {
    // Reserve space for the length of the signature list
    std.mem.writeInt(u32, buffer[0..4], @intCast(buffer.len - 4), .little);

    var current_slice = buffer[4..];

    // Create signatures with algorithm over signed data
    for (private_keys) |private_key| {
        // TODO: move this to a function
        const private_key_slice = private_key.privateKey();
        const der = try Element.parse(private_key_slice, 0);
        const der2 = try Element.parse(private_key_slice, der.slice.start);
        const der3 = try Element.parse(private_key_slice, der2.slice.end);
        const pk_slice = private_key_slice[der3.slice.start..der3.slice.end];

        const algorithm: SigningEntry.Signer.Algorithm = switch (hash) {
            inline .sha256 => switch (private_key.algorithm) {
                inline .rsaEncryption => .sha256_RSASSA_PSS,
                inline .X9_62_id_ecPublicKey => .sha256_ECDSA,
            },
            inline .sha512 => switch (private_key.algorithm) {
                inline .rsaEncryption => .sha512_RSASSA_PSS,
                inline .X9_62_id_ecPublicKey => .sha512_ECDSA,
            },
        };

        const signature = sig: {
            switch (hash) {
                inline .sha256 => switch (private_key.algorithm) {
                    inline .rsaEncryption => unreachable,
                    inline .X9_62_id_ecPublicKey => |named_curve| switch (named_curve) {
                        .secp521r1 => unreachable,
                        inline else => |curve| {
                            const Scheme = std.crypto.sign.ecdsa.Ecdsa(curve.Curve(), std.crypto.hash.sha2.Sha256);
                            var private_key_real: [Scheme.SecretKey.encoded_length]u8 = undefined;
                            @memcpy(&private_key_real, pk_slice);
                            const sk = try Scheme.SecretKey.fromBytes(private_key_real);
                            const kp = try Scheme.KeyPair.fromSecretKey(sk);

                            const sig = try kp.sign(signed_data, null);
                            break :sig &sig.toBytes();
                        },
                    },
                },
                inline .sha512 => switch (private_key.algorithm) {
                    inline .rsaEncryption => unreachable,
                    inline .X9_62_id_ecPublicKey => |named_curve| switch (named_curve) {
                        .secp521r1 => unreachable,
                        inline else => |curve| {
                            const Scheme = std.crypto.sign.ecdsa.Ecdsa(curve.Curve(), std.crypto.hash.sha2.Sha512);
                            var private_key_real: [Scheme.SecretKey.encoded_length]u8 = undefined;
                            @memcpy(&private_key_real, private_key_slice);
                            const sk = try Scheme.SecretKey.fromBytes(private_key_real);
                            const kp = try Scheme.KeyPair.fromSecretKey(sk);

                            const sig = try kp.sign(signed_data, null);
                            break :sig &sig.toBytes();
                        },
                    },
                },
            }
        };

        // Digitally sign a string and verify it with the public key

        // TODO: noise
        std.debug.assert(signature.len == 64);
        const signature_length = signature.len + 4 + 4 + 4;
        const sig_slice = current_slice[0..signature_length];
        current_slice = current_slice[signature_length..];

        // Write out signature over signed data
        std.mem.writeInt(u32, sig_slice[0..][0..4], @intCast(signature_length - 4), .little);
        std.mem.writeInt(u32, sig_slice[4..][0..4], @intFromEnum(algorithm), .little);
        std.mem.writeInt(u32, sig_slice[8..][0..4], @intCast(signature.len), .little);
        @memcpy(sig_slice[12..][0..signature.len], signature);
    }

    std.debug.assert(current_slice.len == 0);

    // std.debug.assert(std.mem.readInt(u32, signer_bytes.items[signature_length_idx..][0..4], .little) == std.math.maxInt(u32));
    // std.mem.writeInt(u32, signer_bytes.items[signature_length_idx..][0..4], @intCast(signer_bytes.items.len - signature_length_idx - 4), .little);
    // std.debug.assert(std.mem.readInt(u32, signer_bytes.items[signature_length_idx..][0..4], .little) != std.math.maxInt(u32));
}

test writeSignatures {
    // Create signed data chunk
    const hash = std.crypto.hash.sha2.Sha256;

    const ally = std.testing.allocator;
    const digest = [_]u8{0} ** hash.digest_length;

    const cert_bytes = try pem.decodeCertificateAlloc(.Certificate, ally, test_file.PEM) orelse unreachable;
    defer ally.free(cert_bytes);

    const enc_key_bytes = try pem.decodeCertificateAlloc(.EncryptedPrivateKey, ally, test_file.PEM) orelse unreachable;
    defer ally.free(enc_key_bytes);

    const enc_key = try pem.EncryptedPrivateKeyInfo.init(enc_key_bytes);
    const key = try enc_key.decryptAlloc(ally, test_file.PEM_password);
    defer ally.free(key.binary_buf);

    const unparsed_cert = std.crypto.Certificate{ .buffer = cert_bytes, .index = 0 };
    const cert = try unparsed_cert.parse();

    const signed_data_size = calculateSizeOfSignedData(&digest, &.{cert}, &.{key});

    const signed_data = try ally.alloc(u8, signed_data_size);
    defer ally.free(signed_data);

    writeSignedData(.sha256, &digest, signed_data, &.{cert}, &.{key});

    // Write signatures
    const size = calculateSizeOfSignatures(.sha256, &.{key});
    const signatures_bytes = try ally.alloc(u8, size);
    defer ally.free(signatures_bytes);

    try writeSignatures(.sha256, signatures_bytes, signed_data, &.{key});

    const signatures = try parse_v2_signatures(ally, signatures_bytes);
    defer ally.free(signatures);

    try std.testing.expectEqual(@as(usize, 1), signatures.len);
    try std.testing.expectEqual(SigningEntry.Signer.Algorithm.sha256_ECDSA, signatures[0].algorithm);
}

pub fn sign(context: *SigningContext, ally: std.mem.Allocator, public_certificates: []const std.crypto.Certificate.Parsed, private_keys: []const pem.PrivateKeyInfo) !void {
    std.debug.assert(public_certificates.len > 0);
    std.debug.assert(private_keys.len > 0);

    const public_key = public_certificates[0];

    const spki = try pem.SubjectPublicKeyInfo.fromCertificate(public_key);

    const size = calculateSizeOfSignedData(context.final_digest, public_certificates, private_keys);
    const total_capacity =
        calculateSizeOfSignedData(context.final_digest, public_certificates, private_keys) +
        calculateSizeOfSignatures(context.hash, private_keys) +
        4 + spki.buffer.len;

    var signer_bytes = try std.ArrayListUnmanaged(u8).initCapacity(ally, total_capacity + 8);

    const list_length_prefix = signer_bytes.addManyAsSliceAssumeCapacity(4); // signer list length prefix
    std.mem.writeInt(u32, list_length_prefix[0..4], @intCast(total_capacity + 4), .little);
    // Reserve space for size of signer
    const length_prefix = signer_bytes.addManyAsSliceAssumeCapacity(4); // signer length prefix
    // Write length of signer chunk to start
    std.mem.writeInt(u32, length_prefix[0..4], @intCast(total_capacity), .little);

    const signed_data_chunk = signer_bytes.addManyAsSliceAssumeCapacity(size);

    writeSignedData(context.hash, context.final_digest, signed_data_chunk, public_certificates, private_keys);

    const signatures_size = calculateSizeOfSignatures(context.hash, private_keys);
    const signatures_slice = signer_bytes.addManyAsSliceAssumeCapacity(signatures_size);

    try writeSignatures(context.hash, signatures_slice, signed_data_chunk, private_keys);

    std.log.debug("signatures size {}", .{signatures_size});
    std.log.debug("signatures slice {}", .{std.fmt.fmtSliceHexUpper(signatures_slice)});

    // Append SubjectPublicKeyInfo from first x509 certificate
    std.log.debug("spki buffer len {}", .{spki.buffer.len});
    std.debug.assert(spki.buffer.len > 0);
    const pk_slice = signer_bytes.addManyAsSliceAssumeCapacity(spki.buffer.len + 4);
    std.mem.writeInt(u32, pk_slice[0..][0..4], @intCast(spki.buffer.len), .little);
    @memcpy(pk_slice[4..], spki.buffer);

    std.log.debug("public key slice {}", .{std.fmt.fmtSliceHexUpper(pk_slice)});

    try context.v2_signers.append(ally, try signer_bytes.toOwnedSlice(ally));
}

test sign {
    const ally = std.testing.allocator;

    const cert_bytes = try pem.decodeCertificateAlloc(.Certificate, ally, test_file.PEM) orelse unreachable;
    defer ally.free(cert_bytes);

    const enc_key_bytes = try pem.decodeCertificateAlloc(.EncryptedPrivateKey, ally, test_file.PEM) orelse unreachable;
    defer ally.free(enc_key_bytes);

    const enc_key = try pem.EncryptedPrivateKeyInfo.init(enc_key_bytes);
    const key = try enc_key.decryptAlloc(ally, test_file.PEM_password);
    defer ally.free(key.binary_buf);

    const unparsed_cert = std.crypto.Certificate{ .buffer = cert_bytes, .index = 0 };
    const cert = try unparsed_cert.parse();

    // Open APK
    const const_apk_data = @embedFile("./signing/app-unsigned.apk");
    const apk_data = try std.testing.allocator.dupe(u8, const_apk_data);
    defer std.testing.allocator.free(apk_data);
    var context = try getV2SigningContext(std.testing.allocator, apk_data, .sha256);
    defer context.deinit(std.testing.allocator);

    try sign(&context, ally, &.{cert}, &.{key});

    const slices = try parse_v2_signer(context.v2_signers.items[0], null);
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A,
        0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, 0x04, 0x62, 0x39, 0x8B, 0x23, 0xE4,
        0xA4, 0x0A, 0xEE, 0xFB, 0x43, 0xBA, 0x6D, 0xF6, 0x8D, 0xD8, 0x0E, 0xE9, 0xEB, 0x68, 0xBF, 0xC8,
        0x2A, 0x56, 0x46, 0x33, 0x26, 0xAF, 0x7E, 0xF2, 0xEC, 0xE2, 0xCD, 0x14, 0xDD, 0x3D, 0x22, 0xCD,
        0xD7, 0x49, 0x9C, 0x5C, 0x03, 0xC4, 0xC6, 0x75, 0x4A, 0x13, 0x52, 0xC9, 0x49, 0xF1, 0x39, 0xE7,
        0xB1, 0x9E, 0x25, 0x68, 0x2B, 0xD1, 0xD6, 0x1B, 0x7B, 0x8E, 0xD2,
    }, slices[2]);
    // try std.testing.expectEqualSlices(u8, &[_]u8{}, slices[1]);
    // try std.testing.expectEqualSlices(u8, &[_]u8{}, slices[2]);
}

pub const VerifyContext = struct {
    signing_block: ?SigningOffsets = null,
    signing_entry_tag: ?SigningEntry.Tag = null,
    signing_entry: ?[]const u8 = null,
    last_signer: usize = 0,
    last_signed_data_block: ?SplitSlice = null,
    last_signature_sequence: ?SplitSlice = null,
    last_public_key_chunk: ?SplitSlice = null,
};

pub fn verify(ally: std.mem.Allocator, apk_contents: []u8, opt_verify_ctx: ?*VerifyContext) !void {
    const signing_block = try get_offsets(ally, apk_contents);
    if (opt_verify_ctx) |verify_ctx| {
        verify_ctx.signing_block = signing_block;
    }

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
        if (opt_verify_ctx) |verify_ctx| {
            verify_ctx.signing_entry_tag = .V2;
            verify_ctx.signing_entry = v2_block;
        }
        try verify_v2(signing_block, ally, v2_block, &default_algorithm_try_order, opt_verify_ctx);
        return;
    }
}

const SigningOffsets = struct {
    signing_block_offset: u64,
    central_directory_offset: u64,
    end_of_central_directory_offset: u64,

    signing_block: []const u8,
    apk_contents: []u8,

    /// Updates the EOCD directory offset to point to start of signing block
    pub fn update_eocd_directory_offset(signing: SigningOffsets) void {
        std.debug.assert(signing.signing_block_offset < std.math.maxInt(u32));
        const pos = @as(u32, @intCast(signing.signing_block_offset));
        const eocd = signing.apk_contents[signing.end_of_central_directory_offset..];
        std.mem.writeInt(u32, eocd[16..20], pos, .little);
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
    pub fn locate_entry(signing: SigningOffsets, tag: SigningEntry.Tag) !?[]const u8 {
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

    /// Splits an APK into chunks for signing/verifying.
    pub fn splitAPK(offsets: SigningOffsets, ally: std.mem.Allocator) ![][]const u8 {
        const apk_contents = offsets.apk_contents;
        const spos = offsets.signing_block_offset;
        const cdpos = offsets.central_directory_offset;
        const end_of_cd_pos = offsets.end_of_central_directory_offset;
        const section1 = apk_contents[0..spos]; // -8 to account for second signing block size field
        const section3 = apk_contents[cdpos..end_of_cd_pos];
        const section4 = apk_contents[end_of_cd_pos..];

        std.debug.assert(section1.len != 0);
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
};

/// Locates the signing block and verifies that the:
/// - two size fields of the APK signing Block contain the same value
/// - ZIP central directory is immediately followed by the ZIP end of central directory record
/// - ZIP end of central directory record is not followed by more data
///
/// # Parameters
/// - apk_contents: the contents of the APK file as a byte slice
///
/// # Return
/// Returns an instance of the Signing struct
pub fn get_offsets(alloc: std.mem.Allocator, apk_contents: []u8) !SigningOffsets {
    const fixed_buffer_stream = std.io.FixedBufferStream([]const u8){ .buffer = apk_contents, .pos = 0 };
    var stream_source = std.io.StreamSource{ .const_buffer = fixed_buffer_stream };

    // TODO: change zig-archive to allow operating without a buffer
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);
    archive_reader.load() catch return error.LoadArchive;

    const signing_block = try get_signing_block_offset(&stream_source, archive_reader.directory_offset);

    const expected_eocd_start = archive_reader.directory_offset + archive_reader.directory_size;

    // TODO: verify central directory immediately follows ZIP eocd
    // if (!std.mem.eql(u8, apk_contents[expected_eocd_start..][0..4], &std.mem.toBytes(archive.formats.zip.internal.EndOfCentralDirectoryRecord.signature))) {
    //     return error.EOCDDoesNotImmediatelyFollowCentralDirectory;
    // }

    // TODO: verify eocd is end of file. Is the comment field allowed to contain data?

    return SigningOffsets{
        .signing_block_offset = signing_block,
        .central_directory_offset = archive_reader.directory_offset,
        .end_of_central_directory_offset = expected_eocd_start,
        .signing_block = apk_contents[signing_block..archive_reader.directory_offset],
        .apk_contents = apk_contents,
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
/// [The following description of the algorithm is copied from the Android Source documentation.](https://source.android.com/docs/security/features/apksigning/v2#v2-verification)
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
///    d. [Compute the digest of the APK contents](https://source.android.com/docs/security/features/apksigning/v2#integrity-protected-contents)
///       using the same digest algorithm as the digest algorithm used by the signature algorithm.
///    e. Verify that the computed digest is identical to the corresponding `digest` from `digests`
///    f. Verify that `SubjectPublicKeyInfo` of the first `certificate` of `certificates` is identical to `public key`.
/// 4. Verification succeeds if at least one `signer` was found and step 3 succeeded for each found `signer`.
pub fn verify_v2(
    offsets: SigningOffsets,
    ally: std.mem.Allocator,
    entry_v2: []const u8,
    algorithm_try_order: []const SigningEntry.Signer.Algorithm,
    opt_verify_ctx: ?*VerifyContext,
) !void {
    const signer_list_iter = try get_length_prefixed_slice(entry_v2);

    var signer_count: usize = 0;
    var iter = try get_length_prefixed_slice_iter(signer_list_iter.slice);
    while (try iter.next()) |signer_slice| {
        signer_count += 1;
        if (opt_verify_ctx) |verify_ctx| {
            verify_ctx.last_signer = signer_count;
        }

        // Slice the signer into its 3 constituent fields:
        // 1. The signed data block
        // 2. The signatures
        // 3. The SubjectPublicKeyInfo of the first certificate
        const signer = try parse_v2_signer(signer_slice, opt_verify_ctx);
        const signed_data_block = signer[0];
        const signature_sequence = signer[1];
        const public_key_chunk = signer[2];
        const public_key = try pem.SubjectPublicKeyInfo.parse(public_key_chunk);

        // A. choose strongest algorithm
        const selected_signature = signature: for (algorithm_try_order) |algorithm_try| {
            break :signature get_signer_algorithm(signature_sequence, algorithm_try) orelse continue;
        } else {
            return error.AlgorithmNotInList;
        };

        // B. Verify signature aginst signed data
        switch (selected_signature.algorithm) {
            .sha256_RSASSA_PSS => {
                if (public_key.algorithm != .rsaEncryption) return error.MismatchedPublicKey;
                const pk_components = try std.crypto.Certificate.rsa.PublicKey.parseDer(public_key_chunk[public_key.data.start..public_key.data.end]);
                const pub_key = try std.crypto.Certificate.rsa.PublicKey.fromBytes(pk_components.exponent, pk_components.modulus);

                const rsa = std.crypto.Certificate.rsa;
                const Sha256 = std.crypto.hash.sha2.Sha256;
                const modulus_len = 256;

                const sig = rsa.PSSSignature.fromBytes(modulus_len, selected_signature.signature);
                _ = try rsa.PSSSignature.verify(modulus_len, sig, signed_data_block, pub_key, Sha256);
            },
            .sha256_ECDSA => {
                switch (public_key.algorithm.X9_62_id_ecPublicKey) {
                    .secp521r1 => return error.Unsupported,
                    inline else => |named_curve| {
                        const Ecdsa = std.crypto.sign.ecdsa.Ecdsa(named_curve.Curve(), std.crypto.hash.sha2.Sha256);
                        const pub_key = try Ecdsa.PublicKey.fromSec1(public_key_chunk[public_key.data.start..public_key.data.end]);

                        const sig = try Ecdsa.Signature.fromDer(selected_signature.signature);
                        _ = try sig.verify(signed_data_block, pub_key);
                    },
                }
            },
            .sha512_RSASSA_PSS,
            .sha256_RSASSA_PKCS1_v1_5,
            .sha512_RSASSA_PKCS1_v1_5,
            .sha512_ECDSA,
            .sha256_DSA_PKCS1_v1_5,
            => return error.Unimplemented,
            _ => return error.Unknown,
        }

        // C. Verify algorithm lists are the same
        const digest_sequence = try get_length_prefixed_slice(signed_data_block);
        {
            var digest_iter = try get_length_prefixed_slice_iter(digest_sequence.slice);
            var signature_iter = try get_length_prefixed_slice_iter(signature_sequence);
            while (try digest_iter.next()) |digest_chunk| {
                const signature = try signature_iter.next() orelse return error.MismatchedAlgorithmList;
                const digest_algorithm_id = std.mem.readInt(u32, digest_chunk[0..4], .little);
                const digest_algorithm: SigningEntry.Signer.Algorithm = @enumFromInt(digest_algorithm_id);

                const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .little);
                const signature_algorithm: SigningEntry.Signer.Algorithm = @enumFromInt(signature_algorithm_id);

                if (digest_algorithm != signature_algorithm) return error.MismatchedAlgorithmList;
            }
        }

        // TODO
        // D. Compute digest
        offsets.update_eocd_directory_offset();
        const chunks = try offsets.splitAPK(ally);

        switch (selected_signature.algorithm) {
            .sha256_RSASSA_PSS,
            .sha256_ECDSA,
            .sha256_RSASSA_PKCS1_v1_5,
            .sha256_DSA_PKCS1_v1_5,
            => {
                const Sha256 = std.crypto.hash.sha2.Sha256;

                // Allocate enough memory to store all the digests
                const digest_mem = try ally.alloc(u8, Sha256.digest_length * chunks.len);
                defer ally.free(digest_mem);

                // Loop over every chunk and compute its digest
                for (chunks, 0..) |chunk, i| {
                    var hash = Sha256.init(.{});

                    var size_buf: [4]u8 = undefined;
                    const size = @as(u32, @intCast(chunk.len));
                    std.mem.writeInt(u32, &size_buf, size, .little);

                    hash.update(&.{0xa5}); // Magic value byte
                    hash.update(&size_buf); // Size in bytes, le u32
                    hash.update(chunk); // Chunk contents

                    hash.final(digest_mem[i * Sha256.digest_length ..][0..Sha256.digest_length]);
                }
                // E. Verify computed digest matches stored digest
                // Compute the digest over all chunks

                var hash = Sha256.init(.{});
                var size_buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &size_buf, @as(u32, @intCast(chunks.len)), .little);
                hash.update(&.{0x5a}); // Magic value byte for final digest
                hash.update(&size_buf);
                hash.update(digest_mem);
                const final_digest = hash.finalResult();

                var digest_iter = try get_length_prefixed_slice_iter(digest_sequence.slice);
                const stored_digest = stored_digest: while (try digest_iter.next()) |digest_chunk| {
                    const digest_algorithm_id = std.mem.readInt(u32, digest_chunk[0..4], .little);
                    const digest_algorithm: SigningEntry.Signer.Algorithm = @enumFromInt(digest_algorithm_id);

                    if (digest_algorithm != selected_signature.algorithm) continue;
                    const digest_length = std.mem.readInt(u32, digest_chunk[4..8], .little);
                    const digest = digest_chunk[8..][0..digest_length];

                    break :stored_digest digest;
                } else {
                    return error.StoredDigestNotFound;
                };

                // Compare the final digest with the one stored in the signing block
                const digest_is_equal = std.mem.eql(u8, stored_digest, &final_digest);
                if (!digest_is_equal) return error.DigestMismatch;
            },
            .sha512_RSASSA_PSS,
            .sha512_RSASSA_PKCS1_v1_5,
            .sha512_ECDSA,
            => return error.Unimplemented,
            _ => return error.Unknown,
        }

        // F. Verify SubjectPublicKeyInfo of first certificate is equal to public key

        const x509_sequence = try get_length_prefixed_slice(digest_sequence.remaining orelse return error.MissingCertificate);

        var x509_iter = get_length_prefixed_slice_iter(x509_sequence.slice) catch return error.MissingCertificate;
        const x509_chunk = try x509_iter.next() orelse return error.MissingCertificate; // get first
        const x509_cert = std.crypto.Certificate{ .buffer = x509_chunk, .index = 0 };
        const x509_parsed = try x509_cert.parse();

        const pub_key = public_key_chunk[public_key.data.start..public_key.data.end];

        if (!std.mem.eql(u8, pub_key, x509_parsed.pubKey())) return error.MismatchedCertificate;
    }
    if (signer_count == 0) return error.NoSignersFound;
}

fn get_signer_algorithm(signature_sequence: []const u8, algorithm_find: SigningEntry.Signer.Algorithm) ?SigningEntry.Signer.Signature {
    var signature_iter = get_length_prefixed_slice_iter(signature_sequence) catch return null;
    while (signature_iter.next() catch return null) |signature| {
        // Find strongest algorithm
        const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .little);
        const algorithm: SigningEntry.Signer.Algorithm = @enumFromInt(signature_algorithm_id);

        if (algorithm == algorithm_find) {
            const signed_data_sig = get_length_prefixed_slice(signature[4..]) catch return null;
            return SigningEntry.Signer.Signature{
                .algorithm = algorithm,
                .signature = signed_data_sig.slice,
            };
        }
    }
    return null;
}

/// Parses signing block into memory. Does not verify that the APK is correctly signed.
pub fn parse(ally: std.mem.Allocator, apk_contents: []u8) ![]SigningEntry {
    const signing_block = try get_offsets(ally, apk_contents);

    var entry_list = std.ArrayList(SigningEntry).init(ally);

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
        try entry_list.append(try parse_v2(ally, signing_block, v2_block));
    }

    return entry_list.toOwnedSlice();
}

pub fn parse_v2_signatures(ally: std.mem.Allocator, signatures_buffer: []const u8) ![]SigningEntry.Signer.Signature {
    const sub_slice = try get_length_prefixed_slice(signatures_buffer);

    var signatures = std.ArrayListUnmanaged(SigningEntry.Signer.Signature){};
    var signature_iter = try get_length_prefixed_slice_iter(sub_slice.slice);
    while (try signature_iter.next()) |signature| {
        // Parse signatures
        const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .little);

        const signed_data_sig = get_length_prefixed_slice(signature[4..]) catch return error.UnexpectedEndOfStream;

        try signatures.append(ally, .{
            .algorithm = @as(SigningEntry.Signer.Algorithm, @enumFromInt(signature_algorithm_id)),
            .signature = signed_data_sig.slice,
        });
    }
    return try signatures.toOwnedSlice(ally);
}

pub fn parse_v2_signer(signer_buffer: []const u8, opt_verify_ctx: ?*VerifyContext) ![3][]const u8 {
    // const signer = try get_length_prefixed_slice(signer_buffer);
    const signed_data_block = try get_length_prefixed_slice(signer_buffer);
    if (opt_verify_ctx) |verify_ctx| {
        verify_ctx.last_signed_data_block = signed_data_block;
    }
    const signature_sequence = try get_length_prefixed_slice(signed_data_block.remaining orelse return error.UnexpectedEndOfStream);
    if (opt_verify_ctx) |verify_ctx| {
        verify_ctx.last_signature_sequence = signature_sequence;
    }
    const public_key_chunk = try get_length_prefixed_slice(signature_sequence.remaining orelse return error.UnexpectedEndOfStream);
    if (opt_verify_ctx) |verify_ctx| {
        verify_ctx.last_public_key_chunk = public_key_chunk;
    }
    return .{
        signed_data_block.slice,
        signature_sequence.slice,
        public_key_chunk.slice,
    };
}

/// Parses signing block into memory - not to be used for verifying APKs! Reads all of the signing block into
/// memory to allow inspection and manipulation.
pub fn parse_v2(alloc: std.mem.Allocator, signing_block: SigningOffsets, entry_slice: []const u8) !SigningEntry {
    _ = signing_block;
    var signers = std.ArrayList(SigningEntry.Signer).init(alloc);
    errdefer signers.deinit();

    const signer_list_iter = try get_length_prefixed_slice(entry_slice);

    var iter = try get_length_prefixed_slice_iter(signer_list_iter.slice);
    while (try iter.next()) |signer_slice| {
        const signer = try parse_v2_signer(signer_slice, null);
        const signed_data_block = signer[0];

        var signatures = std.ArrayListUnmanaged(SigningEntry.Signer.Signature){};
        errdefer signatures.deinit(alloc);

        const signature_sequence = signer[1];
        const public_key_chunk = signer[2];

        const public_key = try pem.SubjectPublicKeyInfo.parse(public_key_chunk);

        var signature_iter = try get_length_prefixed_slice(signature_sequence);
        var signature_opt: ?[]const u8 = signature_iter.slice;
        while (signature_opt) |signature| {
            // Parse signatures
            const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .little);

            const signed_data_sig = get_length_prefixed_slice(signature[4..]) catch return error.UnexpectedEndOfStream;

            try signatures.append(alloc, .{
                .algorithm = @as(SigningEntry.Signer.Algorithm, @enumFromInt(signature_algorithm_id)),
                .signature = signed_data_sig.slice,
            });

            // End of loop
            signature_iter = get_length_prefixed_slice(signature_iter.remaining orelse break) catch break;
            signature_opt = signature_iter.slice;
        }

        // Parse signed data
        const signed_data = signed_data: {
            const digest_sequence = try get_length_prefixed_slice(signed_data_block);

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

        try signers.append(.{
            .alloc = alloc,
            .signed_data = signed_data,
            .signatures = signatures,
            .public_key = public_key.getBytes(),
        });
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
    if (length > new_slice.len) {
        return error.OutOfBounds;
    }
    if (length == new_slice.len) return .{ .slice = new_slice[0..length], .remaining = null };
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
    if (length > new_slice.len) {
        return error.OutOfBounds;
    }
    if (length == new_slice.len) return .{ .slice = new_slice[0..length], .remaining = null };
    return .{ .slice = new_slice[0..length], .remaining = new_slice[length..] };
}

// Imports
const std = @import("std");
const archive = @import("archive");
const Element = std.crypto.Certificate.der.Element;
const test_file = @import("signing/test.zig");
