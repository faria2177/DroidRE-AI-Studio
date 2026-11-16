import 'package:flutter/foundation.dart';

import 'dex_inspector.dart';
import 'dex_symbol_index.dart';

@immutable
class DexDebugParameter {
  const DexDebugParameter({required this.index, required this.name});

  /// Parameter ordinal, excluding the implicit instance receiver.
  final int index;
  final String? name;

  Map<String, Object?> toJson() => {'index': index, 'name': name};
}

@immutable
class DexDebugPosition {
  const DexDebugPosition({
    required this.address,
    required this.line,
    required this.sourceFile,
    required this.prologueEnd,
    required this.epilogueBegin,
  });

  /// 16-bit code-unit offset, not a byte offset.
  final int address;
  final int line;
  final String? sourceFile;
  final bool prologueEnd;
  final bool epilogueBegin;

  Map<String, Object?> toJson() => {
        'codeUnitOffset': address,
        'sourceLine': line,
        'sourceFile': sourceFile,
        'prologueEnd': prologueEnd,
        'epilogueBegin': epilogueBegin,
      };
}

@immutable
class DexDebugLocalRange {
  const DexDebugLocalRange({
    required this.register,
    required this.name,
    required this.typeDescriptor,
    required this.signature,
    required this.startAddress,
    required this.endAddressExclusive,
    required this.restarted,
  });

  final int register;
  final String? name;
  final String? typeDescriptor;
  final String? signature;
  final int startAddress;

  /// Null when an invalid or truncated stream leaves this range uncertain.
  final int? endAddressExclusive;
  final bool restarted;

  Map<String, Object?> toJson() => {
        'register': register,
        'name': name,
        'type': typeDescriptor,
        'signature': signature,
        'startCodeUnit': startAddress,
        'endCodeUnitExclusive': endAddressExclusive,
        'restarted': restarted,
        'endKnown': endAddressExclusive != null,
      };
}

@immutable
class DexDebugInfoReport {
  const DexDebugInfoReport({
    required this.available,
    required this.debugInfoOffset,
    required this.lineStart,
    required this.parameters,
    required this.positions,
    required this.locals,
    required this.sequenceEnded,
    required this.partial,
    required this.warnings,
  });

  final bool available;
  final int? debugInfoOffset;
  final int? lineStart;
  final List<DexDebugParameter> parameters;
  final List<DexDebugPosition> positions;
  final List<DexDebugLocalRange> locals;
  final bool sequenceEnded;
  final bool partial;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
        'available': available,
        'debugInfoOffset': debugInfoOffset,
        'lineStart': lineStart,
        'parameterNames': [for (final parameter in parameters) parameter.toJson()],
        'positions': [for (final position in positions) position.toJson()],
        'localRanges': [for (final local in locals) local.toJson()],
        'endSequenceSeen': sequenceEnded,
        'partial': partial,
        'warnings': warnings,
        'note': 'Read-only DEX debug information. Lines and locals are '
            'hints from the APK and do not reconstruct original source.',
      };
}

class _LiveDebugLocal {
  const _LiveDebugLocal({
    required this.register,
    required this.start,
    required this.name,
    required this.type,
    required this.signature,
    required this.restarted,
  });

  final int register;
  final int start;
  final String? name;
  final String? type;
  final String? signature;
  final bool restarted;

  _LiveDebugLocal restart(int at) => _LiveDebugLocal(
        register: register,
        start: at,
        name: name,
        type: type,
        signature: signature,
        restarted: true,
      );
}

/// Bounded DEX 035–040 debug_info_item state-machine reader.
///
/// Reads available source positions and local/parameter names. It never
/// synthesizes names or line numbers when debug information is stripped.
class DexDebugInfoInspector {
  const DexDebugInfoInspector._();

  static const maxDebugBytes = 128 * 1024;
  static const maxOperations = 5000;
  static const maxPositions = 512;
  static const maxLocalRanges = 256;
  static const maxParameters = 255;

