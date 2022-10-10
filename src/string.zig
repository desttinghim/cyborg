const std = @import("std");

const CodePointBytes = [3]u8;
const CodePoint = u24;

/// A modified UTF-8 encoding. Identical to UTF-8, except for the following:
/// - Only one-, two-, and three-byte encodings are used
/// - Code points in the range U+10000...U+10ffff are encoded as a surrogate pair, each of which is represented as a three-byte encoded value.
/// - The code point U+0000 is encoded in two-byte form
/// - A plain null byte (value 0) indicates the end of a string, as is the standard in C language interpretation.
/// MUTF-8 is an encoding format for UTF-16, instead of being a more direct encoding format for Unicode characters.
///
/// strcmp() will not return a properly signed result. Compare character by character if ordering is necessary.
///
/// MUTF-8 is closer to the CESU-8 format than to the UTF-8 format.
const MUTF8 = struct {
    pub fn isValidChar() bool {}

    pub fn readCodePoint(reader: anytype) !CodePoint {
        _ = reader;
    }
};

const Formats = enum {
    SimpleName,
    MemberName,
    FullClassName,
    TypeDescriptor,
    ShortyDescriptor,
};

pub fn isValidSimpleName(bytes: []u8) bool {
    var fbs = std.io.FixedBufferStream(u8){
        .buffer = bytes,
        .pos = 0,
    };
    const reader = fbs.reader();
    while (try MUTF8.readCodePoint(reader)) |codepoint| {
        switch (codepoint) {
            'A'...'Z',
            'a'...'z',
            '0'...'9',
            '$',
            '-',
            '_',
            std.unicode.utf8Decode("\u00a1")...std.unicode.utf8Decode("\u1fff"),
            std.unicode.utf8Decode("\u2010")...std.unicode.utf8Decode("\u2027"),
            std.unicode.utf8Decode("\u2030")...std.unicode.utf8Decode("\ud7ff"),
            std.unicode.utf8Decode("\ue000")...std.unicode.utf8Decode("\uffef"),
            std.unicode.utf8Decode("\u10000")...std.unicode.utf8Decode("\u10ffff"),
            => {},
            ' ',
            std.unicode.utf8Decode("\u00a0"),
            std.unicode.utf8Decode("\u2000")...std.unicode.utf8Decode("\u200a"),
            std.unicode.utf8Decode("\u202f"),
            => {
                // NOTE: since version 040
            },
            else => return false,
        }
    }
    return true;
}

pub fn isValidMemberName(bytes: []u8) bool {
    return bytes[0] == '<' and bytes[bytes.len - 1] == '>' and !isValidSimpleName(bytes[1 .. bytes.len - 1]);
}

pub fn isValidFullClassName(bytes: []u8) bool {
    // TODO optional package prefix
    return bytes[bytes.len - 1] == '/';
}

const TypeDescriptor = union(enum) {
    Void,
    Type: union(enum) {
        NonArrayTypeDescriptor: NonArrayTypeDescriptor,
        Array: NonArrayTypeDescriptor,
    },
    NonArrayTypeDescriptor: NonArrayTypeDescriptor,
};

const NonArrayTypeDescriptor = union(enum) {
    Boolean: bool,
    Byte: u8,
    Short: i16,
    Char: i8,
    Int: i32,
    Long: i64,
    Float: f32,
    Double: f64,
    Class: FullClassName,
};

const FullClassName = union(enum) {
    FullClassName: []CodePoint,
    OptionalPackagePrefix: []CodePoint,
};

const ShortyDescriptor = struct {
    shorty_return_type: ReturnTypeDescriptor,
    field_type: []TypeDescriptor,
};

const ReturnTypeDescriptor = enum(CodePoint) {
    Void = 'V',
    Boolean = 'Z',
    Byte = 'B',
    Short = 'S',
    Char = 'C',
    Int = 'I',
    Long = 'J',
    Float = 'F',
    Double = 'D',
    Class = 'L',
    Array = '[',
};

const TypeDescriptor = enum(CodePoint) {
    Boolean = 'Z',
    Byte = 'B',
    Short = 'S',
    Char = 'C',
    Int = 'I',
    Long = 'J',
    Float = 'F',
    Double = 'D',
    Class = 'L',
    Array = '[',
};
