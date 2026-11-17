import 'dart:typed_data';
import 'package:droidre_ai_studio/services/dart_snapshot_version_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only a sized region with plausible classic header yields hash candidate', () {
    final bytes = Uint8List(64);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 0xdcdcf5f5, Endian.little);
    data.setInt64(4, 60, Endian.little);
    bytes.setRange(20, 52, '0123456789abcdef0123456789abcdef'.codeUnits);
    expect(DartSnapshotVersionEvidence.inspect(bytes, 64)['hash'],
        '0123456789abcdef0123456789abcdef');
    expect(DartSnapshotVersionEvidence.inspect(bytes, 0)['status'],
        'insufficient-sized-region');
    data.setInt64(4, 1000, Endian.little);
    expect(DartSnapshotVersionEvidence.inspect(bytes, 64)['status'], 'unsupported-length');
  });
}
