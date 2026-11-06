import 'package:droidre_ai_studio/services/dalvik_disassembler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes register operands, literal and return opcodes', () {
    final decoded = DalvikDisassembler.decode([0x1012, 0x000e]);
    expect(decoded.instructions, hasLength(2));
    expect(decoded.instructions[0].line, '0000: const/4 v0, #1');
    expect(decoded.instructions[1].line, '0001: return-void');
    expect(decoded.truncated, isFalse);
  });

  test('decodes method invocation registers and reference index', () {
    final decoded = DalvikDisassembler.decode([0x2071, 3, 0x0010, 0x000e]);
    expect(decoded.instructions.first.line,
        '0000: invoke-static {v0, v1}, method@3');
    expect(decoded.instructions[1].offset, 3);
  });

  test('decodes payloads without interpreting data as instructions', () {
    final decoded = DalvikDisassembler.decode([0x0100, 1, 0, 0, 0, 0]);
    expect(decoded.instructions.single.mnemonic, 'packed-switch-payload');
    expect(decoded.instructions.single.width, 6);
  });

  test('rejects unknown opcodes rather than guessing width', () {
    expect(() => DalvikDisassembler.decode([0x00f0]), throwsFormatException);
    expect(() => DalvikDisassembler.decode([0x0014]), throwsFormatException);
  });

  test('allows bounded display without losing instruction boundaries', () {
    final decoded = DalvikDisassembler.decode([0x000e, 0x000e],
        maxInstructions: 1);
    expect(decoded.truncated, isTrue);
    expect(decoded.instructions.single.offset, 0);
  });
}
