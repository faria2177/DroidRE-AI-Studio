import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'dalvik_disassembler.dart';
import 'dex_inspector.dart';
import 'dex_symbol_index.dart';
import 'package_binary_reader.dart';

@immutable
class DexGraphMethod {
  const DexGraphMethod({required this.dexFile, required this.method});

  final String dexFile;
  final DexMethodSummary method;
}

@immutable
class DexCallEdge {
  const DexCallEdge({required this.caller, required this.callee,
    required this.opcode});

  final String caller;
  final String callee;
  final String opcode;
}

@immutable
class DexGraphResult {
  const DexGraphResult({required this.root, required this.edges,
    required this.declarations, required this.scannedDexFiles,
    required this.scannedMethods, required this.skippedMethods,
    required this.skippedDexFiles, required this.truncated,
    required this.warnings});

  final String root;
  final List<DexCallEdge> edges;
  final Map<String, DexGraphMethod> declarations;
  final int scannedDexFiles;
  final int scannedMethods;
  final int skippedMethods;
  final int skippedDexFiles;
  final bool truncated;
  final List<String> warnings;

  List<DexCallEdge> get directIncoming =>
      edges.where((edge) => edge.callee == root).toList();
  List<DexCallEdge> get directOutgoing =>
      edges.where((edge) => edge.caller == root).toList();

  List<DexCallEdge> get secondLevelOutgoing {
    final callees = directOutgoing.map((edge) => edge.callee).toSet();
    return edges.where((edge) => callees.contains(edge.caller) &&
        edge.caller != root).take(100).toList();
  }

  List<DexCallEdge> get secondLevelIncoming {
    final callers = directIncoming.map((edge) => edge.caller).toSet();
    return edges.where((edge) => callers.contains(edge.callee) &&
        edge.callee != root).take(100).toList();
  }
}

/// Bounded, static cross-DEX call graph. Signature matching works across
/// classes.dex/classes2.dex, unlike DEX-local method ID comparisons.
/// Virtual dispatch, reflection, dynamic loading and unknown opcodes are not
/// resolved; reported graph edges are syntactic invocation sites only.
class DexCallGraph {
  const DexCallGraph._();

  static const maxDexFiles = 24;
  static const maxScannedMethods = 6000;
  static const maxCodeUnits = 1500000;
  static const maxEdges = 18000;

  static Future<DexGraphResult> scanApk(
    String apkPath, List<String> dexNames, String rootDex, int rootMethodId,
  ) => Isolate.run(() => _scan(
    dexNames,
    (name) => PackageBinaryReader.read(apkPath: apkPath, entryName: name,
        maxBytes: DexInspector.maxBytes),
    rootDex,
    rootMethodId,
  ));

  /// The in-memory adapter makes graph construction independently testable.
  static DexGraphResult scanBytes(
    Map<String, Uint8List> dexEntries, String rootDex, int rootMethodId,
  ) => _scan(dexEntries.keys.toList(), (name) => dexEntries[name]!,
      rootDex, rootMethodId);

  static DexGraphResult _scan(
    List<String> names, Uint8List Function(String) read,
    String rootDex, int rootMethodId,
  ) {
    if (!names.contains(rootDex)) {
      throw const FormatException('Selected DEX is not in the package');
    }
    final rootBytes = read(rootDex);
    final rootIndex = DexSymbolIndex(rootBytes);
    final root = rootIndex.methodAt(rootMethodId);
    final edges = <DexCallEdge>[];
    final seenEdges = <String>{};
    final declarations = <String, DexGraphMethod>{};
    var dexCount = 0;
    var scanned = 0;
    var skipped = 0;
    var skippedDex = 0;
    var codeUnits = 0;
    var truncated = names.length > maxDexFiles;
    final warnings = <String>[];

    for (final name in names.take(maxDexFiles)) {
      if (scanned >= maxScannedMethods || codeUnits >= maxCodeUnits ||
          edges.length >= maxEdges) {
        truncated = true;
        break;
      }
      try {
        final bytes = name == rootDex ? rootBytes : read(name);
        final symbols = DexSymbolIndex(bytes);
        final summary = DexInspector.inspectBytes(bytes);
        dexCount++;
        for (final klass in summary.classes) {
          for (final method in klass.details) {
            if (method.methodIdIndex < 0) {
              continue;
            }
            final caller = symbols.methodAt(method.methodIdIndex);
            declarations.putIfAbsent(caller, () =>
                DexGraphMethod(dexFile: name, method: method));
            if (method.codeOffset == 0) {
              continue;
            }
            if (scanned >= maxScannedMethods ||
                codeUnits + method.instructionCount > maxCodeUnits ||
                edges.length >= maxEdges) {
              truncated = true;
              break;
            }
            scanned++;
            codeUnits += method.instructionCount;
            try {
              final offset = method.codeOffset;
              final data = ByteData.sublistView(bytes);
              if (offset < 0 || offset > bytes.length - 16 ||
                  method.instructionCount > 100000 ||
                  method.instructionCount > (bytes.length - offset - 16) ~/ 2) {
                throw const FormatException('Invalid code item');
              }
              final words = List<int>.generate(method.instructionCount,
                  (i) => data.getUint16(offset + 16 + i * 2, Endian.little),
                  growable: false);
              final decoded = DalvikDisassembler.decode(words,
                  maxInstructions: 50000);
              if (decoded.truncated) {
                skipped++;
                continue;
              }
              for (final instruction in decoded.instructions) {
                if (!instruction.mnemonic.startsWith('invoke-') ||
                    instruction.mnemonic.startsWith('invoke-custom')) {
                  continue;
                }
                final targetId = words[instruction.offset + 1];
                final callee = symbols.methodAt(targetId);
                final key = '$caller\u0000$callee\u0000${instruction.mnemonic}';
                if (seenEdges.add(key)) {
                  edges.add(DexCallEdge(caller: caller, callee: callee,
                      opcode: instruction.mnemonic));
                }
                if (edges.length >= maxEdges) {
                  truncated = true;
                  break;
                }
              }
            } on FormatException {
              skipped++;
            }
          }
          if (truncated) {
            break;
          }
        }
      } on FormatException catch (error) {
        skippedDex++;
        warnings.add('$name: ${error.message}');
      }
      if (truncated) {
        break;
      }
    }
    return DexGraphResult(root: root, edges: edges,
        declarations: declarations, scannedDexFiles: dexCount,
        scannedMethods: scanned, skippedMethods: skipped,
        skippedDexFiles: skippedDex, truncated: truncated,
        warnings: warnings);
  }
}
