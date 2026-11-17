import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'aarch64_preview_decoder.dart';
import 'elf_inspector.dart';
import 'elf_section_inspector.dart';
import 'package_binary_reader.dart';

class NativeBranchReference {
  const NativeBranchReference(this.source, this.target, this.mnemonic);
  final int source, target;
  final String mnemonic;
  bool get call => mnemonic == 'bl';
  String get line => '${Aarch64PreviewDecoder.hex(source)}  $mnemonic  '
      '${Aarch64PreviewDecoder.hex(target)}';
}

class NativeBranchReport {
  const NativeBranchReport(this.references, this.scannedWords, this.partial);
  final List<NativeBranchReference> references;
  final int scannedWords;
  final bool partial;
}

/// Bounded static ARM64 linear sweep. Includes direct branch targets only.
/// Embedded data may look like instructions; no runtime call graph is claimed.
class NativeBranchReferences {
  const NativeBranchReferences._();
  static const maxWords = 16384;
  static const maxReferences = 256;

  static Future<NativeBranchReport> incoming(String apkPath, String entryName,
      int sectionIndex, int target) => Isolate.run(() => inspectBytes(
        PackageBinaryReader.read(apkPath: apkPath, entryName: entryName,
            maxBytes: ElfInspector.maxBytes),
        sectionIndex, target,
      ));

  static NativeBranchReport inspectBytes(Uint8List bytes, int sectionIndex,
      int target, {int limit = maxWords}) {
    final header = ElfInspector.inspectBytes(bytes);
    if (header.bits != 64 || header.machine != 'AArch64 (EM_AARCH64)' ||
        header.byteOrder != 'Little-endian' ||
        (header.fileType != 'Executable' && header.fileType != 'Shared object / position-independent') ||
        target < 0 || target % 4 != 0 || limit < 1 || limit > maxWords) {
      throw const FormatException('Incoming preview requires ARM64 and an aligned target');
    }
    final sections = ElfSectionInspector.inspectBytes(bytes).sections;
    if (sectionIndex < 1 || sectionIndex >= sections.length) {
      throw const FormatException('Section index outside preview');
    }
    final section = sections[sectionIndex];
    final count = (section.size ~/ 4).clamp(0, limit).toInt();
    if (!section.fileBacked || section.type != 'PROGBITS' ||
        !section.flags.contains('EXEC') || section.flags.contains('COMPRESSED') ||
        count == 0 || section.virtualAddress < 0 || section.virtualAddress % 4 != 0 ||
        section.virtualAddress > Aarch64PreviewDecoder.maxAddress - (count - 1) * 4) {
      throw const FormatException('Unsupported executable section');
    }
    final data = ByteData.sublistView(bytes);
    final found = <NativeBranchReference>[];
    var partial = section.size != count * 4;
    for (var i = 0; i < count; i++) {
      final ins = Aarch64PreviewDecoder.decode(
          data.getUint32(section.fileOffset + i * 4, Endian.little),
          section.virtualAddress + i * 4);
      if (!ins.supported) {
        partial = true;
      }
      if (ins.target == target) {
        if (found.length == maxReferences) {
          partial = true;
          continue;
        }
        found.add(NativeBranchReference(ins.address, target, ins.mnemonic));
      }
    }
    return NativeBranchReport(List.unmodifiable(found), count, partial);
  }

  static List<NativeBranchReference> outgoing(List<Aarch64Instruction> instructions) =>
      List.unmodifiable([
        for (final ins in instructions)
          if (ins.target != null)
            NativeBranchReference(ins.address, ins.target!, ins.mnemonic),
      ]);
}