  static DexDebugInfoReport inspectBytes(
    Uint8List dex,
    DexMethodSummary method, {
    String? defaultSourceFile,
  }) {
    if (method.codeOffset == 0) {
      return const DexDebugInfoReport(
        available: false,
        debugInfoOffset: null,
        lineStart: null,
        parameters: [],
        positions: [],
        locals: [],
        sequenceEnded: false,
        partial: false,
        warnings: [],
      );
    }
    final symbols = DexSymbolIndex(dex);
    symbols.check(method.codeOffset, 16);
    final registers = symbols.u16(method.codeOffset);
    if (registers != method.registerCount) {
      throw const FormatException('Method registers changed since indexing');
    }
    final instructionCount = symbols.u32(method.codeOffset + 12);
    if (instructionCount > 100000) {
      throw const FormatException('Method instructions exceed recovery limit');
    }
    symbols.check(method.codeOffset + 16, instructionCount * 2);

    final debugAt = symbols.u32(method.codeOffset + 8);
    if (debugAt == 0) {
      return const DexDebugInfoReport(
        available: false,
        debugInfoOffset: null,
        lineStart: null,
        parameters: [],
        positions: [],
        locals: [],
        sequenceEnded: false,
        partial: false,
        warnings: [],
      );
    }

    final parameters = <DexDebugParameter>[];
    final positions = <DexDebugPosition>[];
    final locals = <DexDebugLocalRange>[];
    final active = <int, _LiveDebugLocal>{};
    final lastInRegister = <int, _LiveDebugLocal>{};
    final warnings = <String>[];
    var partial = false;
    var ended = false;
    int? lineStart;
    var line = 0;
    var address = 0;
    var cursor = debugAt;
    var sourceFile = defaultSourceFile;
    var prologueEnd = false;
    var epilogueBegin = false;

    void warn(String message) {
      partial = true;
      if (warnings.length < 32 && !warnings.contains(message)) {
        warnings.add(message);
      }
    }

    int nextByte() {
      if (cursor < debugAt ||
          cursor - debugAt >= maxDebugBytes ||
          cursor >= dex.length) {
        throw const FormatException('Debug stream exceeds bounded input');
      }
      return dex[cursor++];
    }

    int uleb() {
      var result = 0;
      for (var i = 0; i < 5; i++) {
        final byte = nextByte();
        if (i == 4 && (byte & 0xf0) != 0) {
          throw const FormatException('Invalid debug ULEB128 value');
        }
        result |= (byte & 0x7f) << (7 * i);
        if ((byte & 0x80) == 0) {
          return result;
        }
      }
      throw const FormatException('Debug ULEB128 too long');
    }

    int sleb() {
      var value = 0;
      var shift = 0;
      for (var i = 0; i < 5; i++) {
        final byte = nextByte();
        value |= (byte & 0x7f) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) {
          if (shift < 32 && (byte & 0x40) != 0) {
            value |= -1 << shift;
          }
          return value.toSigned(32);
        }
      }
      throw const FormatException('Debug SLEB128 too long');
    }

    String? stringP1() {
      final value = uleb();
      return value == 0 ? null : symbols.stringAt(value - 1);
    }

    String? typeP1() {
      final value = uleb();
      return value == 0 ? null : symbols.typeAt(value - 1);
    }

    void advance(int delta) {
      if (delta < 0 || delta > instructionCount - address) {
        throw const FormatException('Debug PC runs past method code');
      }
      address += delta;
    }

    void addLocal(_LiveDebugLocal state, int? end) {
      if (locals.length < maxLocalRanges) {
        locals.add(DexDebugLocalRange(
          register: state.register,
          name: state.name,
          typeDescriptor: state.type,
          signature: state.signature,
          startAddress: state.start,
          endAddressExclusive: end,
          restarted: state.restarted,
        ));
      } else {
        warn('Local range display limited to $maxLocalRanges');
      }
    }

    void endLocal(int register) {
      final previous = active.remove(register);
      if (previous == null) {
        warn('DBG_END_LOCAL without an active register v$register');
        return;
      }
      addLocal(previous, address);
      lastInRegister[register] = previous;
    }

    void startLocal(int register, String? name, String? type,
        String? signature) {
      if (register < 0 || register >= registers) {
        throw const FormatException('Debug local register is outside method');
      }
      if (active.containsKey(register)) {
        endLocal(register); // Implicitly end the previous local at this PC.
      }
      if (active.length >= maxLocalRanges) {
        warn('Concurrent local preview limit reached');
        return;
      }
      active[register] = _LiveDebugLocal(
        register: register,
        start: address,
        name: name,
        type: type,
        signature: signature,
        restarted: false,
      );
    }

