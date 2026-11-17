import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Explicit trusted SDK apksigner verification. Does not sign, modify,
/// merge, install, or execute APKs.
class ApkSignerVerification {
  const ApkSignerVerification._();
  static const maxOutput = 131072;
  static List<String> arguments(String jar, String apk) =>
    ['-jar', jar, 'verify', '--verbose', '--print-certs', apk];

  static List<String> parseSigners(String text) {
    if (text.length > maxOutput) {
      throw const FormatException('Verification output exceeded limit');
    }
    final pattern = RegExp(r'^Signer #(\d+) certificate SHA-256 digest:\s*([a-fA-F0-9]{64})\s*$',
      multiLine: true);
    final byIndex = <int, String>{};
    for (final match in pattern.allMatches(text)) {
      final index = int.tryParse(match.group(1)!);
      if (index == null || index < 1 || index > 32 || byIndex.containsKey(index)) {
        throw const FormatException('Ambiguous signer list');
      }
      byIndex[index] = match.group(2)!.toLowerCase();
    }
    final countMatch = RegExp(r'^Number of signers:\s*(\d+)\s*$', multiLine: true)
      .allMatches(text).toList();
    if (byIndex.isEmpty || countMatch.length != 1 ||
        int.tryParse(countMatch.single.group(1)!) != byIndex.length ||
        !List.generate(byIndex.length, (i) => i + 1).every(byIndex.containsKey)) {
      throw const FormatException('Complete signer list not observed');
    }
    final certs = byIndex.values.toSet().toList()..sort();
    if (certs.length != byIndex.length) {
      throw const FormatException('Duplicate signer certificates');
    }
    return certs;
  }

  static bool sameSignerSet(List<List<String>> sets) => sets.isNotEmpty &&
    sets.every((s) => s.isNotEmpty && s.toSet().length == s.length &&
      s.length == sets.first.length && s.toSet().containsAll(sets.first));

  static Future<Map<String, Object?>> verifySet({
    required String java, required String jar, required List<String> apks,
  }) => Isolate.run(() async {
    if (!Platform.isWindows || !p.isAbsolute(java) || !p.isAbsolute(jar) ||
        p.basename(java).toLowerCase() != 'java.exe' ||
        p.basename(jar).toLowerCase() != 'apksigner.jar' ||
        !await File(java).exists() || !await File(jar).exists() ||
        apks.isEmpty || apks.length > 32) {
      throw const FormatException('Select trusted SDK apksigner.jar, JDK java.exe and 1–32 APKs');
    }
    var total = 0;
    final hashes = <String>{};
    final sets = <List<String>>[];
    final report = <Map<String, Object?>>[];
    for (final path in apks) {
      if (!p.isAbsolute(path) || !path.toLowerCase().endsWith('.apk') ||
          await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) {
        throw const FormatException('Select regular local APK files');
      }
      final file = File(path);
      final length = await file.length();
      total += length;
      if (length < 22 || total > 1024 * 1024 * 1024) {
        throw const FormatException('APK set exceeds aggregate 1 GiB');
      }
      final hash = (await sha256.bind(file.openRead()).first).toString();
      if (!hashes.add(hash)) {
        throw const FormatException('Duplicate APK payload');
      }
      final process = await Process.start(java, arguments(jar, path),
        runInShell: false, environment: {'JAVA_TOOL_OPTIONS': '',
          '_JAVA_OPTIONS': '', 'JDK_JAVA_OPTIONS': ''});
      final output = StringBuffer(), errors = StringBuffer();
      var oversized = false;
      void append(StringBuffer buffer, String part) {
        final remaining = maxOutput - buffer.length;
        if (part.length > remaining) {
          oversized = true;
          process.kill();
        }
        if (remaining > 0) {
          buffer.write(part.substring(0, part.length.clamp(0, remaining).toInt()));
        }
      }
      final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => append(output, s));
      final err = process.stderr.transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => append(errors, s));
      try {
        final result = await Future.wait<Object?>([
          process.exitCode, out.asFuture<void>(), err.asFuture<void>(),
        ]).timeout(const Duration(seconds: 60));
        if (oversized || result.first != 0) {
          throw FormatException('SDK signature verification failed: ${p.basename(path)} (exit ${result.first})');
        }
        final signers = parseSigners(output.toString());
        if ((await sha256.bind(file.openRead()).first).toString() != hash) {
          throw const FormatException('APK changed during verification');
        }
        sets.add(signers);
        report.add({'file': p.basename(path), 'sha256': hash,
          'verifiedBySelectedSdk': true, 'signerCertificateSha256': signers});
      } finally {
        process.kill();
        await out.cancel();
        await err.cancel();
      }
    }
    return {'sameCurrentSignerSet': sameSignerSet(sets), 'members': report,
      'note': 'Selected SDK reported successful verification. Current certificate equality alone does not establish publisher trust, signer lineage, dependencies or installability.'};
  });
}
