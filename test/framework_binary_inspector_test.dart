import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/framework_binary_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('observes Hermes header prefix and raw strings without claiming decompilation', () {
    final bytes = Uint8List(96);
    final data = ByteData.sublistView(bytes);
    data.setUint64(0, FrameworkBinaryInspector.hermesMagic, Endian.little);
    data.setUint32(8, 96, Endian.little);
    data.setUint32(32, bytes.length, Endian.little);
    data.setUint32(40, 1, Endian.little);
    data.setUint32(52, 3, Endian.little);
    bytes.setRange(64, 69, ascii.encode('hello'));
    final result = FrameworkBinaryInspector.inspectBytes('assets/index.android.bundle', bytes);
    expect(result['kind'], 'hermes-bytecode');
    expect(result['version'], 96);
    expect(result['functionCountHeader'], 1);
    expect(result['partial'], true);
    expect((result['strings'] as List).single['text'], 'hello');
    data.setUint32(32, 1000, Endian.little);
    expect(() => FrameworkBinaryInspector.inspectBytes('assets/index.android.bundle', bytes),
      throwsFormatException);
  });

  test('validates classic IL2CPP string range and offsets', () {
    final bytes = Uint8List(128);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, FrameworkBinaryInspector.metadataMagic, Endian.little);
    data.setUint32(4, 29, Endian.little);
    data.setUint32(24, 64, Endian.little);
    data.setUint32(28, 12, Endian.little);
    bytes.setRange(64, 75, ascii.encode('Demo.Method'));
    const name = 'assets/bin/Data/Managed/Metadata/global-metadata.dat';
    final result = FrameworkBinaryInspector.inspectBytes(name, bytes);
    expect(result['kind'], 'unity-il2cpp-metadata');
    expect((result['strings'] as List).single['offset'], 64);
    expect((result['strings'] as List).single['text'], 'Demo.Method');
    data.setUint32(28, 1000, Endian.little);
    expect(() => FrameworkBinaryInspector.inspectBytes(name, bytes), throwsFormatException);
    data.setUint32(4, 31, Endian.little);
    expect(FrameworkBinaryInspector.inspectBytes(name, bytes)['ranges'], isNull);
  });

  test('reads NativeScript declared package data and plain JS text', () {
    final result = FrameworkBinaryInspector.inspectBytes('assets/app/package.json',
      Uint8List.fromList(utf8.encode('{"name":"demo","dependencies":{"a":"1"}}')));
    expect(result['kind'], 'nativescript-text-candidate');
    expect(result['declaredDependencyNames'], ['a']);
    expect(FrameworkBinaryInspector.inspectBytes('assets/index.android.bundle',
      Uint8List.fromList(utf8.encode('function hello() {}')))['kind'],
      'react-native-text-bundle-candidate');
  });

  test('unknown binary is not interpreted as JavaScript', () {
    expect(FrameworkBinaryInspector.inspectBytes('assets/index.android.bundle',
      Uint8List.fromList([0, 1, 255, 12]))['kind'], 'unknown-binary');
    expect(() => FrameworkBinaryInspector.inspectBytes('classes.dex',
      Uint8List.fromList([1, 2])), throwsFormatException);
  });
}
