//! This file implements signing and verification of Android APKs as described at the
//! [Android Source APK Signature Scheme v2 page (as of 2023-04-16)][https://source.android.com/docs/security/features/apksigning/v2]

const Element = std.crypto.Certificate.der.Element;

pub const SigningChain = struct {
    /// Which public key to store outside of the signed data block
    primary_certificate: usize = 0,
    certificates: std.ArrayListUnmanaged(std.crypto.Certificate),
    private_keys: std.ArrayListUnmanaged(),

    pub const AlgorithmIdentifier = union(enum) {};

    /// Encrypted data containing a private key
    pub const EncryptedPrivateKey = struct {
        algorithm: AlgorithmIdentifier,
        encrypted_data: []const u8,
    };

    pub const PrivateKeyInfo = struct {
        algorithm: AlgorithmIdentifier,
        version: enum {},
        data: []const u8,
    };
};

/// Contents of a PEM file for testing parsing. Includes an encrypted private key and the matching
/// public certificate. Automatically generated using a shell script from ApkGolf.
/// WARN: Do not trust/use this certificate in the wild! There is no knowing what it may have been
/// used for after being published online.
const PEM =
    \\Bag Attributes
    \\    friendlyName: android
    \\    localKeyID: 54 69 6D 65 20 31 37 30 32 31 36 32 38 34 37 35 32 37
    \\Key Attributes: <No Attributes>
    \\-----BEGIN ENCRYPTED PRIVATE KEY-----
    \\MIGrMFcGCSqGSIb3DQEFDTBKMCkGCSqGSIb3DQEFDDAcBAi5Sg3u6HvHtgICCAAw
    \\DAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEELo8w1H/ZnZ8v3j2Rb97SAYEUHON
    \\U4L4PtauE/F4HnuxpN8cTXFOIq6Qub3ORHDsqk+ACy/A7N/JE3hyMCV8EcNfDQq9
    \\1AaaEnRAAwP7u6sCOx31jv+YivcuEhKuInj+4Vog
    \\-----END ENCRYPTED PRIVATE KEY-----
    \\Bag Attributes
    \\    friendlyName: android
    \\    localKeyID: 54 69 6D 65 20 31 37 30 32 31 36 32 38 34 37 35 32 37
    \\subject=C =
    \\issuer=C =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBKzCB0aADAgECAgRdOjvMMAwGCCqGSM49BAMCBQAwCzEJMAcGA1UEBhMAMB4X
    \\DTE3MTAxMTAwMzI0MVoXDTE4MDEwOTAwMzI0MVowCzEJMAcGA1UEBhMAMFkwEwYH
    \\KoZIzj0CAQYIKoZIzj0DAQcDQgAEYjmLI+SkCu77Q7pt9o3YDunraL/IKlZGMyav
    \\fvLs4s0U3T0izddJnFwDxMZ1ShNSyUnxOeexniVoK9HWG3uO0qMhMB8wHQYDVR0O
    \\BBYEFJzHhvkxZ88VjoTyL21tJOYKtgVOMAwGCCqGSM49BAMCBQADRwAwRAIgSyy8
    \\Mg9zvJEfqNl94sgOIdpNn4PHdH7pOVuHP8I10TsCIDz7q63Pda/dIc03HCNkoMMY
    \\VR9SpX5DHe/L1KbojzoT
    \\-----END CERTIFICATE-----
;

/// Password to decrypt the PEM test file.
const PEM_password = "android";

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

test getPEMSlice {
    const private_key = getPEMSlice(.EncryptedPrivateKey, PEM) orelse return error.MissingEncryptedPrivateKey;
    try std.testing.expectEqualStrings(
        \\MIGrMFcGCSqGSIb3DQEFDTBKMCkGCSqGSIb3DQEFDDAcBAi5Sg3u6HvHtgICCAAw
        \\DAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEELo8w1H/ZnZ8v3j2Rb97SAYEUHON
        \\U4L4PtauE/F4HnuxpN8cTXFOIq6Qub3ORHDsqk+ACy/A7N/JE3hyMCV8EcNfDQq9
        \\1AaaEnRAAwP7u6sCOx31jv+YivcuEhKuInj+4Vog
    , private_key);
}

