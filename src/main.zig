const std = @import("std");
const testing = std.testing;
const archive = @import("archive");

// const c = @import("c.zig");
pub const dex = @import("dex.zig");
pub const binxml = @import("binxml.zig");
pub const signing = @import("signing.zig");
pub const dexter = @import("dexter.zig");

comptime {
    _ = dexter;
    _ = signing;
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const usage =
    \\USAGE: zandroid <subcommand>
    \\SUBCOMMANDS:
    \\  zip     <file>                  Reads a zip file and lists the contents
    \\  zip     <file> <filename>       Reads the contents of a file from a zip file
    \\  align   <file>                  Aligns a zip file
    \\  verify  <file>                  Verifies the signature of an APK file
    \\  sign    <file>                  Signs an APK file
    \\  view-signatures <file>          Parses and displays signatures from an APK
    \\  binxml  <file>                  Reads an Android binary XML file
    \\  xml     <file>                  Converts an XML file to an Android binary XML file
    \\  apk     <file>                  Reads the AndroidManifest.xml in the indicated apk
    \\  dex     <file>                  Reads a Dalvik EXecutable file
    \\
;

const Subcommand = enum {
    zip,
    // xml,
    binxml,
    apk,
    dex,
    @"align",
    sign,
    verify,
    // pkg,
    @"view-signatures",
};

pub fn main() !void {
    const stdout = std.io.getStdOut();
    try run(stdout);
    // catch |err| {
    //     switch (err) {
    //         else => |e| {
    //             _ = try stdout.write("Error! ");
    //             _ = try stdout.write(@errorName(e));
    //             _ = try stdout.write("\n");
    //         },
    //     }
    //     _ = try stdout.write(usage);
    // };
}

pub fn run(stdout: std.fs.File) !void {
    const alloc = gpa.allocator();
    const args = try std.process.argsAlloc(alloc);

    if (args.len < 2) {
        return error.MissingSubcommand;
    }

    const cmd = std.meta.stringToEnum(Subcommand, args[1]) orelse return error.InvalidSubcommand;

    switch (cmd) {
        .zip => try readZip(alloc, args, stdout),
        .binxml => try readBinXml(alloc, args, stdout),
        // .xml => try readXml(alloc, args, stdout),
        .apk => try readApk(alloc, args, stdout),
        .dex => try readDex(alloc, args, stdout),
        .@"align" => try alignZip(alloc, args, stdout),
        .sign => try signZip(alloc, args, stdout),
        .verify => try verifyAPK(alloc, args, stdout),
        // .pkg => try writePackage(alloc, args, stdout),
        .@"view-signatures" => try viewSignaturesAPK(alloc, args, stdout),
    }
}

// pub fn print_attributes(stdout: std.fs.File, doc: c.xmlDocPtr, node: *c.xmlNode) !void {
//     var cur_attribute = node.properties;
//     _ = doc;
//     while (cur_attribute) |attribute| : (cur_attribute = attribute.*.next) {
//         const attr_name = attribute.*.name;
//         const attr_value = c.xmlGetProp(node, attr_name);
//         defer c.xmlFree.?(attr_value);
//         try std.fmt.format(stdout.writer(), " {s}={s}", .{ attr_name, attr_value });
//     }
// }

// const XMLReaderType = enum(c_int) {
//     None = c.XML_READER_TYPE_NONE,
//     Element = c.XML_READER_TYPE_ELEMENT,
//     Attribute = c.XML_READER_TYPE_ATTRIBUTE,
//     Text = c.XML_READER_TYPE_TEXT,
//     CData,
//     EntityReference,
//     Entity,
//     ProcessingInstruction,
//     Comment,
//     Document,
//     DocumentType,
//     DocumentFragment,
//     Notation,
//     Whitespace,
//     SignificantWhitespace = c.XML_READER_TYPE_SIGNIFICANT_WHITESPACE,
//     EndElement = c.XML_READER_TYPE_END_ELEMENT,
//     EndEntity,
//     XMLDeclaration,
// };
//
// pub fn print_node(stdout: std.fs.File, reader: c.xmlTextReaderPtr) !void {
//     var name: [*:0]const u8 = c.xmlTextReaderConstName(reader) orelse "--";
//     var t = c.xmlTextReaderNodeType(reader);
//     try stdout.writer().print("{:<5} {s: <25} {s: <20} {:<10} {:<10}", .{
//         c.xmlTextReaderDepth(reader),
//         @tagName(@as(XMLReaderType, @enumFromInt(t))),
//         name,
//         c.xmlTextReaderIsEmptyElement(reader),
//         c.xmlTextReaderHasValue(reader),
//     });
//
//     if (c.xmlTextReaderConstValue(reader)) |value| {
//         try stdout.writer().print("{s}\n", .{value});
//     } else {
//         _ = try stdout.writer().write("\n");
//     }
// }
//
// pub fn readXml(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
//     var reader = c.xmlNewTextReaderFilename(args[2].ptr);
//     if (reader == null) {
//         try std.fmt.format(stdout.writer(), "error: could not open file {s}\n", .{args[2]});
//         return error.XMLReaderInit;
//     }
//     defer {
//         c.xmlFreeTextReader(reader);
//         c.xmlCleanupParser();
//     }
//
//     var builder = binxml.XMLTree.Builder.init(alloc);
//
//     var attributes = std.ArrayList(binxml.XMLTree.Builder.Attribute_b).init(alloc);
//     defer attributes.deinit();
//
//     var ret = c.xmlTextReaderRead(reader);
//     while (ret == 1) : (ret = c.xmlTextReaderRead(reader)) {
//         // try print_node(stdout, reader);
//         var node_type = @as(XMLReaderType, @enumFromInt(c.xmlTextReaderNodeType(reader)));
//         const line_number = @as(u32, @intCast(c.xmlTextReaderGetParserLineNumber(reader)));
//         try attributes.resize(0); // clear list
//         switch (node_type) {
//             .Element => {
//                 const name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingNameForElement);
//                 const namespace = if (c.xmlTextReaderConstNamespaceUri(reader)) |namespace| std.mem.span(namespace) else null;
//                 const is_empty = c.xmlTextReaderIsEmptyElement(reader) == 1;
//
//                 if (c.xmlTextReaderHasAttributes(reader) == 1) {
//                     const count = @as(usize, @intCast(c.xmlTextReaderAttributeCount(reader)));
//                     for (0..count) |i| {
//                         if (c.xmlTextReaderMoveToAttributeNo(reader, @as(c_int, @intCast(i))) != 1) continue;
//                         const attr_ns = if (c.xmlTextReaderConstNamespaceUri(reader)) |ns| std.mem.span(ns) else null;
//                         const attr_name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingAttributeName);
//                         const value = std.mem.span(c.xmlTextReaderConstValue(reader) orelse return error.MissingAttributeValue);
//                         if (c.xmlTextReaderIsNamespaceDecl(reader) == 1) {
//                             try builder.startNamespace(attr_name, value);
//                             continue;
//                         }
//                         try attributes.append(.{
//                             .namespace = attr_ns,
//                             .name = attr_name,
//                             .value = value,
//                         });
//                     }
//                 }
//
//                 try builder.startElement(name, attributes.items, .{
//                     .namespace = (namespace),
//                     .line_number = line_number,
//                 });
//                 if (is_empty) {
//                     try builder.endElement(name, .{
//                         .namespace = namespace,
//                         .line_number = line_number,
//                     });
//                     // try stdout.writer().print("{}", .{builder.xml_tree.nodes.getLast()});
//                 }
//             },
//             .EndElement => {
//                 const name = std.mem.span(c.xmlTextReaderConstLocalName(reader) orelse return error.MissingNameForEndElement);
//                 const namespace = if (c.xmlTextReaderConstNamespaceUri(reader)) |namespace| std.mem.span(namespace) else null;
//                 try builder.endElement(name, .{
//                     .namespace = namespace,
//                     .line_number = line_number,
//                 });
//                 // try stdout.writer().print("{}", .{builder.xml_tree.nodes.getLast()});
//             },
//             // .CData => builder.insertCData(.{}),
//             else => {},
//         }
//     }
//
//     try print_xml_tree(builder.xml_tree, stdout);
// }

pub fn readZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var stream_source = std.io.StreamSource{ .file = file };
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);

    try archive_reader.load();

    for (archive_reader.directory.items, 0..) |cd_record, i| {
        _ = cd_record;
        const header = archive_reader.getHeader(i);
        _ = try stdout.write(header.filename);
        _ = try stdout.write("\n");
    }
    // TODO: write out more info on the zip file
}

