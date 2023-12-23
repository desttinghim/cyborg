const std = @import("std");
const pem = @import("pem.zig");
const signing = @import("../signing.zig");

const Element = std.crypto.Certificate.der.Element;

/// Contents of a PEM file for testing parsing. Includes an encrypted private key and the matching
/// public certificate. Automatically generated using a shell script from ApkGolf.
/// WARN: Do not trust/use this certificate in the wild! There is no knowing what it may have been
/// used for after being published online.
pub const PEM =
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

/// Base64 encrypted private key. Manually extracted for testing.
const ENCRYPTED_PRIVATE_KEY =
    \\MIGrMFcGCSqGSIb3DQEFDTBKMCkGCSqGSIb3DQEFDDAcBAi5Sg3u6HvHtgICCAAw
    \\DAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEELo8w1H/ZnZ8v3j2Rb97SAYEUHON
    \\U4L4PtauE/F4HnuxpN8cTXFOIq6Qub3ORHDsqk+ACy/A7N/JE3hyMCV8EcNfDQq9
    \\1AaaEnRAAwP7u6sCOx31jv+YivcuEhKuInj+4Vog
;

/// Base64 encoded private key, same as in PEM.
/// WARN: Do not trust/use this certificate in the wild! There is no knowing what it may have been
/// used for after being published online.
const PEM_dec =
    \\-----BEGIN PRIVATE KEY-----
    \\MEECAQAwEwYHKoZIzj0CAQYIKoZIzj0DAQcEJzAlAgEBBCB0sVsDgQt9tVWsmfuM
    \\jMWItifK/yJuJIWbXA+ETTE25g==
    \\-----END PRIVATE KEY-----
    \\
;

/// Decoded certificate bytes
const PRIVATE_CERT_BYTES = [_]u8{
    0x30, 0x41, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x04, 0x27, 0x30, 0x25, 0x02, 0x01,
    0x01, 0x04, 0x20, 0x74, 0xB1, 0x5B, 0x03, 0x81, 0x0B, 0x7D, 0xB5, 0x55, 0xAC, 0x99, 0xFB, 0x8C,
    0x8C, 0xC5, 0x88, 0xB6, 0x27, 0xCA, 0xFF, 0x22, 0x6E, 0x24, 0x85, 0x9B, 0x5C, 0x0F, 0x84, 0x4D,
    0x31, 0x36, 0xE6,
};

/// Decoded private key bytes
const PRIVATE_KEY_BYTES = [_]u8{
    0x30, 0x25, 0x02, 0x01, 0x01, 0x04, 0x20, 0x74, 0xB1, 0x5B, 0x03, 0x81, 0x0B, 0x7D, 0xB5, 0x55,
    0xAC, 0x99, 0xFB, 0x8C, 0x8C, 0xC5, 0x88, 0xB6, 0x27, 0xCA, 0xFF, 0x22, 0x6E, 0x24, 0x85, 0x9B,
    0x5C, 0x0F, 0x84, 0x4D, 0x31, 0x36, 0xE6,
};

/// Password to decrypt the PEM test file.
pub const PEM_password = "android";

test "getPEMSlice" {
    const private_key = pem.getPEMSlice(.EncryptedPrivateKey, PEM) orelse return error.MissingEncryptedPrivateKey;
    try std.testing.expectEqualStrings(ENCRYPTED_PRIVATE_KEY, private_key);
}

test "PrivateKeyInfo" {
    // Get base64 encoded slice
    const base64_priv_key = pem.getPEMSlice(.PrivateKey, PEM_dec) orelse return error.MissingPrivateKey;
    try std.testing.expectEqualStrings(
        \\MEECAQAwEwYHKoZIzj0CAQYIKoZIzj0DAQcEJzAlAgEBBCB0sVsDgQt9tVWsmfuM
        \\jMWItifK/yJuJIWbXA+ETTE25g==
    , base64_priv_key);

    // Decode it
    const upper_bound: usize = base64_priv_key.len / 4 * 3;
    const buf = try std.testing.allocator.alloc(u8, upper_bound);
    defer std.testing.allocator.free(buf);
    const size = try pem.PEMDecoder.decode(buf, base64_priv_key);
    const decoded = buf[0..size];
    try std.testing.expectEqualSlices(u8, &PRIVATE_CERT_BYTES, decoded);

    // Parse into private key
    const private_key = try pem.PrivateKeyInfo.init(decoded);
    try std.testing.expectEqual(pem.PrivateKeyInfo.Version.v0, private_key.version);
    try std.testing.expectEqual(pem.PrivateKeyInfo.PrivKeyAlgo.X9_62_id_ecPublicKey, private_key.algorithm);
    try std.testing.expectEqualSlices(u8, &PRIVATE_KEY_BYTES, private_key.privateKey());
}

