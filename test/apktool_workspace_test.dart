import 'dart:io';

import 'package:droidre_ai_studio/services/apktool_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses separate arguments without force or copy-original flags', () {
    final args = ApktoolWorkspace.decodeArguments('tool path.jar', 'original app.apk',
        'decoded dir', 'framework dir');
    expect(args, ['-Xmx1536m', '-jar', 'tool path.jar', 'd', 'original app.apk',
      '-o', 'decoded dir', '-p', 'framework dir']);
    expect(ApktoolWorkspace.buildArguments('tool.jar', 'work', 'output.apk', 'frame'),
      ['-Xmx1536m', '-jar', 'tool.jar', 'b', 'work', '-o', 'output.apk', '-p', 'frame']);
  });

  test('only decoded Smali and XML paths are editable', () {
    expect(ApktoolWorkspace.editable('smali_classes2/demo/Main.smali'), true);
    expect(ApktoolWorkspace.editable('res/layout/main.xml'), true);
    expect(ApktoolWorkspace.editable('AndroidManifest.xml'), true);
    for (final path in ['../outside.xml', 'smali/../x.smali', 'classes.dex',
      'assets/code.smali', 'apktool.yml', 'res/layout/a.exe']) {
      expect(ApktoolWorkspace.editable(path), false);
    }
  });

  test('edits only a contained text file in the workspace', () async {
    final parent = await Directory.systemTemp.createTemp('droidre_workspace_');
    try {
      final root = await Directory('${parent.path}/decoded').create();
      final folder = await Directory('${root.path}/smali').create();
      final file = await File('${folder.path}/Demo.smali').writeAsString('original');
      final outside = await File('${parent.path}/secret.xml').writeAsString('private');
      expect(await ApktoolWorkspace.readText(root.path, file.path), 'original');
      await ApktoolWorkspace.saveText(root.path, file.path, 'changed');
      expect(await file.readAsString(), 'changed');
      await expectLater(ApktoolWorkspace.saveText(root.path, outside.path, 'invalid'),
        throwsFormatException);
      expect(await outside.readAsString(), 'private');
    } finally {
      await parent.delete(recursive: true);
    }
  });
}
