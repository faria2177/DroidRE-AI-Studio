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
  });

  final String name;
  final int accessFlags;
  final int methodCount;
  final List<String> methods;
}

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

/// Read-only DEX directory parser (class and method names, not bytecode).
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

    final classes = <DexClassSummary>[];
    for (var i = 0; i < classCount; i++) {
      final offset = classesOff + i * 32;
      final name = className(u32(offset));
      final flags = u32(offset + 4);
      final classDataOff = u32(offset + 24);
      final methods = <String>[];
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
            leb(); // access_flags
            leb(); // code_off
            if (methods.length < 200) methods.add(methodName(index));
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
