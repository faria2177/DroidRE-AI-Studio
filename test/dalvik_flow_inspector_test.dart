import 'package:droidre_ai_studio/services/dalvik_disassembler.dart';
import 'package:droidre_ai_studio/services/dalvik_flow_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packed-switch targets are relative to switch opcode, not payload', () {
    // switch @0 -> payload @4, case key 10 -> return @3
    final words = [0x002b, 4, 0, 0x000e, 0x0100, 1, 10, 0, 3, 0];
    final flow = DalvikFlowInspector.inspect(
      words, DalvikDisassembler.decode(words),
    );
    expect(flow.entries, contains('0x0000 case 10 -> 0x0003'));
    expect(flow.warnings, isEmpty);
  });

  test('sparse-switch uses signed keys and source-relative case targets', () {
    final words = [0x002c, 4, 0, 0x000e, 0x0200, 1,
      0xfffd, 0xffff, 3, 0];
    final flow = DalvikFlowInspector.inspect(
      words, DalvikDisassembler.decode(words),
    );
    expect(flow.entries, contains('0x0000 case -3 -> 0x0003'));
    expect(flow.warnings, isEmpty);
  });

  test('fill-array-data shows width and count without reading data as code', () {
    final words = [0x0026, 4, 0, 0x000e, 0x0300, 2, 2, 0, 0x0010, 0x0020];
    final flow = DalvikFlowInspector.inspect(
      words, DalvikDisassembler.decode(words),
    );
    expect(flow.entries.single, contains('2 elements × 2 bytes'));
    expect(flow.warnings, isEmpty);
  });

  test('reports incorrect payload type and invalid jump boundaries', () {
    final wrongPayload = [0x002b, 4, 0, 0x000e,
      0x0300, 1, 1, 0, 0x00ff];
    final wrongFlow = DalvikFlowInspector.inspect(
      wrongPayload, DalvikDisassembler.decode(wrongPayload),
    );
    expect(wrongFlow.warnings.join(' '), contains('no matching decoded payload'));

    // goto at 0 points inside a 3-word const instruction starting at 1.
    final branch = [0x0228, 0x0014, 0, 0];
    final branchFlow = DalvikFlowInspector.inspect(
      branch, DalvikDisassembler.decode(branch),
    );
    expect(branchFlow.warnings.join(' '),
        contains('non-decoded instruction boundary'));
  });

  test('rejects case target outside the code without crashing', () {
    final words = [0x002b, 4, 0, 0x000e, 0x0100, 1, 7, 0, 100, 0];
    final flow = DalvikFlowInspector.inspect(
      words, DalvikDisassembler.decode(words),
    );
    expect(flow.entries.single, contains('case 7'));
    expect(flow.warnings.join(' '), contains('outside the method'));
  });
}
