import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/apk_report.dart';
import 'android_manifest_parser.dart';
import 'package_binary_reader.dart';

class SplitMember {
  const SplitMember(this.name, this.hash, this.manifest);
  final String name, hash;
  final ManifestInfo manifest;
}

class SplitSetInspector {
  const SplitSetInspector._();
  static Map<String, Object?> compare(List<SplitMember> members) {
    if (members.isEmpty || members.length > 32) {
      throw const FormatException('Choose 1–32 APK files');
    }
    final issues = <String>[];
    final first = members.first.manifest;
    final splitNames = <String>{};
    final hashes = <String>{};
    var bases = 0;
    for (final member in members) {
      final m = member.manifest;
      if (!m.decoded || !RegExp(r'^[A-Za-z][\w]*(?:\.[A-Za-z][\w]*)+$').hasMatch(m.packageName) ||
          !RegExp(r'^\d+$').hasMatch(m.versionCode) ||
          (m.versionCodeMajor.isNotEmpty && !RegExp(r'^\d+$').hasMatch(m.versionCodeMajor))) {
        issues.add('${member.name}: identity unresolved');
      }
      if (m.packageName != first.packageName || m.versionCode != first.versionCode ||
          (m.versionCodeMajor.isEmpty ? '0' : m.versionCodeMajor) !=
          (first.versionCodeMajor.isEmpty ? '0' : first.versionCodeMajor)) {
        issues.add('${member.name}: package/version mismatch');
      }
      if (m.splitName.isEmpty) {
        bases++;
      } else if (!splitNames.add(m.splitName)) {
        issues.add('${member.name}: duplicate split name');
      }
      if (!hashes.add(member.hash)) {
        issues.add('${member.name}: duplicate payload');
      }
    }
    if (bases != 1) {
      issues.add('Expected one base manifest; observed $bases');
    }
    return {'identityConsistent': issues.isEmpty, 'issues': issues,
      'members': members.map((m) => {'name': m.name, 'sha256': m.hash,
        'package': m.manifest.packageName, 'versionCode': m.manifest.versionCode,
        'versionCodeMajor': m.manifest.versionCodeMajor, 'split': m.manifest.splitName}).toList(),
      'note': 'Manifest evidence only. No certificate, split dependency, ABI compatibility, merged APK or installability verification.'};
  }

  static Future<Map<String, Object?>> inspect(List<String> paths) => Isolate.run(() async {
    if (paths.length > 32 || paths.isEmpty) {
      throw const FormatException('Choose 1–32 APKs');
    }
    final members = <SplitMember>[];
    var total = 0;
    for (final path in paths) {
      final file = File(path);
      if (!path.toLowerCase().endsWith('.apk') ||
          await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) {
        throw const FormatException('Select regular APK files');
      }
      final length = await file.length();
      total += length;
      if (length < 22 || total > 1024 * 1024 * 1024) {
        throw const FormatException('Split set exceeds 1 GiB or file too small');
      }
      final hash = (await sha256.bind(file.openRead()).first).toString();
      final manifest = AndroidManifestParser.parse(PackageBinaryReader.read(
        apkPath: path, entryName: 'AndroidManifest.xml', maxBytes: 4 * 1024 * 1024));
      if ((await sha256.bind(file.openRead()).first).toString() != hash) {
        throw const FormatException('APK changed during analysis');
      }
      members.add(SplitMember(p.basename(path), hash, manifest));
    }
    return compare(members);
  });
}
