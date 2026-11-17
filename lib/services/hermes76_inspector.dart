import 'dart:convert';
import 'dart:typed_data';

/// Version-locked HBC 76 static instruction preview.
/// Opcode order/operands derived from hbctool v0.1.5 (MIT);
/// upstream license is retained in third_party/licenses/hbctool-MIT.txt.
class Hermes76Inspector {
  const Hermes76Inspector._();
  static const magic = 0x1f1903c103bc1fc6;
  static const maxFunctions = 64;
  static const maxInstructions = 128;
  static const opcodes = <(String, List<String>)>[
    ('NewObjectWithBuffer', ['Reg8', 'UInt16', 'UInt16', 'UInt16', 'UInt16']),
    ('NewObjectWithBufferLong', ['Reg8', 'UInt16', 'UInt16', 'UInt32', 'UInt32']),
    ('NewObject', ['Reg8']),
    ('NewObjectWithParent', ['Reg8', 'Reg8']),
    ('NewArrayWithBuffer', ['Reg8', 'UInt16', 'UInt16', 'UInt16']),
    ('NewArrayWithBufferLong', ['Reg8', 'UInt16', 'UInt16', 'UInt32']),
    ('NewArray', ['Reg8', 'UInt16']),
    ('Mov', ['Reg8', 'Reg8']),
    ('MovLong', ['Reg32', 'Reg32']),
    ('Negate', ['Reg8', 'Reg8']),
    ('Not', ['Reg8', 'Reg8']),
    ('BitNot', ['Reg8', 'Reg8']),
    ('TypeOf', ['Reg8', 'Reg8']),
    ('Eq', ['Reg8', 'Reg8', 'Reg8']),
    ('StrictEq', ['Reg8', 'Reg8', 'Reg8']),
    ('Neq', ['Reg8', 'Reg8', 'Reg8']),
    ('StrictNeq', ['Reg8', 'Reg8', 'Reg8']),
    ('Less', ['Reg8', 'Reg8', 'Reg8']),
    ('LessEq', ['Reg8', 'Reg8', 'Reg8']),
    ('Greater', ['Reg8', 'Reg8', 'Reg8']),
    ('GreaterEq', ['Reg8', 'Reg8', 'Reg8']),
    ('Add', ['Reg8', 'Reg8', 'Reg8']),
    ('AddN', ['Reg8', 'Reg8', 'Reg8']),
    ('Mul', ['Reg8', 'Reg8', 'Reg8']),
    ('MulN', ['Reg8', 'Reg8', 'Reg8']),
    ('Div', ['Reg8', 'Reg8', 'Reg8']),
    ('DivN', ['Reg8', 'Reg8', 'Reg8']),
    ('Mod', ['Reg8', 'Reg8', 'Reg8']),
    ('Sub', ['Reg8', 'Reg8', 'Reg8']),
    ('SubN', ['Reg8', 'Reg8', 'Reg8']),
    ('LShift', ['Reg8', 'Reg8', 'Reg8']),
    ('RShift', ['Reg8', 'Reg8', 'Reg8']),
    ('URshift', ['Reg8', 'Reg8', 'Reg8']),
    ('BitAnd', ['Reg8', 'Reg8', 'Reg8']),
    ('BitXor', ['Reg8', 'Reg8', 'Reg8']),
    ('BitOr', ['Reg8', 'Reg8', 'Reg8']),
    ('InstanceOf', ['Reg8', 'Reg8', 'Reg8']),
    ('IsIn', ['Reg8', 'Reg8', 'Reg8']),
    ('GetEnvironment', ['Reg8', 'UInt8']),
    ('StoreToEnvironment', ['Reg8', 'UInt8', 'Reg8']),
    ('StoreToEnvironmentL', ['Reg8', 'UInt16', 'Reg8']),
    ('StoreNPToEnvironment', ['Reg8', 'UInt8', 'Reg8']),
    ('StoreNPToEnvironmentL', ['Reg8', 'UInt16', 'Reg8']),
    ('LoadFromEnvironment', ['Reg8', 'Reg8', 'UInt8']),
    ('LoadFromEnvironmentL', ['Reg8', 'Reg8', 'UInt16']),
    ('GetGlobalObject', ['Reg8']),
    ('GetNewTarget', ['Reg8']),
    ('CreateEnvironment', ['Reg8']),
    ('DeclareGlobalVar', ['UInt32:S']),
    ('GetByIdShort', ['Reg8', 'Reg8', 'UInt8', 'UInt8:S']),
    ('GetById', ['Reg8', 'Reg8', 'UInt8', 'UInt16:S']),
    ('GetByIdLong', ['Reg8', 'Reg8', 'UInt8', 'UInt32:S']),
    ('TryGetById', ['Reg8', 'Reg8', 'UInt8', 'UInt16:S']),
    ('TryGetByIdLong', ['Reg8', 'Reg8', 'UInt8', 'UInt32:S']),
    ('PutById', ['Reg8', 'Reg8', 'UInt8', 'UInt16:S']),
    ('PutByIdLong', ['Reg8', 'Reg8', 'UInt8', 'UInt32:S']),
    ('TryPutById', ['Reg8', 'Reg8', 'UInt8', 'UInt16:S']),
    ('TryPutByIdLong', ['Reg8', 'Reg8', 'UInt8', 'UInt32:S']),
    ('PutNewOwnByIdShort', ['Reg8', 'Reg8', 'UInt8:S']),
    ('PutNewOwnById', ['Reg8', 'Reg8', 'UInt16:S']),
    ('PutNewOwnByIdLong', ['Reg8', 'Reg8', 'UInt32:S']),
    ('PutNewOwnNEById', ['Reg8', 'Reg8', 'UInt16:S']),
    ('PutNewOwnNEByIdLong', ['Reg8', 'Reg8', 'UInt32:S']),
    ('PutOwnByIndex', ['Reg8', 'Reg8', 'UInt8']),
    ('PutOwnByIndexL', ['Reg8', 'Reg8', 'UInt32']),
    ('PutOwnByVal', ['Reg8', 'Reg8', 'Reg8', 'UInt8']),
    ('DelById', ['Reg8', 'Reg8', 'UInt16:S']),
    ('DelByIdLong', ['Reg8', 'Reg8', 'UInt32:S']),
    ('GetByVal', ['Reg8', 'Reg8', 'Reg8']),
    ('PutByVal', ['Reg8', 'Reg8', 'Reg8']),
    ('DelByVal', ['Reg8', 'Reg8', 'Reg8']),
    ('PutOwnGetterSetterByVal', ['Reg8', 'Reg8', 'Reg8', 'Reg8', 'UInt8']),
    ('GetPNameList', ['Reg8', 'Reg8', 'Reg8', 'Reg8']),
    ('GetNextPName', ['Reg8', 'Reg8', 'Reg8', 'Reg8', 'Reg8']),
    ('Call', ['Reg8', 'Reg8', 'UInt8']),
    ('Construct', ['Reg8', 'Reg8', 'UInt8']),
    ('Call1', ['Reg8', 'Reg8', 'Reg8']),
    ('CallDirect', ['Reg8', 'UInt8', 'UInt16']),
    ('Call2', ['Reg8', 'Reg8', 'Reg8', 'Reg8']),
    ('Call3', ['Reg8', 'Reg8', 'Reg8', 'Reg8', 'Reg8']),
    ('Call4', ['Reg8', 'Reg8', 'Reg8', 'Reg8', 'Reg8', 'Reg8']),
    ('CallLong', ['Reg8', 'Reg8', 'UInt32']),
    ('ConstructLong', ['Reg8', 'Reg8', 'UInt32']),
    ('CallDirectLongIndex', ['Reg8', 'UInt8', 'UInt32']),
    ('CallBuiltin', ['Reg8', 'UInt8', 'UInt8']),
    ('Ret', ['Reg8']),
    ('Catch', ['Reg8']),
    ('DirectEval', ['Reg8', 'Reg8']),
    ('Throw', ['Reg8']),
    ('ThrowIfUndefinedInst', ['Reg8']),
    ('Debugger', []),
    ('AsyncBreakCheck', []),
    ('ProfilePoint', ['UInt16']),
    ('Unreachable', []),
    ('CreateClosure', ['Reg8', 'Reg8', 'UInt16']),
    ('CreateClosureLongIndex', ['Reg8', 'Reg8', 'UInt32']),
    ('CreateGeneratorClosure', ['Reg8', 'Reg8', 'UInt16']),
    ('CreateGeneratorClosureLongIndex', ['Reg8', 'Reg8', 'UInt32']),
    ('CreateThis', ['Reg8', 'Reg8', 'Reg8']),
    ('SelectObject', ['Reg8', 'Reg8', 'Reg8']),
    ('LoadParam', ['Reg8', 'UInt8']),
    ('LoadParamLong', ['Reg8', 'UInt32']),
    ('LoadConstUInt8', ['Reg8', 'UInt8']),
    ('LoadConstInt', ['Reg8', 'Imm32']),
    ('LoadConstDouble', ['Reg8', 'Double']),
    ('LoadConstString', ['Reg8', 'UInt16:S']),
    ('LoadConstStringLongIndex', ['Reg8', 'UInt32:S']),
    ('LoadConstUndefined', ['Reg8']),
    ('LoadConstNull', ['Reg8']),
    ('LoadConstTrue', ['Reg8']),
    ('LoadConstFalse', ['Reg8']),
    ('LoadConstZero', ['Reg8']),
    ('CoerceThisNS', ['Reg8', 'Reg8']),
    ('LoadThisNS', ['Reg8']),
    ('ToNumber', ['Reg8', 'Reg8']),
    ('ToInt32', ['Reg8', 'Reg8']),
    ('AddEmptyString', ['Reg8', 'Reg8']),
    ('GetArgumentsPropByVal', ['Reg8', 'Reg8', 'Reg8']),
    ('GetArgumentsLength', ['Reg8', 'Reg8']),
    ('ReifyArguments', ['Reg8']),
    ('CreateRegExp', ['Reg8', 'UInt32:S', 'UInt32:S', 'UInt32']),
    ('SwitchImm', ['Reg8', 'UInt32', 'Addr32', 'UInt32', 'UInt32']),
    ('StartGenerator', []),
    ('ResumeGenerator', ['Reg8', 'Reg8']),
    ('CompleteGenerator', []),
    ('CreateGenerator', ['Reg8', 'Reg8', 'UInt16']),
    ('CreateGeneratorLongIndex', ['Reg8', 'Reg8', 'UInt32']),
    ('IteratorBegin', ['Reg8', 'Reg8']),
    ('IteratorNext', ['Reg8', 'Reg8', 'Reg8']),
    ('IteratorClose', ['Reg8', 'UInt8']),
    ('Jmp', ['Addr8']),
    ('JmpLong', ['Addr32']),
    ('JmpTrue', ['Addr8', 'Reg8']),
    ('JmpTrueLong', ['Addr32', 'Reg8']),
    ('JmpFalse', ['Addr8', 'Reg8']),
    ('JmpFalseLong', ['Addr32', 'Reg8']),
    ('JmpUndefined', ['Addr8', 'Reg8']),
    ('JmpUndefinedLong', ['Addr32', 'Reg8']),
    ('SaveGenerator', ['Addr8']),
    ('SaveGeneratorLong', ['Addr32']),
    ('JLess', ['Addr8', 'Reg8', 'Reg8']),
    ('JLessLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotLess', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotLessLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JLessN', ['Addr8', 'Reg8', 'Reg8']),
    ('JLessNLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotLessN', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotLessNLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JLessEqual', ['Addr8', 'Reg8', 'Reg8']),
    ('JLessEqualLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotLessEqual', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotLessEqualLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JLessEqualN', ['Addr8', 'Reg8', 'Reg8']),
    ('JLessEqualNLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotLessEqualN', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotLessEqualNLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JGreater', ['Addr8', 'Reg8', 'Reg8']),
    ('JGreaterLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotGreater', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotGreaterLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JGreaterN', ['Addr8', 'Reg8', 'Reg8']),
    ('JGreaterNLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotGreaterN', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotGreaterNLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JGreaterEqual', ['Addr8', 'Reg8', 'Reg8']),
    ('JGreaterEqualLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotGreaterEqual', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotGreaterEqualLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JGreaterEqualN', ['Addr8', 'Reg8', 'Reg8']),
    ('JGreaterEqualNLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotGreaterEqualN', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotGreaterEqualNLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JEqual', ['Addr8', 'Reg8', 'Reg8']),
    ('JEqualLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JNotEqual', ['Addr8', 'Reg8', 'Reg8']),
    ('JNotEqualLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JStrictEqual', ['Addr8', 'Reg8', 'Reg8']),
    ('JStrictEqualLong', ['Addr32', 'Reg8', 'Reg8']),
    ('JStrictNotEqual', ['Addr8', 'Reg8', 'Reg8']),
    ('JStrictNotEqualLong', ['Addr32', 'Reg8', 'Reg8']),
  ];

  static Map<String, Object?> inspect(Uint8List bytes) {
    if (bytes.length < 148 || bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('Invalid HBC 76 file length');
    }
    final d = ByteData.sublistView(bytes);
    int u32(int at) => d.getUint32(at, Endian.little);
    if (d.getUint64(0, Endian.little) != magic || u32(8) != 76) {
      throw const FormatException('Only HBC version 76 is decoded');
    }
    final declared = u32(32);
    if (declared < 148 || declared > bytes.length) {
      throw const FormatException('Invalid HBC declared length');
    }
    final end = declared - 20; // Exclude the version-era SHA-1 footer.
    final count = u32(40);
    final global = u32(36);
    if (count == 0 || global >= count || count > (end - 128) ~/ 16) {
      throw const FormatException('Invalid HBC function table');
    }
    // Only the standard no-CJS layout is interpreted here.
    if (u32(88) != 0) {
      throw const FormatException('CJS layout is unsupported by this preview');
    }
    var cursor = 128;
    int skip(int n) {
      if (n < 0 || n > end - cursor) {
        throw const FormatException('HBC segment outside declared file');
      }
      final start = cursor;
      cursor = (cursor + n + 3) & ~3;
      if (cursor > end) {
        throw const FormatException('HBC alignment exceeds file');
      }
      return start;
    }
    skip(count * 16);
    skip(u32(44) * 4);
    skip(u32(48) * 4);
    final stringCount = u32(52);
    final strings = skip(stringCount * 4);
    final overflowCount = u32(56);
    final overflow = skip(overflowCount * 8);
    final storageBytes = u32(60);
    final storage = skip(storageBytes);
    skip(u32(72));
    skip(u32(76));
    skip(u32(80));
    skip(u32(64) * 8);
    skip(u32(68));
    final codeStart = cursor;
    final debugOffset = u32(92);
    final codeEnd = debugOffset == 0 ? end : debugOffset;
    if (codeEnd < codeStart || codeEnd > end) {
      throw const FormatException('HBC debug offset outside code range');
    }
    String name(int id) {
      if (id >= stringCount) {
        return '<unresolved string $id>';
      }
      final word = u32(strings + id * 4);
      final wide = (word & 1) != 0;
      var at = (word >> 1) & 0x7fffff;
      var length = word >> 24;
      if (length == 255) {
        if (at >= overflowCount) {
          return '<invalid overflow string>';
        }
        length = u32(overflow + at * 8 + 4);
        at = u32(overflow + at * 8);
      }
      final size = length * (wide ? 2 : 1);
      if (at > storageBytes || size > storageBytes - at) {
        return '<invalid string range>';
      }
      final units = length.clamp(0, 128).toInt();
      final value = wide ? String.fromCharCodes(List.generate(units,
          (i) => d.getUint16(storage + at + i * 2, Endian.little))) :
          utf8.decode(bytes.sublist(storage + at, storage + at + units),
            allowMalformed: true);
      return units != length ? '$value…' : value;
    }
    final ids = <int>{global, ...List.generate(count.clamp(0, maxFunctions - 1).toInt(), (i) => i)};
    final rows = <Map<String, Object?>>[];
    var previews = 0;
    for (final id in ids) {
      final at = 128 + id * 16;
      final w0 = u32(at), w1 = u32(at + 4), w2 = u32(at + 8);
      final flags = bytes[at + 15];
      if ((flags & 0x20) != 0) {
        rows.add({'id': id, 'status': 'overflow-header-unsupported'});
        continue;
      }
      final start = w0 & 0x1ffffff;
      final size = w1 & 0x7fff;
      final nameId = w1 >> 15;
      if (start < codeStart || start > codeEnd || size > codeEnd - start) {
        rows.add({'id': id, 'status': 'invalid-function-range'});
        continue;
      }
      final row = <String, Object?>{'id': id, 'nameStringId': nameId,
        'name': name(nameId), 'fileOffset': start, 'bytecodeBytes': size,
        'parameters': w0 >> 25, 'frameSize': w2 >> 25, 'flags': flags,
        'status': 'small-header-observed'};
      if (previews < 8 && size > 0) {
        row['preview'] = decode(bytes, start, size);
        previews++;
      }
      rows.add(row);
    }
    return {'version': 76, 'globalFunction': global, 'functionCount': count,
      'sampledFunctions': rows, 'partial': true,
      'note': 'Version-locked linear instruction preview. No overflow headers, CJS, full CFG, switch table or original JS recovery.'};
  }

  static Map<String, Object?> decode(Uint8List bytes, int start, int size) {
    if (start < 0 || size < 0 || start > bytes.length || size > bytes.length - start) {
      throw const FormatException('Invalid instruction range');
    }
    final d = ByteData.sublistView(bytes);
    final end = start + size;
    var at = start;
    final result = <Map<String, Object?>>[];
    String? warning;
    while (at < end && result.length < maxInstructions) {
      final pos = at;
      final opcode = bytes[at++];
      if (opcode >= opcodes.length) {
        warning = 'Unknown opcode at ${pos - start}; stopped';
        break;
      }
      final (name, operands) = opcodes[opcode];
      final args = <String>[];
      for (final operand in operands) {
        final type = operand.split(':').first;
        final width = switch (type) {
          'Reg8' || 'UInt8' || 'Addr8' => 1,
          'UInt16' => 2,
          'Reg32' || 'UInt32' || 'Addr32' || 'Imm32' => 4,
          'Double' => 8,
          _ => 0,
        };
        if (width == 0 || width > end - at) {
          warning = 'Truncated or unsupported operand at ${pos - start}; stopped';
          break;
        }
        final num value = switch (type) {
          'Addr8' => d.getInt8(at),
          'Addr32' || 'Imm32' => d.getInt32(at, Endian.little),
          'Double' => d.getFloat64(at, Endian.little),
          _ => switch (width) {
            1 => bytes[at], 2 => d.getUint16(at, Endian.little),
            _ => d.getUint32(at, Endian.little),
          },
        };
        args.add(type.startsWith('Reg') ? 'r$value' :
          operand.endsWith(':S') ? 'string[$value]' : value.toString());
        at += width;
      }
      if (warning != null) {
        break;
      }
      String? pseudo;
      if (name == 'Mov' || name == 'MovLong' || name == 'LoadConstInt' ||
          name == 'LoadConstUInt8' || name == 'LoadConstDouble') {
        pseudo = '${args[0]} = ${args[1]}';
      } else if (name == 'Ret') {
        pseudo = 'return ${args[0]}';
      } else if (const {'LoadConstUndefined','LoadConstNull','LoadConstTrue',
          'LoadConstFalse','LoadConstZero'}.contains(name)) {
        final literal = name == 'LoadConstZero' ? '0' : name.substring(9).toLowerCase();
        pseudo = '${args[0]} = $literal';
      } else if (name == 'Add' || name == 'AddN' || name == 'Sub' || name == 'SubN' ||
          name == 'Mul' || name == 'MulN' || name == 'Div' || name == 'DivN') {
        final operator = name.startsWith('Add') ? '+' : name.startsWith('Sub') ? '-' :
            name.startsWith('Mul') ? '*' : '/';
        pseudo = '${args[0]} = ${args[1]} $operator ${args[2]}';
      }
      result.add({'offset': pos - start, 'opcode': opcode, 'mnemonic': name,
        'operands': args, if (pseudo != null) 'registerPseudocode': pseudo});
      // SwitchImm involves an out-of-line jump table; don't guess targets.
    }
    return {'instructions': result, 'partial': warning != null || at < end,
      if (warning != null) 'warning': warning,
      'scope': 'Linear register hints, not reconstructed JavaScript control flow.'};
  }
}
