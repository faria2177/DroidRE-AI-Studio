/// Fixed-width, deliberately partial AArch64 decoder. Unknown or reserved
/// encodings remain .word, never guessed. No machine code is executed.
class Aarch64Instruction {
  const Aarch64Instruction(this.address, this.word, this.mnemonic,
      this.operands, {this.target});

  final int address;
  final int word;
  final String mnemonic;
  final String operands;
  final int? target;

  bool get supported => mnemonic != '.word';
  String get line =>
      '${Aarch64PreviewDecoder.hex(address)}  '
      '${word.toRadixString(16).padLeft(8, '0')}  '
      '$mnemonic${operands.isEmpty ? '' : ' $operands'}';
}

class Aarch64PreviewDecoder {
  const Aarch64PreviewDecoder._();

  static String hex(int value) => value < 0
      ? '-0x${(-value).toRadixString(16)}'
      : '0x${value.toRadixString(16)}';

  static const _conditions = [
    'eq', 'ne', 'cs', 'cc', 'mi', 'pl', 'vs', 'vc',
    'hi', 'ls', 'ge', 'lt', 'gt', 'le', 'al', 'nv',
  ];

  static Aarch64Instruction decode(int word, int address) {
    if (word < 0 || word > 0xffffffff || address < 0 ||
        address > 0x7ffffffff0000000 || address % 4 != 0) {
      throw const FormatException('Invalid AArch64 word or address');
    }
    final rd = word & 31;
    final rn = (word >> 5) & 31;
    final wide = (word & 0x80000000) != 0;
    String reg(int number, bool is64, {bool stack = false}) {
      if (number == 31) {
        return stack ? (is64 ? 'sp' : 'wsp') : (is64 ? 'xzr' : 'wzr');
      }
      return '${is64 ? 'x' : 'w'}$number';
    }

    Aarch64Instruction ins(String name, [String args = '']) =>
        Aarch64Instruction(address, word, name, args);
    Aarch64Instruction branch(String name, int delta, [String prefix = '']) {
      final target = address + delta;
      return Aarch64Instruction(address, word, name,
          '$prefix${hex(target)}', target: target);
    }

    if (word == 0xd503201f) {
      return ins('nop');
    }
    if ((word & 0x7c000000) == 0x14000000) {
      return branch(wide ? 'bl' : 'b', (word & 0x3ffffff).toSigned(26) * 4);
    }
    if ((word & 0xff000010) == 0x54000000) {
      return branch('b.${_conditions[word & 15]}',
          ((word >> 5) & 0x7ffff).toSigned(19) * 4);
    }
    if ((word & 0x7e000000) == 0x34000000) {
      return branch((word & 0x01000000) == 0 ? 'cbz' : 'cbnz',
          ((word >> 5) & 0x7ffff).toSigned(19) * 4, '${reg(rd, wide)}, ');
    }
    if ((word & 0x7e000000) == 0x36000000) {
      final bit = ((word >> 26) & 32) | ((word >> 19) & 31);
      return branch((word & 0x01000000) == 0 ? 'tbz' : 'tbnz',
          ((word >> 5) & 0x3fff).toSigned(14) * 4,
          '${reg(rd, wide)}, #$bit, ');
    }
    final indirect = switch (word & 0xfffffc1f) {
      0xd61f0000 => 'br',
      0xd63f0000 => 'blr',
      0xd65f0000 => 'ret',
      _ => null,
    };
    if (indirect != null && rn != 31) {
      return ins(indirect, reg(rn, true));
    }
    if ((word & 0xffe0001f) == 0xd4000001) {
      return ins('svc', '#${(word >> 5) & 0xffff}');
    }
    if ((word & 0x1f800000) == 0x11000000) {
      final subtract = (word & 0x40000000) != 0;
      final flags = (word & 0x20000000) != 0;
      final immediate = ((word >> 10) & 0xfff) <<
          ((word & 0x00400000) == 0 ? 0 : 12);
      final mnemonic = '${subtract ? 'sub' : 'add'}${flags ? 's' : ''}';
      return ins(mnemonic,
          '${reg(rd, wide, stack: !flags)}, '
          '${reg(rn, wide, stack: true)}, #$immediate');
    }
    if ((word & 0x1f800000) == 0x12800000) {
      final halfword = (word >> 21) & 3;
      final mnemonic = switch ((word >> 29) & 3) {
        0 => 'movn', 2 => 'movz', 3 => 'movk', _ => null,
      };
      if (mnemonic != null && (wide || halfword < 2)) {
        return ins(mnemonic, '${reg(rd, wide)}, #${(word >> 5) & 0xffff}'
            '${halfword == 0 ? '' : ', lsl #${halfword * 16}'}');
      }
    }
    if ((word & 0x1f000000) == 0x10000000) {
      final imm = ((((word >> 5) & 0x7ffff) << 2) |
          ((word >> 29) & 3)).toSigned(21);
      final target = wide ? (address & ~0xfff) + imm * 4096 : address + imm;
      return ins(wide ? 'adrp' : 'adr', '${reg(rd, true)}, ${hex(target)}');
    }
    // Unsigned immediate integer load/store, 32/64-bit only.
    final loadStore = switch (word & 0xffc00000) {
      0xb9000000 || 0xf9000000 => 'str',
      0xb9400000 || 0xf9400000 => 'ldr',
      _ => null,
    };
    if (loadStore != null) {
      final is64 = (word & 0x40000000) != 0;
      final offset = ((word >> 10) & 0xfff) * (is64 ? 8 : 4);
      return ins(loadStore,
          '${reg(rd, is64)}, [${reg(rn, true, stack: true)}, #$offset]');
    }
    return ins('.word', '${hex(word)} // unsupported encoding');
  }
}
