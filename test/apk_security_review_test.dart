import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/apk_analyzer.dart';
import 'package:droidre_ai_studio/services/apk_security_review.dart';
import 'package:droidre_ai_studio/services/apk_signature_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List signedFixture({bool bad = false}) {
  // Synthetic signing block and empty central directory; no genuine signature.
  final bytes = Uint8List(66);
  final d = ByteData.sublistView(bytes);
  d.setUint64(0, bad ? 35 : 36, Endian.little);
  d.setUint64(8, 4, Endian.little);
  d.setUint32(16, 0x7109871a, Endian.little);
  d.setUint64(20, 36, Endian.little);
  bytes.setRange(28, 44, 'APK Sig Block 42'.codeUnits);
  d.setUint32(44, 0x06054b50, Endian.little);
  d.setUint32(60, 44, Endian.little);
  return bytes;
}

void main() {
  test('recognizes v2 ID without authenticating signing payload', () {
    final evidence = ApkSignatureInspector.inspectBytes(signedFixture());
    expect(evidence.status, 'block-observed');
    expect(evidence.schemes, ['APK v2']);
    expect(evidence.toJson()['cryptographicallyVerified'], false);
  });

  test('malformed block and truncated ZIP are unknown', () {
    expect(ApkSignatureInspector.inspectBytes(signedFixture(bad: true)).status, 'unknown');
    expect(ApkSignatureInspector.inspectBytes(Uint8List(10)).status, 'unknown');
  });

  test('unsigned ZIP has no observed signing block', () {
    final zip = Uint8List.fromList(ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.string('test', 'text'))));
    expect(ApkSignatureInspector.inspectBytes(zip).status, 'no-block-observed');
  });

  test('reviews declarations and compares same-size changed payloads', () async {
    final dir = await Directory.systemTemp.createTemp('droidre_review_');
    try {
      Future<String> fixture(String id, String text, bool permission) async {
        final zip = Archive()
          ..addFile(ArchiveFile.string('AndroidManifest.xml',
              '<manifest package="demo.app">${permission ? '<uses-permission android:name="android.permission.CAMERA"/>' : ''}</manifest>'))
          ..addFile(ArchiveFile.string('assets/value.txt', text))
          ..addFile(ArchiveFile.string('assets/same.txt', 'same'));
        final path = '${dir.path}/$id.apk';
        await File(path).writeAsBytes(ZipEncoder().encode(zip));
        return path;
      }
      final before = await ApkAnalyzer.inspect(path: await fixture('old', 'ABC', false),
          displayName: 'old.apk', id: 'old');
      final after = await ApkAnalyzer.inspect(path: await fixture('new', 'XYZ', true),
          displayName: 'new.apk', id: 'new');
      final review = await ApkSecurityReview.inspect(after);
      expect(review['permissionReview'], hasLength(1));
      final diff = await ApkSecurityReview.compare(before, after);
      expect(diff['permissionsAdded'], ['android.permission.CAMERA']);
      expect(diff['samePackage'], true);
      expect(diff['verifiedUnchanged'], 1);
      expect((diff['differences'] as List).whereType<Map>()
          .singleWhere((item) => item['path'] == 'assets/value.txt')['status'], 'changed-content');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
