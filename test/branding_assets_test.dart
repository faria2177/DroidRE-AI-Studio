import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brand asset and Android density launcher icons are valid PNG files', () {
    final files = [
      'assets/branding/droidre_logo.png',
      'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png',
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'])
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
    ];
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      expect(bytes.length, greaterThan(100), reason: file);
      expect(bytes.take(8).toList(),
          [137, 80, 78, 71, 13, 10, 26, 10], reason: file);
    }
  });

  test('Android launcher points to the custom adaptive icon', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(manifest, contains('@mipmap/ic_launcher'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(adaptive, contains('@color/droidre_icon_background'));
  });
}
