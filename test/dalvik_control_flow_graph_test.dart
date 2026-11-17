import 'package:droidre_ai_studio/services/dalvik_control_flow_graph.dart';
import 'package:droidre_ai_studio/services/dalvik_disassembler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DalvikControlFlowGraph graph(List<int> words, {int maxInstructions = 20000}) =>
      DalvikControlFlowGraph.build(words,
          DalvikDisassembler.decode(words, maxInstructions: maxInstructions));

  test('splits conditional diamond and reports both normal paths', () {
    // if-eqz @0 -> 4, fallthrough @2, goto @3 -> 5, return @5.
    final result = graph([0x0038, 4, 0x0012, 0x0228, 0x1012, 0x000e]);
    expect(result.partial, isFalse);
    expect(result.blocks.map((block) => block.start), [0, 2, 4, 5]);
    expect(result.blocks.first.successors.map((edge) => edge.target), [4, 2]);
    expect(result.blocks.every((block) => block.reachable == true), isTrue);
  });

  test('keeps a backward branch and separates unreachable normal code', () {
    final result = graph([0x0012, 0xff28, 0x000e]);
    expect(result.partial, isFalse);
    expect(result.blocks.map((block) => block.start), [0, 2]);
    expect(result.blocks.first.successors.single.target, 0);
    expect(result.blocks.last.reachable, isFalse);
    expect(result.describe().join(' '), contains('[backward]'));
  });

  test('switch edges have keys and payloads remain outside the graph', () {
    final result = graph([0x002b, 4, 0, 0x000e, 0x0100, 1, 10, 0, 3, 0]);
    expect(result.partial, isFalse);
    expect(result.blocks.map((block) => block.start), [0, 3]);
    expect(result.blocks.first.successors.first.caseKey, 10);
    expect(result.blocks.first.successors.first.target, 3);
    expect(result.blocks.first.successors.last.kind, DalvikEdgeKind.fallthrough);
  });

  test('invalid branch boundaries or truncated decoding mark partial', () {
    final invalid = graph([0x0228, 0x0014, 0, 0, 0x000e]);
    expect(invalid.partial, isTrue);
    expect(invalid.blocks.last.reachable, isNull);
    expect(invalid.warnings.join(' '), contains('invalid or undecoded'));
    final truncated = graph([0x0038, 3, 0x000e, 0x000e], maxInstructions: 2);
    expect(truncated.partial, isTrue);
    expect(truncated.describe().join(' '), contains('(partial)'));
  });

  test('does not treat throw or return as fallthrough', () {
    final result = graph([0x0027, 0x000e]);
    expect(result.blocks.first.successors, isEmpty);
    expect(result.blocks.last.reachable, isFalse);
  });
}