test "retrieve private key" {
    const base64_enc_priv_key = getPEMSlice(.EncryptedPrivateKey, PEM) orelse return error.MissingEncryptedPrivateKey;
    const decoder = std.base64.standard.decoderWithIgnore("\n");
    const upper_bound: usize = base64_enc_priv_key.len / 4 * 3;
    const buf = try std.testing.allocator.alloc(u8, upper_bound);
    defer std.testing.allocator.free(buf);
    const size = try decoder.decode(buf, base64_enc_priv_key);
    const decoded = buf[0..size];

    const sequence = try std.crypto.Certificate.der.Element.parse(decoded, 0);
    const encryption_algorithm_seq = try std.crypto.Certificate.der.Element.parse(decoded, sequence.slice.start);
    const algorithm_oid = try std.crypto.Certificate.der.Element.parse(decoded, encryption_algorithm_seq.slice.start);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.object_identifier, algorithm_oid.identifier.tag);

    const AlgorithmCategory = enum {
        pkcs5PBES2,
        pkcs5PBKDF2,
        hmacWithSHA256,

        pub const map = std.ComptimeStringMap(@This(), .{
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0D }, .pkcs5PBES2 },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0C }, .pkcs5PBKDF2 },
            .{ &[_]u8{ 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x09 }, .hmacWithSHA256 },
        });
    };

    const algorithm_category = try parseEnum(AlgorithmCategory, decoded, algorithm_oid);
    try std.testing.expectEqual(AlgorithmCategory.pkcs5PBES2, algorithm_category);

    const AlgorithmParams = union(AlgorithmCategory) {
        pkcs5PBES2: struct {
            salt: union(enum) {
                specified: std.crypto.Certificate.der.Element.Slice,
                otherSource: std.crypto.Certificate.der.Element,
            },
            iterationCount: usize,
            keyLength: usize,
            prf: std.crypto.Certificate.der.Element,
        },
    };
    _ = AlgorithmParams;
    const alg_param_sequence = try std.crypto.Certificate.der.Element.parse(decoded, algorithm_oid.slice.end);

    // Calculate the private key from the password
    const kdf_seq = try std.crypto.Certificate.der.Element.parse(decoded, alg_param_sequence.slice.start);
    const kdf_id = try std.crypto.Certificate.der.Element.parse(decoded, kdf_seq.slice.start);
    const kdf_category = try parseEnum(AlgorithmCategory, decoded, kdf_id);
    try std.testing.expectEqual(AlgorithmCategory.pkcs5PBKDF2, kdf_category);

    const kdf_param_seq = try std.crypto.Certificate.der.Element.parse(decoded, kdf_id.slice.end);
    const salt = try std.crypto.Certificate.der.Element.parse(decoded, kdf_param_seq.slice.start);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.octetstring, salt.identifier.tag);
    const iteration_count = try std.crypto.Certificate.der.Element.parse(decoded, salt.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.integer, iteration_count.identifier.tag);
    const rounds = std.mem.readInt(u16, make_slice(decoded, iteration_count.slice)[0..2], .big);
    try std.testing.expectEqual(@as(u16, 2048), rounds);
    const prf_sequence = try std.crypto.Certificate.der.Element.parse(decoded, iteration_count.slice.end);
    const prf_id = try std.crypto.Certificate.der.Element.parse(decoded, prf_sequence.slice.start);
    const prf_category = try parseEnum(AlgorithmCategory, decoded, prf_id);
    try std.testing.expectEqual(AlgorithmCategory.hmacWithSHA256, prf_category);
    const prf = std.crypto.auth.hmac.sha2.HmacSha256;

    var decryption_key: [32]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(&decryption_key, PEM_password, make_slice(decoded, salt.slice), rounds, prf);

    // Decrypt the data using the retrieved private key
    const encryption_seq = try std.crypto.Certificate.der.Element.parse(decoded, kdf_seq.slice.end);
    const encryption_scheme = try std.crypto.Certificate.der.Element.parse(decoded, encryption_seq.slice.start);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.object_identifier, encryption_scheme.identifier.tag);
    const encryption_scheme_data = try std.crypto.Certificate.der.Element.parse(decoded, encryption_scheme.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.octetstring, encryption_scheme_data.identifier.tag);
    const iv_slice = make_slice(decoded, encryption_scheme_data.slice);
    var iv_array: [16]u8 = undefined;
    @memcpy(&iv_array, iv_slice);

    const encrypted_data = try std.crypto.Certificate.der.Element.parse(decoded, encryption_algorithm_seq.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.octetstring, encrypted_data.identifier.tag);
    const ed_slice = make_slice(decoded, encrypted_data.slice);
    try std.testing.expectEqual(@as(usize, 80), ed_slice.len);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x73, 0x8D, 0x53, 0x82, 0xF8, 0x3E, 0xD6, 0xAE, 0x13, 0xF1,
        0x78, 0x1E, 0x7B, 0xB1, 0xA4, 0xDF, 0x1C, 0x4D, 0x71, 0x4E,
        0x22, 0xAE, 0x90, 0xB9, 0xBD, 0xCE, 0x44, 0x70, 0xEC, 0xAA,
        0x4F, 0x80, 0x0B, 0x2F, 0xC0, 0xEC, 0xDF, 0xC9, 0x13, 0x78,
        0x72, 0x30, 0x25, 0x7C, 0x11, 0xC3, 0x5F, 0x0D, 0x0A, 0xBD,
        0xD4, 0x06, 0x9A, 0x12, 0x74, 0x40, 0x03, 0x03, 0xFB, 0xBB,
        0xAB, 0x02, 0x3B, 0x1D, 0xF5, 0x8E, 0xFF, 0x98, 0x8A, 0xF7,
        0x2E, 0x12, 0x12, 0xAE, 0x22, 0x78, 0xFE, 0xE1, 0x5A, 0x20,
    }, ed_slice);

    const message = try std.testing.allocator.alloc(u8, ed_slice.len);
    defer std.testing.allocator.free(message);
    const Aes256 = std.crypto.core.aes.Aes256;
    const aes = Aes256.initDec(decryption_key);
    cbc(@TypeOf(aes), aes, message, ed_slice, iv_array);

    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x30, 0x41, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x04, 0x27, 0x30, 0x25, 0x02, 0x01,
        0x01, 0x04, 0x20, 0x74, 0xB1, 0x5B, 0x03, 0x81, 0x0B, 0x7D, 0xB5, 0x55, 0xAC, 0x99, 0xFB, 0x8C,
        0x8C, 0xC5, 0x88, 0xB6, 0x27, 0xCA, 0xFF, 0x22, 0x6E, 0x24, 0x85, 0x9B, 0x5C, 0x0F, 0x84, 0x4D,
        0x31, 0x36, 0xE6, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    }, message);

    const private_key_info_sequence = try Element.parse(message, 0);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.sequence, private_key_info_sequence.identifier.tag);
    const version = try Element.parse(message, private_key_info_sequence.slice.start);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.integer, version.identifier.tag);
    const version_number = std.mem.readInt(u8, make_slice(message, version.slice)[0..1], .big);
    try std.testing.expectEqual(@as(u16, 0), version_number);

    const private_key_algorithm_seq = try Element.parse(message, version.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.sequence, private_key_algorithm_seq.identifier.tag);
    const private_key_algorithm = try Element.parse(message, private_key_algorithm_seq.slice.start);
    const priv_key_algo = try std.crypto.Certificate.parseAlgorithmCategory(message, private_key_algorithm);
    _ = priv_key_algo;

    const private_key_param = try Element.parse(message, private_key_algorithm.slice.end);
    const named_curve = try std.crypto.Certificate.parseNamedCurve(message, private_key_param);
    _ = named_curve;

    const private_key = try Element.parse(message, private_key_algorithm_seq.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.octetstring, private_key.identifier.tag);
    const private_key_slice = make_slice(message, private_key.slice);

    const seq = try Element.parse(private_key_slice, 0);
    const integer = try Element.parse(private_key_slice, seq.slice.start);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.integer, integer.identifier.tag);
    const octet_str = try Element.parse(private_key_slice, integer.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.octetstring, octet_str.identifier.tag);

    const Scheme = std.crypto.sign.ecdsa.EcdsaP256Sha256;
    var private_key_real: [Scheme.SecretKey.encoded_length]u8 = undefined;
    @memcpy(&private_key_real, make_slice(private_key_slice, octet_str.slice));
    const sk = try Scheme.SecretKey.fromBytes(private_key_real);
    const kp = try Scheme.KeyPair.fromSecretKey(sk);

    const sig = try kp.sign("hello", null);
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xC3, 0x94, 0x31, 0xDF, 0xD3, 0x85, 0xE4, 0x70, 0xE1, 0x2A, 0x50, 0x9F, 0x22, 0x53, 0x5C, 0xAA,
        0x09, 0x44, 0xD9, 0xF2, 0x62, 0xCF, 0x3E, 0x0E, 0xB6, 0x7D, 0x10, 0x1B, 0x52, 0x75, 0x86, 0x70,
        0xDD, 0xED, 0x36, 0xE4, 0xE7, 0x3C, 0x37, 0x86, 0x3F, 0x2F, 0x7C, 0xA8, 0x56, 0xF0, 0xF9, 0xA4,
        0xA6, 0x72, 0xA3, 0xF4, 0x71, 0x06, 0x61, 0xE7, 0x0E, 0x0D, 0x07, 0x04, 0x13, 0xBF, 0x2E, 0x5A,
    }, &sig.toBytes());
    try sig.verify("hello", kp.public_key);
}

