import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/source_project_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports Android source ZIP, preserves assets and exports reviewed draft', () async {
    final root = await Directory.systemTemp.createTemp('source-import-');
    try {
      final archive = Archive();
      void add(String name, List<int> bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes));
      add('app/build.gradle', utf8.encode('plugins {}'));
      add('app/src/main/AndroidManifest.xml', utf8.encode('<manifest package="com.demo"/>'));
      add('app/src/main/java/Main.java', utf8.encode('class Main {}'));
      add('app/src/main/assets/logo.bin', [1,2,3]);
      add('local.properties', utf8.encode('sdk.dir=private'));
      final file = await File('${root.path}/project.zip').writeAsBytes(ZipEncoder().encode(archive));
      expect(SourceProjectImport.isSourceZip(file.path), true);
      final dest = '${root.path}/copy';
      await SourceProjectImport.extractZip(file.path, dest);
      final report = await SourceProjectImport.describe(dest, 'demo', '1');
      expect(report.sourceProject, true);
      expect(report.entryCount, 4);
      expect(report.manifest.packageName, 'com.demo');
      final zip = await SourceProjectImport.exportZip(dest, {'app/src/main/java/Main.java':'class Edited {}'});
      final result = ZipDecoder().decodeBytes(zip);
      expect(utf8.decode(result.findFile('app/src/main/java/Main.java')!.readBytes()!), 'class Edited {}');
      expect(result.findFile('app/src/main/assets/logo.bin')!.readBytes(), [1,2,3]);
      expect(await File('$dest/app/src/main/java/Main.java').readAsString(), 'class Main {}');
    } finally { await root.delete(recursive: true); }
  });
  test('rejects unsafe paths and recognizes Flutter', () {
    for (final path in ['../a','/root','C:/x','dir/CON.txt','a\\b']) {
      expect(() => SourceProjectImport.safePath(path), throwsFormatException);
    }
    expect(SourceProjectImport.framework(['pubspec.yaml','lib/main.dart']), 'Flutter source project');
  });
}
