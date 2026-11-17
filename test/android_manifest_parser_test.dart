import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/android_manifest_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects bad document header and incomplete text', () {
    final bytes = Uint8List.fromList([3, 0, 0, 0, 8, 0, 0, 0]);
    expect(AndroidManifestParser.parse(bytes).decoded, false);
    expect(AndroidManifestParser.parse(Uint8List.fromList('<notManifest/>'.codeUnits)).decoded, false);
  });
  test('bounded deterministic malformed binary XML does not crash', () {
    final random = Random(71);
    for (var i = 0; i < 200; i++) {
      final bytes = Uint8List.fromList(List.generate(8 + random.nextInt(128), (_) => random.nextInt(256)));
      bytes[0] = 3;
      bytes[1] = 0;
      final d = ByteData.sublistView(bytes);
      d.setUint16(2, 8, Endian.little);
      d.setUint32(4, bytes.length, Endian.little);
      expect(AndroidManifestParser.parse(bytes).decoded, false);
    }
  });
  test('reads package, SDK and permissions from XML manifest', () {
    final bytes = Uint8List.fromList(utf8.encode('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
  package="com.sample.app" android:versionCode="8"
  android:versionName="1.2">
  <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36"/>
  <uses-permission android:name="android.permission.CAMERA"/>
  <application>
    <activity android:name=".MainActivity"/>
  </application>
</manifest>
'''));
    final result = AndroidManifestParser.parse(bytes);
    expect(result.decoded, isTrue);
    expect(result.packageName, 'com.sample.app');
    expect(result.versionName, '1.2');
    expect(result.targetSdk, '36');
    expect(result.permissions, contains('android.permission.CAMERA'));
    expect(result.activities, contains('.MainActivity'));
  });

  test('handles invalid binary XML without crashing', () {
    final info = AndroidManifestParser.parse(
      Uint8List.fromList([3, 0, 8, 0, 255, 255, 0, 0]),
    );
    expect(info.decoded, isFalse);
  });
}