const PEM_dec =
    \\-----BEGIN PRIVATE KEY-----
    \\MEECAQAwEwYHKoZIzj0CAQYIKoZIzj0DAQcEJzAlAgEBBCB0sVsDgQt9tVWsmfuM
    \\jMWItifK/yJuJIWbXA+ETTE25g==
    \\-----END PRIVATE KEY-----
    \\
;

test "unencrypted private key" {
    const base64_priv_key = getPEMSlice(.PrivateKey, PEM_dec) orelse return error.MissingPrivateKey;
    try std.testing.expectEqualStrings(
        \\MEECAQAwEwYHKoZIzj0CAQYIKoZIzj0DAQcEJzAlAgEBBCB0sVsDgQt9tVWsmfuM
        \\jMWItifK/yJuJIWbXA+ETTE25g==
    , base64_priv_key);
    const decoder = std.base64.standard.decoderWithIgnore("\n");
    const upper_bound: usize = base64_priv_key.len / 4 * 3;
    const buf = try std.testing.allocator.alloc(u8, upper_bound);
    defer std.testing.allocator.free(buf);
    const size = try decoder.decode(buf, base64_priv_key);
    const decoded = buf[0..size];
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0x30, 0x41, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x04, 0x27, 0x30, 0x25, 0x02, 0x01,
        0x01, 0x04, 0x20, 0x74, 0xB1, 0x5B, 0x03, 0x81, 0x0B, 0x7D, 0xB5, 0x55, 0xAC, 0x99, 0xFB, 0x8C,
        0x8C, 0xC5, 0x88, 0xB6, 0x27, 0xCA, 0xFF, 0x22, 0x6E, 0x24, 0x85, 0x9B, 0x5C, 0x0F, 0x84, 0x4D,
        0x31, 0x36, 0xE6,
    }, decoded);

    const private_key_info_sequence = try Element.parse(decoded, 0);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.sequence, private_key_info_sequence.identifier.tag);

    const version = try Element.parse(decoded, private_key_info_sequence.slice.start);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.integer, version.identifier.tag);
    const version_number = std.mem.readInt(u8, make_slice(decoded, version.slice)[0..1], .big);
    try std.testing.expectEqual(@as(u16, 0), version_number);

    const private_key_algorithm = try Element.parse(decoded, version.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.sequence, private_key_algorithm.identifier.tag);

    const private_key = try Element.parse(decoded, private_key_algorithm.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.octetstring, private_key.identifier.tag);
}

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

