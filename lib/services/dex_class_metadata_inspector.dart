import 'package:flutter/foundation.dart';

import 'dex_inspector.dart';
import 'dex_symbol_index.dart';

@immutable
class DexRecoveredField {
  const DexRecoveredField({
    required this.index,
    required this.name,
    required this.typeDescriptor,
    required this.accessFlags,
    required this.isStatic,
  });

  final int index;
  final String name;
  final String typeDescriptor;
  final int accessFlags;
  final bool isStatic;

  String get smaliDeclaration =>
      '.field ${DexClassMetadataInspector.fieldModifiers(accessFlags)}'
      '$name:$typeDescriptor';
}

@immutable
class DexClassMetadata {
  const DexClassMetadata({
    required this.descriptor,
    required this.accessFlags,
    required this.superDescriptor,
    required this.interfaces,
    required this.sourceFile,
    required this.fields,
    required this.declaredFieldCount,
    required this.truncated,
    required this.warnings,
  });

  final String descriptor;
  final int accessFlags;
  final String? superDescriptor;
  final List<String> interfaces;
  final String? sourceFile;
  final List<DexRecoveredField> fields;
  final int declaredFieldCount;
  final bool truncated;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
        'descriptor': descriptor,
        'accessFlags': accessFlags,
        'superDescriptor': superDescriptor,
        'interfaces': interfaces,
        'sourceFile': sourceFile,
        'declaredFieldCount': declaredFieldCount,
        'decodedFieldCount': fields.length,
        'truncated': truncated,
        'warnings': warnings,
        'fields': [
          for (final field in fields)
            {
              'index': field.index,
              'name': field.name,
              'type': field.typeDescriptor,
              'accessFlags': field.accessFlags,
              'static': field.isStatic,
            }
        ],
      };
}

/// Bounds-checked inspection of one DEX class_def and its encoded fields.
/// No class is loaded or executed, and no original Java is claimed.
class DexClassMetadataInspector {
  const DexClassMetadataInspector._();

  static const maxFields = 512;
  static const maxInterfaces = 128;

  static String classModifiers(int flags) {
    final parts = <String>[
      if ((flags & 0x1) != 0) 'public',
      if ((flags & 0x10) != 0) 'final',
      if ((flags & 0x200) != 0) 'interface',
      if ((flags & 0x400) != 0) 'abstract',
      if ((flags & 0x1000) != 0) 'synthetic',
      if ((flags & 0x2000) != 0) 'annotation',
      if ((flags & 0x4000) != 0) 'enum',
    ];
    return parts.isEmpty ? '' : '${parts.join(' ')} ';
  }

  static String fieldModifiers(int flags) {
    final parts = <String>[
      if ((flags & 0x1) != 0) 'public',
      if ((flags & 0x2) != 0) 'private',
      if ((flags & 0x4) != 0) 'protected',
      if ((flags & 0x8) != 0) 'static',
      if ((flags & 0x10) != 0) 'final',
      if ((flags & 0x40) != 0) 'volatile',
      if ((flags & 0x80) != 0) 'transient',
      if ((flags & 0x1000) != 0) 'synthetic',
      if ((flags & 0x4000) != 0) 'enum',
    ];
    return parts.isEmpty ? '' : '${parts.join(' ')} ';
  }

