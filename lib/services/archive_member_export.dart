import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/apk_report.dart';
import 'package_binary_reader.dart';

class ArchiveMemberExport {
  const ArchiveMemberExport._();
  static const maxBytes = 80 * 1024 * 1024;

  static bool eligible(String path) {
    final lower = path.toLowerCase();
    if (path.isEmpty || path.length > 512 || path.contains('\\') ||
        path.contains(':') || path.contains('\u0000') ||
        path.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      return false;
    }
    return lower.endsWith('.apk') || lower.endsWith('/libil2cpp.so') ||
        lower.endsWith('/global-metadata.dat') ||
        lower == 'assets/index.android.bundle' ||
        (lower.startsWith('assets/app/') && (lower.endsWith('.js') || lower.endsWith('.json')));
  }

  static String outputName(String path) {
    if (!eligible(path)) {
      throw const FormatException('Unsupported archive member');
    }
    final clean = path.split('/').last.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (clean.length > 120) {
      throw const FormatException('Member name too long');
    }
    return 'member-$clean';
  }

  static Future<Uint8List> read(ApkReport report, String path) => Isolate.run(() async {
    if (!eligible(path) || !report.entries.any((e) => e.name == path &&
        e.isFile && e.size > 0 && e.size <= maxBytes)) {
      throw const FormatException('Member not in bounded indexed inventory');
    }
    final file = File(report.localPath);
    if (await file.length() > 1024 * 1024 * 1024 ||
        (await sha256.bind(file.openRead()).first).toString() != report.sha256) {
      throw const FormatException('Archive changed; reimport first');
    }
    return PackageBinaryReader.read(apkPath: report.localPath, entryName: path,
        maxBytes: maxBytes);
  });
}