pub fn make_slice(buffer: []const u8, s: Element.Slice) []const u8 {
    return buffer[s.start..s.end];
}

pub const PublicKey = struct {
    algorithm: PubKeyAlgo,
    cert: std.crypto.Certificate,
    data: Element.Slice,

    const PubKeyAlgo = std.crypto.Certificate.Parsed.PubKeyAlgo;

    pub fn parse(buffer: []const u8) PublicKey {
        var cert = std.crypto.Certificate{
            .buffer = buffer,
            .index = 0,
        };
        const pk_info = try Element.parse(buffer, 0);
        const pk_alg_elem = try Element.parse(buffer, pk_info.slice.start);
        const pk_alg_tag = try Element.parse(buffer, pk_alg_elem.slice.start);
        const alg = try std.crypto.Certificate.parseAlgorithmCategory(buffer, pk_alg_tag);

        const pub_key_algo: PubKeyAlgo = switch (alg) {
            .X9_62_id_ecPublicKey => curve: {
                const params_elem = try Element.parse(buffer, pk_alg_tag.slice.end);
                const named_curve = try std.crypto.Certificate.parseNamedCurve(buffer, params_elem);
                break :curve .{ .X9_62_id_ecPublicKey = named_curve };
            },
            .rsaEncryption => .{ .rsaEncryption = {} },
        };

        const pub_key_elem = try Element.parse(buffer, pk_alg_elem.slice.end);
        return .{
            .algorithm = pub_key_algo,
            .cert = .{
                .buffer = buffer,
                .data = try cert.parseBitString(pub_key_elem),
                .index = 0,
            },
        };
    }
};

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