    void emitPosition() {
      if (address >= instructionCount || line < 1 || line > 10000000) {
        throw const FormatException('Invalid debug source position');
      }
      if (positions.length < maxPositions) {
        positions.add(DexDebugPosition(
          address: address,
          line: line,
          sourceFile: sourceFile,
          prologueEnd: prologueEnd,
          epilogueBegin: epilogueBegin,
        ));
      } else {
        warn('Source position preview limited to $maxPositions');
      }
      prologueEnd = false;
      epilogueBegin = false;
    }

    try {
      symbols.check(debugAt, 1);
      final initialLine = uleb();
      lineStart = initialLine;
      if (initialLine < 1 || initialLine > 10000000) {
        throw const FormatException('Invalid initial debug line');
      }
      line = initialLine;
      final count = uleb();
      if (count > maxParameters) {
        throw const FormatException('Debug parameter list too large');
      }

      // DEX debug parameters exclude the implicit instance receiver.
      if (method.methodIdIndex >= 0) {
        if (method.methodIdIndex >= symbols.methodCount) {
          throw const FormatException('Invalid method ID for debug parameters');
        }
        final methodAt = symbols.methodsOffset + method.methodIdIndex * 8;
        final protoIndex = symbols.u16(methodAt + 2);
        if (protoIndex >= symbols.protoCount) {
          throw const FormatException('Invalid prototype for debug parameters');
        }
        final protoAt = symbols.protosOffset + protoIndex * 12;
        final paramsAt = symbols.u32(protoAt + 8);
        final expected = paramsAt == 0 ? 0 : symbols.u32(paramsAt);
        if (expected > maxParameters) {
          throw const FormatException('Method parameter list too long');
        }
        if (count != expected) {
          warn('Debug parameter count $count differs from '
              'prototype count $expected');
        }
      }

      for (var i = 0; i < count; i++) {
        parameters.add(DexDebugParameter(index: i, name: stringP1()));
      }

      for (var opCount = 0; opCount < maxOperations; opCount++) {
        final opcode = nextByte();
        switch (opcode) {
          case 0x00:
            ended = true;
          case 0x01:
            advance(uleb());
          case 0x02:
            line += sleb();
          case 0x03:
          case 0x04:
            final register = uleb();
            final name = stringP1();
            final type = typeP1();
            final signature = opcode == 0x04 ? stringP1() : null;
            startLocal(register, name, type, signature);
          case 0x05:
            final register = uleb();
            if (register >= registers) {
              throw const FormatException('DBG_END_LOCAL invalid register');
            }
            endLocal(register);
          case 0x06:
            final register = uleb();
            if (register >= registers) {
              throw const FormatException('DBG_RESTART_LOCAL invalid register');
            }
            if (active.containsKey(register)) {
              warn('DBG_RESTART_LOCAL for already active v$register');
            } else if (lastInRegister[register] == null) {
              warn('DBG_RESTART_LOCAL has no previous v$register');
            } else if (active.length >= maxLocalRanges) {
              warn('Concurrent local preview limit reached');
            } else {
              active[register] = lastInRegister[register]!.restart(address);
            }
          case 0x07:
            prologueEnd = true;
          case 0x08:
            epilogueBegin = true;
          case 0x09:
            sourceFile = stringP1();
          default:
            if (opcode < 0x0a) {
              throw const FormatException('Unsupported debug opcode');
            }
            final adjusted = opcode - 0x0a;
            advance(adjusted ~/ 15);
            line += -4 + adjusted % 15;
            emitPosition();
        }
        if (ended) {
          break;
        }
      }
      if (!ended) {
        warn('Debug opcode sequence missing DBG_END_SEQUENCE '
            'or exceeded $maxOperations events');
      }
    } on FormatException catch (error) {
      warn('Malformed debug information: $error');
    }

    for (final state in active.values) {
      addLocal(state, ended ? instructionCount : null);
    }
    return DexDebugInfoReport(
      available: true,
      debugInfoOffset: debugAt,
      lineStart: lineStart,
      parameters: List.unmodifiable(parameters),
      positions: List.unmodifiable(positions),
      locals: List.unmodifiable(locals),
      sequenceEnded: ended,
      partial: partial,
      warnings: List.unmodifiable(warnings),
    );
  }
}
