import 'package:flutter/foundation.dart';

import 'dalvik_disassembler.dart';
import 'dex_inspector.dart';
import 'dex_symbol_index.dart';

@immutable
class DexCatchHandler {
  const DexCatchHandler({
    required this.typeDescriptor,
    required this.address,
  });

  /// Null for a catch-all handler.
  final String? typeDescriptor;
  /// Address in 16-bit code units, relative to the method's first opcode.
  final int address;

  Map<String, Object?> toJson() => {
    'type': typeDescriptor,
    'handlerAddress': address,
    'catchAll': typeDescriptor == null,
  };
}

@immutable
class DexTryRegion {
  const DexTryRegion({
    required this.startAddress,
    required this.endAddress,
    required this.handlers,
  });

  final int startAddress;
  /// Exclusive end, in code units.
  final int endAddress;
  final List<DexCatchHandler> handlers;

  Map<String, Object?> toJson() => {
    'startAddress': startAddress,
    'endAddressExclusive': endAddress,
    'handlers': [for (final handler in handlers) handler.toJson()],
  };
}

@immutable
class DexMethodPoolReference {
  const DexMethodPoolReference({
    required this.codeUnitOffset,
    required this.opcode,
    required this.kind,
    required this.index,
    required this.label,
    required this.resolved,
  });

  final int codeUnitOffset;
  final String opcode;
  final String kind;
  final int index;
  final String label;
  final bool resolved;

  Map<String, Object?> toJson() => {
    'codeUnitOffset': codeUnitOffset,
    'opcode': opcode,
    'kind': kind,
    'index': index,
    'label': label,
    'resolvedInThisDex': resolved,
  };
}

@immutable
class DexMethodSemantics {
  const DexMethodSemantics({
    required this.tries,
    required this.references,
    required this.warnings,
    required this.partial,
  });

  final List<DexTryRegion> tries;
  final List<DexMethodPoolReference> references;
  final List<String> warnings;
  final bool partial;

  Map<String, Object?> toJson() => {
    'tryRegions': [for (final item in tries) item.toJson()],
    'poolReferences': [for (final item in references) item.toJson()],
    'partial': partial,
    'warnings': warnings,
  };
}

/// Bounded DEX code_item metadata extraction. The reports are read-only.
///
/// The try/handler list is parsed from the DEX structure (not guessed from
/// Dalvik opcodes). References are instruction-offset-aware but do not resolve
/// resources in other DEX files or reconstruct executable source.
class DexMethodSemanticsInspector {
  const DexMethodSemanticsInspector._();

  static const maxTries = 128;
  static const maxEncodedHandlers = 256;
  static const maxTypedCatches = 64;
  static const maxReferences = 160;
  static const maxInstructions = 50000;

  static DexMethodSemantics inspectBytes(
    Uint8List dex,
    DexMethodSummary method,
  ) {
    if (method.codeOffset == 0) {
      return const DexMethodSemantics(
        tries: [], references: [], warnings: [], partial: false);
    }
    final symbols = DexSymbolIndex(dex);
    final at = method.codeOffset;
    symbols.check(at, 16);
    final registers = symbols.u16(at);
    if (registers != method.registerCount) {
      throw const FormatException('Method registers changed since indexing');
    }
    final triesCount = symbols.u16(at + 6);
    final insnsSize = symbols.u32(at + 12);
    if (insnsSize > 100000) {
      throw const FormatException('Method code exceeds recovery limits');
    }
    symbols.check(at + 16, insnsSize * 2);

    final warnings = <String>[];
    var partial = false;
    void warn(String message) {
      partial = true;
      if (warnings.length < 24) {
        warnings.add(message);
      }
    }

    final tries = <DexTryRegion>[];
    if (triesCount != 0) {
      if (triesCount > maxTries) {
        warn('Try region count $triesCount exceeds $maxTries; '
            'exception metadata omitted');
      } else {
        try {
          tries.addAll(_readTries(
            symbols, at, insnsSize, triesCount));
        } on FormatException catch (error) {
          warn('Malformed exception metadata: $error');
        }
      }
    }

    final units = List<int>.generate(
      insnsSize,
      (i) => symbols.u16(at + 16 + i * 2),
      growable: false,
    );
    final references = <DexMethodPoolReference>[];
    try {
      final decoded = DalvikDisassembler.decode(
        units, maxInstructions: maxInstructions);
      if (decoded.truncated) {
        warn('Instruction preview exceeds $maxInstructions operations');
      }
      void add(int pc, String mnemonic, String kind, int index) {
        if (references.length >= maxReferences) {
          if (!warnings.contains('Reference preview limited to $maxReferences')) {
            warn('Reference preview limited to $maxReferences');
          }
          return;
        }
        final name = symbols.resolve(kind, index);
        references.add(DexMethodPoolReference(
          codeUnitOffset: pc,
          opcode: mnemonic,
          kind: kind,
          index: index,
          label: name,
          resolved: name != '$kind@$index',
        ));
      }

      for (final instruction in decoded.instructions) {
        final pc = instruction.offset;
        final opcode = units[pc] & 0xff;
        String? kind;
        if (opcode == 0x1a || opcode == 0x1b) {
          kind = 'string';
        } else if (opcode == 0x1c || opcode == 0x1f ||
            opcode == 0x20 ||
            (opcode >= 0x22 && opcode <= 0x25)) {
          kind = 'type';
        } else if (opcode >= 0x52 && opcode <= 0x6d) {
          kind = 'field';
        } else if ((opcode >= 0x6e && opcode <= 0x72) ||
            (opcode >= 0x74 && opcode <= 0x78) ||
            opcode == 0xfa || opcode == 0xfb) {
          kind = 'method';
        } else if (opcode == 0xfc || opcode == 0xfd) {
          kind = 'callsite';
        } else if (opcode == 0xfe) {
          kind = 'methodhandle';
        } else if (opcode == 0xff) {
          kind = 'proto';
        }
        if (kind == null) {
          continue;
        }
        final index = opcode == 0x1b
            ? units[pc + 1] | (units[pc + 2] << 16)
            : units[pc + 1];
        add(pc, instruction.mnemonic, kind, index);
        if (opcode == 0xfa || opcode == 0xfb) {
          add(pc, instruction.mnemonic, 'proto', units[pc + 3]);
        }
      }
    } on FormatException catch (error) {
      warn('Instruction reference decoding is incomplete: $error');
    }
    return DexMethodSemantics(
      tries: List.unmodifiable(tries),
      references: List.unmodifiable(references),
      warnings: List.unmodifiable(warnings),
      partial: partial,
    );
  }