pub const SigningOptions = struct {
    hash_with: HashWith = .{},
    sign_with: SignWith = .{},

    const HashWith = struct {
        sha256: bool = true,
        sha512: bool = false,
    };

    const SignWith = struct {
        ECDSA: ?std.crypto.Certificate = null,
        RSASSA_PSS: ?std.crypto.Certificate = null,
        RSASSA_PKCS1_v1_5: ?std.crypto.Certificate = null,
    };
};

/// Takes an unsigned APK files and returns a signed one
///
/// To sign an APK, we need a keystore. Android projects store their keys in the `.jks` format, which is a
/// java specific encoding for storing public keys and private keys. I have not researched how specifically this encoding works.
///
/// PEM files are used more often in open source projects outside of the java ecosystem. They store the certificates in a base64
/// encoded string in a file between a `----BEGIN [PRIVATE KEY | CERTIFICATE]----` tag and `----END [PRIVATE KEY | CERTIFICATE]----`
/// tag.
///
/// Certificates that store the public key are in the x.509 format. The private key format varies based on the specific algorithm being used.
/// All of the sub-formats are based on the ASN.1 DER binary encoding.
pub fn sign(ally: std.mem.Allocator, apk_contents: []u8, pub_key: std.crypto.Certificate.Parsed, opt: SigningOptions) ![]u8 {
    const fixed_buffer_stream = std.io.FixedBufferStream([]const u8){ .buffer = apk_contents, .pos = 0 };
    var stream_source = std.io.StreamSource{ .const_buffer = fixed_buffer_stream };

    // TODO: change zig-archive to allow operating without a buffer
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(ally, &stream_source);
    try archive_reader.load();

    const expected_eocd_start = archive_reader.directory_offset + archive_reader.directory_size;

    var offsets = SigningOffsets{
        .signing_block_offset = archive_reader.directory_offset,
        .central_directory_offset = archive_reader.directory_offset,
        .end_of_central_directory_offset = expected_eocd_start,
        .signing_block = undefined,
        .apk_contents = apk_contents,
    };

    const chunks = try offsets.splitApk();

    var signing_block = SigningEntry{ .V2 = std.ArrayList(SigningEntry.Signer).init(ally) };

    // TODO: allow multiple certs to be passed
    const signer = try signing_block.V2.addOne();
    signer.* = .{
        .alloc = ally,
        .signed_data = .{},
        .signatures = .{},
        .public_key = pub_key.pubKey(),
    };

    if (!opt.hash_with.sha256 and !opt.hash_with.sha512) {
        return error.NoDigestSelected;
    }

    var signed_data: SigningEntry.Signer.SignedData = .{
        .alloc = ally,
        .digests = .{},
        .certificates = .{},
        .attributes = .{},
    };

    if (opt.hash_with.sha256) {
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

        // Compute the digest over all chunks
        var hash = Sha256.init(.{});
        var size_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &size_buf, @as(u32, @intCast(chunks.len)), .little);
        hash.update(&.{0x5a}); // Magic value byte for final digest
        hash.update(&size_buf);
        hash.update(digest_mem);
        const final_digest = try ally.dupe(u8, hash.finalResult());

        if (opt.sign_with.ECDSA) |cert| {
            try signed_data.digests.append(.{
                .algorithm = .sha256_ECDSA,
                .data = final_digest,
            });
            try signed_data.certificates.append(cert);
        }
        if (opt.sign_with.RSASSA_PSS) |cert| {
            try signed_data.digests.append(.{
                .algorithm = .sha256_RSASSA_PSS,
                .data = final_digest,
            });
            try signed_data.certificates.append(cert);
        }
        if (opt.sign_with.RSASSA_PKCS1_v1_5) |cert| {
            try signed_data.digests.append(.{
                .algorithm = .sha256_PKCS1_v1_5,
                .data = final_digest,
            });
            try signed_data.certificates.append(cert);
        }
    }

    if (opt.hash_with.sha512) {
        const Sha512 = std.crypto.hash.sha2.Sha512;

        // Allocate enough memory to store all the digests
        const digest_mem = try ally.alloc(u8, Sha512.digest_length * chunks.len);
        defer ally.free(digest_mem);

        // Loop over every chunk and compute its digest
        for (chunks, 0..) |chunk, i| {
            var hash = Sha512.init(.{});

            var size_buf: [4]u8 = undefined;
            const size = @as(u32, @intCast(chunk.len));
            std.mem.writeInt(u32, &size_buf, size, .little);

            hash.update(&.{0xa5}); // Magic value byte
            hash.update(&size_buf); // Size in bytes, le u32
            hash.update(chunk); // Chunk contents

            hash.final(digest_mem[i * Sha512.digest_length ..][0..Sha512.digest_length]);
        }

        // Compute the digest over all chunks
        var hash = Sha512.init(.{});
        var size_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &size_buf, @as(u32, @intCast(chunks.len)), .little);
        hash.update(&.{0x5a}); // Magic value byte for final digest
        hash.update(&size_buf);
        hash.update(digest_mem);
        const final_digest = try ally.dupe(u8, hash.finalResult());

        if (opt.sign_with.ECDSA) |cert| {
            try signed_data.digests.append(.{
                .algorithm = .sha512_ECDSA,
                .data = final_digest,
            });
            try signed_data.certificates.append(cert);
        }
        if (opt.sign_with.RSASSA_PSS) |cert| {
            try signed_data.digests.append(.{
                .algorithm = .sha512_RSASSA_PSS,
                .data = final_digest,
            });
            try signed_data.certificates.append(cert);
        }
        if (opt.sign_with.RSASSA_PKCS1_v1_5) |cert| {
            try signed_data.digests.append(.{
                .algorithm = .sha512_PKCS1_v1_5,
                .data = final_digest,
            });
            try signed_data.certificates.append(cert);
        }
    }

    // Append x509 certificates
    // Append additional attributes

    // Write out signed data
    // const signed_data_slice: []const u8 = signed_data.encode();
    // _ = signed_data_slice;

    // Create signatures with algorithm over signed data
    // if (opt.hash_with.sha256) {
    //     if (opt.sign_with.ECDSA) |cert| {
    //         switch (public_key.algo.X9_62_id_ecPublicKey) {
    //             .secp521r1 => return error.Unsupported,
    //             inline else => |named_curve| {
    //                 const Ecdsa = std.crypto.sign.ecdsa.Ecdsa(named_curve.Curve(), std.crypto.hash.sha2.Sha256);
    //                 const pub_key = try Ecdsa.PublicKey.fromSec1(public_key_chunk.slice[public_key.data.start..public_key.data.end]);

    //                 const sig = try Ecdsa.Signature.fromDer(selected_signature.signature);
    //                 _ = try sig.verify(signed_data_block.slice, pub_key);
    //             },
    //         }
    //     }
    //     if (opt.sign_with.RSASSA_PSS) |cert| {
    //         const pk_components = try std.crypto.Certificate.rsa.PublicKey.parseDer(public_key_chunk.slice[public_key.data.start..public_key.data.end]);
    //         const pub_key = try std.crypto.Certificate.rsa.PublicKey.fromBytes(pk_components.exponent, pk_components.modulus);

    //         const rsa = std.crypto.Certificate.rsa;
    //         const Sha256 = std.crypto.hash.sha2.Sha256;
    //         const modulus_len = 256;

    //         const sig = rsa.PSSSignature.fromBytes(modulus_len, selected_signature.signature);
    //         _ = try rsa.PSSSignature.verify(modulus_len, sig, signed_data_block.slice, pub_key, Sha256);
    //     }
    // }
    // if (opt.hash_with.sha512) {}
    // switch (selected_signature.algorithm) {
    //     .sha256_RSASSA_PSS => {
    //         if (public_key.algo != .rsaEncryption) return error.MismatchedPublicKey;
    //     },
    //     .sha256_ECDSA => {
    //     },
    //     .sha512_RSASSA_PSS,
    //     .sha256_RSASSA_PKCS1_v1_5,
    //     .sha512_RSASSA_PKCS1_v1_5,
    //     .sha512_ECDSA,
    //     .sha256_DSA_PKCS1_v1_5,
    //     => return error.Unimplemented,
    //     _ => return error.Unknown,
    // }

    // Append public key from first x509 certificate
}

