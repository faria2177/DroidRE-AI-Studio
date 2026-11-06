import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package_binary_reader.dart';

@immutable
class DexClassSummary {
  const DexClassSummary({
    required this.name,
    required this.accessFlags,
    required this.methodCount,
    required this.methods,
    this.details = const [],
  });

  final String name;
  final int accessFlags;
  final int methodCount;
  final List<String> methods;
  final List<DexMethodSummary> details;
}

@immutable
class DexMethodSummary {
  const DexMethodSummary({
    required this.name,
    required this.prototype,
    required this.accessFlags,
    required this.codeOffset,
    required this.registerCount,
    required this.instructionCount,
    required this.codeUnits,
  });

  final String name;
  final String prototype;
  final int accessFlags;
  final int codeOffset;
  final int registerCount;
  final int instructionCount;
  final List<int> codeUnits;

  String get smaliPreview {
    final modifiers = <String>[
      if ((accessFlags & 1) != 0) 'public',
      if ((accessFlags & 2) != 0) 'private',
      if ((accessFlags & 4) != 0) 'protected',
      if ((accessFlags & 8) != 0) 'static',
      if ((accessFlags & 16) != 0) 'final',
      if ((accessFlags & 256) != 0) 'native',
      if ((accessFlags & 1024) != 0) 'abstract',
    ];
    final result = StringBuffer('.method ${modifiers.join(' ')} $name$prototype\n');
    if (codeOffset == 0) {
      result.writeln('    # No code_item (abstract/native/external)');
    } else {
      result.writeln('    .registers $registerCount');
      for (var i = 0; i < codeUnits.length; i++) {
        final word = codeUnits[i];
        final opcode = word & 0xff;
        final mnemonic = _opcodeLabel(opcode);
        result.writeln('    # ${i.toRadixString(16).padLeft(4, '0')}: '
            '0x${word.toRadixString(16).padLeft(4, '0')}'
            '${mnemonic == null ? '' : '  $mnemonic'}');
      }
      if (codeUnits.length < instructionCount) {
        result.writeln('    # Preview truncated to ${codeUnits.length} code units');
      }
    }
    result.write('.end method');
    return result.toString();
  }
}

// Byte-level hints only: these are NOT decoded instructions or Smali operands.
String? _opcodeLabel(int opcode) => switch (opcode) {
  0x01 => 'move',
  0x02 => 'move/from16',
  0x03 => 'move/16',
  0x0a => 'move-result',
  0x0c => 'move-result-object',
  0x0e => 'return-void',
  0x0f => 'return',
  0x10 => 'return-wide',
  0x11 => 'return-object',
  0x12 => 'const/4',
  0x13 => 'const/16',
  0x14 => 'const',
  0x1a => 'const-string',
  0x1b => 'const-string/jumbo',
  0x22 => 'new-instance',
  0x28 => 'goto',
  0x32 => 'if-eq',
  0x6e => 'invoke-virtual',
  0x70 => 'invoke-direct',
  0x71 => 'invoke-static',
  0x72 => 'invoke-interface',
  _ => null,
};

@immutable
class DexFileSummary {
  const DexFileSummary({
    required this.version,
    required this.stringCount,
    required this.methodIdCount,
    required this.classes,
  });

  final String version;
  final int stringCount;
  final int methodIdCount;
  final List<DexClassSummary> classes;
}

/// Read-only DEX index reader with bounded raw code-unit previews.
class DexInspector {
  const DexInspector._();

  static const maxBytes = 32 * 1024 * 1024;

  static Future<DexFileSummary> inspectEntry(String apkPath, String entryName) =>
      Isolate.run(() => inspectBytes(PackageBinaryReader.read(
            apkPath: apkPath,
            entryName: entryName,
            maxBytes: maxBytes,
          )));

