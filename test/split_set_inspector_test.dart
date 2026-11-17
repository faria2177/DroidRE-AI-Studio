import 'package:droidre_ai_studio/models/apk_report.dart';
import 'package:droidre_ai_studio/services/split_set_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one base and unique consistent split names', () {
    const base = SplitMember('base.apk', 'a',
      ManifestInfo(packageName: 'com.demo', versionCode: '1', decoded: true));
    const split = SplitMember('config.apk', 'b',
      ManifestInfo(packageName: 'com.demo', versionCode: '1', splitName: 'config.en', decoded: true));
    expect(SplitSetInspector.compare([base, split])['identityConsistent'], true);
    expect(SplitSetInspector.compare([base, base])['identityConsistent'], false);
    expect(SplitSetInspector.compare([split])['identityConsistent'], false);
    const wrong = SplitMember('wrong.apk', 'c',
      ManifestInfo(packageName: 'com.other', versionCode: '1', splitName: 'config.x', decoded: true));
    expect(SplitSetInspector.compare([base, wrong])['identityConsistent'], false);
  });
}
