const std = @import("std");
const Element = std.crypto.Certificate.der.Element;

/// Type of certificate to retrieve from PEM file
pub const CertType = enum {
    EncryptedPrivateKey,
    PrivateKey,
    Certificate,
};

/// Returns the first slice of base64 encoded bytes between the header and footer that
/// corresponds to the passed `CertType`.
pub fn getPEMSlice(cert_type: CertType, file_buf: []const u8) ?[]const u8 {
    const header = switch (cert_type) {
        .EncryptedPrivateKey => "-----BEGIN ENCRYPTED PRIVATE KEY-----",
        .PrivateKey => "-----BEGIN PRIVATE KEY-----",
        .Certificate => "-----BEGIN CERTIFICATE-----",
    };
    const footer = switch (cert_type) {
        .EncryptedPrivateKey => "-----END ENCRYPTED PRIVATE KEY-----",
        .PrivateKey => "-----END PRIVATE KEY-----",
        .Certificate => "-----END CERTIFICATE-----",
    };
    const start_with_header = std.mem.indexOf(u8, file_buf, header) orelse return null;
    const start = 1 + (std.mem.indexOfScalarPos(u8, file_buf, start_with_header, '\n') orelse return null);
    const end = std.mem.indexOf(u8, file_buf, footer) orelse return null;
    const trimmed_slice = std.mem.trim(u8, file_buf[start..end], " \n");
    return trimmed_slice;
}

/// Base64 decoder to use when decoding PEM certificates
pub const PEMDecoder = std.base64.standard.decoderWithIgnore("\n");

/// Finds the first certificate of `cert_type` in the PEM file and returns the decoded
/// binary data. Caller owns returned memory. Returns null if there is no certificate of
/// the matching type.
pub fn decodeCertificateAlloc(cert_type: CertType, ally: std.mem.Allocator, file_buf: []const u8) !?[]const u8 {
    const base64_buf = getPEMSlice(cert_type, file_buf) orelse return null;

    const upper_bound: usize = base64_buf.len / 4 * 3;
    const buf = try ally.alloc(u8, upper_bound);
    const size = try PEMDecoder.decode(buf, base64_buf);

    const buf_resized = try ally.realloc(buf, size);
    return buf_resized;
}

