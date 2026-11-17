import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:droidre_ai_studio/services/apk_asset_editor.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fixture({bool binary = false, String extra = ''}) {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('AndroidManifest.xml', [1, 2, 3]))
    ..addFile(ArchiveFile.bytes('classes.dex', [4, 5, 6]))
    ..addFile(ArchiveFile.bytes('assets/config.json',
        binary ? [0, 1] : utf8.encode('{"message":"old"}')))
    ..addFile(ArchiveFile.bytes('META-INF/OLD.SF', [7]))
    ..addFile(ArchiveFile.bytes('META-INF/OLD.RSA', [8]))
    ..addFile(ArchiveFile.bytes('META-INF/MANIFEST.MF', [9]))
    ..addFile(ArchiveFile.bytes('META-INF/NOTICE', [10]));
  if (extra.isNotEmpty) {
    archive.addFile(ArchiveFile.bytes(extra, [11]));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('edits one asset, verifies retained payloads and clears old signatures', () {
    final input = fixture();
    final original = sha256.convert(input);
    final result = ApkAssetEditor.rebuildBytes(input, 'assets/config.json',
        '{"message":"new"}');
    final archive = ZipDecoder().decodeBytes(result.bytes, throwOnError: true);
    final map = {for (final f in archive.files) f.name: f.readBytes()!};
    expect(utf8.decode(map['assets/config.json']!), '{"message":"new"}');
    expect(map['classes.dex'], [4, 5, 6]);
    expect(map['AndroidManifest.xml'], [1, 2, 3]);
    expect(map['META-INF/NOTICE'], [10]);
    expect(map.keys, isNot(contains('META-INF/OLD.RSA')));
    expect(map.keys, isNot(contains('META-INF/MANIFEST.MF')));
    expect(result.unchanged, 3);
    expect(result.removedSignatures, 3);
    expect(result.beforeHash, isNot(result.afterHash));
    expect(sha256.convert(input), original);
  });

  test('rejects missing, compiled and unsafe paths', () {
    for (final name in ['classes.dex', 'AndroidManifest.xml',
      'assets/../config.json', 'assets/missing.json']) {
      expect(() => ApkAssetEditor.rebuildBytes(fixture(), name, '{}'),
          throwsFormatException);
    }
    expect(() => ApkAssetEditor.rebuildBytes(fixture(extra: '../bad.txt'),
        'assets/config.json', '{}'), throwsFormatException);
  });

  test('rejects invalid JSON, binary asset and unchanged content', () {
    expect(() => ApkAssetEditor.rebuildBytes(fixture(), 'assets/config.json', '{'),
        throwsFormatException);
    expect(() => ApkAssetEditor.rebuildBytes(fixture(binary: true),
        'assets/config.json', '{}'), throwsFormatException);
    expect(() => ApkAssetEditor.rebuildBytes(fixture(), 'assets/config.json',
        '{"message":"old"}'), throwsFormatException);
  });

  test('rejects oversized text', () {
    expect(() => ApkAssetEditor.rebuildBytes(fixture(), 'assets/config.json',
        List.filled(ApkAssetEditor.maxAsset + 1, 'x').join()), throwsFormatException);
  });
}