pub fn signZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const pempath = try std.fs.realpathAlloc(alloc, args[2]);
    const filepath = try std.fs.realpathAlloc(alloc, args[3]);
    const outpath = args[4];

    const pemfile = try std.fs.openFileAbsolute(pempath, .{});
    const pem = try pemfile.readToEndAlloc(alloc, std.math.maxInt(u32));

    // Locate and decode private + public certificate
    const priv_key_decoded = try signing.pem.decodeCertificateAlloc(.EncryptedPrivateKey, alloc, pem) orelse return error.MissingEncryptedPrivateKey;
    defer alloc.free(priv_key_decoded);

    const pub_key_decoded = try signing.pem.decodeCertificateAlloc(.Certificate, alloc, pem) orelse return error.MissingPublicKey;
    defer alloc.free(pub_key_decoded);

    // Decrypt private key
    const encrypted_private_key = try signing.pem.EncryptedPrivateKeyInfo.init(priv_key_decoded);
    const private_key = try encrypted_private_key.decryptAlloc(alloc, args[5]);
    defer alloc.free(private_key.binary_buf);

    // Parse public key
    const certificate = std.crypto.Certificate{ .buffer = pub_key_decoded, .index = 0 };
    const parsed = try certificate.parse();

    // Open APK
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    // Read zip archive into memory
    const unsigned_apk = try file.reader().readAllAlloc(alloc, std.math.maxInt(u64));
    defer alloc.free(unsigned_apk);

    var signing_context = try signing.getV2SigningContext(alloc, unsigned_apk, .sha256);

    try signing.sign(&signing_context, alloc, &.{parsed}, &.{private_key});

    const signed_apk = try signing_context.writeSignedAPKAlloc(alloc);
    defer alloc.free(signed_apk);

    const outfile = try std.fs.cwd().createFile(outpath, .{});
    defer outfile.close();
    try outfile.writeAll(signed_apk);
    try outfile.sync();

    try stdout.writer().print("Wrote signed file to {s}\n", .{outpath});

    // TODO: parse signing options
    // TODO: Sign with specified options
    // TODO: Write new zip file with signing block added
}

