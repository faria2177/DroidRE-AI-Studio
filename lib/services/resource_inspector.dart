import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'android_binary_xml_decoder.dart';
import 'package_binary_reader.dart';

@immutable
class ResourceTableSummary {
  const ResourceTableSummary({
    required this.packageCount,
    required this.packages,
    required this.stringPoolChunks,
  });

  final int packageCount;
  final List<String> packages;
  final int stringPoolChunks;
}

@immutable
class ResourcePreview {
  const ResourcePreview({
    required this.name,
    required this.bytes,
    required this.hexHeader,
    this.textContent,
    this.decodedXml,
    this.xmlElementCount = 0,
    this.xmlAttributeCount = 0,
    this.xmlDecodeError,
  });

  final String name;
  final Uint8List bytes;
  final String hexHeader;
  final String? textContent;
  final String? decodedXml;
  final int xmlElementCount;
  final int xmlAttributeCount;
  final String? xmlDecodeError;

  bool get isImage => RegExp(r'\.(png|jpg|jpeg|webp|gif)$',
      caseSensitive: false).hasMatch(name);
}

/// Bounded, read-only inspection of compiled resource tables and ZIP assets.
class ResourceInspector {
  const ResourceInspector._();

  static const maxTableBytes = 40 * 1024 * 1024;
  static const maxPreviewBytes = 2 * 1024 * 1024;

  static Future<ResourceTableSummary> inspectTable(String path) => Isolate.run(
    () => inspectTableBytes(PackageBinaryReader.read(
      apkPath: path,
      entryName: 'resources.arsc',
      maxBytes: maxTableBytes,
    )),
  );

  static Future<ResourcePreview> preview(String apkPath, String name) =>
      Isolate.run(() => previewBytes(name, PackageBinaryReader.read(
        apkPath: apkPath,
        entryName: name,
        maxBytes: maxPreviewBytes,
      )));

  static ResourcePreview previewBytes(String name, Uint8List bytes) {
    final sample = bytes.take(64).map((value) =>
      value.toRadixString(16).padLeft(2, '0')).join(' ');
    final isTextFile = RegExp(r'\.(txt|json|xml|svg|css|html|properties|md)$',
      caseSensitive: false).hasMatch(name);
    // Binary XML starts with 0x00080003, not UTF-8 markup.
    final looksBinary = bytes.take(64).any((value) => value == 0);
    DecodedAndroidXml? decoded;
    String? decodeError;
    if (name.toLowerCase().endsWith('.xml') &&
        bytes.length >= 8 && bytes[0] == 3 && bytes[1] == 0) {
      try {
        decoded = AndroidBinaryXmlDecoder.decode(bytes);
      } on FormatException catch (error) {
        decodeError = error.message;
      }
    }
    return ResourcePreview(
      name: name,
      bytes: bytes,
      hexHeader: sample,
      textContent: isTextFile && !looksBinary
          ? utf8.decode(bytes.take(4096).toList(), allowMalformed: true)
          : null,
      decodedXml: decoded?.xml,
      xmlElementCount: decoded?.elements ?? 0,
      xmlAttributeCount: decoded?.attributes ?? 0,
      xmlDecodeError: decodeError,
    );
  }

  static ResourceTableSummary inspectTableBytes(Uint8List bytes) {
    if (bytes.length < 12 || bytes.length > maxTableBytes) {
      throw const FormatException('Resource table is incomplete or too large');
    }
    final data = ByteData.sublistView(bytes);
    void check(int offset, int size) {
      if (offset < 0 || size < 0 || offset > bytes.length ||
          size > bytes.length - offset) {
        throw const FormatException('Invalid resource table chunk bounds');
      }
    }

    int u16(int offset) {
      check(offset, 2);
      return data.getUint16(offset, Endian.little);
    }

    int u32(int offset) {
      check(offset, 4);
      return data.getUint32(offset, Endian.little);
    }

    if (u16(0) != 0x0002 || u16(2) < 12 || u32(4) != bytes.length) {
      throw const FormatException('Not a supported Android resources.arsc table');
    }
    final packageCount = u32(8);
    if (packageCount > 1000) {
      throw const FormatException('Resource table package count is invalid');
    }
    final packages = <String>[];
    var stringPools = 0;
    var cursor = u16(2);
    while (cursor < bytes.length) {
      check(cursor, 8);
      final type = u16(cursor);
      final headerSize = u16(cursor + 2);
      final chunkSize = u32(cursor + 4);
      if (chunkSize < headerSize || headerSize < 8 || chunkSize == 0) {
        throw const FormatException('Invalid resource table chunk size');
      }
      check(cursor, chunkSize);
      if (type == 0x0001) stringPools++;
      if (type == 0x0200) {
        if (headerSize < 12 + 256) {
          throw const FormatException('Truncated resource package header');
        }
        final id = u32(cursor + 8);
        final nameUnits = <int>[];
        for (var i = 0; i < 128; i++) {
          final value = u16(cursor + 12 + i * 2);
          if (value == 0) break;
          nameUnits.add(value);
        }
        final name = String.fromCharCodes(nameUnits);
        packages.add('$name (id 0x${id.toRadixString(16)})');
      }
      cursor += chunkSize;
    }
    if (cursor != bytes.length || packages.length != packageCount) {
      throw const FormatException('Resource table package list is inconsistent');
    }
    return ResourceTableSummary(
      packageCount: packageCount,
      packages: packages,
      stringPoolChunks: stringPools,
    );
  }
}
