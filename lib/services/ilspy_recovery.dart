import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum IlspyMode { il, csharp, types, project }

class IlspyResult {
  const IlspyResult(this.output, this.exitCode, this.partial, this.folder);
  final String output;
  final int exitCode;
  final bool partial;
  final String? folder;
}

class IlspyRecovery {
  const IlspyRecovery._();
  static const maxOutput = 128 * 1024;
  static const maxInput = 32 * 1024 * 1024;

  static List<String> arguments(String input, IlspyMode mode, {String? output}) {
    if (mode == IlspyMode.project && (output == null || output.isEmpty)) {
      throw const FormatException('Project output directory required');
    }
    return ['--disable-updatecheck',
      if (mode == IlspyMode.il) '--ilcode',
      if (mode == IlspyMode.types) ...['--list', 'c,i,s,d,e'],
      if (mode == IlspyMode.project) ...['--project', '--outputdir', output!],
      input];
  }

  static Future<IlspyResult> run({
    required String executable, required String input, required String expectedHash,
    required IlspyMode mode, String? destination,
  }) async {
    if (!Platform.isWindows || !p.isAbsolute(executable) ||
        p.basename(executable).toLowerCase() != 'ilspycmd.exe' ||
        !await File(executable).exists() || !p.isAbsolute(input)) {
      throw const FormatException('Select trusted installed ilspycmd.exe on Windows');
    }
    final source = File(input);
    if (await source.length() > maxInput ||
        (await sha256.bind(source.openRead()).first).toString() != expectedHash) {
      throw const FormatException('Input changed or exceeds 32 MiB; reopen binary');
    }
    final String? folder;
    if (mode == IlspyMode.project) {
      if (destination == null) {
        throw const FormatException('Choose a project destination');
      }
      final parent = Directory(await Directory(destination).resolveSymbolicLinks());
      folder = (await parent.createTemp('droidre-ilspy-')).path;
    } else {
      folder = null;
    }
    final process = await Process.start(executable,
      arguments(input, mode, output: folder), runInShell: false,
      workingDirectory: folder ?? p.dirname(input));
    final out = StringBuffer();
    final err = StringBuffer();
    var clipped = false;
    void append(StringBuffer buffer, String chunk) {
      final remaining = maxOutput - buffer.length;
      if (chunk.length > remaining) {
        clipped = true;
      }
      if (remaining > 0) {
        buffer.write(chunk.substring(0, chunk.length.clamp(0, remaining).toInt()));
      }
    }
    final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => append(out, s));
    final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => append(err, s));
    try {
      final results = await Future.wait<Object?>([
        process.exitCode, stdout.asFuture<void>(), stderr.asFuture<void>(),
      ]).timeout(const Duration(minutes: 5));
      final code = results.first as int;
      var hasSource = false;
      if (folder != null) {
        var visited = 0;
        await for (final entry in Directory(folder).list(recursive: true, followLinks: false)) {
          if (++visited > 10000) {
            clipped = true;
            break;
          }
          if (entry is File && entry.path.toLowerCase().endsWith('.cs')) {
            hasSource = true;
            break;
          }
        }
      }
      return IlspyResult('$out\n$err', code,
          code != 0 || clipped || (folder != null ? !hasSource : out.isEmpty), folder);
    } finally {
      process.kill();
      await stdout.cancel();
      await stderr.cancel();
    }
  }
}