pub fn verifyAPK(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    _ = stdout;
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    const apk_map = try std.os.mmap(null, try file.getEndPos(), std.os.PROT.WRITE, std.os.MAP.PRIVATE, file.handle, 0);
    defer std.os.munmap(apk_map);

    var verify_ctx: signing.VerifyContext = .{};

    signing.verify(alloc, apk_map, &verify_ctx) catch |e| {
        if (verify_ctx.signing_block) |block| {
            std.log.err("Signing Block found: {}", .{std.fmt.fmtSliceHexUpper(block.signing_block)});
        }
        if (verify_ctx.signing_entry_tag) |entry_tag| {
            std.log.err("Entry found: {}", .{entry_tag});
        }
        if (verify_ctx.signing_entry) |entry| {
            std.log.err("Entry found: {}", .{std.fmt.fmtSliceHexUpper(entry)});
        }
        if (verify_ctx.last_signer != 0) {
            std.log.err("Last signer: {}", .{verify_ctx.last_signer});
        }
        if (verify_ctx.last_signed_data_block) |block| {
            std.log.err("Last signed data block: {}", .{std.fmt.fmtSliceHexUpper(block.slice)});
            if (verify_ctx.last_signature_sequence == null) {
                if (block.remaining) |remains| {
                    std.log.err("Remaining after last signed data block: {}", .{std.fmt.fmtSliceHexUpper(remains)});
                }
            }
        }
        if (verify_ctx.last_signature_sequence) |block| {
            std.log.err("Last signature sequence: {}", .{std.fmt.fmtSliceHexUpper(block.slice)});
            if (verify_ctx.last_public_key_chunk == null) {
                if (block.remaining) |remains| {
                    std.log.err("Remaining after last signature sequence: {}", .{std.fmt.fmtSliceHexUpper(remains)});
                }
            }
        }
        if (verify_ctx.last_public_key_chunk) |chunk| {
            std.log.err("Last public key length: {}", .{chunk.slice.len});
            std.log.err("Last public key chunk: {}", .{std.fmt.fmtSliceHexUpper(chunk.slice)});
            if (chunk.remaining) |remains| {
                std.log.err("Remaining after last public key chunk: {}", .{std.fmt.fmtSliceHexUpper(remains)});
            }
        }
        if (verify_ctx.last_signature_algorithm) |algorithm| {
            std.log.err("Last signature algorithm: {}", .{algorithm});
        }
        return e;
    };
}