test "retrieve private key" {
    const decoded = try pem.decodeCertificateAlloc(.EncryptedPrivateKey, std.testing.allocator, PEM) orelse unreachable;
    defer std.testing.allocator.free(decoded);

    // Parse encrypted private key
    const encrypted_private_key = try pem.EncryptedPrivateKeyInfo.init(decoded);

    const ed_slice = pem.slice(decoded, encrypted_private_key.data);
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

    try std.testing.expectEqual(pem.EncryptedPrivateKeyInfo.PBES_Info.PBES2, encrypted_private_key.info);
    try std.testing.expectEqual(pem.EncryptedPrivateKeyInfo.KeyDerivationFunction.PBKDF2, encrypted_private_key.info.PBES2.kdf);
    // try std.testing.expectEqualSlices(u8, &[_]u8{}, encrypted_private_key.info.PBES2.kdf.PBKDF2.salt);
    try std.testing.expectEqual(@as(u32, 2048), encrypted_private_key.info.PBES2.kdf.PBKDF2.iteration_count);
    try std.testing.expectEqual(pem.EncryptedPrivateKeyInfo.PsuedoRandomFunction.hmacWithSHA256, encrypted_private_key.info.PBES2.kdf.PBKDF2.prf);

    // Calculate decryption key from password
    const decryption_key = try encrypted_private_key.getDecryptionKey(PEM_password);

    // Allocate space for the decrypted message
    const message = try std.testing.allocator.alloc(u8, ed_slice.len);
    defer std.testing.allocator.free(message);

    // Decrypt the data
    try encrypted_private_key.decrypt(decryption_key, message);
    try std.testing.expectEqualSlices(u8, &PRIVATE_CERT_BYTES, message[0..PRIVATE_CERT_BYTES.len]);

    // Parse private key from decrypted data
    const private_key_info = try pem.PrivateKeyInfo.init(message);
    try std.testing.expectEqual(pem.PrivateKeyInfo.Version.v0, private_key_info.version);
    try std.testing.expectEqual(pem.PrivateKeyInfo.PrivKeyAlgo.X9_62_id_ecPublicKey, private_key_info.algorithm);
    try std.testing.expectEqualSlices(u8, &PRIVATE_KEY_BYTES, private_key_info.privateKey());

    const private_key_slice = private_key_info.privateKey();

    // TODO: verify which parts of the private key are supposed to be used for signing
    const seq = try Element.parse(private_key_slice, 0);
    const integer = try Element.parse(private_key_slice, seq.slice.start);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.integer, integer.identifier.tag);
    const octet_str = try Element.parse(private_key_slice, integer.slice.end);
    try std.testing.expectEqual(std.crypto.Certificate.der.Tag.octetstring, octet_str.identifier.tag);

    // Digitally sign a string and verify it with the public key
    const Scheme = std.crypto.sign.ecdsa.EcdsaP256Sha256;
    var private_key_real: [Scheme.SecretKey.encoded_length]u8 = undefined;
    @memcpy(&private_key_real, pem.slice(private_key_slice, octet_str.slice));
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

test "sign apk" {
    // Retrieve private keys
    const decoded = try pem.decodeCertificateAlloc(.EncryptedPrivateKey, std.testing.allocator, PEM) orelse unreachable;
    defer std.testing.allocator.free(decoded);

    // Parse encrypted private key
    const encrypted_private_key = try pem.EncryptedPrivateKeyInfo.init(decoded);

    const ed_slice = pem.slice(decoded, encrypted_private_key.data);

    // Calculate decryption key from password
    const decryption_key = try encrypted_private_key.getDecryptionKey(PEM_password);

    // Allocate space for the decrypted message
    const message = try std.testing.allocator.alloc(u8, ed_slice.len);
    defer std.testing.allocator.free(message);

    // Decrypt the data
    try encrypted_private_key.decrypt(decryption_key, message);

    // Parse private key from decrypted data
    const private_key_info = try pem.PrivateKeyInfo.init(message);

    const privkeys = [_]pem.PrivateKeyInfo{private_key_info};

    // Retrieve public key
    const pub_key_decoded = try pem.decodeCertificateAlloc(.Certificate, std.testing.allocator, PEM) orelse unreachable;
    defer std.testing.allocator.free(pub_key_decoded);

    var pub_cert = std.crypto.Certificate{ .buffer = pub_key_decoded, .index = 0 };
    const pub_parsed = try pub_cert.parse();

    const pubkeys = [_]std.crypto.Certificate.Parsed{pub_parsed};

    // Open APK
    const const_apk_data = @embedFile("app-unsigned.apk");
    const apk_data = try std.testing.allocator.dupe(u8, const_apk_data);
    defer std.testing.allocator.free(apk_data);
    var apk = try signing.getV2SigningContext(std.testing.allocator, apk_data, .sha256);
    defer apk.deinit(std.testing.allocator);

    try signing.sign(&apk, std.testing.allocator, &pubkeys, &privkeys);

    const signed_apk = try apk.writeSignedAPKAlloc(std.testing.allocator);
    defer std.testing.allocator.free(signed_apk);

    const cd_end_offset = const_apk_data.len - apk.offsets.central_directory_offset;
    try std.testing.expectEqualSlices(u8, "APK Sig Block 42", signed_apk[signed_apk.len - cd_end_offset - 16 ..][0..16]);

    // FIXME: the generated APK fails to verify - something is wrong in the construction of the fields.
    // I am stumped regarding the cause, even after pulling up the generated file in a hex viewer.
    try signing.verify(std.testing.allocator, signed_apk);
}
