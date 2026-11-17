import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/apk_report.dart';

class JadxRecoveryResult {
  const JadxRecoveryResult(this.folder, this.javaFiles, this.resourceFiles,
      this.exitCode, this.partial, this.log);
  final String folder, log;
  final int javaFiles, resourceFiles, exitCode;
  final bool partial;
}

/// Windows bridge to a trusted, separately installed JADX distribution.
/// The external decompiler is not a sandbox. No APK code is executed.
class JadxSourceRecovery {
  const JadxSourceRecovery._();
  static const maxLog = 32000;
  static const maxInventory = 20000;

  static List<String> arguments(String jar, String input, String root,
      {bool resources = true}) => [
    '-Xmx1536m', '-cp', jar, 'jadx.cli.JadxCLI',
    '--threads-count', '2', '--output-dir', root,
    if (!resources) '--no-res',
    input,
  ];

  static Future<JadxRecoveryResult> recover({
    required ApkReport report,
    required String java,
    required String jar,
    required String destination,
    bool resources = true,
  }) async {
    if (!Platform.isWindows || !p.isAbsolute(java) || !p.isAbsolute(jar) ||
        p.basename(java).toLowerCase() != 'java.exe' ||
        !p.basename(jar).toLowerCase().endsWith('-all.jar') ||
        !await File(java).exists() || !await File(jar).exists()) {
      throw const FormatException('Select installed java.exe and the trusted JADX distribution all.jar');
    }
    if (!report.fileName.toLowerCase().endsWith('.apk') ||
        (await sha256.bind(File(report.localPath).openRead()).first).toString() != report.sha256) {
      throw const FormatException('APK changed or unsupported; reimport first');
    }
    final parent = Directory(await Directory(destination).resolveSymbolicLinks());
    final session = await parent.createTemp('droidre-jadx-');
    final output = p.join(session.path, 'decompiled');
    final config = await Directory(p.join(session.path, 'config')).create();
    final cache = await Directory(p.join(session.path, 'cache')).create();
    final temp = await Directory(p.join(session.path, 'temp')).create();
    final process = await Process.start(java, arguments(jar, report.localPath, output,
        resources: resources), runInShell: false, workingDirectory: session.path,
      environment: {
        'JADX_CONFIG_DIR': config.path,
        'JADX_CACHE_DIR': cache.path,
        'JADX_TMP_DIR': temp.path,
        'JADX_DISABLE_XML_SECURITY': 'false',
        'JADX_DISABLE_ZIP_SECURITY': 'false',
        'JADX_DISABLE_ALL_SECURITY_FLAGS': 'false',
      });
    var log = '';
    void append(String part) {
      log += part;
      if (log.length > maxLog) {
        log = log.substring(log.length - maxLog);
      }
    }
    final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
    final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
    int code;
    try {
      final result = await Future.wait<Object?>([
        process.exitCode, stdout.asFuture<void>(), stderr.asFuture<void>(),
      ]).timeout(const Duration(minutes: 15));
      code = result.first as int;
    } finally {
      process.kill();
      await stdout.cancel();
      await stderr.cancel();
    }
    if (!await Directory(output).exists()) {
      throw FormatException('JADX produced no output (exit $code).\n$log');
    }
    final counts = await inventory(output);
    final result = JadxRecoveryResult(output, counts.$1, counts.$2, code,
        code != 0 || counts.$3 || counts.$1 == 0, log);
    await File(p.join(session.path, 'RECOVERY_REPORT.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'inputSha256': report.sha256,
        'frameworkHint': report.framework,
        'output': 'decompiled',
        'javaFiles': result.javaFiles,
        'resourceFiles': result.resourceFiles,
        'exitCode': result.exitCode,
        'partial': result.partial,
        'note': 'Decompiler output; not original source or a verified buildable project. '
            'Native code and Dart AOT are not recovered as Java.',
      }), flush: true);
    return result;
  }

  static Future<(int, int, bool)> inventory(String root,
      {int limit = maxInventory}) async {
    if (limit < 1 || limit > maxInventory) {
      throw const FormatException('Invalid inventory limit');
    }
    final base = await Directory(root).resolveSymbolicLinks();
    var java = 0;
    var resources = 0;
    var visited = 0;
    var partial = false;
    await for (final entity in Directory(base).list(recursive: true, followLinks: false)) {
      if (++visited > limit) {
        partial = true;
        break;
      }
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: base).replaceAll('\\', '/');
      if (relative.startsWith('sources/') && relative.endsWith('.java')) {
        java++;
      } else if (relative.startsWith('resources/')) {
        resources++;
      }
    }
    return (java, resources, partial);
  }
}
