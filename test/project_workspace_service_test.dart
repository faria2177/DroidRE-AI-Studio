import 'dart:io';

import 'package:droidre_ai_studio/services/project_workspace_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated directories do not consume traversal budget', () async {
    final root = await Directory.systemTemp.createTemp('prune_');
    try {
      final build = await Directory('${root.path}/build').create();
      for (var i = 0; i < 30; i++) {
        await File('${build.path}/$i.java').writeAsString('generated');
      }
      await File('${root.path}/Main.java').writeAsString('source');
      final result = await ProjectWorkspaceService.listBounded(root.path, entryLimit: 4);
      expect(result.paths, ['Main.java']);
      expect(result.partial, false);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('lists supported source paths and skips hidden build files', () async {
    final root = await Directory.systemTemp.createTemp('workspace_test_');
    try {
      await File('${root.path}/Main.cs').writeAsString('class Main {}');
      await File('${root.path}/binary.dll').writeAsString('binary');
      await Directory('${root.path}/build').create();
      await File('${root.path}/build/Generated.cs').writeAsString('generated');
      final result = await ProjectWorkspaceService.list(root.path);
      expect(result.paths, ['Main.cs']);
      expect(await ProjectWorkspaceService.read(root.path, 'Main.cs'), 'class Main {}');
      expect(result.partial, false);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('strict source path and text bounds', () async {
    final root = await Directory.systemTemp.createTemp('workspace_bounds_');
    try {
      await File('${root.path}/large.java').writeAsString(
          List.filled(ProjectWorkspaceService.maxTextBytes + 1, 'x').join());
      await File('${root.path}/bad.txt').writeAsBytes([0, 1]);
      await expectLater(ProjectWorkspaceService.read(root.path, 'large.java'), throwsFormatException);
      await expectLater(ProjectWorkspaceService.read(root.path, 'bad.txt'), throwsFormatException);
      await expectLater(ProjectWorkspaceService.read(root.path, '../outside.java'), throwsFormatException);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('export validates text without writing original', () {
    expect(ProjectWorkspaceService.exportBytes('hello'), 'hello'.codeUnits);
    expect(() => ProjectWorkspaceService.exportBytes('\u0000'), throwsFormatException);
    expect(ProjectWorkspaceService.eligible('code/demo.csproj'), true);
    expect(ProjectWorkspaceService.eligible('.git/config.txt'), false);
  });
}