pub fn viewSignaturesAPK(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    const apk_map = try std.os.mmap(null, try file.getEndPos(), std.os.PROT.WRITE, std.os.MAP.PRIVATE, file.handle, 0);
    defer std.os.munmap(apk_map);

    const signature = try signing.parse(alloc, apk_map);
    // TODO: correct deinit code
    // defer {
    //     for (signature) |*entry| {
    //         entry.deinit();
    //     }
    // }
    for (signature) |entry| switch (entry) {
        .V2 => |signers| for (signers.items, 0..) |signer, i| {
            try std.fmt.format(stdout.writer(), "Signer {}:\n", .{i});
            try std.fmt.format(stdout.writer(), "\tPublic Key: {}\n", .{std.fmt.fmtSliceHexUpper(signer.public_key)});
            try std.fmt.format(stdout.writer(), "\tSigned Data Signatures\n", .{});
            for (signer.signatures.items) |sig| {
                try std.fmt.format(stdout.writer(), "\t\tAlgorithm: {}, Signature: {}\n", .{ sig.algorithm, std.fmt.fmtSliceHexUpper(sig.signature) });
            }
            try std.fmt.format(stdout.writer(), "\tSigned Data\n\t\tDigests\n", .{});
            for (signer.signed_data.digests.items) |digest| {
                try std.fmt.format(stdout.writer(), "\t\t\tAlgorithm: {}, Digest: {}\n", .{ digest.algorithm, std.fmt.fmtSliceHexUpper(digest.data) });
            }
            try std.fmt.format(stdout.writer(), "\t\tCertificates\n", .{});
            for (signer.signed_data.certificates.items) |cert| {
                try std.fmt.format(stdout.writer(), "\t\t\tCertificate: {}\n", .{std.fmt.fmtSliceHexUpper(cert.certificate.buffer)});
                try std.fmt.format(stdout.writer(), "\t\t\t\tVersion: {}\n", .{cert.version});
                try std.fmt.format(stdout.writer(), "\t\t\t\tCommon name: {s}\n", .{cert.commonName()});
                try std.fmt.format(stdout.writer(), "\t\t\t\tIssuer: {s}\n", .{cert.issuer()});
                try std.fmt.format(stdout.writer(), "\t\t\t\tSubject: {s}\n", .{cert.subject()});
                try std.fmt.format(stdout.writer(), "\t\t\t\tSignature Algorithm: {}\n", .{cert.signature_algorithm});
                try std.fmt.format(stdout.writer(), "\t\t\t\tSignature: {}\n", .{std.fmt.fmtSliceHexUpper(cert.signature())});
                // Seems to mostly just be the certificate?
                // if (cert.message_slice.start < cert.message_slice.end) {
                //     try std.fmt.format(stdout.writer(), "\t\t\t\tMessage: {}\n", .{std.fmt.fmtSliceHexLower(cert.message())});
                // }
                try std.fmt.format(stdout.writer(), "\t\t\t\tPub Key Algorithm: {}\n", .{cert.pub_key_algo});
                try std.fmt.format(stdout.writer(), "\t\t\t\tPub Key: {}\n", .{std.fmt.fmtSliceHexUpper(cert.pubKey())});
                try std.fmt.format(stdout.writer(), "\t\t\t\tNot valid before: {}\tNot valid after: {}\n", .{ cert.validity.not_before, cert.validity.not_after });
                try std.fmt.format(stdout.writer(), "\t\t\t\tSubject Alt Name: {s}\n", .{cert.subjectAltName()});
            }
            try std.fmt.format(stdout.writer(), "\t\tAttributes\n", .{});
            for (signer.signed_data.attributes.items) |attribute| {
                try std.fmt.format(stdout.writer(), "\t\t\tId: {}, Value: {d}\n", .{ attribute.id, std.fmt.fmtSliceHexUpper(attribute.value) });
            }
        },
    };
}

pub fn alignZip(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var stream_source = std.io.StreamSource{ .file = file };
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);

    try archive_reader.load();

    for (archive_reader.directory.items, 0..) |cd_record, i| {
        _ = cd_record;
        const header = archive_reader.getHeader(i);
        _ = try stdout.write(header.filename);
        _ = try stdout.write("\n");
    }

    // TODO: align zip items
}

