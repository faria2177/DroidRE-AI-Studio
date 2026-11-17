import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/apk_report.dart';

/// Explicit local desktop bridge to a USER supplied trusted Apktool JAR.
/// Never executes a file from an imported APK. No shell command composition.
class ApktoolWorkspace {
  ApktoolWorkspace({required this.javaPath, required this.jarPath});
  final String javaPath;
  final String jarPath;
  static const maxTextBytes = 512 * 1024;
  static const maxLogChars = 32000;

  static bool get supported => Platform.isWindows;
  static bool editable(String relative) {
    final parts = relative.replaceAll('\\', '/').split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..' ||
        part.contains(':') || part.contains('\u0000'))) {
      return false;
    }
    return relative == 'AndroidManifest.xml' ||
        (RegExp(r'^smali(?:_classes[0-9]+)?$').hasMatch(parts.first) &&
          parts.last.endsWith('.smali')) ||
        (parts.first == 'res' && parts.last.endsWith('.xml'));
  }

  static List<String> decodeArguments(String jar, String input, String root,
      String framework) =>
      ['-Xmx1536m', '-jar', jar, 'd', input, '-o', root, '-p', framework];

  static List<String> buildArguments(String jar, String root, String output,
      String framework) =>
      ['-Xmx1536m', '-jar', jar, 'b', root, '-o', output, '-p', framework];

  Future<String> _run(List<String> arguments) async {
    if (!supported) {
      throw UnsupportedError('Windows desktop is required');
    }
    if (!p.isAbsolute(javaPath) || !p.isAbsolute(jarPath) ||
        p.basename(javaPath).toLowerCase() != 'java.exe' ||
        !jarPath.toLowerCase().endsWith('.jar') ||
        !await File(javaPath).exists() || !await File(jarPath).exists()) {
      throw const FormatException('Select installed java.exe and trusted Apktool JAR');
    }
    final process = await Process.start(javaPath, arguments, runInShell: false);
    var log = '';
    void append(String text) {
      log += text;
      if (log.length > maxLogChars) {
        log = log.substring(log.length - maxLogChars);
      }
    }
    final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true))
        .listen(append);
    final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true))
        .listen(append);
    final drained = Future.wait([stdout.asFuture<void>(), stderr.asFuture<void>()]);
    try {
      final results = await Future.wait<Object?>([process.exitCode, drained])
          .timeout(const Duration(minutes: 10));
      final code = results.first as int;
      if (code != 0) {
        throw ProcessException(javaPath, const [], 'Apktool exit $code\n$log', code);
      }
      return log;
    } finally {
      process.kill();
      await stdout.cancel();
      await stderr.cancel();
    }
  }

  Future<(String, String)> decode(ApkReport report, String parent) async {
    if (!report.fileName.toLowerCase().endsWith('.apk') ||
        (await sha256.bind(File(report.localPath).openRead()).first).toString() != report.sha256) {
      throw const FormatException('APK changed or unsupported; reimport first');
    }
    final selected = Directory(await Directory(parent).resolveSymbolicLinks());
    final session = await selected.createTemp('droidre-apktool-');
    final root = p.join(session.path, 'decoded');
    final framework = await Directory(p.join(session.path, 'framework')).create();
    final log = await _run(decodeArguments(jarPath, report.localPath, root, framework.path));
    if (!await File(p.join(root, 'apktool.yml')).exists()) {
      throw const FormatException('Apktool did not produce a decoded workspace');
    }
    return (root, log);
  }

  Future<(String, String)> build(String root) async {
    final canonical = await Directory(root).resolveSymbolicLinks();
    if (!await File(p.join(canonical, 'apktool.yml')).exists()) {
      throw const FormatException('Apktool project metadata missing');
    }
    final parent = Directory(p.dirname(canonical));
    final framework = p.join(parent.path, 'framework');
    final staging = await parent.createTemp('rebuild-');
    final output = p.join(staging.path, 'rebuilt-unsigned.apk');
    final log = await _run(buildArguments(jarPath, canonical, output, framework));
    if (!await File(output).exists() || await File(output).length() < 22) {
      throw const FormatException('Apktool did not produce an APK');
    }
    return (output, log);
  }

  static Future<File> checkedFile(String root, String selected) async {
    final base = await Directory(root).resolveSymbolicLinks();
    final file = File(selected);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Select an existing regular text file');
    }
    final actual = await file.resolveSymbolicLinks();
    if (!p.isWithin(base, actual) || !editable(p.relative(actual, from: base)
        .replaceAll('\\', '/'))) {
      throw const FormatException('Choose a Smali or XML file inside the decoded workspace');
    }
    if (await file.length() > maxTextBytes) {
      throw const FormatException('File exceeds the 512 KiB text limit');
    }
    return File(actual);
  }

  static Future<String> readText(String root, String selected) async {
    final file = await checkedFile(root, selected);
    final bytes = await file.readAsBytes();
    if (bytes.length > maxTextBytes || bytes.contains(0)) {
      throw const FormatException('Not bounded UTF-8 text');
    }
    return utf8.decode(bytes);
  }

  static Future<void> saveText(String root, String selected, String text) async {
    final file = await checkedFile(root, selected);
    final bytes = utf8.encode(text);
    if (bytes.length > maxTextBytes || bytes.contains(0)) {
      throw const FormatException('Replacement exceeds UTF-8 text limits');
    }
    // Ensure the original was text too.
    await readText(root, selected);
    await file.writeAsBytes(bytes, flush: true);
  }
}