/// Encrypted private key format as defined in (TODO: insert RFC here). In cyborg, this
/// is used to sign APKs.
pub const EncryptedPrivateKeyInfo = struct {
    binary_buf: []const u8,
    info: PBES_Info,
    data: Slice,

    pub const Slice = std.crypto.Certificate.Parsed.Slice;

    pub const PasswordBasedEncryptionScheme = enum {
        // PBES1,
        PBES2,

        pub const map = std.ComptimeStringMap(@This(), .{
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0D }, .PBES2 },
        });
    };

    pub const PBES_Info = union(PasswordBasedEncryptionScheme) {
        PBES2: struct {
            kdf: KeyDerivationInfo,
            scheme: EncryptionSchemeInfo,
        },
    };

    pub const KeyDerivationFunction = enum {
        PBKDF2,

        pub const map = std.ComptimeStringMap(@This(), .{
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0C }, .PBKDF2 },
        });
    };

    pub const KeyDerivationInfo = union(KeyDerivationFunction) {
        PBKDF2: struct {
            salt: Element,
            iteration_count: u32,
            key_length: ?u32,
            prf: PsuedoRandomFunction,
        },
    };

    /// MAC: Message Authentication Code
    pub const PsuedoRandomFunction = enum {
        hmacWithSHA1,
        hmacWithSHA224,
        hmacWithSHA256,
        hmacWithSHA384,
        hmacWithSHA512,
        hmacWithSHA512_224,
        hmacWithSHA512_256,

        // digestAlgorithm ::= {rsadsi 2}
        pub const map = std.ComptimeStringMap(@This(), .{
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x07 }, .hmacWithSHA1 },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x08 }, .hmacWithSHA224 },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x09 }, .hmacWithSHA256 },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x0A }, .hmacWithSHA384 },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x0B }, .hmacWithSHA512 },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x0C }, .hmacWithSHA512_224 },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x0D }, .hmacWithSHA512_256 },
        });
    };

    pub const EncryptionScheme = enum {
        desCBC,
        des_EDE3_CBC,
        rc2CBC,
        rc5_CBC_PAD,
        aes128_CBC_PAD,
        aes192_CBC_PAD,
        aes256_CBC_PAD,

        pub const map = std.ComptimeStringMap(@This(), .{
            .{ &[_]u8{ 0x01, 0x03, 0x0E, 0x03, 0x02, 0x07 }, .desCBC },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x03, 0x07 }, .des_EDE3_CBC },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x03, 0x02 }, .rc2CBC },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x03, 0x09 }, .rc5_CBC_PAD },
            .{ &[_]u8{ 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x02 }, .aes128_CBC_PAD },
            .{ &[_]u8{ 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x16 }, .aes192_CBC_PAD },
            .{ &[_]u8{ 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01, 0x2A }, .aes256_CBC_PAD },
        });
    };

    pub const EncryptionSchemeInfo = union(enum) {
        desCBC: Slice,
        des_EDE3_CBC: Slice,
        rc2CBC: Element,
        rc5_CBC_PAD: Element,
        aes128_CBC_PAD: Slice,
        aes192_CBC_PAD: Slice,
        aes256_CBC_PAD: Slice,
    };

    pub fn init(binary_buf: []const u8) !EncryptedPrivateKeyInfo {
        const sequence = try Element.parse(binary_buf, 0);
        const pbes_params_alg_seq = try Element.parse(binary_buf, sequence.slice.start);
        const pbes_params_alg_tag = try Element.parse(binary_buf, pbes_params_alg_seq.slice.start);
        const pbes_params_alg = try parseEnum(PasswordBasedEncryptionScheme, binary_buf, pbes_params_alg_tag);

        const pbes_params_seq = try Element.parse(binary_buf, pbes_params_alg_tag.slice.end);

        const info = switch (pbes_params_alg) {
            .PBES2 => info: {
                const kdf_seq = try Element.parse(binary_buf, pbes_params_seq.slice.start);
                const kdf_id = try Element.parse(binary_buf, kdf_seq.slice.start);
                const kdf_category = try parseEnum(KeyDerivationFunction, binary_buf, kdf_id);
                const kdf = switch (kdf_category) {
                    .PBKDF2 => key_derivation: {
                        const kdf_param_seq = try Element.parse(binary_buf, kdf_id.slice.end);
                        const salt = try Element.parse(binary_buf, kdf_param_seq.slice.start);
                        const iteration_count = try Element.parse(binary_buf, salt.slice.end);
                        const rounds = std.mem.readVarInt(u32, slice(binary_buf, iteration_count.slice), .big);

                        // TODO: check for key length here
                        const key_length = null;

                        const prf_sequence = try Element.parse(binary_buf, iteration_count.slice.end);
                        const prf_id = try Element.parse(binary_buf, prf_sequence.slice.start);
                        const prf_category = try parseEnum(PsuedoRandomFunction, binary_buf, prf_id);

                        break :key_derivation .{
                            .PBKDF2 = .{
                                .salt = salt,
                                .iteration_count = rounds,
                                .key_length = key_length,
                                .prf = prf_category,
                            },
                        };
                    },
                };

                const encryption_seq = try Element.parse(binary_buf, kdf_seq.slice.end);
                const encryption_tag = try Element.parse(binary_buf, encryption_seq.slice.start);
                const encryption_category = try parseEnum(EncryptionScheme, binary_buf, encryption_tag);
                const scheme_data = try Element.parse(binary_buf, encryption_tag.slice.end);
                const encryption_scheme: EncryptionSchemeInfo = switch (encryption_category) {
                    .desCBC => .{ .desCBC = scheme_data.slice },
                    .des_EDE3_CBC => .{ .des_EDE3_CBC = scheme_data.slice },
                    .aes128_CBC_PAD => .{ .aes128_CBC_PAD = scheme_data.slice },
                    .aes192_CBC_PAD => .{ .aes192_CBC_PAD = scheme_data.slice },
                    .aes256_CBC_PAD => .{ .aes256_CBC_PAD = scheme_data.slice },
                    .rc2CBC,
                    .rc5_CBC_PAD,
                    => return error.Unimplemented,
                };

                break :info .{
                    .PBES2 = .{
                        .kdf = kdf,
                        .scheme = encryption_scheme,
                    },
                };
            },
            // else => return error.Unimplemented,
        };

        const encrypted_data = try Element.parse(binary_buf, pbes_params_alg_seq.slice.end);

        return .{
            .binary_buf = binary_buf,
            .info = info,
            .data = encrypted_data.slice,
        };
    }

    const DecryptionKey = union(enum) {
        PBKDF2: [32]u8,
    };

    pub fn getDecryptionKey(private_key: EncryptedPrivateKeyInfo, password: []const u8) !DecryptionKey {
        switch (private_key.info) {
            .PBES2 => |pbes2| {
                switch (pbes2.kdf) {
                    .PBKDF2 => |pbkdf2| {
                        var decryption_key: [32]u8 = undefined;
                        switch (pbkdf2.prf) {
                            .hmacWithSHA1 => {
                                const prf = std.crypto.auth.hmac.HmacSha1;
                                try std.crypto.pwhash.pbkdf2(
                                    &decryption_key,
                                    password,
                                    slice(private_key.binary_buf, pbkdf2.salt.slice),
                                    pbkdf2.iteration_count,
                                    prf,
                                );
                            },
                            .hmacWithSHA224 => {
                                const prf = std.crypto.auth.hmac.sha2.HmacSha224;
                                try std.crypto.pwhash.pbkdf2(
                                    &decryption_key,
                                    password,
                                    slice(private_key.binary_buf, pbkdf2.salt.slice),
                                    pbkdf2.iteration_count,
                                    prf,
                                );
                            },
                            .hmacWithSHA256 => {
                                const prf = std.crypto.auth.hmac.sha2.HmacSha256;
                                try std.crypto.pwhash.pbkdf2(
                                    &decryption_key,
                                    password,
                                    slice(private_key.binary_buf, pbkdf2.salt.slice),
                                    pbkdf2.iteration_count,
                                    prf,
                                );
                            },
                            .hmacWithSHA384 => {
                                const prf = std.crypto.auth.hmac.sha2.HmacSha384;
                                try std.crypto.pwhash.pbkdf2(
                                    &decryption_key,
                                    password,
                                    slice(private_key.binary_buf, pbkdf2.salt.slice),
                                    pbkdf2.iteration_count,
                                    prf,
                                );
                            },
                            .hmacWithSHA512 => {
                                const prf = std.crypto.auth.hmac.sha2.HmacSha512;
                                try std.crypto.pwhash.pbkdf2(
                                    &decryption_key,
                                    password,
                                    slice(private_key.binary_buf, pbkdf2.salt.slice),
                                    pbkdf2.iteration_count,
                                    prf,
                                );
                            },
                            .hmacWithSHA512_224,
                            .hmacWithSHA512_256,
                            => return error.Unimplemented,
                        }
                        return .{ .PBKDF2 = decryption_key };
                    },
                }
            },
            // else => return error.Unimplemented,
        }
    }

    pub fn decrypt(private_key: EncryptedPrivateKeyInfo, decryption_key: DecryptionKey, buffer: []u8) !void {
        switch (private_key.info) {
            .PBES2 => |pbes2| {
                switch (pbes2.scheme) {
                    .aes256_CBC_PAD => |iv| {
                        const iv_slice = slice(private_key.binary_buf, iv);
                        var iv_array: [16]u8 = undefined;
                        @memcpy(&iv_array, iv_slice);

                        const encrypted_data = slice(private_key.binary_buf, private_key.data);

                        // TODO: does the decryption key vary in length?
                        const key = decryption_key.PBKDF2;

                        const Aes256 = std.crypto.core.aes.Aes256;
                        const aes = Aes256.initDec(key);
                        cbc(@TypeOf(aes), aes, buffer, encrypted_data, iv_array);
                    },
                    else => return error.Unimplemented,
                }
            },
        }
    }

    pub fn decryptAlloc(private_key: EncryptedPrivateKeyInfo, ally: std.mem.Allocator, password: []const u8) !PrivateKeyInfo {
        const ed_slice = slice(private_key.binary_buf, private_key.data);

        // Calculate decryption key from password
        const decryption_key = try private_key.getDecryptionKey(password);

        // Allocate space for the decrypted message
        const message = try ally.alloc(u8, ed_slice.len);
        errdefer ally.free(message);

        // Decrypt the data
        try private_key.decrypt(decryption_key, message);

        const private_key_info = try PrivateKeyInfo.init(message);
        return private_key_info;
    }
};

