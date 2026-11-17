import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package_binary_reader.dart';

class GhidraCall {
  const GhidraCall(this.address, this.name);
  final String address, name;
}

class GhidraFunction {
  GhidraFunction(this.address, this.name);
  final String address, name;
  final calls = <GhidraCall>[];
  String? pseudocode, status;
}

class GhidraEvidence {
  const GhidraEvidence(this.language, this.functions, this.limited);
  final String language;
  final List<GhidraFunction> functions;
  final bool limited;
}

class GhidraRun {
  const GhidraRun(this.evidence, this.folder, this.hash, this.log);
  final GhidraEvidence evidence;
  final String folder, hash, log;
}

class GhidraHeadlessService {
  const GhidraHeadlessService._();
  static const maxInput = 32 * 1024 * 1024;
  static const maxReport = 8 * 1024 * 1024;
  static const scriptName = 'DroidREHeadlessExport.java';

  static List<String> arguments(String utilityJar, String session,
      String sample, String scriptFolder, String report, String selector) {
    if (selector != '@first' &&
        !RegExp(r'^[A-Za-z0-9_.$:@?<>][A-Za-z0-9_.$:@?<>-]{0,127}$').hasMatch(selector)) {
      throw const FormatException('Enter an exact simple function name or Ghidra address');
    }
    return [
      '-Xmx1536m', '-XX:ActiveProcessorCount=2', '-Djava.awt.headless=true',
      '-Djava.system.class.loader=ghidra.GhidraClassLoader',
      '-Dfile.encoding=UTF-8', '-Duser.language=en', '-Duser.country=US',
      '-cp', utilityJar, 'ghidra.GhidraLauncher',
      'ghidra.app.util.headless.AnalyzeHeadless',
      session, 'DroidRE', '-import', sample, '-readOnly',
      '-deleteProject', '-max-cpu', '2', '-analysisTimeoutPerFile', '90',
      '-scriptPath', scriptFolder, '-postScript', scriptName, report, selector,
    ];
  }

  static GhidraEvidence parse(String text) {
    if (text.length > maxReport) {
      throw const FormatException('Ghidra evidence exceeds limit');
    }
    String decode(String input, int limit) {
      final result = utf8.decode(base64Decode(input));
      if (result.isEmpty || result.length > limit || result.contains('\u0000')) {
        throw const FormatException('Invalid exported evidence field');
      }
      return result;
    }
    final lines = const LineSplitter().convert(text);
    if (lines.length < 2 || lines.length > 6500) {
      throw const FormatException('Incomplete or oversized Ghidra export');
    }
    final header = lines.first.split('\t');
    if (header.length != 2 || header.first != 'DROIDRE1') {
      throw const FormatException('Unrecognized Ghidra evidence format');
    }
    final language = decode(header[1], 200);
    final functions = <String, GhidraFunction>{};
    var previews = 0;
    for (final line in lines.skip(1).take(lines.length - 2)) {
      final fields = line.split('\t');
      if (fields.length < 3) {
        throw const FormatException('Invalid Ghidra record');
      }
      final address = decode(fields[1], 128);
      if (fields[0] == 'F' && fields.length == 3) {
        if (functions.containsKey(address) || functions.length >= 256) {
          throw const FormatException('Duplicate or excessive function records');
        }
        functions[address] = GhidraFunction(address, decode(fields[2], 256));
      } else {
        final function = functions[address];
        if (function == null || fields.length != 4) {
          throw const FormatException('Orphan Ghidra evidence record');
        }
        if (fields[0] == 'C' && function.calls.length < 24) {
          function.calls.add(GhidraCall(decode(fields[2], 128), decode(fields[3], 256)));
        } else if (fields[0] == 'P' && previews < 12 &&
            function.pseudocode == null &&
            const {'observed', 'clipped', 'unresolved'}.contains(fields[2])) {
          function.status = fields[2];
          function.pseudocode = decode(fields[3], 12000);
          previews++;
        } else {
          throw const FormatException('Invalid or excessive Ghidra record');
        }
      }
    }
    final end = lines.last.split('\t');
    if (end.length != 4 || end.first != 'END' ||
        int.tryParse(end[1]) != functions.length ||
        int.tryParse(end[2]) != previews ||
        !const {'limited', 'sampled'}.contains(end[3])) {
      throw const FormatException('Ghidra export missing completion marker');
    }
    return GhidraEvidence(language, functions.values.toList(), end[3] == 'limited');
  }

