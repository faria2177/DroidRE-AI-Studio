import 'dalvik_control_flow_graph.dart';
import 'dalvik_disassembler.dart';

/// Conservative Java-like viewer, not compilable Java. Original registers,
/// descriptor references, and instruction offsets stay visible.
class DalvikPseudocode {
  const DalvikPseudocode._();

  static const _conditions = {
    'eq': '==', 'ne': '!=', 'lt': '<', 'ge': '>=', 'gt': '>', 'le': '<=',
  };
  static const _arithmetic = {
    'add': '+', 'sub': '-', 'rsub': '-', 'mul': '*', 'div': '/',
    'rem': '%', 'and': '&', 'or': '|', 'xor': '^', 'shl': '<<',
    'shr': '>>', 'ushr': '>>>',
  };

  static String _label(int offset) =>
      'L${offset.toRadixString(16).padLeft(4, '0')}';

  static String _target(String operand) =>
      operand.startsWith(':') ? 'L${operand.substring(1)}' : operand;

  static String _literal(String operand) =>
      operand.startsWith('#') ? operand.substring(1) : operand;

  static bool _producer(String mnemonic) =>
      mnemonic.startsWith('invoke-') || mnemonic.startsWith('filled-new-array');

  static bool _result(String mnemonic) =>
      mnemonic == 'move-result' || mnemonic == 'move-result-wide' ||
      mnemonic == 'move-result-object';

  static String render(DalvikDecodeResult decoded, {
    required String methodName,
    required String prototype,
    DalvikControlFlowGraph? graph,
  }) {
    final out = StringBuffer()
      ..writeln('// Approximate Java-like pseudocode; not compilable Java.')
      ..writeln('// Registers and labels preserved; no full type inference or exception flow.')
      ..writeln('method $methodName$prototype {');
    final leaders = <int>{for (final block in graph?.blocks ?? <DalvikBasicBlock>[]) block.start};
    final instructions = decoded.instructions;
    bool adjacentResult(int index) {
      if (index < 0 || index + 1 >= instructions.length) {
        return false;
      }
      final current = instructions[index];
      final next = instructions[index + 1];
      // Do not bind across a branch entry or an incomplete control graph.
      return graph != null && !graph.partial &&
          _producer(current.mnemonic) && _result(next.mnemonic) &&
          next.offset == current.offset + current.width &&
          !leaders.contains(next.offset);
    }

    for (var i = 0; i < instructions.length; i++) {
      final instruction = instructions[i];
      final pc = instruction.offset.toRadixString(16).padLeft(4, '0');
      final label = _label(instruction.offset);
      final name = instruction.mnemonic;
      final args = instruction.operands;
      final parts = args.split(', ');
      final op = name.split('-').first;
      final symbol = _arithmetic[op];
      String statement;

      if (name.endsWith('-payload')) {
        statement = '/* non-executable payload: $name $args */';
      } else if (name == 'nop') {
        statement = '// nop';
      } else if (name == 'return-void') {
        statement = 'return;';
      } else if (name.startsWith('return')) {
        statement = 'return $args;';
      } else if (name == 'throw') {
        statement = 'throw $args;';
      } else if (_result(name)) {
        statement = adjacentResult(i - 1)
            ? '$args = result_${_label(instructions[i - 1].offset)}; // $name'
            : '// $name $args: result producer not safely linked';
      } else if (name == 'move-exception') {
        statement = '$args = caught_exception; // handler entry, type unknown';
      } else if (_producer(name)) {
        // Raw register list and method descriptor avoid guessing parameter types.
        final call = name.startsWith('invoke-')
            ? 'call_${name.substring(7).replaceAll('/', '_')}($args)'
            : 'filled_array($args)';
        statement = adjacentResult(i) ? 'result_$label = $call;' : '$call;';
      } else if (name == 'const-string' || name == 'const-string/jumbo') {
        final separator = args.indexOf(', ');
        statement = separator < 0 ? '// $name $args' :
            '${args.substring(0, separator)} = ${args.substring(separator + 2)};';
      } else if (name.startsWith('const') && parts.length == 2) {
        statement = '${parts[0]} = ${_literal(parts[1])}; // $name';
      } else if (name.startsWith('move') && parts.length == 2) {
        statement = '${parts[0]} = ${parts[1]};';
      } else if (name == 'new-instance' && parts.length == 2) {
        statement = '${parts[0]} = allocate(${parts[1]}); // constructor not implied';
      } else if (name == 'new-array' && parts.length == 3) {
        statement = '${parts[0]} = new_array(${parts[2]}, ${parts[1]});';
      } else if (name == 'array-length' && parts.length == 2) {
        statement = '${parts[0]} = ${parts[1]}.length;';
      } else if (name == 'check-cast' && parts.length == 2) {
        statement = '${parts[0]} = (${parts[1]}) ${parts[0]};';
      } else if (name == 'instance-of' && parts.length == 3) {
        statement = '${parts[0]} = (${parts[1]} instanceof ${parts[2]}) ? 1 : 0;';
      } else if (name.startsWith('if-')) {
        final condition = name.substring(3);
        final zero = condition.endsWith('z');
        final comparison = _conditions[zero
            ? condition.substring(0, condition.length - 1) : condition];
        statement = comparison == null || parts.length != (zero ? 2 : 3)
            ? '// $name $args'
            : 'if (${parts[0]} $comparison ${zero ? '0' : parts[1]}) '
              'goto ${_target(parts.last)}; // $name; register types unknown';
      } else if (name.startsWith('goto')) {
        statement = 'goto ${_target(args)};';
      } else if (name.startsWith('iget') && parts.length == 3) {
        statement = '${parts[0]} = field(${parts[1]}, ${parts[2]});';
      } else if (name.startsWith('iput') && parts.length == 3) {
        statement = 'field(${parts[1]}, ${parts[2]}) = ${parts[0]};';
      } else if (name.startsWith('sget') && parts.length == 2) {
        statement = '${parts[0]} = ${parts[1]};';
      } else if (name.startsWith('sput') && parts.length == 2) {
        statement = '${parts[1]} = ${parts[0]};';
      } else if (name.startsWith('aget') && parts.length == 3) {
        statement = '${parts[0]} = ${parts[1]}[${parts[2]}];';
      } else if (name.startsWith('aput') && parts.length == 3) {
        statement = '${parts[1]}[${parts[2]}] = ${parts[0]};';
      } else if (name == 'packed-switch' || name == 'sparse-switch') {
        statement = '/* switch: $name $args; see Dalvik control-flow graph */';
      } else if (symbol != null && parts.length == 2 && name.endsWith('/2addr')) {
        statement = '${parts[0]} = ${parts[0]} $symbol ${parts[1]}; // $name';
      } else if (symbol != null && parts.length == 3) {
        final left = op == 'rsub' ? _literal(parts[2]) : parts[1];
        final right = op == 'rsub' ? parts[1] : _literal(parts[2]);
        statement = '${parts[0]} = $left $symbol $right; // $name';
      } else if ((op == 'neg' || op == 'not') && parts.length == 2) {
        statement = '${parts[0]} = ${op == 'neg' ? '-' : '~'}${parts[1]}; // $name';
      } else {
        statement = '// $name $args';
      }
      out.writeln('  $label: $statement // Dalvik @0x$pc');
    }
    if (decoded.truncated) {
      out.writeln('  // Display limit reached; the remaining code is not shown.');
    }
    out.writeln('}');
    return out.toString();
  }
}
