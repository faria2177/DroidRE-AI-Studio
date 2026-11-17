import 'dalvik_disassembler.dart';

enum DalvikEdgeKind { fallthrough, branch, jump, switchCase }

class DalvikControlEdge {
  const DalvikControlEdge(this.target, this.kind, {this.caseKey});

  final int target;
  final DalvikEdgeKind kind;
  final int? caseKey;
}

class DalvikBasicBlock {
  const DalvikBasicBlock({
    required this.start,
    required this.endExclusive,
    required this.instructions,
    required this.successors,
    required this.reachable,
  });

  final int start;
  final int endExclusive;
  final int instructions;
  final List<DalvikControlEdge> successors;

  /// Normal execution only. Null means the available graph is incomplete.
  final bool? reachable;
}

class DalvikControlFlowGraph {
  const DalvikControlFlowGraph({
    required this.blocks,
    required this.partial,
    required this.warnings,
  });

  final List<DalvikBasicBlock> blocks;
  final bool partial;
  final List<String> warnings;

  static const maxSwitchEdges = 4096;
  static const maxDisplayedBlocks = 128;
  static const maxDisplayedEdges = 20;

  static String _label(int value) =>
      '0x${value.toRadixString(16).padLeft(4, '0')}';

  /// Builds normal-flow basic blocks from authoritative instruction offsets.
  /// Payloads are data, never executable blocks. Exception edges, dynamic
  /// dispatch, register/type verification and semantic loop detection are
  /// deliberately outside this graph.
  static DalvikControlFlowGraph build(
    List<int> words,
    DalvikDecodeResult decoded,
  ) {
    final warnings = <String>[];
    var partial = decoded.truncated;
    void warn(String message) {
      partial = true;
      if (warnings.length < 40) {
        warnings.add(message);
      }
    }

    final all = <int, DalvikInstruction>{
      for (final instruction in decoded.instructions)
        instruction.offset: instruction,
    };
    final code = decoded.instructions
        .where((instruction) => !instruction.mnemonic.endsWith('-payload'))
        .toList();
    final executable = <int>{for (final instruction in code) instruction.offset};
    if (words.isEmpty) {
      return const DalvikControlFlowGraph(
        blocks: [], partial: false, warnings: [],
      );
    }
    if (!executable.contains(0)) {
      warn('No decoded executable entry at 0x0000');
    }
    final leaders = <int>{if (executable.contains(0)) 0};
    final outgoing = <int, List<DalvikControlEdge>>{};
    var switchEdges = 0;

    int signed32(int index) =>
        (words[index] | (words[index + 1] << 16)).toSigned(32);

    for (var i = 0; i < code.length; i++) {
      final instruction = code[i];
      final pc = instruction.offset;
      final next = pc + instruction.width;
      final opcode = words[pc] & 0xff;
      final edges = <DalvikControlEdge>[];
      outgoing[pc] = edges;

      void add(int target, DalvikEdgeKind kind, {int? key}) {
        if (!executable.contains(target)) {
          warn('${_label(pc)} invalid or undecoded ${kind.name} '
              'target: ${_label(target)}');
          return;
        }
        edges.add(DalvikControlEdge(target, kind, caseKey: key));
        if (kind != DalvikEdgeKind.fallthrough) {
          leaders.add(target);
        }
      }

      void fallthrough() => add(next, DalvikEdgeKind.fallthrough);
      final conditional = opcode >= 0x32 && opcode <= 0x3d;
      final jump = opcode >= 0x28 && opcode <= 0x2a;
      final isSwitch = opcode == 0x2b || opcode == 0x2c;
      final terminal = (opcode >= 0x0e && opcode <= 0x11) || opcode == 0x27;
      if (conditional || jump) {
        final delta = switch (opcode) {
          0x28 => (words[pc] >> 8).toSigned(8),
          0x2a => signed32(pc + 1),
          _ => words[pc + 1].toSigned(16),
        };
        add(pc + delta, jump ? DalvikEdgeKind.jump : DalvikEdgeKind.branch);
        if (conditional) {
          fallthrough();
        }
      } else if (isSwitch) {
        final payloadPc = pc + signed32(pc + 1);
        final expected = opcode == 0x2b
            ? 'packed-switch-payload' : 'sparse-switch-payload';
        final payload = all[payloadPc];
        if (payload == null || payload.mnemonic != expected || payloadPc.isOdd) {
          warn('${_label(pc)} invalid switch payload');
        } else {
          final count = words[payloadPc + 1];
          for (var j = 0; j < count; j++) {
            if (switchEdges >= maxSwitchEdges) {
              warn('Switch edge inspection limit reached');
              break;
            }
            switchEdges++;
            final key = opcode == 0x2b
                ? (signed32(payloadPc + 2) + j).toSigned(32)
                : signed32(payloadPc + 2 + j * 2);
            final delta = opcode == 0x2b
                ? signed32(payloadPc + 4 + j * 2)
                : signed32(payloadPc + 2 + count * 2 + j * 2);
            add(pc + delta, DalvikEdgeKind.switchCase, key: key);
          }
        }
        fallthrough();
      } else if (!terminal) {
        fallthrough();
      }
      if (i + 1 < code.length &&
          (conditional || jump || isSwitch || terminal ||
              code[i + 1].offset != next)) {
        leaders.add(code[i + 1].offset);
      }
    }

    final raw = <(int, int, int, List<DalvikControlEdge>)>[];
    for (var i = 0; i < code.length;) {
      final first = i;
      i++;
      while (i < code.length && !leaders.contains(code[i].offset)) {
        i++;
      }
      final last = code[i - 1];
      raw.add((code[first].offset, last.offset + last.width,
          i - first, outgoing[last.offset]!));
    }

    final byStart = {for (final block in raw) block.$1: block};
    final visited = <int>{};
    final queue = <int>[if (byStart.containsKey(0)) 0];
    for (var i = 0; i < queue.length; i++) {
      final start = queue[i];
      if (!visited.add(start)) {
        continue;
      }
      final block = byStart[start]!;
      for (final edge in block.$4) {
        if (!byStart.containsKey(edge.target)) {
          warn('Successor is not a basic-block entry: ${_label(edge.target)}');
        } else if (!visited.contains(edge.target)) {
          queue.add(edge.target);
        }
      }
    }
    return DalvikControlFlowGraph(
      blocks: List.unmodifiable([
        for (final block in raw)
          DalvikBasicBlock(
            start: block.$1,
            endExclusive: block.$2,
            instructions: block.$3,
            successors: List.unmodifiable(block.$4),
            reachable: visited.contains(block.$1) ? true : partial ? null : false,
          ),
      ]),
      partial: partial,
      warnings: List.unmodifiable(warnings),
    );
  }

  List<String> describe() {
    final lines = <String>[
      'Normal-flow basic blocks: ${blocks.length}${partial ? ' (partial)' : ''}',
      'Exception edges excluded; reachability is normal-flow only.',
    ];
    for (final block in blocks.take(maxDisplayedBlocks)) {
      final edges = <String>[
        for (final edge in block.successors.take(maxDisplayedEdges))
          '${edge.kind.name}${edge.caseKey == null ? '' : '(${edge.caseKey})'} '
              '-> ${_label(edge.target)}'
              '${edge.target <= block.start ? ' [backward]' : ''}',
      ];
      lines.add('${_label(block.start)}..${_label(block.endExclusive)} '
          '(exclusive): ${edges.join(', ')}'
          '${block.reachable == false ? ' [not reached by normal flow]' :
              block.reachable == null ? ' [reachability unknown]' : ''}'
          '${block.successors.length > maxDisplayedEdges ? ' [more edges]' : ''}');
    }
    if (blocks.length > maxDisplayedBlocks) {
      lines.add('Block display limited to $maxDisplayedBlocks entries.');
    }
    for (final warning in warnings) {
      lines.add('WARNING: $warning');
    }
    return lines;
  }
}
