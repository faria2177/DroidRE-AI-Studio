import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'elf_inspector.dart';
import 'dart_snapshot_version_evidence.dart';
import 'elf_section_inspector.dart';
import 'elf_symbol_inspector.dart';
import 'package_binary_reader.dart';

class FlutterSnapshotRegion {
  const FlutterSnapshotRegion({
    required this.symbol,
    required this.role,
    required this.section,
    required this.fileOffset,
    required this.availableBytes,
    required this.headerHex,
    required this.snapshotMagic,
  });

  final ElfSymbol symbol;
  final String role;
  final ElfSectionInfo section;
  final int fileOffset;
  final int availableBytes;
  final String headerHex;

  /// Only a signature observation, never snapshot format/version validation.
  final bool snapshotMagic;

  Map<String, Object?> toJson() => {
    'symbol': symbol.name,
    'role': role,
    'section': section.name,
    'sectionIndex': section.index,
    'virtualAddress': '0x${symbol.value.toRadixString(16)}',
    'fileOffset': '0x${fileOffset.toRadixString(16)}',
    'declaredSymbolBytes': symbol.size,
    'availableBytes': availableBytes,
    'headerHex': headerHex,
    'snapshotMagic': snapshotMagic,
    if (role.endsWith('data'))
      'versionEvidence': DartSnapshotVersionEvidence.inspect(
        Uint8List.fromList(headerHex.isEmpty ? [] : headerHex.split(' ').map((s) => int.parse(s, radix: 16)).toList()),
        availableBytes),
  };
}

class FlutterAotReport {
  const FlutterAotReport({
    required this.architecture,
    required this.layout,
    required this.regions,
    required this.scannedSymbols,
    required this.partial,
    required this.warnings,
  });

  final String architecture;
  final String layout;
  final List<FlutterSnapshotRegion> regions;
  final int scannedSymbols;
  final bool partial;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'architecture': architecture,
    'layout': layout,
    'scannedSymbols': scannedSymbols,
    'partial': partial,
    'warnings': warnings,
    'regions': regions.map((region) => region.toJson()).toList(),
    'note': 'Static ELF snapshot evidence only; not a Dart object or source decoder.',
  };
}

/// Recognizes declared Dart snapshot regions without deserializing or running
/// a Dart VM. Supports the older VM/isolate names and consolidated data/text
/// names; never guesses addresses from unrelated strings or stripped symbols.
class FlutterAotInspector {
  const FlutterAotInspector._();

  static const _roles = {
    'kDartVmSnapshotData': 'legacy-vm-data',
    'kDartVmSnapshotInstructions': 'legacy-vm-text',
    'kDartIsolateSnapshotData': 'legacy-isolate-data',
    'kDartIsolateSnapshotInstructions': 'legacy-isolate-text',
    'kDartSnapshotData': 'data',
    'kDartSnapshotText': 'text',
    'kDartSnapshotBuildId': 'build-id',
  };
  static const maxHeaderBytes = 64;

  static Future<FlutterAotReport> inspectEntry(
    String apkPath, String entryName,
  ) => Isolate.run(() => inspectBytes(PackageBinaryReader.read(
    apkPath: apkPath, entryName: entryName, maxBytes: ElfInspector.maxBytes,
  )));

  static FlutterAotReport inspectBytes(Uint8List bytes) {
    final elf = ElfInspector.inspectBytes(bytes);
    if (elf.fileType != 'Shared object / position-independent' &&
        elf.fileType != 'Executable') {
      throw const FormatException('Dart AOT preview requires an executable ELF image');
    }
    final sectionReport = ElfSectionInspector.inspectBytes(bytes);
    final symbols = ElfSymbolInspector.inspectBytes(bytes, exactNames: {
      for (final name in _roles.keys) ...[name, '_$name'],
    });
    final warnings = <String>[...sectionReport.warnings, ...symbols.warnings];
    final regions = <FlutterSnapshotRegion>[];
    final seen = <(String, int, int)>{};
    var partial = sectionReport.truncated || symbols.truncated || warnings.isNotEmpty;

    void warn(String message) {
      partial = true;
      if (warnings.length < 40) {
        warnings.add(message);
      }
    }

    for (final sym in symbols.symbols) {
      final name = sym.name.startsWith('_') ? sym.name.substring(1) : sym.name;
      final role = _roles[name]!;
      if (!seen.add((role, sym.sectionIndex, sym.value))) {
        continue;
      }
      if (sym.sectionIndex < 1 || sym.sectionIndex >= sectionReport.sections.length ||
          sym.imported || sym.size < 0) {
        warn('Unmapped snapshot symbol: ${sym.name}');
        continue;
      }
      final section = sectionReport.sections[sym.sectionIndex];
      final text = role.endsWith('text');
      if (!section.fileBacked || section.type != 'PROGBITS' ||
          section.flags.contains('COMPRESSED') ||
          section.virtualAddress < 0 || sym.value < section.virtualAddress ||
          (text && !section.flags.contains('EXEC')) ||
          (!text && section.flags.contains('EXEC'))) {
        warn('Snapshot symbol is not in a compatible file-backed section: ${sym.name}');
        continue;
      }
      final relative = sym.value - section.virtualAddress;
      if (relative >= section.size ||
          sym.size > section.size - relative) {
        warn('Snapshot symbol range exceeds its section: ${sym.name}');
        continue;
      }
      final offset = section.fileOffset + relative;
      // Missing symbol size is common; only sample up to the section end.
      // Do not infer that the rest of the section belongs to this snapshot.
      final available = sym.size == 0 ? 0 : sym.size;
      final sampleLimit = sym.size == 0 ? section.size - relative : sym.size;
      final sampleSize = sampleLimit.clamp(0, maxHeaderBytes).toInt();
      final sample = bytes.sublist(offset, offset + sampleSize);
      final magic = role.endsWith('data') && sample.length >= 4 &&
          sample[0] == 0xf5 && sample[1] == 0xf5 &&
          sample[2] == 0xdc && sample[3] == 0xdc;
      if (sym.size == 0) {
        warn('Snapshot extent is unknown: ${sym.name}');
      }
      if (role.endsWith('data') && !magic) {
        warn('Expected data snapshot signature not observed: ${sym.name}');
      }
      regions.add(FlutterSnapshotRegion(
        symbol: sym, role: role, section: section, fileOffset: offset,
        availableBytes: available,
        headerHex: sample.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' '),
        snapshotMagic: magic,
      ));
    }
    final found = regions.map((region) => region.role).toSet();
    final modern = found.contains('data') && found.contains('text');
    final legacy = found.containsAll({
      'legacy-vm-data', 'legacy-vm-text',
      'legacy-isolate-data', 'legacy-isolate-text',
    });
    final layout = modern && legacy ? 'consolidated-and-legacy-aliases' :
        modern ? 'consolidated' : legacy ? 'legacy' :
        regions.isEmpty ? 'not-detected' : 'incomplete-symbol-layout';
    if (!modern && !legacy) {
      warn('Complete recognized snapshot symbol layout not found; absence is not proof of a non-Flutter binary.');
    }
    return FlutterAotReport(
      architecture: elf.machine, layout: layout,
      regions: List.unmodifiable(regions), scannedSymbols: symbols.scanned,
      partial: partial, warnings: List.unmodifiable(warnings),
    );
  }
}