pub fn readBinXml(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();

    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    const document = try binxml.Document.readAlloc(file.seekableStream(), file.reader(), arena_alloc);

    try printInfo(document, stdout);
}

pub fn readApk(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});

    var stream_source = std.io.StreamSource{ .file = file };
    var archive_reader = archive.formats.zip.reader.ArchiveReader.init(alloc, &stream_source);

    try archive_reader.load();

    // Read manifest
    const manifest_header = archive_reader.findFile("AndroidManifest.xml") orelse return error.MissingManifest;

    const manifest_string = try archive_reader.extractFileString(manifest_header, alloc, true);
    defer alloc.free(manifest_string);

    var manifest_stream = std.io.FixedBufferStream([]const u8){ .pos = 0, .buffer = manifest_string };
    const document = try binxml.Document.readAlloc(manifest_stream.seekableStream(), manifest_stream.reader(), alloc);

    try printInfo(document, stdout);

    // Read resource table
    const resource_header = archive_reader.findFile("resources.arsc") orelse return error.MissingResourceTable;

    const resource_string = try archive_reader.extractFileString(resource_header, alloc, true);
    defer alloc.free(resource_string);

    var resource_stream = std.io.FixedBufferStream([]const u8){ .pos = 0, .buffer = resource_string };
    const resource_document = try binxml.Document.readAlloc(resource_stream.seekableStream(), resource_stream.reader(), alloc);

    try printInfo(resource_document, stdout);
}

