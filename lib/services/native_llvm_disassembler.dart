import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'elf_inspector.dart';
import 'elf_section_inspector.dart';
import 'package_binary_reader.dart';

class NativeLlvmPreview {
  const NativeLlvmPreview(this.architecture, this.start, this.end,
      this.output, this.truncated);
  final String architecture, output;
  final int start, end;
  final bool truncated;
}

/// Uses an explicitly selected trusted NDK/LLVM tool, never an imported binary.
class NativeLlvmDisassembler {
  const NativeLlvmDisassembler._();
  static const maxPreviewBytes = 4096;
  static const maxOutputChars = 128 * 1024;

  static List<String> arguments(String input, String section, int start, int end) {
    if (!RegExp(r'^[A-Za-z0-9_.$-]{1,128}$').hasMatch(section) ||
        start < 0 || end <= start || end - start > maxPreviewBytes) {
      throw const FormatException('Invalid executable section or preview window');
    }
    return [
      '--disassemble', '--section=$section',
      '--start-address=0x${start.toRadixString(16)}',
      '--stop-address=0x${end.toRadixString(16)}', input,
    ];
  }

  static Future<NativeLlvmPreview> inspect({
    required String executable, required String apkPath,
    required String entryName, required int sectionIndex,
    int? functionAddress, int? functionSize,
  }) => Isolate.run(() async {
    if (!Platform.isWindows || !p.isAbsolute(executable) ||
        p.basename(executable).toLowerCase() != 'llvm-objdump.exe' ||
        !await File(executable).exists()) {
      throw const FormatException('Select a trusted Windows LLVM llvm-objdump.exe');
    }
    final bytes = PackageBinaryReader.read(apkPath: apkPath,
        entryName: entryName, maxBytes: ElfInspector.maxBytes);
    final header = ElfInspector.inspectBytes(bytes);
    final supported = switch ((header.machine, header.bits)) {
      ('ARM (EM_ARM)', 32) || ('AArch64 (EM_AARCH64)', 64) ||
      ('Intel x86 (EM_386)', 32) || ('x86-64 (EM_X86_64)', 64) => true,
      _ => false,
    };
    if (!supported || header.byteOrder != 'Little-endian' ||
        (header.fileType != 'Executable' &&
         header.fileType != 'Shared object / position-independent')) {
      throw const FormatException('Unsupported ELF architecture or type');
    }
    final sections = ElfSectionInspector.inspectBytes(bytes).sections;
    if (sectionIndex < 1 || sectionIndex >= sections.length) {
      throw const FormatException('Section index outside preview');
    }
    final section = sections[sectionIndex];
    if (!section.fileBacked || section.type != 'PROGBITS' ||
        !section.flags.contains('EXEC') || section.flags.contains('COMPRESSED') ||
        section.virtualAddress < 0 || section.size <= 0 ||
        section.virtualAddress > 0x7fffffffffffffff - section.size) {
      throw const FormatException('Not a supported executable file range');
    }
    var start = section.virtualAddress;
    var size = section.size;
    if (functionAddress != null) {
      // ARM ELF function symbol bit zero is the Thumb state marker.
      final address = header.machine == 'ARM (EM_ARM)'
          ? functionAddress & ~1 : functionAddress;
      if (functionSize == null || functionSize <= 0 ||
          address < start || address - start >= size ||
          functionSize > size - (address - start)) {
        throw const FormatException('Function range outside executable section');
      }
      start = address;
      size = functionSize;
    }
    final end = start + size.clamp(1, maxPreviewBytes).toInt();
    final temp = await Directory.systemTemp.createTemp('droidre-llvm-');
    try {
      final input = await File(p.join(temp.path, 'sample.elf')).writeAsBytes(bytes);
      final args = arguments(input.path, section.name, start, end);
      final process = await Process.start(executable, args,
          runInShell: false,
          environment: {'DEBUGINFOD_URLS': ''});
      final output = StringBuffer();
      var truncated = false;
      void append(String chunk) {
        final remaining = maxOutputChars - output.length;
        if (chunk.length > remaining) {
          truncated = true;
        }
        if (remaining > 0) {
          output.write(chunk.substring(0, chunk.length.clamp(0, remaining).toInt()));
        }
      }
      final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
      final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
      try {
        final result = await Future.wait<Object?>([
          process.exitCode, stdout.asFuture<void>(), stderr.asFuture<void>(),
        ]).timeout(const Duration(seconds: 45));
        if (result.first != 0) {
          throw FormatException('LLVM disassembly failed:\n$output');
        }
        return NativeLlvmPreview(header.machine, start, end, output.toString(),
            truncated || size > maxPreviewBytes);
      } finally {
        process.kill();
        await stdout.cancel();
        await stderr.cancel();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