  static DexClassMetadata inspectBytes(
    Uint8List bytes,
    DexClassSummary klass, {
    int fieldLimit = maxFields,
  }) {
    if (fieldLimit < 1 || fieldLimit > maxFields) {
      throw const FormatException('Invalid field preview limit');
    }
    final symbols = DexSymbolIndex(bytes);
    final classCount = symbols.u32(96);
    final classDefsOff = symbols.u32(100);
    if (classCount > 100000 ||
        klass.classDefIndex < 0 || klass.classDefIndex >= classCount) {
      throw const FormatException('Invalid DEX class index');
    }
    symbols.check(classDefsOff, classCount * 32);
    final def = classDefsOff + klass.classDefIndex * 32;
    final descriptor = symbols.typeAt(symbols.u32(def));
    final expected = descriptor.startsWith('L') && descriptor.endsWith(';')
        ? descriptor.substring(1, descriptor.length - 1)
            .replaceAll('/', '.')
        : descriptor;
    if (expected != klass.name) {
      throw const FormatException('DEX class identity mismatch');
    }
    final accessFlags = symbols.u32(def + 4);
    final superIndex = symbols.u32(def + 8);
    final superDescriptor = superIndex == 0xffffffff
        ? null : symbols.typeAt(superIndex);
    final interfacesAt = symbols.u32(def + 12);
    final sourceIndex = symbols.u32(def + 16);
    final source = sourceIndex == 0xffffffff
        ? null : symbols.stringAt(sourceIndex);
    final warnings = <String>[];
    var truncated = false;
    final interfaces = <String>[];
    if (interfacesAt != 0) {
      final count = symbols.u32(interfacesAt);
      if (count > 100000) {
        throw const FormatException('Unbounded DEX interface count');
      }
      symbols.check(interfacesAt + 4, count * 2);
      for (var i = 0; i < count && i < maxInterfaces; i++) {
        interfaces.add(symbols.typeAt(
          symbols.u16(interfacesAt + 4 + 2 * i),
        ));
      }
      if (count > maxInterfaces) {
        truncated = true;
        warnings.add('Interface preview limited to $maxInterfaces of $count');
      }
    }

    final fields = <DexRecoveredField>[];
    var declaredFields = 0;
    final classDataAt = symbols.u32(def + 24);
    if (classDataAt != 0) {
      var cursor = classDataAt;
      int uleb() {
        var value = 0;
        for (var i = 0; i < 5; i++) {
          symbols.check(cursor, 1);
          final next = bytes[cursor++];
          if (i == 4 && (next & 0xf0) != 0) {
            throw const FormatException('Invalid class field ULEB128');
          }
          value |= (next & 0x7f) << (i * 7);
          if ((next & 0x80) == 0) {
            return value;
          }
        }
        throw const FormatException('DEX ULEB128 field too long');
      }

      final staticCount = uleb();
      final instanceCount = uleb();
      uleb(); // direct_methods_size (parsed by DexMethodPager)
      uleb(); // virtual_methods_size
      declaredFields = staticCount + instanceCount;
      if (declaredFields > symbols.fieldCount ||
          declaredFields > 100000) {
        throw const FormatException('Invalid class field declaration count');
      }
      for (final group in <(int, bool)>[
        (staticCount, true),
        (instanceCount, false),
      ]) {
        var fieldIndex = 0;
        for (var i = 0; i < group.$1; i++) {
          fieldIndex += uleb();
          final flags = uleb();
          if (fieldIndex >= symbols.fieldCount) {
            throw const FormatException('DEX field index overflow');
          }
          if (fields.length < fieldLimit) {
            final at = symbols.fieldsOffset + fieldIndex * 8;
            final owner = symbols.typeAt(symbols.u16(at));
            if (owner != descriptor) {
              throw const FormatException(
                  'DEX field is assigned to another class');
            }
            final type = symbols.typeAt(symbols.u16(at + 2));
            final name = symbols.stringAt(symbols.u32(at + 4));
            fields.add(DexRecoveredField(
              index: fieldIndex,
              name: name,
              typeDescriptor: type,
              accessFlags: flags,
              isStatic: group.$2,
            ));
          }
        }
      }
      if (declaredFields > fieldLimit) {
        truncated = true;
        warnings.add('Field preview limited to $fieldLimit of '
            '$declaredFields declarations');
      }
    }
    return DexClassMetadata(
      descriptor: descriptor,
      accessFlags: accessFlags,
      superDescriptor: superDescriptor,
      interfaces: List.unmodifiable(interfaces),
      sourceFile: source,
      fields: List.unmodifiable(fields),
      declaredFieldCount: declaredFields,
      truncated: truncated,
      warnings: List.unmodifiable(warnings),
    );
  }

  static String structurePreview(DexClassMetadata metadata) {
    final out = StringBuffer()
      ..writeln('# DEX structure preview: NOT assemblable Smali.')
      ..writeln('.class ${classModifiers(metadata.accessFlags)}'
          '${metadata.descriptor}');
    if (metadata.superDescriptor != null) {
      out.writeln('.super ${metadata.superDescriptor}');
    }
    for (final item in metadata.interfaces) {
      out.writeln('.implements $item');
    }
    if (metadata.sourceFile != null) {
      out.writeln('# Source file hint: ${metadata.sourceFile}');
    }
    out.writeln();
    for (final field in metadata.fields) {
      out.writeln(field.smaliDeclaration);
    }
    if (metadata.truncated) {
      out.writeln('# PARTIAL: class/interface metadata truncated.');
    }
    return out.toString();
  }
}
