import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'dex_inspector.dart';
import 'dex_symbol_index.dart';
import 'package_binary_reader.dart';

@immutable
class DexMethodSearchResult {
  const DexMethodSearchResult({
    required this.methods,
    required this.scannedMethods,
    required this.scannedClasses,
    required this.truncated,
  });

  final List<DexMethodSummary> methods;
  final int scannedMethods;
  final int scannedClasses;
  final bool truncated;
}

/// Searches declared DEX methods, including those outside the initial class
/// preview. Reference-only method IDs are not treated as declarations.
class DexMethodSearch {
  const DexMethodSearch._();

  static const maxResults = 200;
  static const maxScannedMethods = 250000;

  static Future<DexMethodSearchResult> searchEntry(
    String apkPath,
    String entryName,
    String query,
  ) => Isolate.run(() => searchBytes(
    PackageBinaryReader.read(
      apkPath: apkPath,
      entryName: entryName,
      maxBytes: DexInspector.maxBytes,
    ),
    query,
  ));

  static DexMethodSearchResult searchBytes(
    Uint8List bytes,
    String query, {
    int resultLimit = maxResults,
    int scanLimit = maxScannedMethods,
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.length < 2 || needle.length > 128) {
      throw const FormatException('Method query must be 2–128 characters');
    }
    if (resultLimit < 1 || resultLimit > maxResults ||
        scanLimit < 1 || scanLimit > maxScannedMethods) {
      throw const FormatException('Method search limits are invalid');
    }

    final symbols = DexSymbolIndex(bytes);
    final classCount = symbols.u32(96);
    final classOffset = symbols.u32(100);
    if (classCount > 100000) {
      throw const FormatException('DEX has too many classes');
    }
    symbols.check(classOffset, classCount * 32);
    final matches = <DexMethodSummary>[];
    var scannedMethods = 0;
    var scannedClasses = 0;
    var truncated = false;

    for (var classIndex = 0; classIndex < classCount; classIndex++) {
      final definition = classOffset + classIndex * 32;
      final classType = symbols.u32(definition);
      final descriptor = symbols.typeAt(classType);
      final owner = descriptor.startsWith('L') && descriptor.endsWith(';')
          ? descriptor.substring(1, descriptor.length - 1).replaceAll('/', '.')
          : descriptor;
      scannedClasses++;
      final dataOffset = symbols.u32(definition + 24);
      if (dataOffset == 0) continue;
      symbols.check(dataOffset, 1);
      var cursor = dataOffset;

      int leb() {
        var value = 0;
        for (var i = 0; i < 5; i++) {
          symbols.check(cursor, 1);
          final byte = bytes[cursor++];
          if (i == 4 && (byte & 0xf0) != 0) {
            throw const FormatException('Invalid DEX ULEB128 value');
          }
          value |= (byte & 0x7f) << (7 * i);
          if ((byte & 0x80) == 0) return value;
        }
        throw const FormatException('Invalid DEX ULEB128 length');
      }

      final staticFields = leb();
      final instanceFields = leb();
      final directMethods = leb();
      final virtualMethods = leb();
      if (staticFields + instanceFields > 500000 ||
          directMethods + virtualMethods > symbols.methodCount) {
        throw const FormatException('DEX class data count is invalid');
      }
      for (var i = 0; i < staticFields + instanceFields; i++) {
        leb();
        leb();
      }

      for (final count in <int>[directMethods, virtualMethods]) {
        var methodIndex = 0;
        for (var i = 0; i < count; i++) {
          if (scannedMethods >= scanLimit || matches.length >= resultLimit) {
            truncated = true;
            break;
          }
          methodIndex += leb();
          final flags = leb();
          final codeOffset = leb();
          if (methodIndex >= symbols.methodCount) {
            throw const FormatException('DEX method index is invalid');
          }
          scannedMethods++;
          final idOffset = symbols.methodsOffset + methodIndex * 8;
          final name = symbols.stringAt(symbols.u32(idOffset + 4));
          if (!name.toLowerCase().contains(needle)) continue;

          if (symbols.u16(idOffset) != classType) {
            throw const FormatException('DEX method declaring class is invalid');
          }
          final prototype = symbols.protoAt(symbols.u16(idOffset + 2));
          var registers = 0;
          var instructionCount = 0;
          final codeUnits = <int>[];
          if (codeOffset != 0) {
            symbols.check(codeOffset, 16);
            registers = symbols.u16(codeOffset);
            instructionCount = symbols.u32(codeOffset + 12);
            symbols.check(codeOffset + 16, instructionCount * 2);
            for (var j = 0; j < instructionCount && j < 64; j++) {
              codeUnits.add(symbols.u16(codeOffset + 16 + j * 2));
            }
          }
          matches.add(DexMethodSummary(
            name: name,
            prototype: prototype,
            accessFlags: flags,
            codeOffset: codeOffset,
            registerCount: registers,
            instructionCount: instructionCount,
            codeUnits: codeUnits,
            methodIdIndex: methodIndex,
            ownerName: owner,
          ));
        }
        if (truncated) break;
      }
      if (truncated) break;
    }

    return DexMethodSearchResult(
      methods: matches,
      scannedMethods: scannedMethods,
      scannedClasses: scannedClasses,
      truncated: truncated,
    );
  }
}
