import 'package:flutter/foundation.dart';

@immutable
class DalvikInstruction {
  const DalvikInstruction({
    required this.offset,
    required this.width,
    required this.mnemonic,
    required this.operands,
  });

  final int offset;
  final int width;
  final String mnemonic;
  final String operands;

  String get line => '${offset.toRadixString(16).padLeft(4, '0')}: '
      '$mnemonic${operands.isEmpty ? '' : ' $operands'}';
}

@immutable
class DalvikDecodeResult {
  const DalvikDecodeResult({required this.instructions, required this.truncated});

  final List<DalvikInstruction> instructions;
  final bool truncated;

  String get text {
    final result = instructions.map((item) => item.line).join('\n');
    return truncated ? '$result\n# Display limited to ${instructions.length} instructions' : result;
  }
}

class _Op {
  const _Op(this.name, this.format);

  final String name;
  final String format;
}

/// Decoder for standard Dalvik opcode formats (DEX 035-040).
/// It does not verify register types/control-flow validity or recover Java.
class DalvikDisassembler {
  const DalvikDisassembler._();

  static final Map<int, _Op> _opcodes = _buildOpcodes();

  static int _signed(int value, int bits) => value.toSigned(bits);

  static int _width(String format) => switch (format) {
    '10x' || '12x' || '11n' || '11x' || '10t' => 1,
    '20t' || '21t' || '21s' || '21h' || '21c' || '22x' ||
    '22t' || '22s' || '22b' || '22c' || '23x' => 2,
    '30t' || '31t' || '31i' || '31c' || '32x' || '35c' || '3rc' => 3,
    '45cc' || '4rcc' => 4,
    '51l' => 5,
    _ => throw const FormatException('Unknown Dalvik instruction format'),
  };

  static String _referenceKind(int opcode) {
    if (opcode == 0x1a || opcode == 0x1b) return 'string';
    if (opcode == 0x1c || opcode == 0x1f || opcode == 0x20 ||
        opcode == 0x22 || opcode == 0x23 || opcode == 0x24 || opcode == 0x25) {
      return 'type';
    }
    if (opcode >= 0x52 && opcode <= 0x6d) return 'field';
    if (opcode == 0xfc || opcode == 0xfd) return 'callsite';
    if (opcode == 0xfe) return 'methodhandle';
    if (opcode == 0xff) return 'proto';
    return 'method';
  }

