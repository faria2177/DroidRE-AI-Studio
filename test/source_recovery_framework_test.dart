import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/source_recovery_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Archive makeArchive(List<String> names) {
    final a = Archive();
    for (final path in names) {
      a.addFile(ArchiveFile.string(path, 'fixture'));
    }
    return a;
  }

  (String, String) analyze(Archive source, {String frameworkHint = ''}) {
    final bundle = SourceRecoveryBundle.fromArchive(
      source,
      frameworkHint: frameworkHint,
    );
    final decoded = ZipDecoder().decodeBytes(
      bundle.zipBytes, throwOnError: true);
    String text(String name) => utf8.decode(
      decoded.files.singleWhere((item) => item.name == name).readBytes()!);
    return (
      text('framework/TECHNOLOGY_ANALYSIS.md'),
      text('REPORT.json'),
    );
  }

  test('Flutter APK indicators are not treated as recoverable Dart', () {
    final (notes, json) = analyze(makeArchive([
      'assets/flutter_assets/AssetManifest.bin',
      'lib/arm64-v8a/libflutter.so',
      'lib/arm64-v8a/libapp.so',
    ]));
    expect(notes, contains('Flutter'));
    expect(notes, contains('Original Dart source is not recovered'));
    expect(notes, contains('libapp.so'));
    final report = jsonDecode(json) as Map<String, dynamic>;
    expect(report['detectedFramework'], 'Flutter');
    expect(report['nativeLibrariesFound'], 2);
    expect(report['schemaVersion'], 2);
  });

  test('React Native bundle gets JavaScript-specific limitations', () {
    final (notes, json) = analyze(makeArchive([
      'assets/index.android.bundle',
    ]));
    expect(notes, contains('React Native'));
    expect(notes, contains('source maps'));
    expect(jsonDecode(json)['detectedFramework'], 'React Native');
  });

  test('Unity and NativeScript are classified without source claims', () {
    final (unityNotes, _) = analyze(makeArchive([
      'lib/arm64-v8a/libunity.so',
    ]));
    expect(unityNotes, contains('Unity C# source'));
    final (nsNotes, _) = analyze(makeArchive([
      'lib/arm64-v8a/libnativescript.so',
    ]));
    expect(nsNotes, contains('NativeScript'));
  });

  test('Native/unknown emits non-compilable warning', () {
    final (notes, report) = analyze(makeArchive([
      'res/raw/readme.txt',
    ]));
    expect(notes, contains('NON-COMPILABLE'));
    expect(jsonDecode(report)['detectedFramework'],
        'Android DEX / unknown framework');
  });
}
