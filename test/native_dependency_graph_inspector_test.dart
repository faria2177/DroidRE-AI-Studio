import 'package:droidre_ai_studio/services/elf_dependency_inspector.dart';
import 'package:droidre_ai_studio/services/native_dependency_graph_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

const abi = 'lib/arm64-v8a';
const root = '$abi/libmain.so';
const helper = '$abi/libhelper.so';

ElfDependencyReport dependency(
  List<String> needed, {
  String? soname,
  bool truncated = false,
  List<String> warnings = const [],
}) => ElfDependencyReport(
  needed: needed,
  soname: soname,
  rpath: null,
  runpath: null,
  source: 'SHT_DYNAMIC',
  examinedEntries: needed.length + 1,
  truncated: truncated,
  warnings: warnings,
);

void main() {
  test('links DT_NEEDED to packaged same-ABI basename', () {
    final graph = NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [root, helper],
      reports: {
        root: dependency(['libhelper.so', 'libc.so']),
        helper: dependency([]),
      },
    );
    expect(graph.nodes, hasLength(2));
    expect(graph.edges, hasLength(2));
    expect(graph.edges.first.status, NativeDependencyStatus.packaged);
    expect(graph.edges.first.toPath, helper);
    expect(graph.edges.last.status, NativeDependencyStatus.notPackaged);
    expect(graph.edges.last.toPath, isNull);
    expect(graph.cycles, isEmpty);
    expect(graph.truncated, isFalse);
  });

  test('SONAME alias resolves a library whose filename differs', () {
    final aliasPath = '$abi/libhashed_123.so';
    final graph = NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [root, aliasPath],
      reports: {
        root: dependency(['libpublic.so']),
        aliasPath: dependency([], soname: 'libpublic.so'),
      },
    );
    expect(graph.edges.single.toPath, aliasPath);
    expect(graph.nodes.last.soname, 'libpublic.so');
  });

  test('conflicting SONAME and basename is ambiguous, not guessed', () {
    final shadow = '$abi/libshadow.so';
    final graph = NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [root, helper, shadow],
      reports: {
        root: dependency(['libhelper.so']),
        helper: dependency([]),
        shadow: dependency([], soname: 'libhelper.so'),
      },
    );
    expect(graph.edges.single.status, NativeDependencyStatus.ambiguous);
    expect(graph.edges.single.candidates, containsAll([helper, shadow]));
    expect(graph.edges.single.toPath, isNull);
  });

  test('does not connect two different ABIs', () {
    expect(() => NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [root, 'lib/armeabi-v7a/libhelper.so'],
      reports: {root: dependency(['libhelper.so'])},
    ), throwsFormatException);
  });

  test('marks cycles without infinite traversal', () {
    final graph = NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [root, helper],
      reports: {
        root: dependency(['libhelper.so']),
        helper: dependency(['libmain.so']),
      },
    );
    expect(graph.cycles, hasLength(1));
    expect(graph.cycles.single, contains('libmain.so'));
    expect(graph.cycles.single, contains('libhelper.so'));
  });

  test('skipped packaged libraries do not become not-packaged nodes', () {
    final graph = NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [root, helper],
      reports: {root: dependency(['libhelper.so'])},
      failures: {helper: 'Size limit'},
    );
    expect(graph.nodes.last.inspected, isFalse);
    expect(graph.nodes.last.warning, 'Size limit');
    expect(graph.edges.single.status, NativeDependencyStatus.packaged);
    expect(graph.truncated, isTrue);
    expect(graph.warnings.join(' '), contains('could not be inspected'));
  });

  test('warns about partial child decoder results', () {
    final graph = NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [root],
      reports: {root: dependency([], truncated: true)},
    );
    expect(graph.truncated, isTrue);
    expect(graph.warnings.join(' '), contains('partial'));
  });

  test('caps graph nodes and rejects duplicate source paths', () {
    expect(() => NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [root, root],
      reports: {root: dependency([])},
    ), throwsFormatException);
    expect(() => NativeDependencyGraphInspector.buildGraph(
      rootPath: root,
      abiDirectory: abi,
      paths: [for (var i = 0; i < 65; i++) '$abi/lib$i.so'],
      reports: const {},
    ), throwsFormatException);
  });
}