  static DalvikDecodeResult decode(List<int> units, {
    int maxInstructions = 20000,
    String Function(String kind, int index)? resolveReference,
  }) {
    if (units.length > 200000 || maxInstructions < 1 ||
        maxInstructions > 200000 || units.any((word) => word < 0 || word > 0xffff)) {
      throw const FormatException('Invalid Dalvik code unit bounds');
    }
    final decoded = <DalvikInstruction>[];
    var pos = 0;
    int at(int offset) => units[pos + offset];
    int u32(int offset) => at(offset) | (at(offset + 1) << 16);
    String v(int index) => 'v$index';
    String target(int offset) => ':${(pos + offset).toRadixString(16).padLeft(4, '0')}';
    String ref(int opcode, int index, {String? kindOverride}) {
      final kind = kindOverride ?? _referenceKind(opcode);
      if (resolveReference != null) {
        try {
          final resolved = resolveReference(kind, index);
          if (resolved.isNotEmpty) return resolved;
        } on FormatException {
          // Invalid pool index remains visible without a synthetic name.
        }
      }
      return '$kind@$index';
    }

    while (pos < units.length && decoded.length < maxInstructions) {
      final first = at(0);
      final opcode = first & 255;
      if (opcode == 0 && first != 0) {
        final kind = first >> 8;
        if (kind != 1 && kind != 2 && kind != 3) {
          throw FormatException('Unknown Dalvik payload at code unit $pos');
        }
        if (pos + (kind == 2 ? 2 : 4) > units.length) {
          throw const FormatException('Truncated Dalvik payload header');
        }
        final count = at(1);
        final width = switch (kind) {
          1 => 4 + count * 2,
          2 => 2 + count * 4,
          _ => 4 + ((count * u32(2) + 1) ~/ 2),
        };
        if (width > units.length - pos || (kind == 3 && count == 0)) {
          throw const FormatException('Truncated Dalvik switch/array payload');
        }
        final label = switch (kind) {
          1 => 'packed-switch-payload',
          2 => 'sparse-switch-payload',
          _ => 'fill-array-data-payload',
        };
        decoded.add(DalvikInstruction(
          offset: pos,
          width: width,
          mnemonic: label,
          operands: kind == 3 ? '${u32(2)} elements × ${at(1)} bytes' : '$count entries',
        ));
        pos += width;
        continue;
      }
      final op = _opcodes[opcode];
      if (op == null) {
        // Do not guess unknown instruction widths: that would desynchronise
        // the rest of the disassembly and produce misleading code.
        throw FormatException('Unsupported Dalvik opcode 0x${opcode.toRadixString(16)} '
            'at code unit $pos');
      }
      final width = _width(op.format);
      if (width > units.length - pos) {
        throw FormatException('Truncated ${op.name} instruction at code unit $pos');
      }
      final aa = first >> 8;
      final a = (first >> 8) & 15;
      final b = (first >> 12) & 15;
      String operands;
      switch (op.format) {
        case '10x':
          operands = '';
        case '11x':
          operands = v(aa);
        case '12x':
          operands = '${v(a)}, ${v(b)}';
        case '11n':
          operands = '${v(a)}, #${_signed(b, 4)}';
        case '10t':
          operands = target(_signed(aa, 8));
        case '20t':
          operands = target(_signed(at(1), 16));
        case '30t':
          operands = target(_signed(u32(1), 32));
        case '21t':
          operands = '${v(aa)}, ${target(_signed(at(1), 16))}';
        case '22t':
          operands = '${v(a)}, ${v(b)}, ${target(_signed(at(1), 16))}';
        case '21s':
          operands = '${v(aa)}, #${_signed(at(1), 16)}';
        case '21h':
          final shift = opcode == 0x19 ? 48 : 16;
          operands = '${v(aa)}, #${(_signed(at(1), 16) << shift)}';
        case '31i':
          operands = '${v(aa)}, #${_signed(u32(1), 32)}';
        case '51l':
          final value = at(1) | (at(2) << 16) | (at(3) << 32) | (at(4) << 48);
          operands = '${v(aa)}, #${_signed(value, 64)}';
        case '21c':
          operands = '${v(aa)}, ${ref(opcode, at(1))}';
        case '31c':
          operands = '${v(aa)}, ${ref(opcode, u32(1))}';
        case '22c':
          operands = '${v(a)}, ${v(b)}, ${ref(opcode, at(1))}';
        case '22x':
          operands = '${v(aa)}, ${v(at(1))}';
        case '32x':
          operands = '${v(at(1))}, ${v(at(2))}';
        case '23x':
          operands = '${v(aa)}, ${v(at(1) & 255)}, ${v(at(1) >> 8)}';
        case '22s':
          operands = '${v(a)}, ${v(b)}, #${_signed(at(1), 16)}';
        case '22b':
          operands = '${v(aa)}, ${v(at(1) & 255)}, #${_signed(at(1) >> 8, 8)}';
        case '31t':
          operands = '${v(aa)}, ${target(_signed(u32(1), 32))}';
        case '35c':
        case '45cc':
          final count = (first >> 12) & 15;
          if (count > 5) throw const FormatException('Too many invoke registers');
          final registers = [at(2) & 15, (at(2) >> 4) & 15,
            (at(2) >> 8) & 15, (at(2) >> 12) & 15, (first >> 8) & 15]
              .take(count).map(v).join(', ');
          final extra = op.format == '45cc' ? ', ${ref(opcode, at(3), kindOverride: 'proto')}' : '';
          operands = '{$registers}, ${ref(opcode, at(1))}$extra';
        case '3rc':
        case '4rcc':
          final count = aa;
          final start = at(2);
          final registers = count == 0 ? '{}' :
              '{${v(start)} .. ${v(start + count - 1)}}';
          final extra = op.format == '4rcc' ? ', ${ref(opcode, at(3), kindOverride: 'proto')}' : '';
          operands = '$registers, ${ref(opcode, at(1))}$extra';
        default:
          throw const FormatException('Dalvik format not handled');
      }
      decoded.add(DalvikInstruction(
        offset: pos,
        width: width,
        mnemonic: op.name,
        operands: operands,
      ));
      pos += width;
    }
    return DalvikDecodeResult(instructions: decoded, truncated: pos < units.length);
  }

