import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

enum ToolKind { java, adb, llvm, ilspy, dotnet, ghidra }

class ExternalToolManager {
  const ExternalToolManager._();
  static String name(ToolKind kind) => switch (kind) {
    ToolKind.java => 'java.exe',
    ToolKind.adb => 'adb.exe',
    ToolKind.llvm => 'llvm-objdump.exe',
    ToolKind.ilspy => 'ilspycmd.exe',
    ToolKind.dotnet => 'dotnet.exe',
    ToolKind.ghidra => 'Ghidra folder',
  };

  static List<String> versionArgs(ToolKind kind) => switch (kind) {
    ToolKind.java => ['-version'],
    ToolKind.adb => ['version'],
    ToolKind.llvm || ToolKind.ilspy || ToolKind.dotnet => ['--version'],
    ToolKind.ghidra => throw const FormatException('Ghidra version is read from its metadata file'),
  };

  /// Candidate paths only: does not run PATH entries or download software.
  static Future<Map<ToolKind, String>> candidates() async {
    if (!Platform.isWindows) {
      return {};
    }
    final env = Platform.environment;
    final paths = <ToolKind, List<String>>{
      ToolKind.java: [if (env['JAVA_HOME'] != null) p.join(env['JAVA_HOME']!, 'bin', 'java.exe')],
      ToolKind.adb: [for (final key in ['ANDROID_HOME','ANDROID_SDK_ROOT'])
        if (env[key] != null) p.join(env[key]!, 'platform-tools', 'adb.exe'),
        r'C:\Android\Sdk\platform-tools\adb.exe'],
      ToolKind.ilspy: [if (env['USERPROFILE'] != null)
        p.join(env['USERPROFILE']!, '.dotnet', 'tools', 'ilspycmd.exe')],
      ToolKind.dotnet: [if (env['ProgramFiles'] != null)
        p.join(env['ProgramFiles']!, 'dotnet', 'dotnet.exe')],
      ToolKind.llvm: [if (env['ANDROID_NDK_HOME'] != null)
        p.join(env['ANDROID_NDK_HOME']!, 'toolchains', 'llvm', 'prebuilt', 'windows-x86_64', 'bin', 'llvm-objdump.exe')],
      ToolKind.ghidra: [if (env['GHIDRA_HOME'] != null) env['GHIDRA_HOME']!],
    };
    final result = <ToolKind, String>{};
    for (final entry in paths.entries) {
      for (final path in entry.value) {
        if (p.isAbsolute(path) && await (entry.key == ToolKind.ghidra
            ? Directory(path).exists() : File(path).exists())) {
          result[entry.key] = path;
          break;
        }
      }
    }
    return result;
  }

  static Future<String> inspect(ToolKind kind, String path) async {
    if (!Platform.isWindows || !p.isAbsolute(path)) {
      throw const FormatException('Select trusted local Windows tool');
    }
    if (kind == ToolKind.ghidra) {
      final root = await Directory(path).resolveSymbolicLinks();
      final meta = File(p.join(root, 'Ghidra', 'application.properties'));
      if (!await File(p.join(root, 'support', 'analyzeHeadless.bat')).exists() ||
          !await meta.exists() || await meta.length() > 32768) {
        throw const FormatException('Ghidra installation metadata missing');
      }
      final bytes = await meta.openRead(0, 32769).fold<List<int>>([], (a,b) => a..addAll(b));
      if (bytes.length > 32768) {
        throw const FormatException('Metadata exceeds limit');
      }
      final lines = const LineSplitter().convert(utf8.decode(bytes))
          .where((s) => s.startsWith('application.version=') ||
            s.startsWith('application.release.name=')).take(4).toList();
      if (lines.isEmpty) {
        throw const FormatException('Version metadata unavailable');
      }
      return lines.join('\n');
    }
    if (p.basename(path).toLowerCase() != name(kind) ||
        !await File(path).exists()) {
      throw const FormatException('Expected matching executable filename');
    }
    final process = await Process.start(path, versionArgs(kind), runInShell: false,
      workingDirectory: p.dirname(path),
      environment: {'JAVA_TOOL_OPTIONS': '', '_JAVA_OPTIONS': '', 'JDK_JAVA_OPTIONS': ''});
    final buffer = StringBuffer();
    void append(String part) {
      final remain = 16000 - buffer.length;
      if (remain > 0) {
        buffer.write(part.substring(0, part.length.clamp(0, remain).toInt()));
      }
    }
    final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
    final err = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
    try {
      final result = await Future.wait<Object?>([process.exitCode,
        out.asFuture<void>(), err.asFuture<void>()]).timeout(const Duration(seconds: 15));
      if (result.first != 0 || buffer.isEmpty) {
        throw FormatException('Version command failed (exit ${result.first})');
      }
      return buffer.toString();
    } finally {
      process.kill();
      await out.cancel();
      await err.cancel();
    }
  }
}