  static Future<GhidraRun> run({
    required String java, required String ghidraRoot, required String destination,
    required String input, String? member, required String script,
    String selector = '@first',
  }) => Isolate.run(() async {
    if (!Platform.isWindows || !p.isAbsolute(java) ||
        p.basename(java).toLowerCase() != 'java.exe' || !await File(java).exists()) {
      throw const FormatException('Select the trusted compatible Windows JDK java.exe');
    }
    final root = await Directory(ghidraRoot).resolveSymbolicLinks();
    final utility = p.join(root, 'Ghidra', 'Framework', 'Utility', 'lib', 'Utility.jar');
    if (utility.contains(';') || !await File(utility).exists() ||
        !await File(p.join(root, 'support', 'analyzeHeadless.bat')).exists()) {
      throw const FormatException('Select an extracted trusted Ghidra installation');
    }
    final Uint8List bytes;
    if (member != null) {
      if (!member.toLowerCase().endsWith('.so') ||
          await File(input).length() > 1024 * 1024 * 1024) {
        throw const FormatException('Choose a bounded native library member');
      }
      bytes = PackageBinaryReader.read(apkPath: input, entryName: member, maxBytes: maxInput);
    } else {
      final file = File(input);
      if (await FileSystemEntity.type(input, followLinks: false) != FileSystemEntityType.file ||
          await file.length() > maxInput) {
        throw const FormatException('Choose a regular binary up to 32 MiB');
      }
      final read = await file.openRead(0, maxInput + 1)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      bytes = Uint8List.fromList(read);
    }
    if (bytes.length < 64 || bytes.length > maxInput || !(
        (bytes[0] == 0x7f && bytes[1] == 0x45 && bytes[2] == 0x4c && bytes[3] == 0x46) ||
        (bytes[0] == 0x4d && bytes[1] == 0x5a))) {
      throw const FormatException('Expected bounded ELF or MZ/PE candidate');
    }
    final parent = Directory(await Directory(destination).resolveSymbolicLinks());
    if (parent.path.contains(';')) {
      throw const FormatException('Choose output folder without semicolons');
    }
    final session = await parent.createTemp('droidre-ghidra-');
    final scripts = await Directory(p.join(session.path, 'scripts')).create();
    final sample = await File(p.join(session.path, 'sample.bin')).writeAsBytes(bytes);
    await File(p.join(scripts.path, scriptName)).writeAsString(script);
    final report = File(p.join(session.path, 'native-evidence.tsv'));
    final digest = sha256.convert(bytes).toString();
    await File(p.join(session.path, 'INPUT_SHA256.txt')).writeAsString('$digest\n');
    final process = await Process.start(java,
      arguments(utility, session.path, sample.path, scripts.path, report.path, selector),
      workingDirectory: session.path, runInShell: false,
      environment: {'JAVA_TOOL_OPTIONS': '', '_JAVA_OPTIONS': '', 'JDK_JAVA_OPTIONS': '',
        'DEBUGINFOD_URLS': ''});
    final log = StringBuffer();
    void append(String text) {
      final remaining = 64000 - log.length;
      if (remaining > 0) {
        log.write(text.substring(0, text.length.clamp(0, remaining).toInt()));
      }
    }
    final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
    final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
    try {
      final result = await Future.wait<Object?>([
        process.exitCode, stdout.asFuture<void>(), stderr.asFuture<void>(),
      ]).timeout(const Duration(minutes: 5));
      if (result.first != 0 || !await report.exists() || await report.length() > maxReport) {
        throw FormatException('Ghidra failed or did not produce bounded evidence. Session: ${session.path}\n$log');
      }
      final raw = await report.openRead(0, maxReport + 1)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      if (raw.length > maxReport) {
        throw const FormatException('Ghidra evidence exceeds limit');
      }
      return GhidraRun(parse(utf8.decode(raw)), session.path, digest, log.toString());
    } finally {
      process.kill();
      await stdout.cancel();
      await stderr.cancel();
    }
  });
}
