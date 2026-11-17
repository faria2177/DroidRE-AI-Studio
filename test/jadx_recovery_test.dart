import 'dart:io';

import 'package:droidre_ai_studio/models/apk_report.dart';
import 'package:droidre_ai_studio/services/framework_recovery_index.dart';
import 'package:droidre_ai_studio/services/jadx_source_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JADX arguments preserve paths and resource choice', () {
    expect(JadxSourceRecovery.arguments('C:/tool path/jadx-all.jar',
        'C:/apk path/app.apk', 'C:/out path', resources: false),
      ['-Xmx1536m', '-cp', 'C:/tool path/jadx-all.jar', 'jadx.cli.JadxCLI',
        '--threads-count', '2', '--output-dir', 'C:/out path', '--no-res', 'C:/apk path/app.apk']);
  });

  test('counts Java and resource output without treating arbitrary files as source', () async {
    final dir = await Directory.systemTemp.createTemp('jadx_inventory_');
    try {
      await Directory('${dir.path}/sources').create();
      await Directory('${dir.path}/resources').create();
      await File('${dir.path}/sources/Test.java').writeAsString('class Test {}');
      await File('${dir.path}/resources/a.xml').writeAsString('<a/>');
      await File('${dir.path}/other.txt').writeAsString('other');
      expect(await JadxSourceRecovery.inventory(dir.path), (1, 1, false));
      expect((await JadxSourceRecovery.inventory(dir.path, limit: 1)).$3, true);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('framework index distinguishes native, DEX and framework assets', () {
    final report = ApkReport.fromJson({
      'entryCount': 4, 'framework': 'Flutter (indicators found)',
      'entries': [
        {'name': 'classes.dex', 'size': 12},
        {'name': 'lib/arm64-v8a/libapp.so', 'size': 12},
        {'name': 'assets/flutter_assets/AssetManifest.bin', 'size': 12},
        {'name': 'assets/bin/Data/Managed/Metadata/global-metadata.dat', 'size': 12},
      ],
    });
    final index = FrameworkRecoveryIndex.build(report);
    final groups = index['groups'] as Map;
    expect(groups['android-dex'], ['classes.dex']);
    expect(groups['flutter-aot'], ['lib/arm64-v8a/libapp.so']);
    expect(groups['unity-metadata'], hasLength(1));
    expect(index['partial'], false);
  });
}
