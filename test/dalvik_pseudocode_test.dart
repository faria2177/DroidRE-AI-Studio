import 'package:droidre_ai_studio/services/dalvik_control_flow_graph.dart';
import 'package:droidre_ai_studio/services/dalvik_disassembler.dart';
import 'package:droidre_ai_studio/services/dalvik_pseudocode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String render(List<int> words) {
    final decoded = DalvikDisassembler.decode(words);
    return DalvikPseudocode.render(decoded, methodName: 'fixture',
        prototype: '()V', graph: DalvikControlFlowGraph.build(words, decoded));
  }

  test('renders zero and two-register conditional expressions', () {
    final output = render([0x0038, 4, 0x1033, 2, 0x000e]);
    expect(output, contains('if (v0 == 0) goto L0004;'));
    expect(output, contains('if (v0 != v1) goto L0004;'));
    expect(output, contains('Dalvik @0x0002'));
  });

  test('links invoke result once in the same basic block', () {
    final output = render([0x0071, 3, 0, 0x010a, 0x010f]);
    expect(output, contains('result_L0000 = call_static({}, method@3);'));
    expect(output, contains('v1 = result_L0000;'));
    expect(output, contains('return v1;'));
    expect('call_static'.allMatches(output), hasLength(1));
  });

  test('does not bind move-result at a branch entry', () {
    final output = render([0x0038, 5, 0x0071, 3, 0, 0x000a, 0x000e]);
    expect(output, contains('result producer not safely linked'));
    expect(output, isNot(contains('result_L0002 =')));
  });

  test('preserves object receiver and array indexes', () {
    final output = render([0x1052, 3, 0x1059, 4, 0x0044, 0x0201,
        0x004b, 0x0201, 0x000e]);
    expect(output, contains('v0 = field(v1, field@3);'));
    expect(output, contains('field(v1, field@4) = v0;'));
    expect(output, contains('v0 = v1[v2];'));
    expect(output, contains('v1[v2] = v0;'));
  });

  test('renders two-address and reverse-subtract literal operands', () {
    final output = render([0x10b0, 0x10d1, 5, 0x000e]);
    expect(output, contains('v0 = v0 + v1;'));
    expect(output, contains('v0 = 5 - v1;'));
  });

  test('does not invent constructor call from allocation', () {
    final output = render([0x0022, 3, 0x000e]);
    expect(output, contains('v0 = allocate(type@3);'));
    expect(output, contains('constructor not implied'));
  });
}
