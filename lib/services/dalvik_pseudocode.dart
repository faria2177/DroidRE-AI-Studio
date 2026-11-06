import 'dalvik_disassembler.dart';

/// Conservative Java-like *viewer*, not a Java decompiler or compilable code.
/// Keeps Dalvik registers, bytecode labels and instruction offsets visible.
class DalvikPseudocode {
  const DalvikPseudocode._();

  static String render(DalvikDecodeResult decoded, {
    required String methodName,
    required String prototype,
  }) {
    final out = StringBuffer()
      ..writeln('// Approximate Java-like pseudocode; not compilable Java.')
      ..writeln('// No type inference, control-flow structuring or exception edges.')
      ..writeln('method $methodName$prototype {');
    for (final instruction in decoded.instructions) {
      final pc = instruction.offset.toRadixString(16).padLeft(4, '0');
      final label = 'L$pc';
      final name = instruction.mnemonic;
      final args = instruction.operands;
      final parts = args.split(', ');
      String statement;
      if (name == 'nop') {
        statement = '// nop';
      } else if (name == 'return-void') {
        statement = 'return;';
      } else if (name.startsWith('return')) {
        statement = 'return $args;';
      } else if (name == 'throw') {
        statement = 'throw $args;';
      } else if (name.startsWith('const') && parts.length >= 2 &&
          !name.startsWith('const-method')) {
        statement = '${parts[0]} = ${parts.sublist(1).join(', ')};';
      } else if (name.startsWith('move') && parts.length == 2) {
        statement = '${parts[0]} = ${parts[1]};';
      } else if (name.startsWith('new-instance') && parts.length == 2) {
        statement = '${parts[0]} = new ${parts[1]}(); // allocation only';
      } else if (name.startsWith('new-array') && parts.length >= 3) {
        statement = '${parts[0]} = new ${parts[2]}[${parts[1]}];';
      } else if (name.startsWith('if-')) {
        final target = parts.isNotEmpty ? parts.last.replaceAll(':', 'L') : '?';
        statement = 'if (${parts.take(parts.length - 1).join(' $name ')}) '
            'goto $target; // Dalvik condition $name';
      } else if (name.startsWith('goto')) {
        statement = 'goto ${args.replaceAll(':', 'L')};';
      } else if (name.startsWith('invoke-')) {
        statement = 'call_${name.substring(7).replaceAll('/', '_')}($args);';
      } else if (name.startsWith('iget') || name.startsWith('sget')) {
        statement = parts.length >= 2
            ? '${parts[0]} = ${parts.last};' : '// $name $args';
      } else if (name.startsWith('iput') || name.startsWith('sput')) {
        statement = parts.length >= 2
            ? '${parts.last} = ${parts.first};' : '// $name $args';
      } else if (name.startsWith('packed-switch') ||
          name.startsWith('sparse-switch')) {
        statement = '/* switch: $name $args */';
      } else if (name.endsWith('-payload')) {
        statement = '/* payload: $name $args */';
      } else {
        final arithmetic = <String, String>{
          'add': '+', 'sub': '-', 'mul': '*', 'div': '/', 'rem': '%',
          'and': '&', 'or': '|', 'xor': '^', 'shl': '<<', 'shr': '>>',
        };
        final op = name.split('-').first;
        final symbol = arithmetic[op];
        if (symbol != null && parts.length == 3) {
          statement = '${parts[0]} = ${parts[1]} $symbol ${parts[2]};';
        } else {
          statement = '// $name $args';
        }
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
