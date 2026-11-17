import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'aarch64_preview_decoder.dart';
import 'elf_inspector.dart';
import 'elf_section_inspector.dart';
import 'elf_symbol_inspector.dart';
import 'package_binary_reader.dart';

class ElfDisassemblyPage {
  const ElfDisassemblyPage({
    required this.label,
    required this.rangeBytes,
    required this.offset,
    required this.instructions,
    required this.trailingBytes,
    required this.fileOffset,
  });

  final String label;
  final int rangeBytes;
  final int offset;
  final List<Aarch64Instruction> instructions;
  final int trailingBytes;
  final int fileOffset;

  int get nextOffset => offset + instructions.length * 4;
  bool get hasNext => rangeBytes - nextOffset >= 4;
  bool get hasPrevious => offset > 0;
  int get unsupported => instructions.where((item) => !item.supported).length;
  String get text => instructions.map((item) => item.line).join('\n');
}

/// Local linear sweep of file-backed executable ARM64 sections or a sized
/// function symbol. No function boundary guessing, relocation or execution.
class ElfDisassemblyInspector {
  const ElfDisassemblyInspector._();

  static const pageInstructions = 128;

  static Future<ElfDisassemblyPage> inspectEntry(
    String apkPath, String entryName, int sectionIndex, {
    int offset = 0,
    ElfSymbol? function,
  }) => Isolate.run(() => inspectBytes(
    PackageBinaryReader.read(apkPath: apkPath, entryName: entryName,
        maxBytes: ElfInspector.maxBytes),
    sectionIndex, offset: offset, function: function,
  ));

  static ElfDisassemblyPage inspectBytes(Uint8List bytes, int sectionIndex, {
    int offset = 0, int limit = pageInstructions, ElfSymbol? function,
  }) {
    final header = ElfInspector.inspectBytes(bytes);
    if (header.bits != 64 || header.byteOrder != 'Little-endian' ||
        header.machine != 'AArch64 (EM_AARCH64)' ||
        (header.fileType != 'Shared object / position-independent' &&
            header.fileType != 'Executable')) {
      throw const FormatException('Preview requires little-endian ARM64 ELF executable/shared object');
    }
    if (sectionIndex < 1 || offset < 0 || offset % 4 != 0 ||
        limit < 1 || limit > pageInstructions) {
      throw const FormatException('Invalid disassembly page');
    }
    final sections = ElfSectionInspector.inspectBytes(bytes).sections;
    if (sectionIndex >= sections.length) {
      throw const FormatException('ELF section is outside the inspected range');
    }
    final section = sections[sectionIndex];
    if (!section.fileBacked || section.type != 'PROGBITS' ||
        !section.flags.contains('EXEC') || section.flags.contains('COMPRESSED') ||
        section.virtualAddress < 0 ||
        section.virtualAddress > 0x7ffffffff0000000 ||
        section.virtualAddress % 4 != 0) {
      throw const FormatException('Section is not a supported executable range');
    }
    var rangeStart = 0;
    var rangeSize = section.size;
    var label = section.name;
    if (function != null) {
      if (function.type != 'FUNC' || function.imported ||
          function.sectionIndex != sectionIndex ||
          function.value < section.virtualAddress ||
          function.value % 4 != 0 || function.size < 4) {
        throw const FormatException('Function has no supported sized executable range');
      }
      rangeStart = function.value - section.virtualAddress;
      if (rangeStart > section.size ||
          function.size > section.size - rangeStart) {
        throw const FormatException('Function extends outside its ELF section');
      }
      rangeSize = function.size;
      label = function.name;
    }
    if (offset > rangeSize - 4 ||
        rangeStart + offset > section.size - 4) {
      throw const FormatException('No complete instruction at this offset');
    }
    final count = ((rangeSize - offset) ~/ 4).clamp(0, limit).toInt();
    final fileOffset = section.fileOffset + rangeStart + offset;
    final address = section.virtualAddress + rangeStart + offset;
    final data = ByteData.sublistView(bytes);
    return ElfDisassemblyPage(
      label: label, rangeBytes: rangeSize, offset: offset,
      fileOffset: fileOffset, trailingBytes: rangeSize % 4,
      instructions: List.unmodifiable([
        for (var i = 0; i < count; i++)
          Aarch64PreviewDecoder.decode(
            data.getUint32(fileOffset + i * 4, Endian.little), address + i * 4),
      ]),
    );
  }
}