pub fn readDex(alloc: std.mem.Allocator, args: [][]const u8, stdout: std.fs.File) !void {
    const filepath = try std.fs.realpathAlloc(alloc, args[2]);
    const dirpath = std.fs.path.dirname(filepath) orelse return error.NonexistentDirectory;
    const dir = try std.fs.openDirAbsolute(dirpath, .{});
    const file = try dir.openFile(filepath, .{});
    const file_buffer = try file.readToEndAlloc(alloc, std.math.maxInt(u16));
    defer alloc.free(file_buffer);

    // TODO: remove references to Dex internal fields and instead design an API that will allow
    // querying the file directly _without_ creating a bunch of in-memory structures
    var dexfile = try dex.Dex.initFromSlice(file_buffer);

    // var classes = try dex.Dex.readAlloc(file.seekableStream(), file.reader(), alloc);

    var map_iter = dexfile.mapIterator();
    try std.fmt.format(stdout.writer(), "Map Item Count: {}\n", .{map_iter.list_size});
    while (map_iter.next()) |list_item| {
        try std.fmt.format(stdout.writer(), "Map Item: {}\n", .{list_item});
    }

    var string_iter = dexfile.stringIterator();
    while (string_iter.next()) |string| {
        try std.fmt.format(stdout.writer(), "String: {s}\n", .{string});
    }

    var type_iter = dexfile.typeIterator();
    while (type_iter.next()) |t_id| {
        const t = try dexfile.getString(t_id);
        try std.fmt.format(stdout.writer(), "Type Descriptor: {s}\n", .{t});
    }

    {
        var i: usize = 0;
        var proto_iter = dexfile.protoIterator();
        while (proto_iter.next()) |proto| : (i += 1) {
            const shorty = try dexfile.getString(proto.shorty_idx);
            const t = try dexfile.getTypeString(proto.return_type_idx);
            try std.fmt.format(stdout.writer(), "prototype {}\n", .{proto});
            try std.fmt.format(stdout.writer(), "Prototype {}; shorty {s}; (", .{ i, shorty });
            var param_iter_opt = try dexfile.typeListIterator(proto.parameters_off);
            if (param_iter_opt) |*param_iter| {
                while (param_iter.next()) |param| {
                    const param_str = try dexfile.getTypeString(param);
                    try std.fmt.format(stdout.writer(), "{s}", .{param_str});
                }
            }
            try std.fmt.format(stdout.writer(), "){s}\n", .{t});
        }
    }

    {
        var i: usize = 0;
        var field_iter = dexfile.fieldIterator();
        while (field_iter.next()) |id| : (i += 1) {
            const class_str = try dexfile.getTypeString(id.class_idx);
            const type_str = try dexfile.getTypeString(id.type_idx);
            const name_str = try dexfile.getString(id.name_idx);
            try std.fmt.format(stdout.writer(), "Field {}, {s}.{s}: {s}\n", .{ i, class_str, name_str, type_str });
        }
    }

    {
        var i: usize = 0;
        var method_iter = dexfile.methodIterator();
        while (method_iter.next()) |id| : (i += 1) {
            const class_str = try dexfile.getTypeString(id.class_idx);
            const name_str = try dexfile.getString(id.name_idx);
            try std.fmt.format(stdout.writer(), "Method {}: {s} {s}\n", .{ i, class_str, name_str });
        }
    }

    {
        var i: usize = 0;
        var class_def_iter = dexfile.classDefIterator();
        while (class_def_iter.next()) |class| : (i += 1) {
            const class_str = try dexfile.getTypeString(class.class_idx);
            if (class.superclass_idx != dex.NO_INDEX) {
                const superclass_str = try dexfile.getTypeString(class.superclass_idx);
                try std.fmt.format(stdout.writer(), "Class {s} extends {s}\n", .{ class_str, superclass_str });
            } else {
                try std.fmt.format(stdout.writer(), "Class {s}\n", .{class_str});
            }

            const class_data = try dexfile.getClassData(class);
            try std.fmt.format(stdout.writer(), "{}\n", .{class_data});

            try std.fmt.format(stdout.writer(), "Static Fields:\n", .{});
            var static_field_iter = dexfile.classDataIterator(class_data, .static_field);
            while (static_field_iter.next()) |data| {
                const field_id = try dexfile.getField(data.static_field.field_idx);
                const t = try dexfile.getString(field_id.type_idx);
                const name = try dexfile.getString(field_id.name_idx);
                try std.fmt.format(stdout.writer(), "\t{} {s} {s}\n", .{
                    data.static_field.access_flags,
                    t,
                    name,
                });
            }

            try std.fmt.format(stdout.writer(), "Instance Fields:\n", .{});
            var instance_field_iter = dexfile.classDataIterator(class_data, .instance_field);
            while (instance_field_iter.next()) |data| {
                const field_id = try dexfile.getField(data.instance_field.field_idx);
                const t = try dexfile.getString(field_id.type_idx);
                const name = try dexfile.getString(field_id.name_idx);
                try std.fmt.format(stdout.writer(), "\t{} {s} {s}\n", .{
                    data.instance_field.access_flags,
                    t,
                    name,
                });
            }

            try std.fmt.format(stdout.writer(), "Direct Methods:\n", .{});
            var direct_method_iter = dexfile.classDataIterator(class_data, .direct_method);
            while (direct_method_iter.next()) |data| {
                const method_id = try dexfile.getMethod(data.direct_method.method_idx);
                const name_str = try dexfile.getString(method_id.name_idx);
                try std.fmt.format(stdout.writer(), "\t{} {s} {}\n", .{
                    data.direct_method.access_flags,
                    name_str,
                    data.direct_method.code_off,
                });
            }

            try std.fmt.format(stdout.writer(), "Virtual Methods:\n", .{});
            var virtual_method_iter = dexfile.classDataIterator(class_data, .virtual_method);
            while (virtual_method_iter.next()) |data| {
                const method_id = try dexfile.getMethod(data.virtual_method.method_idx);
                const name_str = try dexfile.getString(method_id.name_idx);
                try std.fmt.format(stdout.writer(), "\t{} {s} {}\n", .{
                    data.virtual_method.access_flags,
                    name_str,
                    data.virtual_method.code_off,
                });
            }
        }
    }
}

fn printInfo(document: binxml.Document, stdout: std.fs.File) !void {
    for (document.chunks.items) |chunk| {
        switch (chunk) {
            .Xml => |xml_tree| try print_xml_tree(xml_tree, stdout),
            .Table => |table| try print_table(table, stdout),
            .StringPool => |string_pool| {
                try std.fmt.format(stdout, "String Pool chunk:\n", .{});
                for (0..string_pool.get_len()) |index| {
                    const i = @as(u32, @intCast(index));
                    if (string_pool.getUtf16Raw(i)) |string| {
                        try std.fmt.format(stdout.writer(), "{}: {}\n", .{ i, std.unicode.fmtUtf16le(string) });
                    } else if (string_pool.getUtf8Raw(i)) |string| {
                        try std.fmt.format(stdout.writer(), "{}: {s}\n", .{ i, string });
                    } else {
                        try std.fmt.format(stdout.writer(), "[Unknown Encoding for string {}] \n", .{i});
                    }
                }
            },
        }
    }
}