pub const PrivateKeyInfo = struct {
    binary_buf: []const u8,
    version: Version,
    algorithm: PrivKeyAlgo,
    private_key: Slice,

    pub const Version = enum(u32) {
        v0 = 0,
    };

    pub const PrivKeyAlgo = std.crypto.Certificate.Parsed.PubKeyAlgo;
    pub const Slice = std.crypto.Certificate.Parsed.Slice;

    pub fn init(binary_buf: []const u8) !PrivateKeyInfo {
        const private_key_info_sequence = try Element.parse(binary_buf, 0);
        std.debug.assert(std.crypto.Certificate.der.Tag.sequence == private_key_info_sequence.identifier.tag);

        const Certificate = std.crypto.Certificate;
        const Tag = Certificate.der.Tag;

        const version = try Element.parse(binary_buf, private_key_info_sequence.slice.start);
        if (version.identifier.tag != Tag.integer) return error.InvalidVersionElement;

        const num_slice = slice(binary_buf, version.slice);
        const version_number: Version = @enumFromInt(std.mem.readVarInt(u32, num_slice, .big));

        const private_key_algorithm = try Element.parse(binary_buf, version.slice.end);
        if (private_key_algorithm.identifier.tag != Tag.sequence) return error.InvalidAlgorithmElement;

        const algo_tag_elem = try Element.parse(binary_buf, private_key_algorithm.slice.start);
        const priv_key_algo_tag = try Certificate.parseAlgorithmCategory(binary_buf, algo_tag_elem);
        const priv_key_algo: PrivKeyAlgo = switch (priv_key_algo_tag) {
            .rsaEncryption => .{ .rsaEncryption = {} },
            .X9_62_id_ecPublicKey => x9_62: {
                const params_el = try Element.parse(binary_buf, algo_tag_elem.slice.end);
                const named_curve = try Certificate.parseNamedCurve(binary_buf, params_el);
                break :x9_62 .{ .X9_62_id_ecPublicKey = named_curve };
            },
            .curveEd25519 => return error.Unimplemented,
        };

        const private_key = try Element.parse(binary_buf, private_key_algorithm.slice.end);
        if (private_key.identifier.tag != Tag.octetstring) return error.InvalidPrivateKeyElement;

        return .{
            .binary_buf = binary_buf,
            .version = version_number,
            .algorithm = priv_key_algo,
            .private_key = private_key.slice,
        };
    }

    pub fn privateKey(private_key: PrivateKeyInfo) []const u8 {
        return slice(private_key.binary_buf, private_key.private_key);
    }
};

