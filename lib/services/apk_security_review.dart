import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../models/apk_report.dart';
import 'apk_signature_inspector.dart';

class ApkSecurityReview {
  const ApkSecurityReview._();

  static Future<Map<String, Object?>> inspect(ApkReport report) =>
      Isolate.run(() async {
        await _check(report);
        final signature = ApkSignatureInspector.inspectFile(report.localPath);
        return audit(report, signature);
      });

  // Review indicators, not vulnerability or malware verdicts.
  static const permissionNotes = {
    'READ_SMS': 'Review access to SMS content.',
    'RECEIVE_SMS': 'Review incoming message handling.',
    'SEND_SMS': 'Review outgoing SMS behavior and potential charges.',
    'READ_CONTACTS': 'Review access to contacts.',
    'READ_CALL_LOG': 'Review access to call history.',
    'RECORD_AUDIO': 'Review microphone access.',
    'CAMERA': 'Review camera access.',
    'ACCESS_FINE_LOCATION': 'Review precise location access.',
    'ACCESS_BACKGROUND_LOCATION': 'Review background location access.',
    'MANAGE_EXTERNAL_STORAGE': 'Review broad storage access.',
    'REQUEST_INSTALL_PACKAGES': 'Review app installation requests.',
    'SYSTEM_ALERT_WINDOW': 'Review overlay behavior.',
    'QUERY_ALL_PACKAGES': 'Review broad app visibility.',
  };

  static Map<String, Object?> audit(ApkReport report, ApkSignatureEvidence signature) {
    final permissions = report.manifest.permissions.toSet().toList()..sort();
    final v1 = report.entries.where((entry) =>
        entry.isFile && RegExp(r'^META-INF/[^/]+\.(SF|RSA|DSA|EC)$',
            caseSensitive: false).hasMatch(entry.name)).map((e) => e.name).toList();
    return {
      'schemaVersion': 1,
      'file': report.fileName,
      'sha256': report.sha256,
      'package': report.manifest.packageName,
      'manifestDecoded': report.manifest.decoded,
      'declaredPermissions': permissions,
      'permissionReview': [
        for (final name in permissions)
          if (name.startsWith('android.permission.') &&
              permissionNotes.containsKey(name.substring(19)))
            {'permission': name, 'review': permissionNotes[name.substring(19)]},
      ],
      'components': {
        'activities': report.manifest.activities,
        'services': report.manifest.services,
        'receivers': report.manifest.receivers,
        'providers': report.manifest.providers,
      },
      'signature': signature.toJson(),
      'v1SignatureFileHints': v1,
      'inventoryWarnings': report.warnings,
      'partial': !report.manifest.decoded || report.entries.length != report.entryCount ||
          report.warnings.isNotEmpty || signature.status == 'unknown',
      'scope': 'Static declared metadata only. Permissions may not be granted. '
          'No exported component validation, runtime scan, certificate trust, '
          'cryptographic signature verification or malware verdict.',
    };
  }

  static Future<void> _check(ApkReport report) async {
    final file = File(report.localPath);
    if (!report.fileName.toLowerCase().endsWith('.apk') ||
        await file.length() > 1024 * 1024 * 1024 ||
        (await sha256.bind(file.openRead()).first).toString() != report.sha256) {
      throw const FormatException('APK changed or unsupported; reimport first');
    }
  }

  static const maxMember = 8 * 1024 * 1024;
  static const maxHashed = 64 * 1024 * 1024;
  static const maxFiles = 10000;

  static Future<Map<String, Object?>> compare(ApkReport baseline, ApkReport candidate) =>
      Isolate.run(() async {
        await _check(baseline);
        await _check(candidate);
        final a = _inventory(baseline.localPath);
        final c = _inventory(candidate.localPath);
        final names = {...a.$1.keys, ...c.$1.keys}.toList()..sort();
        final changes = <Map<String, Object?>>[];
        var equal = 0;
        for (final name in names) {
          final old = a.$1[name];
          final next = c.$1[name];
          final status = old == null ? 'added' : next == null ? 'removed' :
              old.$1 != next.$1 ? 'changed-size' :
              old.$2 == null || next.$2 == null ? 'unverified' :
              old.$2 == next.$2 ? 'unchanged' : 'changed-content';
          if (status == 'unchanged') {
            equal++;
          } else {
            changes.add({'path': name, 'status': status,
              'beforeBytes': old?.$1, 'afterBytes': next?.$1,
              'beforeSha256': old?.$2, 'afterSha256': next?.$2});
          }
        }
        final oldPerms = baseline.manifest.permissions.toSet();
        final newPerms = candidate.manifest.permissions.toSet();
        final manifests = baseline.manifest.decoded && candidate.manifest.decoded;
        return {
          'schemaVersion': 1,
          'baseline': baseline.fileName,
          'candidate': candidate.fileName,
          'baselineSha256': baseline.sha256,
          'candidateSha256': candidate.sha256,
          'samePackage': manifests && baseline.manifest.packageName.isNotEmpty
              ? baseline.manifest.packageName == candidate.manifest.packageName : null,
          'baselineVersion': baseline.manifest.versionCode,
          'candidateVersion': candidate.manifest.versionCode,
          'permissionsAdded': manifests ? (newPerms.difference(oldPerms).toList()..sort()) : null,
          'permissionsRemoved': manifests ? (oldPerms.difference(newPerms).toList()..sort()) : null,
          'verifiedUnchanged': equal,
          'differences': changes,
          'partial': a.$2 || c.$2 || !manifests,
          'scope': 'Decoded ZIP member comparison. Same-size un-hashed entries are '
              'unverified, not unchanged. No semantic DEX diff or signer verification.',
        };
      });

  static (Map<String, (int, String?)>, bool) _inventory(String path) {
    final stream = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(stream, throwOnError: true);
      if (archive.files.length > maxFiles) {
        throw const FormatException('Comparison supports up to 10,000 archive members');
      }
      final result = <String, (int, String?)>{};
      var budget = maxHashed;
      var partial = false;
      // Deterministic hash order makes the bounded coverage reproducible.
      final members = archive.files.toList()..sort((a, b) => a.name.compareTo(b.name));
      for (final entry in members) {
        if (entry.isSymbolicLink || entry.size < 0 ||
            entry.name.startsWith('/') || entry.name.contains('\\') ||
            entry.name.split('/').contains('..')) {
          throw const FormatException('Unsafe comparison member');
        }
        if (!entry.isFile) {
          continue;
        }
        if (result.containsKey(entry.name)) {
          throw const FormatException('Duplicate comparison member');
        }
        String? digest;
        if (entry.size <= maxMember && entry.size <= budget) {
          budget -= entry.size;
          final payload = entry.readBytes();
          if (payload != null && payload.length == entry.size) {
            digest = sha256.convert(payload).toString();
          }
        }
        if (digest == null) {
          partial = true;
        }
        result[entry.name] = (entry.size, digest);
      }
      return (result, partial);
    } finally {
      stream.close();
    }
  }
}
