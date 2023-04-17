//! This file implements signing and verification of Android APKs as described at the
//! [Android Source APK Signature Scheme v2 page (as of 2023-04-16)][https://source.android.com/docs/security/features/apksigning/v2]

const SigningEntry = struct {
    length: u64,
    id: u32,
    value: union {},
};

const SigningBlock = struct {
    size_of_block: u64,
    entries: []SigningEntry,
    // size_of_block repeated
    magic: [16]u8 = "APK Sig Block 42",
};

const SignatureAlgorithm = enum(u32) {
    /// RSASSA-PSS with SHA2-256 digest, SHA2-256 MGF1, 32 bytes of salt, trailer: 0xbc
    RSASSA_PSS_256 = 0x0101,
    /// RSASSA-PSS with SHA2-512 digest, SHA2-512 MGF1, 64 bytes of salt, trailer: 0xbc
    RSASSA_PSS_512 = 0x0102,
    /// RSASSA-PKCS1-v1_5 with SHA2-256 digest. This is for build systems which require deterministic signatures.
    RSASSA_PKCS1_v1_5_256 = 0x0103,
    /// RSASSA-PKCS1-v1_5 with SHA2-512 digest. This is for build systems which require deterministic signatures.
    RSASSA_PKCS1_v1_5_512 = 0x0104,
    /// ECDSA with SHA2-256 digest
    ECDSA_256 = 0x0201,
    /// ECDSA with SHA2-512 digest
    ECDSA_512 = 0x0202,
    /// DSA with SHA2-256 digest
    DSA_256 = 0x0301,
};

const Digest = struct {
    const magic = 0x5a;

    chunk_count: u32,
};
const Attribute = struct {};

const SignedData = struct {
    digests: [][]Digest,
    certificates: std.crypto.Certificate.der,
    attributes: []Attribute,
};

const Signature = struct {
    algorithm: SignatureAlgorithm,
    signature: []const u8,
};

const Signer = struct {
    signed_data: []SignedData,
    signatures: []Signature,
    public_key: std.crypto.Certificate.der,
};

/// Stored inside SigningBlock
const SignatureSchemeBlock = struct {
    const ID = 0x7109871a;
    signers: []Signer,
};

/// Intermediate data structure for signing/verifying an APK. Each section is split into chunks.
/// Each chunk is 1MB, unless it is the final chunk in a section, in which case it may be smaller.
const Chunks = struct {
    const magic = 0xa5;

    contents: [][]const u8,
    central_directory: [][]const u8,
    end_central_direcotry: [][]const u8,
};

/// Splits an APK into chunks for signing/verifying.
fn splitAPK() Chunks {}

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

// Imports
const std = @import("std");
const archive = @import("archive");
