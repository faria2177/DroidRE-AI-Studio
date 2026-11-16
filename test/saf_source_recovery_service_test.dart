import 'package:droidre_ai_studio/models/apk_report.dart';
import 'package:droidre_ai_studio/services/saf_source_recovery_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SafSourceRecoveryService.channel, null);
  });

  test('SAF destination maps preserve user-selected tree label and URI', () {
    final destination = SafRecoveryDestination.fromMap({
      'uri': 'content://files.example/tree/primary%3ADocuments',
      'label': 'Documents',
    });
    expect(destination.label, 'Documents');
    expect(destination.uri, startsWith('content://'));
  });

  test('native platform channel lists and previews selected project files',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SafSourceRecoveryService.channel,
          (call) async {
            calls.add(call);
            if (call.method == 'listRecoveredFiles') {
              return [
                'source/java_like/dex_01/com/example/Main_0001.java.txt',
                'REPORT.json',
              ];
            }
            if (call.method == 'readRecoveredFile') {
              return 'Reconstructed preview; not compilable Java';
            }
            return null;
          },
        );
    final files = await SafSourceRecoveryService.listFiles(
      'content://files.example/tree/selected/document/project',
    );
    expect(files, contains('REPORT.json'));
    final preview = await SafSourceRecoveryService.readFile(
      'content://files.example/tree/selected/document/project',
      'REPORT.json',
    );
    expect(preview, contains('not compilable'));
    expect(calls.map((call) => call.method),
        ['listRecoveredFiles', 'readRecoveredFile']);
    expect((calls.last.arguments as Map)['path'], 'REPORT.json');
  });

  test('project JSON persists public SAF folder instead of Android/data path',
      () {
    final report = ApkReport.fromJson({
      'id': 'sample',
      'fileName': 'sample.apk',
      'localPath': '/private/sample.apk',
      'sha256': 'abc',
    });
    final converted = report.withSafRecovery(
      folderUri:
          'content://com.android.externalstorage.documents/tree/primary%3ADocuments/document/primary%3ADocuments%2FDroidRE_app',
      folderLabel: 'Documents/DroidRE_app',
      fileCount: 42,
      partial: true,
    );
    final restored = ApkReport.fromJson(converted.toJson());
    expect(restored.recoveredFolderUri, converted.recoveredFolderUri);
    expect(restored.recoveredFolderLabel, 'Documents/DroidRE_app');
    expect(restored.recoveredFolderPath, isNull);
    expect(restored.recoveredFileCount, 42);
    expect(restored.recoveryPartial, isTrue);
  });
}
