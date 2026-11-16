import 'dalvik_disassembler.dart';

/// Supplemental, read-only control-flow inspection. This does not verify
/// register types, exception handlers or produce rebuildable Smali.
class DalvikFlowReport {
  const DalvikFlowReport({required this.entries, required this.warnings});

  final List<String> entries;
  final List<String> warnings;
}

class DalvikFlowInspector {
  const DalvikFlowInspector._();

  static const maxCaseEntries = 100;
  static const maxWarnings = 40;

  static DalvikFlowReport inspect(
    List<int> words,
    DalvikDecodeResult decoded,
  ) {
    final entries = <String>[];
    final warnings = <String>[];
    final instructions = <int, DalvikInstruction>{
      for (final instruction in decoded.instructions)
        instruction.offset: instruction,
    };

    String label(int offset) =>
        '0x${offset.toRadixString(16).padLeft(4, '0')}';

    void warning(String message) {
      if (warnings.length < maxWarnings) warnings.add(message);
    }

    int signed32(int offset) =>
        (words[offset] | (words[offset + 1] << 16)).toSigned(32);

    void validateTarget(int from, int target, String purpose) {
      if (target < 0 || target >= words.length) {
        warning('${label(from)} $purpose points outside the method: $target');
        return;
      }
      final destination = instructions[target];
      if (destination == null) {
        warning('${label(from)} $purpose points to a non-decoded '
            'instruction boundary: ${label(target)}');
      } else if (destination.mnemonic.endsWith('-payload')) {
        warning('${label(from)} $purpose jumps into payload data at '
            '${label(target)}');
      }
    }

    for (final instruction in decoded.instructions) {
      final pc = instruction.offset;
      final opcode = words[pc] & 0xff;
      int? branch;
      if (opcode == 0x28) {
        branch = (words[pc] >> 8).toSigned(8);
      } else if (opcode == 0x29 || (opcode >= 0x32 && opcode <= 0x3d)) {
        branch = words[pc + 1].toSigned(16);
      } else if (opcode == 0x2a) {
        branch = signed32(pc + 1);
      }
      if (branch != null) {
        validateTarget(pc, pc + branch, instruction.mnemonic);
        continue;
      }
      if (opcode != 0x26 && opcode != 0x2b && opcode != 0x2c) {
        continue;
      }

      // 31t offsets point to payloads, not ordinary branch instructions.
      final tableOffset = pc + signed32(pc + 1);
      if (tableOffset < 0 || tableOffset >= words.length) {
        warning('${label(pc)} payload reference points outside method: '
            '$tableOffset');
        continue;
      }
      final expected = switch (opcode) {
        0x26 => 'fill-array-data-payload',
        0x2b => 'packed-switch-payload',
        _ => 'sparse-switch-payload',
      };
      final payload = instructions[tableOffset];
      if (payload == null || payload.mnemonic != expected) {
        warning('${label(pc)} expects $expected at '
            '${label(tableOffset)}, but no matching decoded payload exists');
        continue;
      }
      if (tableOffset.isOdd) {
        warning('${label(pc)} payload at ${label(tableOffset)} is '
            'not aligned to a 32-bit boundary');
      }
      if (opcode == 0x26) {
        final elementWidth = words[tableOffset + 1];
        final length = words[tableOffset + 2] |
            (words[tableOffset + 3] << 16);
        if (![1, 2, 4, 8].contains(elementWidth)) {
          warning('${label(tableOffset)} array element width '
              '$elementWidth is unusual');
        }
        if (entries.length < maxCaseEntries) {
          entries.add('fill-array-data ${label(pc)} -> '
              '${label(tableOffset)}: $length elements × '
              '$elementWidth bytes');
        }
        continue;
      }

      final count = words[tableOffset + 1];
      final allowed = maxCaseEntries - entries.length;
      if (count > allowed) {
        warning('${label(pc)} switch cases limited to '
            '$maxCaseEntries displayed entries');
      }
      for (var i = 0; i < count && i < allowed; i++) {
        final key = opcode == 0x2b
            ? signed32(tableOffset + 2) + i
            : signed32(tableOffset + 2 + i * 2);
        final offset = opcode == 0x2b
            ? signed32(tableOffset + 4 + i * 2)
            : signed32(tableOffset + 2 + count * 2 + i * 2);
        // Dalvik switch targets are relative to the switch opcode PC,
        // NOT to the location of the packed/sparse payload.
        final destination = pc + offset;
        entries.add('${label(pc)} case $key -> ${label(destination)}');
        validateTarget(pc, destination, 'switch case $key');
      }
    }
    if (decoded.truncated) {
      warning('Instruction display is truncated; target checks may be '
          'incomplete');
    }
    return DalvikFlowReport(entries: entries, warnings: warnings);
  }
}
