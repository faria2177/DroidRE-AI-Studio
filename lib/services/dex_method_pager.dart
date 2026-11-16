import 'dart:isolate';
import 'dart:typed_data';

import 'dex_inspector.dart';
import 'dex_symbol_index.dart';
import 'package_binary_reader.dart';

/// Reads a bounded page of methods for a class that the initial DEX preview
/// truncated. Does not create a full-DEX method list or execute the archive.
class DexMethodPager {
  const DexMethodPager._();

  static const pageSize = 100;

  static Future<List<DexMethodSummary>> loadEntry(
    String apkPath,
    String entryName,
    DexClassSummary klass, {
    int start = 0,
  }) => Isolate.run(() => loadBytes(
    PackageBinaryReader.read(
      apkPath: apkPath,
      entryName: entryName,
      maxBytes: DexInspector.maxBytes,
    ),
    klass,
    start: start,
  ));

  static List<DexMethodSummary> loadBytes(
    Uint8List bytes,
    DexClassSummary klass, {
    int start = 0,
    int limit = pageSize,
  }) {
    if (start < 0 || limit < 1 || limit > 200) {
      throw const FormatException('Invalid DEX method page window');
    }
    final symbols = DexSymbolIndex(bytes);
    final classCount = symbols.u32(96);
    final classOffset = symbols.u32(100);
    if (classCount > 100000 || klass.classDefIndex < 0 ||
        klass.classDefIndex >= classCount) {
      throw const FormatException('Invalid DEX class definition index');
    }
    symbols.check(classOffset, classCount * 32);
    final definition = classOffset + klass.classDefIndex * 32;
    final rawName = symbols.typeAt(symbols.u32(definition));
    final className = rawName.startsWith('L') && rawName.endsWith(';')
        ? rawName.substring(1, rawName.length - 1).replaceAll('/', '.')
        : rawName;
    if (className != klass.name) {
      throw const FormatException('DEX class definition does not match');
    }

    final classDataOffset = symbols.u32(definition + 24);
    if (classDataOffset == 0) {
      if (klass.methodCount != 0) {
        throw const FormatException('DEX class method metadata has changed');
      }
      return <DexMethodSummary>[];
    }
    symbols.check(classDataOffset, 1);
    var cursor = classDataOffset;

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
    final total = directMethods + virtualMethods;
    if (staticFields + instanceFields > 500000 ||
        total > symbols.methodCount ||
        total != klass.methodCount) {
      throw const FormatException('DEX class method count is invalid');
    }
    if (start > total) {
      throw const FormatException('Method page starts after class end');
    }
    for (var i = 0; i < staticFields + instanceFields; i++) {
      leb();
      leb();
    }

    final methods = <DexMethodSummary>[];
    var ordinal = 0;
    for (final count in <int>[directMethods, virtualMethods]) {
      var methodIndex = 0;
      for (var i = 0; i < count; i++) {
        methodIndex += leb();
        final flags = leb();
        final codeOffset = leb();
        if (methodIndex >= symbols.methodCount) {
          throw const FormatException('Invalid DEX method ID');
        }
        if (ordinal >= start && methods.length < limit) {
          final itemOffset = symbols.methodsOffset + methodIndex * 8;
          final name = symbols.stringAt(symbols.u32(itemOffset + 4));
          final prototype = symbols.protoAt(symbols.u16(itemOffset + 2));
          var registers = 0;
          var unitCount = 0;
          final preview = <int>[];
          if (codeOffset != 0) {
            symbols.check(codeOffset, 16);
            registers = symbols.u16(codeOffset);
            unitCount = symbols.u32(codeOffset + 12);
            symbols.check(codeOffset + 16, unitCount * 2);
            for (var j = 0; j < unitCount && j < 64; j++) {
              preview.add(symbols.u16(codeOffset + 16 + j * 2));
            }
          }
          methods.add(DexMethodSummary(
            name: name,
            prototype: prototype,
            accessFlags: flags,
            codeOffset: codeOffset,
            registerCount: registers,
            instructionCount: unitCount,
            codeUnits: preview,
            methodIdIndex: methodIndex,
            ownerName: className,
          ));
        }
        ordinal++;
      }
    }
    return methods;
  }
}