  static DexFileSummary inspectBytes(Uint8List input) {
    if (input.length < 112 || input.length > maxBytes) {
      throw const FormatException('DEX header is missing or too large');
    }
    final data = ByteData.sublistView(input);
    void check(int offset, int size) {
      if (offset < 0 || size < 0 || offset > input.length ||
          size > input.length - offset) {
        throw const FormatException('DEX offset is outside the file');
      }
    }

    int u32(int offset) {
      check(offset, 4);
      return data.getUint32(offset, Endian.little);
    }

    if (ascii.decode(input.sublist(0, 4)) != 'dex\n' ||
        input[7] != 0 ||
        input[4] < 48 || input[4] > 57 ||
        input[5] < 48 || input[5] > 57 ||
        input[6] < 48 || input[6] > 57) {
      throw const FormatException('Not a standard DEX file');
    }
    final version = ascii.decode(input.sublist(4, 7));
    if (!['035', '036', '037', '038', '039', '040'].contains(version)) {
      throw FormatException('DEX version $version is not supported yet');
    }
    if (u32(32) != input.length || u32(36) < 112 ||
        u32(40) != 0x12345678) {
      throw const FormatException('DEX header length or byte order is invalid');
    }

    (int, int) table(int sizeOffset, int offsetOffset, int stride, int limit) {
      final count = u32(sizeOffset);
      final offset = u32(offsetOffset);
      if (count > limit || (count == 0 && offset != 0) ||
          (count != 0 && offset == 0)) {
        throw const FormatException('Invalid DEX table dimensions');
      }
      check(offset, count * stride);
      return (count, offset);
    }

    final (stringCount, stringsOff) = table(56, 60, 4, 500000);
    final (typesCount, typesOff) = table(64, 68, 4, 500000);
    final (protoCount, protoOff) = table(72, 76, 12, 500000);
    final (methodCount, methodsOff) = table(88, 92, 8, 500000);
    final (classCount, classesOff) = table(96, 100, 32, 100000);

    int lebAt(int offset, List<int> next) {
      var value = 0;
      var shift = 0;
      for (var n = 0; n < 5; n++) {
        check(offset, 1);
        final byte = input[offset++];
        if (n == 4 && byte > 15) {
          throw const FormatException('Invalid DEX ULEB128 value');
        }
        value |= (byte & 127) << shift;
        if ((byte & 128) == 0) {
          next[0] = offset;
          return value;
        }
        shift += 7;
      }
      throw const FormatException('Invalid DEX ULEB128 length');
    }

    final cache = <int, String>{};
    String stringAt(int idx) {
      if (idx < 0 || idx >= stringCount) {
        throw const FormatException('DEX string index is invalid');
      }
      return cache.putIfAbsent(idx, () {
        var offset = u32(stringsOff + idx * 4);
        final next = <int>[offset];
        lebAt(offset, next); // UTF-16 character count
        offset = next[0];
        final start = offset;
        while (offset < input.length && input[offset] != 0 &&
            offset - start <= 8192) {
          offset++;
        }
        if (offset == input.length || offset - start > 8192) {
          throw const FormatException('Unterminated/oversized DEX string');
        }
        // Names are generally ASCII; tolerate malformed modified UTF-8.
        return utf8.decode(input.sublist(start, offset), allowMalformed: true);
      });
    }

    String className(int typeIdx) {
      if (typeIdx < 0 || typeIdx >= typesCount) {
        throw const FormatException('DEX type index is invalid');
      }
      final descriptor = stringAt(u32(typesOff + 4 * typeIdx));
      if (descriptor.startsWith('L') && descriptor.endsWith(';')) {
        return descriptor.substring(1, descriptor.length - 1).replaceAll('/', '.');
      }
      return descriptor;
    }

    String methodName(int methodIdx) {
      if (methodIdx < 0 || methodIdx >= methodCount) {
        throw const FormatException('DEX method index is invalid');
      }
      final offset = methodsOff + methodIdx * 8;
      return stringAt(u32(offset + 4));
    }

    String prototype(int methodIdx) {
      final methodOffset = methodsOff + methodIdx * 8;
      final idx = data.getUint16(methodOffset + 2, Endian.little);
      if (idx >= protoCount) {
        throw const FormatException('DEX prototype index is invalid');
      }
      final off = protoOff + idx * 12;
      final resultType = u32(off + 4);
      final paramsOff = u32(off + 8);
      final params = <String>[];
      if (paramsOff != 0) {
        final count = u32(paramsOff);
        if (count > 255) {
          throw const FormatException('DEX parameter list is too large');
        }
        check(paramsOff + 4, count * 2);
        for (var i = 0; i < count; i++) {
          final type = data.getUint16(paramsOff + 4 + i * 2, Endian.little);
          if (type >= typesCount) {
            throw const FormatException('DEX parameter type is invalid');
          }
          params.add(stringAt(u32(typesOff + type * 4)));
        }
      }
      if (resultType >= typesCount) {
        throw const FormatException('DEX return type is invalid');
      }
      return '(${params.join()})${stringAt(u32(typesOff + resultType * 4))}';
    }

    DexMethodSummary detail(int index, int flags, int codeOffset) {
      var registers = 0;
      var count = 0;
      final codeUnits = <int>[];
      if (codeOffset != 0) {
        check(codeOffset, 16);
        registers = data.getUint16(codeOffset, Endian.little);
        count = u32(codeOffset + 12);
        check(codeOffset + 16, count * 2);
        for (var i = 0; i < count && i < 64; i++) {
          codeUnits.add(data.getUint16(codeOffset + 16 + i * 2, Endian.little));
        }
      }
      return DexMethodSummary(
        name: methodName(index),
        prototype: prototype(index),
        accessFlags: flags,
        codeOffset: codeOffset,
        registerCount: registers,
        instructionCount: count,
        codeUnits: codeUnits,
      );
    }

    final classes = <DexClassSummary>[];
    var detailsRemaining = 20000;
    for (var i = 0; i < classCount; i++) {
      final offset = classesOff + i * 32;
      final name = className(u32(offset));
      final flags = u32(offset + 4);
      final classDataOff = u32(offset + 24);
      final methods = <String>[];
      final details = <DexMethodSummary>[];
      var declaredMethodCount = 0;
      if (classDataOff != 0) {
        check(classDataOff, 1);
        final cursor = <int>[classDataOff];
        int leb() => lebAt(cursor[0], cursor);

        final staticFields = leb();
        final instanceFields = leb();
        final directMethods = leb();
        final virtualMethods = leb();
        if (staticFields + instanceFields > 500000 ||
            directMethods + virtualMethods > methodCount) {
          throw const FormatException('DEX class data size is invalid');
        }
        for (var j = 0; j < staticFields + instanceFields; j++) {
          leb(); // field_idx_diff
          leb(); // access_flags
        }
        declaredMethodCount = directMethods + virtualMethods;
        for (final count in [directMethods, virtualMethods]) {
          var index = 0;
          for (var j = 0; j < count; j++) {
            index += leb();
            final accessFlags = leb();
            final codeOff = leb();
            if (methods.length < 200) {
              methods.add(methodName(index));
              if (detailsRemaining > 0) {
                details.add(detail(index, accessFlags, codeOff));
                detailsRemaining--;
              }
            }
            if (index >= methodCount) {
              throw const FormatException('DEX method index overflow');
            }
          }
        }
      }
      classes.add(DexClassSummary(
        name: name,
        accessFlags: flags,
        methodCount: declaredMethodCount,
        methods: methods,
        details: details,
      ));
    }
    return DexFileSummary(
      version: version,
      stringCount: stringCount,
      methodIdCount: methodCount,
      classes: classes,
    );
  }
}