/// Cipher block chaining mode.
///
///
fn cbc(BlockCipher: anytype, block_cipher: BlockCipher, dst: []u8, src: []const u8, iv: [BlockCipher.block_length]u8) void {
    std.debug.assert(dst.len >= src.len);
    const block_length = BlockCipher.block_length;
    var i: usize = 0;
    var last_block: [block_length]u8 = iv;
    while (i + block_length < src.len) : (i += block_length) {
        var block: [block_length]u8 = undefined;
        // xor block with last block or initialization vector
        block_cipher.decrypt(&block, src[i..][0..block_length]);
        for (block[0..], last_block[0..]) |*byte, prev| {
            byte.* ^= prev;
        }
        // update last block value
        @memcpy(dst[i..][0..block_length], &block);
        @memcpy(&last_block, src[i..][0..block_length]);
    }
    // account for unaligned final block
    if (i < src.len) {
        var pad = [_]u8{0} ** block_length;
        const src_slice = src[i..];
        @memcpy(pad[0..src_slice.len], src_slice);
        block_cipher.decrypt(&pad, &pad);
        for (pad[0..], last_block[0..]) |*byte, prev| {
            byte.* ^= prev;
        }
        const pad_slice = pad[0 .. src.len - i];
        @memcpy(dst[i..][0..pad_slice.len], pad_slice);
    }
}