  static Map<int, _Op> _buildOpcodes() {
    final map = <int, _Op>{};
    void put(int code, String name, String format) => map[code] = _Op(name, format);
    void range(int start, String format, List<String> names) {
      for (var i = 0; i < names.length; i++) {
        put(start + i, names[i], format);
      }
    }

    put(0x00, 'nop', '10x');
    // Non-uniform moves use separate formats.
    put(0x01, 'move', '12x');
    put(0x02, 'move/from16', '22x');
    put(0x03, 'move/16', '32x');
    put(0x04, 'move-wide', '12x');
    put(0x05, 'move-wide/from16', '22x');
    put(0x06, 'move-wide/16', '32x');
    put(0x07, 'move-object', '12x');
    put(0x08, 'move-object/from16', '22x');
    put(0x09, 'move-object/16', '32x');
    range(0x0a, '11x', ['move-result', 'move-result-wide', 'move-result-object',
      'move-exception']);
    put(0x0e, 'return-void', '10x');
    range(0x0f, '11x', ['return', 'return-wide', 'return-object']);
    put(0x12, 'const/4', '11n');
    put(0x13, 'const/16', '21s');
    put(0x14, 'const', '31i');
    put(0x15, 'const/high16', '21h');
    put(0x16, 'const-wide/16', '21s');
    put(0x17, 'const-wide/32', '31i');
    put(0x18, 'const-wide', '51l');
    put(0x19, 'const-wide/high16', '21h');
    put(0x1a, 'const-string', '21c');
    put(0x1b, 'const-string/jumbo', '31c');
    put(0x1c, 'const-class', '21c');
    put(0x1d, 'monitor-enter', '11x');
    put(0x1e, 'monitor-exit', '11x');
    put(0x1f, 'check-cast', '21c');
    put(0x20, 'instance-of', '22c');
    put(0x21, 'array-length', '12x');
    put(0x22, 'new-instance', '21c');
    put(0x23, 'new-array', '22c');
    put(0x24, 'filled-new-array', '35c');
    put(0x25, 'filled-new-array/range', '3rc');
    put(0x26, 'fill-array-data', '31t');
    put(0x27, 'throw', '11x');
    put(0x28, 'goto', '10t');
    put(0x29, 'goto/16', '20t');
    put(0x2a, 'goto/32', '30t');
    put(0x2b, 'packed-switch', '31t');
    put(0x2c, 'sparse-switch', '31t');
    range(0x2d, '23x', ['cmpl-float', 'cmpg-float', 'cmpl-double',
      'cmpg-double', 'cmp-long']);
    range(0x32, '22t', ['if-eq', 'if-ne', 'if-lt', 'if-ge', 'if-gt', 'if-le']);
    range(0x38, '21t', ['if-eqz', 'if-nez', 'if-ltz', 'if-gez', 'if-gtz', 'if-lez']);
    range(0x44, '23x', ['aget', 'aget-wide', 'aget-object', 'aget-boolean',
      'aget-byte', 'aget-char', 'aget-short', 'aput', 'aput-wide', 'aput-object',
      'aput-boolean', 'aput-byte', 'aput-char', 'aput-short']);
    range(0x52, '22c', ['iget', 'iget-wide', 'iget-object', 'iget-boolean',
      'iget-byte', 'iget-char', 'iget-short', 'iput', 'iput-wide', 'iput-object',
      'iput-boolean', 'iput-byte', 'iput-char', 'iput-short']);
    range(0x60, '21c', ['sget', 'sget-wide', 'sget-object', 'sget-boolean',
      'sget-byte', 'sget-char', 'sget-short', 'sput', 'sput-wide', 'sput-object',
      'sput-boolean', 'sput-byte', 'sput-char', 'sput-short']);
    range(0x6e, '35c', ['invoke-virtual', 'invoke-super', 'invoke-direct',
      'invoke-static', 'invoke-interface']);
    range(0x74, '3rc', ['invoke-virtual/range', 'invoke-super/range',
      'invoke-direct/range', 'invoke-static/range', 'invoke-interface/range']);
    range(0x7b, '12x', ['neg-int', 'not-int', 'neg-long', 'not-long', 'neg-float',
      'neg-double', 'int-to-long', 'int-to-float', 'int-to-double',
      'long-to-int', 'long-to-float', 'long-to-double', 'float-to-int',
      'float-to-long', 'float-to-double', 'double-to-int', 'double-to-long',
      'double-to-float', 'int-to-byte', 'int-to-char', 'int-to-short']);
    final binary = ['add-int', 'sub-int', 'mul-int', 'div-int', 'rem-int',
      'and-int', 'or-int', 'xor-int', 'shl-int', 'shr-int', 'ushr-int',
      'add-long', 'sub-long', 'mul-long', 'div-long', 'rem-long',
      'and-long', 'or-long', 'xor-long', 'shl-long', 'shr-long', 'ushr-long',
      'add-float', 'sub-float', 'mul-float', 'div-float', 'rem-float',
      'add-double', 'sub-double', 'mul-double', 'div-double', 'rem-double'];
    range(0x90, '23x', binary);
    range(0xb0, '12x', binary.map((name) => '$name/2addr').toList());
    range(0xd0, '22s', ['add-int/lit16', 'rsub-int', 'mul-int/lit16',
      'div-int/lit16', 'rem-int/lit16', 'and-int/lit16', 'or-int/lit16',
      'xor-int/lit16']);
    range(0xd8, '22b', ['add-int/lit8', 'rsub-int/lit8', 'mul-int/lit8',
      'div-int/lit8', 'rem-int/lit8', 'and-int/lit8', 'or-int/lit8',
      'xor-int/lit8', 'shl-int/lit8', 'shr-int/lit8', 'ushr-int/lit8']);
    put(0xfa, 'invoke-polymorphic', '45cc');
    put(0xfb, 'invoke-polymorphic/range', '4rcc');
    put(0xfc, 'invoke-custom', '35c');
    put(0xfd, 'invoke-custom/range', '3rc');
    put(0xfe, 'const-method-handle', '21c');
    put(0xff, 'const-method-type', '21c');
    return map;
  }
}
