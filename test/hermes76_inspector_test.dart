import 'dart:typed_data';
import 'package:droidre_ai_studio/services/hermes76_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version 76 small function and register instructions', () {
    final bytes = Uint8List(192);
    final d = ByteData.sublistView(bytes);
    void u32(int at, int value) => d.setUint32(at, value, Endian.little);
    d.setUint64(0, Hermes76Inspector.magic, Endian.little);
    u32(8, 76); u32(32, 192); u32(40, 1);
    u32(52, 1); u32(60, 4);
    u32(128, 152 | (1 << 25)); u32(132, 8);
    u32(144, 4 << 24);
    bytes.setRange(148, 152, 'main'.codeUnits);
    final constant = Hermes76Inspector.opcodes.indexWhere((o) => o.$1 == 'LoadConstInt');
    final ret = Hermes76Inspector.opcodes.indexWhere((o) => o.$1 == 'Ret');
    bytes[152] = constant; bytes[153] = 1;
    d.setInt32(154, -7, Endian.little);
    bytes[158] = ret; bytes[159] = 1;
    final report = Hermes76Inspector.inspect(bytes);
    final row = (report['sampledFunctions'] as List).single as Map;
    expect(row['name'], 'main');
    final preview = row['preview'] as Map;
    final instructions = preview['instructions'] as List;
    expect(instructions.first['registerPseudocode'], 'r1 = -7');
    expect(instructions.last['registerPseudocode'], 'return r1');
    u32(8, 77);
    expect(() => Hermes76Inspector.inspect(bytes), throwsFormatException);
  });
  test('unknown or truncated op stops safely', () {
    final result = Hermes76Inspector.decode(Uint8List.fromList([255]), 0, 1);
    expect(result['partial'], true);
    expect(result['instructions'], isEmpty);
  });
}