  static List<DexTryRegion> _readTries(
    DexSymbolIndex symbols, int codeAt,
    int insnsSize, int triesCount,
  ) {
    final triesAt = codeAt + 16 + insnsSize * 2 +
        (insnsSize.isOdd ? 2 : 0);
    symbols.check(triesAt, triesCount * 8);
    final listStart = triesAt + triesCount * 8;
    var cursor = listStart;

    int uleb() {
      var value = 0;
      for (var i = 0; i < 5; i++) {
        symbols.check(cursor, 1);
        final byte = symbols.bytes[cursor++];
        if (i == 4 && (byte & 0xf0) != 0) {
          throw const FormatException('Invalid catch ULEB128');
        }
        value |= (byte & 0x7f) << (7 * i);
        if ((byte & 0x80) == 0) {
          return value;
        }
      }
      throw const FormatException('Catch ULEB128 too long');
    }

    int sleb() {
      var result = 0;
      var shift = 0;
      var byte = 0;
      for (var i = 0; i < 5; i++) {
        symbols.check(cursor, 1);
        byte = symbols.bytes[cursor++];
        result |= (byte & 0x7f) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) {
          if (shift < 32 && (byte & 0x40) != 0) {
            result |= -1 << shift;
          }
          return result.toSigned(32);
        }
      }
      throw const FormatException('Catch SLEB128 too long');
    }

    final handlerCount = uleb();
    if (handlerCount > maxEncodedHandlers) {
      throw const FormatException('Too many encoded catch handlers');
    }
    final byOffset = <int, List<DexCatchHandler>>{};
    for (var i = 0; i < handlerCount; i++) {
      final relative = cursor - listStart;
      final signedSize = sleb();
      final typedCount = signedSize.abs();
      if (typedCount > maxTypedCatches) {
        throw const FormatException('Too many typed catch handlers');
      }
      final handlers = <DexCatchHandler>[];
      for (var j = 0; j < typedCount; j++) {
        final typeIndex = uleb();
        final address = uleb();
        if (address >= insnsSize) {
          throw const FormatException('Typed catch address outside method');
        }
        handlers.add(DexCatchHandler(
          typeDescriptor: symbols.typeAt(typeIndex),
          address: address,
        ));
      }
      if (signedSize <= 0) {
        final catchAll = uleb();
        if (catchAll >= insnsSize) {
          throw const FormatException('Catch-all address outside method');
        }
        handlers.add(DexCatchHandler(
          typeDescriptor: null, address: catchAll));
      }
      byOffset[relative] = List.unmodifiable(handlers);
    }

    final tries = <DexTryRegion>[];
    var previousEnd = 0;
    for (var i = 0; i < triesCount; i++) {
      final pos = triesAt + i * 8;
      final start = symbols.u32(pos);
      final count = symbols.u16(pos + 4);
      final handlerOff = symbols.u16(pos + 6);
      if (count == 0 || start < previousEnd ||
          start >= insnsSize || count > insnsSize - start) {
        throw const FormatException('Invalid or overlapping try range');
      }
      final handlers = byOffset[handlerOff];
      if (handlers == null) {
        throw const FormatException('Unknown encoded handler offset');
      }
      tries.add(DexTryRegion(
        startAddress: start,
        endAddress: start + count,
        handlers: handlers,
      ));
      previousEnd = start + count;
    }
    return tries;
  }
}
