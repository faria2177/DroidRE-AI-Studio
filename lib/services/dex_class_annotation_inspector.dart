import 'package:flutter/foundation.dart';

import 'dex_annotation_value_reader.dart';
import 'dex_inspector.dart';
import 'dex_symbol_index.dart';

@immutable
class DexAnnotationPreview {
  const DexAnnotationPreview(this.type, this.visibility, this.elementCount,
      {this.elements = const [], this.valuesDecoded = false});
  final String type;
  final String visibility;
  final int elementCount;
  final List<Map<String, Object?>> elements;
  final bool valuesDecoded;
  Map<String, Object?> toJson() => {
    'type': type,
    'visibility': visibility,
    'encodedElementCount': elementCount,
    'valuesDecoded': valuesDecoded,
    'elements': elements,
  };
}

@immutable
class DexAnnotationTarget {
  const DexAnnotationTarget(
    this.kind, this.poolIndex, this.parameterIndex, this.annotations);
  final String kind;
  final int? poolIndex;
  final int? parameterIndex;
  final List<DexAnnotationPreview> annotations;
  Map<String, Object?> toJson() => {
    'kind': kind,
    'poolIndex': poolIndex,
    'parameterIndex': parameterIndex,
    'annotations': [for (final a in annotations) a.toJson()],
  };
}

@immutable
class DexClassAnnotationReport {
  const DexClassAnnotationReport(this.targets, this.warnings, this.partial);
  final List<DexAnnotationTarget> targets;
  final List<String> warnings;
  final bool partial;
  Map<String, Object?> toJson() => {
    'targets': [for (final t in targets) t.toJson()],
    'warnings': warnings,
    'partial': partial,
    'note': 'Bounded encoded annotation value preview. Symbolic references '
        'are not evaluated; malformed or oversized values are partial.',
  };
}

/// Read-only annotation_directory and annotation_set inspection.
/// Parses type indices, visibility and bounded encoded element values.
class DexClassAnnotationInspector {
  const DexClassAnnotationInspector._();
  static const maxOwnersPerKind = 64;
  static const maxAnnotationsPerSet = 32;
  static const maxParameterSlots = 32;

