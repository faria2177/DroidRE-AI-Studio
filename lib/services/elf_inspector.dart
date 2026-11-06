import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package_binary_reader.dart';

@immutable
class ElfSummary {
  const ElfSummary({
    required this.bits,
    required this.byteOrder,
    required this.machine,
    required this.fileType,
    required this.entryPoint,
    required this.programHeaders,
    required this.sectionHeaders,
  });

  final int bits;
  final String byteOrder;
  final String machine;
  final String fileType;
  final String entryPoint;
  final int programHeaders;
  final int sectionHeaders;
}

/// Reads the ELF header only: does not execute code or resolve symbols.
class ElfInspector {
  const ElfInspector._();

  static const maxBytes = 80 * 1024 * 1024;

  static Future<ElfSummary> inspectEntry(String apkPath, String entryName) =>
      Isolate.run(() => inspectBytes(PackageBinaryReader.read(
            apkPath: apkPath,
            entryName: entryName,
            maxBytes: maxBytes,
          )));

  static ElfSummary inspectBytes(Uint8List bytes) {
    if (bytes.length < 52 || bytes.length > maxBytes ||
        bytes[0] != 0x7f || bytes[1] != 0x45 ||
        bytes[2] != 0x4c || bytes[3] != 0x46) {
      throw const FormatException('Not a complete ELF header');
    }
    final bits = switch (bytes[4]) {
      1 => 32,
      2 => 64,
      _ => throw const FormatException('Unsupported ELF class'),
    };
    final endian = switch (bytes[5]) {
      1 => Endian.little,
      2 => Endian.big,
      _ => throw const FormatException('Unsupported ELF byte order'),
    };
    final headerLength = bits == 64 ? 64 : 52;
    if (bytes.length < headerLength || bytes[6] != 1) {
      throw const FormatException('Truncated or invalid ELF header');
    }
    final data = ByteData.sublistView(bytes);
    int u16(int offset) => data.getUint16(offset, endian);
    int u32(int offset) => data.getUint32(offset, endian);
    int u64(int offset) => data.getUint64(offset, endian);
    final type = u16(16);
    final machine = u16(18);
    final entry = bits == 64 ? u64(24) : u32(24);
    final declaredSize = u16(bits == 64 ? 52 : 40);
    if (declaredSize < headerLength) {
      throw const FormatException('Invalid ELF header size');
    }
    return ElfSummary(
      bits: bits,
      byteOrder: endian == Endian.little ? 'Little-endian' : 'Big-endian',
      machine: switch (machine) {
        3 => 'Intel x86 (EM_386)',
        40 => 'ARM (EM_ARM)',
        62 => 'x86-64 (EM_X86_64)',
        183 => 'AArch64 (EM_AARCH64)',
        243 => 'RISC-V (EM_RISCV)',
        _ => 'Machine $machine',
      },
      fileType: switch (type) {
        1 => 'Relocatable',
        2 => 'Executable',
        3 => 'Shared object / position-independent',
        4 => 'Core dump',
        _ => 'Type $type',
      },
      entryPoint: '0x${entry.toRadixString(16)}',
      programHeaders: u16(bits == 64 ? 56 : 44),
      sectionHeaders: u16(bits == 64 ? 60 : 48),
    );
  }
}