pub const ParseEnumError = error{ CertificateFieldHasWrongDataType, CertificateHasUnrecognizedObjectId };

fn parseEnum(comptime E: type, bytes: []const u8, element: std.crypto.Certificate.der.Element) ParseEnumError!E {
    if (element.identifier.tag != .object_identifier)
        return error.CertificateFieldHasWrongDataType;
    const oid_bytes = bytes[element.slice.start..element.slice.end];
    return E.map.get(oid_bytes) orelse return error.CertificateHasUnrecognizedObjectId;
}

pub fn slice(buffer: []const u8, s: Element.Slice) []const u8 {
    return buffer[s.start..s.end];
}

pub const SubjectPublicKeyInfo = struct {
    buffer: []const u8,
    algorithm: PubKeyAlgo,
    data: Element.Slice,

    pub const PubKeyAlgo = std.crypto.Certificate.Parsed.PubKeyAlgo;

    pub fn parse(buffer: []const u8) !SubjectPublicKeyInfo {
        const pub_key_info = try Element.parse(buffer, 0);
        std.debug.assert(pub_key_info.identifier.tag == .sequence);

        const pub_key_signature_algorithm = try Element.parse(buffer, pub_key_info.slice.start);
        std.debug.assert(pub_key_signature_algorithm.identifier.tag == .sequence);

        const pub_key_algo_elem = try Element.parse(buffer, pub_key_signature_algorithm.slice.start);
        std.debug.assert(pub_key_algo_elem.identifier.tag == .object_identifier);

        const pub_key_algo_tag = try std.crypto.Certificate.parseAlgorithmCategory(buffer, pub_key_algo_elem);

        const pub_key_algo: PubKeyAlgo = switch (pub_key_algo_tag) {
            .rsaEncryption => .{ .rsaEncryption = {} },
            .X9_62_id_ecPublicKey => curve: {
                const params_elem = try Element.parse(buffer, pub_key_algo_elem.slice.end);
                const named_curve = try std.crypto.Certificate.parseNamedCurve(buffer, params_elem);
                break :curve .{ .X9_62_id_ecPublicKey = named_curve };
            },
            .curveEd25519 => return error.Unimplemented,
        };

        const pub_key_elem = try Element.parse(buffer, pub_key_signature_algorithm.slice.end);
        var cert = std.crypto.Certificate{
            .buffer = buffer,
            .index = 0,
        };
        const pub_key = try cert.parseBitString(pub_key_elem);
        return .{
            .algorithm = pub_key_algo,
            .buffer = buffer[0..pub_key.end],
            .data = pub_key,
        };
    }

    pub fn fromCertificate(cert: std.crypto.Certificate.Parsed) !SubjectPublicKeyInfo {
        const bytes_to_parse = cert.certificate.buffer[cert.subject_slice.end..];
        var spki = try parse(bytes_to_parse);
        spki.buffer = spki.buffer[0..spki.data.end];
        return spki;
    }

    pub fn getBytes(spki: SubjectPublicKeyInfo) []const u8 {
        return spki.buffer[spki.data.start..spki.data.end];
    }

    test fromCertificate {
        const ally = std.testing.allocator;
        const cert_bytes = try decodeCertificateAlloc(.Certificate, ally, test_file.PEM) orelse unreachable;
        defer ally.free(cert_bytes);

        const unparsed_cert = std.crypto.Certificate{ .buffer = cert_bytes, .index = 0 };
        const cert = try unparsed_cert.parse();

        const spki = try fromCertificate(cert);
        try std.testing.expectEqual(SubjectPublicKeyInfo.PubKeyAlgo.X9_62_id_ecPublicKey, spki.algorithm);
        try std.testing.expectEqualSlices(u8, cert.pubKey(), spki.getBytes());
    }
};

const test_file = @import("test.zig");