fn print_xml_tree(xml_tree: binxml.XMLTree, stdout: std.fs.File) !void {
    var indent: usize = 0;
    for (xml_tree.nodes.items, 0..) |node, node_id| {
        if (node.extended == .Attribute) {
            indent += 1;
        }
        var iloop: usize = 1;
        while (iloop < indent) : (iloop += 1) {
            try std.fmt.format(stdout, "\t", .{});
        }
        switch (node.extended) {
            .CData => |cdata| {
                const data = xml_tree.string_pool.get_formatter(cdata.data).?;

                try std.fmt.format(stdout.writer(), "{}", .{data});
            },
            .Namespace => |namespace| {
                const prefix = xml_tree.string_pool.get_formatter(namespace.prefix).?;
                const uri = xml_tree.string_pool.get_formatter(namespace.uri).?;

                try std.fmt.format(stdout.writer(), "xmlns:{}={}", .{
                    prefix,
                    uri,
                });
            },
            .EndElement => |end| {
                if (xml_tree.string_pool.get_formatter(end.name)) |name| {
                    try std.fmt.format(stdout.writer(), "</{}>", .{name});
                }
            },
            .Attribute => |attribute| {
                try std.fmt.format(stdout.writer(), "<", .{});
                {
                    if (xml_tree.string_pool.get_formatter(attribute.namespace)) |ns| {
                        try std.fmt.format(stdout.writer(), "{}:", .{ns});
                    }
                    if (xml_tree.string_pool.get_formatter(attribute.name)) |name| {
                        try std.fmt.format(stdout.writer(), "{}", .{name});
                    }
                }
                for (xml_tree.attributes.items) |*attr| {
                    if (attr.*.node != node_id) continue;
                    try std.fmt.format(stdout, "\n", .{});
                    var iloop2: usize = 1;
                    while (iloop2 < indent + 1) : (iloop2 += 1) {
                        try std.fmt.format(stdout, "\t", .{});
                    }
                    if (xml_tree.string_pool.get_formatter(attr.*.namespace)) |ns| {
                        try std.fmt.format(stdout.writer(), "{}/", .{ns});
                    }
                    if (xml_tree.string_pool.get_formatter(attr.*.name)) |name| {
                        try std.fmt.format(stdout.writer(), "{}", .{name});
                    }
                    try std.fmt.format(stdout.writer(), "={s}", .{attr.*.typed_value});
                }
                try std.fmt.format(stdout.writer(), ">", .{});
            },
        }
        try std.fmt.format(stdout.writer(), "\n", .{});
        if (node.extended == .EndElement) {
            indent -= 1;
        }
    }
}

fn print_table(table: binxml.ResourceTable, stdout: std.fs.File) !void {
    for (table.packages.items) |package| {
        try std.fmt.format(stdout.writer(), "Package {} (ID {})\n", .{ std.unicode.fmtUtf16le(package.name), package.id });
        try std.fmt.format(stdout.writer(), "\tType Strings {}\n\tLast Public Type {}\n\tKey Strings {}\n\tLast Public Key {}\n\tType ID Offset {}\n", .{
            package.type_strings,
            package.last_public_type,
            package.key_strings,
            package.last_public_key,
            package.type_id_offset,
        });
        for (package.type_spec.items) |type_spec| {
            try std.fmt.format(stdout.writer(), "\tType Spec {}\n", .{type_spec.id});
            for (type_spec.entry_indices) |*entry| {
                try std.fmt.format(stdout.writer(), "\t\t{}\n", .{entry.*});
            }
        }
        for (package.table_type.items) |table_type| {
            try std.fmt.format(stdout.writer(), "\tTable Type {}, {}\n", .{ table_type.id, table_type.flags });
            // try std.fmt.format(stdout.writer(), "\t\tConfig: {}\n", .{table_type.config});
            for (table_type.entries.items) |*entry| {
                if (entry.*.value) |*value| {
                    value.*.string_pool = &package.key_string_pool;
                }
                if (package.key_string_pool.getUtf16(entry.key)) |entry_string| {
                    try std.fmt.format(stdout.writer(), "\t\t{}: {?}\n", .{ std.unicode.fmtUtf16le(entry_string), entry.value });
                }
            }
        }
    }
}
