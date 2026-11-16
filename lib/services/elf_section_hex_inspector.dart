import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'elf_inspector.dart';
import 'elf_section_inspector.dart';
import 'package_binary_reader.dart';

@immutable
class ElfSectionHexPreview {
  const ElfSectionHexPreview({
    required this.sectionIndex,
    required this.sectionName,
    required this.sectionSize,
    required this.sectionOffset,
    required this.fileOffset,
    required this.bytesShown,
    required this.hexDump,
  });

  final int sectionIndex;
  final String sectionName;
  final int sectionSize;
  final int sectionOffset;
  final int fileOffset;
  final int bytesShown;
  final String hexDump;

  bool get hasPrevious => sectionOffset > 0;
  bool get hasNext => sectionOffset + bytesShown < sectionSize;
}

/// Generates a small read-only hex/ASCII preview for one validated ELF section.
/// No section can be edited, extracted, executed, or disassembled by this API.
/// Each page is limited to 256 bytes even if the ELF file is much larger.
class ElfSectionHexInspector {
  const ElfSectionHexInspector._();

  static const pageBytes = 256;

  static Future<ElfSectionHexPreview> inspectEntry(
    String apkPath,
    String entryName,
    int sectionIndex, {
    int sectionOffset = 0,
  }) => Isolate.run(() => inspectBytes(
    PackageBinaryReader.read(
      apkPath: apkPath,
      entryName: entryName,
      maxBytes: ElfInspector.maxBytes,
    ),
    sectionIndex,
    sectionOffset: sectionOffset,
  ));

  static ElfSectionHexPreview inspectBytes(
    Uint8List bytes,
    int sectionIndex, {
    int sectionOffset = 0,
    int byteLimit = pageBytes,
  }) {
    if (sectionIndex < 0 || sectionIndex >= ElfSectionInspector.maxResults ||
        sectionOffset < 0 || byteLimit < 1 || byteLimit > pageBytes) {
      throw const FormatException('Invalid ELF hex preview request');
    }

    // Do not trust a caller-provided offset, size or section type. Re-parse the
    // ELF headers and independently validate the selected section on every
    // request, including requests for later pages.
    final report = ElfSectionInspector.inspectBytes(bytes);
    if (sectionIndex >= report.sections.length) {
      throw const FormatException('ELF section index not available');
    }
    final section = report.sections[sectionIndex];
    if (!section.fileBacked) {
      throw const FormatException('Section has no file-backed bytes');
    }
    if (sectionOffset >= section.size) {
      throw const FormatException('Section preview offset exceeds its data');
    }
    final left = section.size - sectionOffset;
    final count = left < byteLimit ? left : byteLimit;
    final start = section.fileOffset + sectionOffset;
    if (start < 0 || count < 1 ||
        start > bytes.length || count > bytes.length - start) {
      throw const FormatException('ELF hex preview exceeds file bounds');
    }

    final lines = <String>[];
    for (var pos = 0; pos < count; pos += 16) {
      final lineLength = count - pos < 16 ? count - pos : 16;
      final octets = bytes.sublist(start + pos, start + pos + lineLength);
      final hexBytes = octets
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final ascii = String.fromCharCodes([
        for (final value in octets)
          value >= 32 && value <= 126 ? value : 46,
      ]);
      lines.add(
        '0x${(start + pos).toRadixString(16).padLeft(8, '0')}  '
        '${hexBytes.padRight(47)}  |$ascii|',
      );
    }
    return ElfSectionHexPreview(
      sectionIndex: sectionIndex,
      sectionName: section.name,
      sectionSize: section.size,
      sectionOffset: sectionOffset,
      fileOffset: start,
      bytesShown: count,
      hexDump: lines.join('\n'),
    );
  }
}
