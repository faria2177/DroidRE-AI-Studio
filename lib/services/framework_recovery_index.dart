import '../models/apk_report.dart';

/// Framework-specific inventory hints, never fabricated source files.
class FrameworkRecoveryIndex {
  const FrameworkRecoveryIndex._();

  static Map<String, Object?> build(ApkReport report) {
    final groups = <String, List<String>>{
      'android-dex': [],
      'flutter-aot': [],
      'flutter-assets': [],
      'react-native-bundle': [],
      'unity-native': [],
      'unity-managed': [],
      'unity-metadata': [],
      'nativescript': [],
    };
    var partial = report.entries.length != report.entryCount || report.warnings.isNotEmpty;
    for (final entry in report.entries) {
      if (!entry.isFile) {
        continue;
      }
      final name = entry.name;
      String? kind;
      if (RegExp(r'^classes(?:[0-9]+)?\.dex$').hasMatch(name)) {
        kind = 'android-dex';
      } else if (name.startsWith('lib/') &&
          (name.endsWith('/libapp.so') || name.endsWith('/libflutter.so'))) {
        kind = 'flutter-aot';
      } else if (name.startsWith('assets/flutter_assets/')) {
        kind = 'flutter-assets';
      } else if (name == 'assets/index.android.bundle') {
        kind = 'react-native-bundle';
      } else if (name.startsWith('lib/') &&
          (name.endsWith('/libunity.so') || name.endsWith('/libil2cpp.so'))) {
        kind = 'unity-native';
      } else if (name.startsWith('assets/bin/Data/Managed/') && name.endsWith('.dll')) {
        kind = 'unity-managed';
      } else if (name == 'assets/bin/Data/Managed/Metadata/global-metadata.dat') {
        kind = 'unity-metadata';
      } else if ((name.startsWith('lib/') && name.endsWith('/libnativescript.so')) ||
          name.startsWith('assets/app/')) {
        kind = 'nativescript';
      }
      if (kind != null) {
        final list = groups[kind]!;
        if (list.length < 250) {
          list.add(name);
        } else {
          partial = true;
        }
      }
    }
    for (final list in groups.values) {
      list.sort();
    }
    return {
      'schemaVersion': 1,
      'frameworkHint': report.framework,
      'sourceSha256': report.sha256,
      'groups': groups,
      'partial': partial,
      'note': 'Inventory hints only. Java/Dalvik preview targets DEX; '
          'Flutter AOT, native libraries, Hermes/JS and Unity managed/IL2CPP '
          'require separate analysis. No original framework project is recovered.',
    };
  }
}