pub fn verify(ally: std.mem.Allocator, apk_contents: []u8) !void {
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
        try verify_v2(signing_block, ally, v2_block, &default_algorithm_try_order);
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
    try archive_reader.load();

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
pub fn verify_v2(offsets: SigningOffsets, ally: std.mem.Allocator, entry_v2: []const u8, algorithm_try_order: []const SigningEntry.Signer.Algorithm) !void {
    const signer_list_iter = try get_length_prefixed_slice(entry_v2);

    var signer_count: usize = 0;
    var iter = try get_length_prefixed_slice_iter(signer_list_iter.slice);
    while (try iter.next()) |signer_slice| {
        signer_count += 1;

        const signed_data_block = try get_length_prefixed_slice(signer_slice);

        // Get public key
        const signature_sequence = try get_length_prefixed_slice(signed_data_block.remaining orelse return error.UnexpectedEndOfStream);
        const public_key_chunk = try get_length_prefixed_slice(signature_sequence.remaining orelse return error.UnexpectedEndOfStream);
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
            _ => return error.Unknown,
        }

        // C. Verify algorithm lists are the same
        const digest_sequence = try get_length_prefixed_slice(signed_data_block.slice);
        {
            var digest_iter = try get_length_prefixed_slice_iter(digest_sequence.slice);
            var signature_iter = try get_length_prefixed_slice_iter(signature_sequence.slice);
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

        const pub_key = public_key_chunk.slice[public_key.data.start..public_key.data.end];

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

/// Parses signing block into memory - not to be used for verifying APKs! Reads all of the signing block into
/// memory to allow inspection and manipulation.
pub fn parse_v2(alloc: std.mem.Allocator, signing_block: SigningOffsets, entry_slice: []const u8) !SigningEntry {
    _ = signing_block;
    var signers = std.ArrayList(SigningEntry.Signer).init(alloc);
    errdefer signers.deinit();

    const signer_list_iter = try get_length_prefixed_slice(entry_slice);

    var iter = try get_length_prefixed_slice_iter(signer_list_iter.slice);
    // var signer_slice_opt: ?[]const u8 = iter.slice;
    while (try iter.next()) |signer_slice| {
        const signed_data_block = try get_length_prefixed_slice(signer_slice);

        var signatures = std.ArrayListUnmanaged(SigningEntry.Signer.Signature){};
        errdefer signatures.deinit(alloc);

        const signature_sequence = try get_length_prefixed_slice(signed_data_block.remaining orelse return error.UnexpectedEndOfStream);
        const public_key_chunk = try get_length_prefixed_slice(signature_sequence.remaining orelse return error.UnexpectedEndOfStream);

        // std.log.info("{}", .{std.fmt.fmtSliceHexUpper(public_key_chunk.slice)});

        var certi = std.crypto.Certificate{
            .buffer = public_key_chunk.slice,
            .index = 0,
        };

        const subject_pk_info = try Element.parse(public_key_chunk.slice, 0);
        const pk_alg_elem = try Element.parse(public_key_chunk.slice, subject_pk_info.slice.start);
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
        _ = pub_key_algo;

        const pub_key_elem = try Element.parse(public_key_chunk.slice, pk_alg_elem.slice.end);
        const subject_pk_bitstring = try certi.parseBitString(pub_key_elem);

        var signature_iter = try get_length_prefixed_slice(signature_sequence.slice);
        var signature_opt: ?[]const u8 = signature_iter.slice;
        while (signature_opt) |signature| {
            // Parse signatures
            const signature_algorithm_id = std.mem.readInt(u32, signature[0..4], .little);

            const signed_data_sig = get_length_prefixed_slice(signature[4..]) catch return error.UnexpectedEndOfStream;

            // std.debug.print("signature algorithm id {x}\n", .{signature_algorithm_id});

            // std.debug.print("Signature: {}\n", .{std.fmt.fmtSliceHexUpper(signed_data_sig.slice)});

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

        // {
        //     const sdpk = signed_data.certificates.items[0].pubKey();
        //     std.debug.assert(std.mem.eql(u8, public_key_chunk.slice[subject_pk_bitstring.start..subject_pk_bitstring.end], sdpk));
        // }

        // Ensures signed data and signatures have the same list of algorithms
        // for (signatures.items, signed_data.digests.items) |signature, digest| {
        //     if (signature.algorithm != digest.algorithm) return error.MismatchedAlgorithms;
        // }

        try signers.append(.{
            .alloc = alloc,
            .signed_data = signed_data,
            .signatures = signatures,
            .public_key = public_key_chunk.slice[subject_pk_bitstring.start..subject_pk_bitstring.end],
        });

        // End of loop
        // iter = get_length_prefixed_slice(iter.remaining orelse break) catch break;
        // signer_slice_opt = iter.slice;
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