  static DexClassAnnotationReport inspectBytes(
    Uint8List dex, DexClassSummary klass,
  ) {
    final symbols = DexSymbolIndex(dex);
    final valueReader = DexAnnotationValueReader(dex, symbols);
    final classCount = symbols.u32(96);
    final classDefsAt = symbols.u32(100);
    if (classCount > 100000 ||
        klass.classDefIndex < 0 || klass.classDefIndex >= classCount) {
      throw const FormatException('Invalid class definition for annotations');
    }
    symbols.check(classDefsAt, classCount * 32);
    final def = classDefsAt + klass.classDefIndex * 32;
    final descriptor = symbols.typeAt(symbols.u32(def));
    final display = descriptor.startsWith('L') && descriptor.endsWith(';')
        ? descriptor.substring(1, descriptor.length - 1)
            .replaceAll('/', '.')
        : descriptor;
    if (display != klass.name) {
      throw const FormatException('Annotation class owner mismatch');
    }
    final directory = symbols.u32(def + 20);
    if (directory == 0) {
      return const DexClassAnnotationReport([], [], false);
    }
    final targets = <DexAnnotationTarget>[];
    final warnings = <String>[];
    var partial = false;
    void warn(String message) {
      partial = true;
      if (warnings.length < 20) {
        warnings.add(message);
      }
    }

    int uleb(int address, List<int> next) {
      var value = 0;
      var at = address;
      for (var i = 0; i < 5; i++) {
        symbols.check(at, 1);
        final byte = dex[at++];
        if (i == 4 && (byte & 0xf0) != 0) {
          throw const FormatException('Invalid annotation ULEB128');
        }
        value |= (byte & 0x7f) << (7 * i);
        if ((byte & 0x80) == 0) {
          next[0] = at;
          return value;
        }
      }
      throw const FormatException('Annotation ULEB128 too long');
    }

    List<DexAnnotationPreview> parseSet(int at) {
      if (at == 0) {
        return const [];
      }
      final count = symbols.u32(at);
      if (count > 1024) {
        throw const FormatException('Invalid annotation set size');
      }
      symbols.check(at + 4, count * 4);
      if (count > maxAnnotationsPerSet) {
        warn('Annotation set limited to $maxAnnotationsPerSet of $count');
      }
      final result = <DexAnnotationPreview>[];
      for (var i = 0; i < count && i < maxAnnotationsPerSet; i++) {
        final off = symbols.u32(at + 4 + i * 4);
        symbols.check(off, 2);
        final visibility = switch (dex[off]) {
          0 => 'build',
          1 => 'runtime',
          2 => 'system',
          _ => 'unknown',
        };
        if (visibility == 'unknown') {
          warn('Unknown annotation visibility byte');
        }
        final pos = <int>[off + 1];
        final type = symbols.typeAt(uleb(pos[0], pos));
        final elements = uleb(pos[0], pos);
        try {
          final decoded = valueReader.decodeElements(pos[0], elements);
          result.add(DexAnnotationPreview(type, visibility, elements,
              elements: decoded.elements, valuesDecoded: decoded.complete));
          if (!decoded.complete) {
            warn('Annotation values limited to '
                '${DexAnnotationValueReader.maxElements} of $elements');
          }
        } on FormatException catch (error) {
          warn('Annotation values incomplete: $error');
          result.add(DexAnnotationPreview(type, visibility, elements));
        }
      }
      return result;
    }

    try {
      symbols.check(directory, 16);
      final classOff = symbols.u32(directory);
      final counts = [
        symbols.u32(directory + 4),
        symbols.u32(directory + 8),
        symbols.u32(directory + 12),
      ];
      if (counts.any((count) => count > 100000) ||
          counts[0] > symbols.fieldCount ||
          counts[1] > symbols.methodCount ||
          counts[2] > symbols.methodCount) {
        throw const FormatException('Invalid annotation owner count');
      }
      symbols.check(directory + 16, counts.reduce((a, b) => a + b) * 8);
      if (classOff != 0) {
        targets.add(DexAnnotationTarget('class', null, null,
            parseSet(classOff)));
      }
      var at = directory + 16;
      for (var k = 0; k < 3; k++) {
        final kind = ['field', 'method', 'parameter'][k];
        final count = counts[k];
        if (count > maxOwnersPerKind) {
          warn('Only first $maxOwnersPerKind of $count '
              '$kind annotation owners decoded');
        }
        for (var i = 0; i < count && i < maxOwnersPerKind; i++) {
          final index = symbols.u32(at + i * 8);
          final valueOff = symbols.u32(at + i * 8 + 4);
          if (index >= (k == 0 ? symbols.fieldCount : symbols.methodCount)) {
            throw const FormatException('Annotation owner outside ID pool');
          }
          if (k != 2) {
            targets.add(DexAnnotationTarget(kind, index, null,
                parseSet(valueOff)));
            continue;
          }
          if (valueOff == 0) {
            continue;
          }
          final slots = symbols.u32(valueOff);
          if (slots > 512) {
            throw const FormatException('Invalid parameter annotation list');
          }
          symbols.check(valueOff + 4, slots * 4);
          if (slots > maxParameterSlots) {
            warn('Parameter list limited to $maxParameterSlots of $slots');
          }
          for (var j = 0; j < slots && j < maxParameterSlots; j++) {
            final setOff = symbols.u32(valueOff + 4 + j * 4);
            if (setOff != 0) {
              targets.add(DexAnnotationTarget(
                kind, index, j, parseSet(setOff)));
            }
          }
        }
        at += count * 8;
      }
    } on FormatException catch (error) {
      warn('Annotation preview incomplete: $error');
    }
    return DexClassAnnotationReport(
      List.unmodifiable(targets), List.unmodifiable(warnings), partial);
  }
}
