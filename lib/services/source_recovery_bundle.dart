import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../models/apk_report.dart';
import 'dex_inspector.dart';
import 'dex_class_metadata_inspector.dart';
import 'dex_class_annotation_inspector.dart';
import 'dex_method_semantics_inspector.dart';
import 'dex_debug_info_inspector.dart';
import 'dex_method_pager.dart';
import 'resource_inspector.dart';

/// Zero-based position in the numerically sorted top-level DEX list.
/// A method index is an ordinal in the class's encoded method list.
@immutable
class SourceRecoveryCursor {
  const SourceRecoveryCursor({
    this.dexIndex = 0,
    this.classIndex = 0,
    this.methodIndex = 0,
  });

  final int dexIndex;
  final int classIndex;
  final int methodIndex;

  String get token => '$dexIndex:$classIndex:$methodIndex';

  factory SourceRecoveryCursor.parse(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 3 ||
        parts.any((part) => !RegExp(r'^\d{1,7}$').hasMatch(part))) {
      throw const FormatException('Use DEX:class:method (zero-based)');
    }
    return SourceRecoveryCursor(
      dexIndex: int.parse(parts[0]),
      classIndex: int.parse(parts[1]),
      methodIndex: int.parse(parts[2]),
    );
  }

  Map<String, Object?> toJson() => {
    'dexIndex': dexIndex,
    'classIndex': classIndex,
    'methodIndex': methodIndex,
    'token': token,
  };
}

@immutable
class SourceRecoveryResult {
  const SourceRecoveryResult({
    required this.zipBytes,
    required this.dexFilesVisited,
    required this.classesExported,
    required this.methodsExported,
    required this.warnings,
    required this.partial,
    this.nextCursor,
  });

  final Uint8List zipBytes;
  final int dexFilesVisited;
  final int classesExported;
  final int methodsExported;
  final List<String> warnings;
  final bool partial;
  final SourceRecoveryCursor? nextCursor;
}

/// Offline, bounded source *preview* bundle, not original source recovery.
///
/// Produces comments-only Dalvik/Java-like reports and manifest/resource
/// previews. The .txt filenames deliberately do not imply compilable Java
/// or assemblable Smali. No decoded code is executed.
class SourceRecoveryBundle {
  const SourceRecoveryBundle._();

  static const maxDexFiles = 3;
  static const maxClasses = 80;
  static const maxMethods = 400;
  static const maxResourceFiles = 32;
  static const maxResourceBytes = 4 * 1024 * 1024;
  static const maxSingleResource = 256 * 1024;
  static const maxOutputBytes = 24 * 1024 * 1024;

  static String _safeClassPath(String name) {
    final pieces = name.replaceAll('/', '.').split('.').take(16);
    return pieces.map((part) {
      final safe = part.replaceAll(RegExp(r'[^a-zA-Z0-9_$-]'), '_');
      if (safe.isEmpty) {
        return '_';
      }
      return safe.length > 50 ? safe.substring(0, 50) : safe;
    }).join('/');
  }

  /// Runs local decoding off the UI isolate. No server is contacted.
  static Future<SourceRecoveryResult> fromProject(ApkReport report, {
    SourceRecoveryCursor cursor = const SourceRecoveryCursor(),
  }) =>
      Isolate.run(() {
        final input = InputFileStream(report.localPath);
        try {
          final archive = ZipDecoder().decodeStream(input, throwOnError: true);
          return fromArchive(archive,
              packageName: report.manifest.packageName,
              sourceSha256: report.sha256,
              frameworkHint: report.framework, cursor: cursor);
        } finally {
          input.close();
        }
      });

  /// Deterministic builder for tests and for local ZIP archive inputs.
  /// Refuses duplicate ZIP member names and bounds all extracted content.
  static SourceRecoveryResult fromArchive(
    Archive source, {
    String packageName = '',
    String sourceSha256 = '',
    String frameworkHint = '',
    SourceRecoveryCursor cursor = const SourceRecoveryCursor(),
  }) {
    if (cursor.dexIndex < 0 || cursor.classIndex < 0 ||
        cursor.methodIndex < 0) {
      throw const FormatException('Negative source recovery cursor');
    }
    if (source.files.length > 10000) {
      throw const FormatException('Archive has too many entries');
    }

    final entries = <String, ArchiveFile>{};
    for (final file in source.files) {
      if (!file.isFile) {
        continue;
      }
      final normalized = file.name.replaceAll('\\', '/');
      if (normalized.startsWith('/') ||
          normalized.split('/').contains('..')) {
        throw const FormatException('Unsafe source archive member path');
      }
      if (entries.containsKey(normalized)) {
        throw const FormatException('Duplicate source archive member');
      }
      entries[normalized] = file;
    }

    final fileNames = entries.keys.toList();
    String detectedFramework;
    if (fileNames.any((path) =>
        path.startsWith('assets/flutter_assets/') ||
        path.endsWith('/libflutter.so')) ||
        frameworkHint.startsWith('Flutter')) {
      detectedFramework = 'Flutter';
    } else if (fileNames.contains('assets/index.android.bundle') ||
        frameworkHint.startsWith('React Native')) {
      detectedFramework = 'React Native';
    } else if (fileNames.any((path) => path.endsWith('/libunity.so')) ||
        frameworkHint.startsWith('Unity')) {
      detectedFramework = 'Unity';
    } else if (fileNames.any((path) => path.endsWith('/libnativescript.so')) ||
        frameworkHint.startsWith('NativeScript')) {
      detectedFramework = 'NativeScript';
    } else {
      detectedFramework = 'Android DEX / unknown framework';
    }
    final nativeLibraries = fileNames.where((name) =>
        name.startsWith('lib/') && name.endsWith('.so')).toList()..sort();

    final output = Archive();
    final warnings = <String>[];
    final records = <Map<String, Object?>>[];
    var classesExported = 0;
    var methodsExported = 0;
    var tryRegionsExported = 0;
    var referencesExported = 0;
    var annotationTypesExported = 0;
    var debugMethodsRecovered = 0;
    var sourcePositionsRecovered = 0;
    var localRangesRecovered = 0;
    var dexVisited = 0;
    var resourcesExported = 0;
    var resourceBytes = 0;
    var partial = false;
    SourceRecoveryCursor? nextCursor;

    void warning(String message) {
      if (warnings.length < 100) {
        warnings.add(message);
      }
      partial = true;
    }

    Uint8List? read(ArchiveFile file, int limit) {
      if (file.size < 0 || file.size > limit || file.isSymbolicLink) {
        warning('Skipped oversized or symbolic member: ${file.name}');
        return null;
      }
      try {
        final content = file.readBytes();
        if (content == null || content.length > limit) {
          warning('Could not read within limit: ${file.name}');
          return null;
        }
        return Uint8List.fromList(content);
      } catch (_) {
        warning('Could not decode source member: ${file.name}');
        return null;
      }
    }

    void textFile(String path, String content) {
      output.addFile(ArchiveFile.string(path, content));
    }

    final dexNames = entries.keys.where((name) =>
        RegExp(r'^classes(\d+)?\.dex$').hasMatch(name)).toList()
      ..sort((a, b) {
        int index(String name) {
          if (name == 'classes.dex') {
            return 1;
          }
          return int.tryParse(name.substring(7, name.length - 4)) ??
              0x7fffffff;
        }
        final order = index(a).compareTo(index(b));
        return order == 0 ? a.compareTo(b) : order;
      });

    if (cursor.dexIndex >= dexNames.length &&
        (cursor.dexIndex != 0 || cursor.classIndex != 0 ||
            cursor.methodIndex != 0)) {
      throw const FormatException('Recovery cursor DEX index is out of range');
    }
    if (dexNames.length - cursor.dexIndex > maxDexFiles) {
      warning('Only the first $maxDexFiles of '
          '${dexNames.length - cursor.dexIndex} remaining DEX files '
          'are included in this preview window');
    }
    if (cursor.token != '0:0:0') {
      warning('This window starts at ${cursor.token}; earlier source is omitted');
    }

    for (var dexIndex = cursor.dexIndex; dexIndex < dexNames.length; dexIndex++) {
      if (dexIndex - cursor.dexIndex >= maxDexFiles ||
          classesExported >= maxClasses || methodsExported >= maxMethods) {
        nextCursor = SourceRecoveryCursor(dexIndex: dexIndex);
        warning('DEX, class or method export limit reached');
        break;
      }
      final dexName = dexNames[dexIndex];
      final dex = read(entries[dexName]!, DexInspector.maxBytes);
      if (dex == null) {
        continue;
      }
      dexVisited++;
      DexFileSummary summary;
      try {
        summary = DexInspector.inspectBytes(dex);
      } catch (_) {
        warning('Unsupported or malformed DEX: $dexName');
        continue;
      }

      final firstClass = dexIndex == cursor.dexIndex ? cursor.classIndex : 0;
      if (firstClass >= summary.classes.length &&
          (firstClass != 0 || cursor.methodIndex != 0 &&
              dexIndex == cursor.dexIndex)) {
        throw const FormatException('Recovery cursor class index is out of range');
      }
      final dexNumber = (dexIndex + 1).toString().padLeft(2, '0');
      final dexFolder = 'recovered/dex_$dexNumber';
      textFile('$dexFolder/INDEX.txt',
          'Source DEX: $dexName\n'
          'DEX version: ${summary.version}\n'
          'Declared classes: ${summary.classes.length}\n'
          'Method ID count: ${summary.methodIdCount}\n'
          'Bounded read-only reconstruction preview.\n'
          'See CLASS_METADATA.json for hierarchy and field detail.\n');
      final classMetadataRecords = <Map<String, Object?>>[];
      final annotationRecords = <Map<String, Object?>>[];

      for (var classIndexInDex = firstClass;
          classIndexInDex < summary.classes.length;
          classIndexInDex++) {
        if (classesExported >= maxClasses ||
            methodsExported >= maxMethods) {
          nextCursor = SourceRecoveryCursor(
            dexIndex: dexIndex, classIndex: classIndexInDex,
          );
          warning('Reached bounded class/method export limit');
          break;
        }
        final klass = summary.classes[classIndexInDex];
        final firstMethod = dexIndex == cursor.dexIndex &&
                classIndexInDex == cursor.classIndex
            ? cursor.methodIndex : 0;
        if (firstMethod != 0 && firstMethod >= klass.methodCount) {
          throw const FormatException('Recovery cursor method index is out of range');
        }
        classesExported++;
        final classIndex = classesExported.toString().padLeft(4, '0');
        final classFolder = '$dexFolder/classes/$classIndex';
        DexClassMetadata? metadata;
        try {
          metadata = DexClassMetadataInspector.inspectBytes(dex, klass);
          if (metadata.truncated) {
            warning('Class metadata preview incomplete for ${klass.name}: '
                '${metadata.warnings.join('; ')}');
          }
        } catch (error) {
          warning('Could not decode class metadata for ${klass.name}: '
              '$error');
        }
        DexClassAnnotationReport? annotations;
        try {
          annotations = DexClassAnnotationInspector.inspectBytes(dex, klass);
          if (annotations.partial) {
            warning('Incomplete annotation inventory for ${klass.name}: '
                '${annotations.warnings.join('; ')}');
          }
          annotationTypesExported += annotations.targets.fold<int>(
            0, (sum, item) => sum + item.annotations.length,
          );
        } catch (error) {
          warning('Cannot decode annotation directory for '
              '${klass.name}: $error');
        }
        annotationRecords.add({
          'class': klass.name,
          'classDefIndex': klass.classDefIndex,
          'annotations': annotations?.toJson(),
        });
        classMetadataRecords.add({
          'class': klass.name,
          'classDefIndex': klass.classDefIndex,
          'declaredMethods': klass.methodCount,
          'metadata': metadata?.toJson(),
          'metadataAvailable': metadata != null,
        });
        final structure = metadata == null
            ? '# Class metadata unavailable; see REPORT.json.\n'
            : DexClassMetadataInspector.structurePreview(metadata);
        final classInfo = StringBuffer()
          ..writeln('Class: ${klass.name}')
          ..writeln('Flags: 0x${klass.accessFlags.toRadixString(16)}')
          ..writeln('Declared method count: ${klass.methodCount}')
          ..writeln('Source class index: ${klass.classDefIndex}')
          ..writeln('No original Java source or Smali fidelity is claimed.')
          ..writeln()
          ..writeln(structure);
        textFile('$classFolder/class.txt', classInfo.toString());
        if (annotations != null && annotations.targets.isNotEmpty) {
          textFile('$classFolder/annotations.json',
              const JsonEncoder.withIndent('  ').convert(annotations.toJson()));
        }

        final methodSemanticRecords = <Map<String, Object?>>[];
        final methodDebugRecords = <Map<String, Object?>>[];
        final methodInfo = StringBuffer();
        final javaLike = StringBuffer()
          ..writeln('// READ-ONLY reconstruction preview.')
          ..writeln('// Java-like pseudo statements are not compilable Java.')
          ..writeln('// Class: ${klass.name}');
        if (metadata != null) {
          javaLike.writeln('// Superclass: '
              '${metadata.superDescriptor ?? '(none)'}');
          javaLike.writeln('// Interfaces: '
              '${metadata.interfaces.join(', ')}');
          for (final field in metadata.fields) {
            javaLike.writeln('// Field: '
                '${field.name}:${field.typeDescriptor}, '
                'access=0x${field.accessFlags.toRadixString(16)}');
          }
        }
        final dalvik = StringBuffer()
          ..writeln('# Decoded Dalvik inspection, NOT assemblable Smali.')
          ..writeln('# Class: ${klass.name}')
          ..writeln(structure);
        var start = firstMethod;
        while (start < klass.methodCount &&
            methodsExported < maxMethods) {
          List<DexMethodSummary> page;
          try {
            page = DexMethodPager.loadBytes(
                dex, klass, start: start,
                limit: DexMethodPager.pageSize);
          } catch (_) {
            warning('Cannot page methods for ${klass.name} at $start');
            break;
          }
          if (page.isEmpty) {
            warning('Method list incomplete for ${klass.name}');
            break;
          }
          var processedInPage = 0;
          for (final method in page) {
            if (methodsExported >= maxMethods) {
              break;
            }
            methodsExported++;
            processedInPage++;
            methodInfo.writeln(
                '${method.name}${method.prototype} '
                'flags=0x${method.accessFlags.toRadixString(16)} '
                'codeOffset=${method.codeOffset}');
            try {
              final semantics = DexMethodSemanticsInspector.inspectBytes(
                  dex, method);
              tryRegionsExported += semantics.tries.length;
              referencesExported += semantics.references.length;
              methodSemanticRecords.add({
                'method': method.name,
                'prototype': method.prototype,
                'methodIdIndex': method.methodIdIndex,
                'codeOffset': method.codeOffset,
                'analysis': semantics.toJson(),
              });
              if (semantics.partial) {
                warning('Incomplete method semantics for '
                    '${klass.name}.${method.name}: '
                    '${semantics.warnings.join('; ')}');
              }
              if (semantics.tries.isNotEmpty) {
                dalvik.writeln('    # Recovered exception ranges, '
                    'code-unit offsets (read-only):');
                for (final region in semantics.tries) {
                  dalvik.writeln('    # try from '
                      '${region.startAddress} to ${region.endAddress} '
                      '(exclusive):');
                  for (final handler in region.handlers) {
                    dalvik.writeln('    # catch '
                        '${handler.typeDescriptor ?? 'all'} '
                        '-> ${handler.address}');
                  }
                }
              }
              if (semantics.references.isNotEmpty) {
                dalvik.writeln('    # '
                    '${semantics.references.length} referenced pool items; '
                    'see method_semantics.json for instruction offsets');
              }
            } catch (error) {
              warning('Method metadata failed: '
                  '${klass.name}.${method.name}: $error');
              methodSemanticRecords.add({
                'method': method.name,
                'prototype': method.prototype,
                'methodIdIndex': method.methodIdIndex,
                'error': error.toString(),
              });
            }
            try {
              final debug = DexDebugInfoInspector.inspectBytes(
                dex, method,
                defaultSourceFile: metadata?.sourceFile,
              );
              methodDebugRecords.add({
                'method': method.name,
                'prototype': method.prototype,
                'methodIdIndex': method.methodIdIndex,
                'codeOffset': method.codeOffset,
                'debug': debug.toJson(),
              });
              if (debug.available) {
                debugMethodsRecovered++;
                sourcePositionsRecovered += debug.positions.length;
                localRangesRecovered += debug.locals.length;
                javaLike.writeln('// Available source debug hints for '
                    '${method.name}${method.prototype}:');
                final parameterNames = debug.parameters
                    .map((parameter) => parameter.name ?? '(unknown)')
                    .join(', ');
                javaLike.writeln('// Parameters: $parameterNames');
                if (debug.positions.isNotEmpty) {
                  dalvik.writeln('    # Source line mapping '
                      '(code-unit offset -> line):');
                  for (final position in debug.positions.take(60)) {
                    final file = position.sourceFile == null
                        ? '(unknown source)'
                        : jsonEncode(position.sourceFile);
                    dalvik.writeln('    # ${position.address} -> '
                        'line ${position.line} [$file]');
                    javaLike.writeln('// DEX PC ${position.address}: '
                        'source line ${position.line} [$file]');
                  }
                  if (debug.positions.length > 60) {
                    dalvik.writeln('    # Further source positions are in '
                        'method_debug_info.json');
                  }
                }
                if (debug.locals.isNotEmpty) {
                  javaLike.writeln('// Live local variables '
                      '(code-unit start..end, null = unknown):');
                  for (final local in debug.locals.take(40)) {
                    final name = jsonEncode(local.name);
                    javaLike.writeln('// v${local.register}: $name '
                        'type=${local.typeDescriptor ?? '(unknown)'} '
                        'pc=${local.startAddress}..'
                        '${local.endAddressExclusive?.toString() ?? '?'} '
                        '${local.restarted ? '(restarted)' : ''}');
                  }
                }
              } else {
                javaLike.writeln('// No DEX debug_info_item for '
                    '${method.name}${method.prototype}; source names '
                    'and line numbers are unavailable.');
              }
              if (debug.partial) {
                warning('Incomplete DEX debug information for '
                    '${klass.name}.${method.name}: '
                    '${debug.warnings.join('; ')}');
              }
            } catch (error) {
              warning('Method debug information failed for '
                  '${klass.name}.${method.name}: $error');
              methodDebugRecords.add({
                'method': method.name,
                'prototype': method.prototype,
                'methodIdIndex': method.methodIdIndex,
                'error': error.toString(),
              });
            }
            try {
              javaLike.writeln(DexInspector.pseudocodeMethodBytes(
                  dex, method));
              dalvik.writeln(DexInspector.disassembleMethodBytes(
                  dex, method));
            } catch (_) {
              warning('Method could not be decoded: '
                  '${klass.name}.${method.name}${method.prototype}');
              javaLike.writeln('// Unsupported method: '
                  '${method.name}${method.prototype}');
              dalvik.writeln('# Unsupported method: '
                  '${method.name}${method.prototype}');
            }
          }
          start += processedInPage;
          if (processedInPage < page.length) {
            warning('Method export cap interrupted class ${klass.name}');
            break;
          }
        }
        if (start < klass.methodCount) {
          warning('Some methods not exported in ${klass.name} '
              '(${klass.methodCount - start} remain or failed)');
          if (methodsExported >= maxMethods) {
            nextCursor = SourceRecoveryCursor(
              dexIndex: dexIndex,
              classIndex: classIndexInDex,
              methodIndex: start,
            );
          }
        }
        textFile('$classFolder/methods.txt', methodInfo.toString());
        textFile('$classFolder/method_semantics.json',
            const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'note': 'Read-only try/catch and referenced pool entries. '
              'Not verified Smali, no cross-DEX resolution.',
          'methods': methodSemanticRecords,
        }));
        textFile('$classFolder/method_debug_info.json',
            const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'note': 'DEX debug_info positions, parameter names and locals '
              'only where encoded. Never invented if stripped.',
          'methods': methodDebugRecords,
        }));
        textFile('$classFolder/java_like.txt', javaLike.toString());
        textFile('$classFolder/dalvik.txt', dalvik.toString());
        // Package-like directory tree. Filenames end in .txt because
        // neither format is executable, compilable or assemblable source.
        final friendlyPath = _safeClassPath(klass.name);
        final sourceFile = '${friendlyPath}_$classIndex';
        textFile('source/java_like/dex_$dexNumber/'
            '$sourceFile.java.txt', javaLike.toString());
        textFile('source/dalvik/dex_$dexNumber/'
            '$sourceFile.dalvik.txt', dalvik.toString());
        records.add({
          'dex': dexName,
          'class': klass.name,
          'declaredMethods': klass.methodCount,
          'classDefIndex': klass.classDefIndex,
          'firstMethodOrdinal': firstMethod,
          'nextMethodOrdinal': start,
          'processedMethods': start - firstMethod,
          'decodedFields': metadata?.fields.length,
          'declaredFields': metadata?.declaredFieldCount,
          'superclass': metadata?.superDescriptor,
          'metadataAvailable': metadata != null,
          'folder': classFolder,
        });
        if (nextCursor != null) {
          break;
        }
      }
      textFile('$dexFolder/ANNOTATIONS_INDEX.json',
          const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'dex': dexName,
        'note': 'Annotation types, visibility, counts and bounded '
            'encoded values; not evaluated or assembly-ready',
        'classes': annotationRecords,
      }));
      textFile('$dexFolder/CLASS_METADATA.json',
          const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'dex': dexName,
        'note': 'Structured class/field preview, not original source '
            'or assemblable Smali',
        'classes': classMetadataRecords,
      }));
      if (nextCursor != null) {
        break;
      }
    }

    if (dexNames.isEmpty) {
      warning('No classes.dex files found in archive');
    }
    if (dexVisited == 0) {
      warning('No supported DEX files were decoded');
    }

    // Only small, regular, explicitly bounded members are copied. The
    // original package paths are never used as output ZIP entry paths.
    final resourceNames = entries.keys.where((name) =>
        name == 'AndroidManifest.xml' ||
        name.startsWith('res/') || name.startsWith('assets/')).toList()
      ..sort();
    if (resourceNames.length > maxResourceFiles) {
      warning('Resource copy limited to $maxResourceFiles of '
          '${resourceNames.length} candidate files');
    }
    for (final name in resourceNames.take(maxResourceFiles)) {
      final file = entries[name]!;
      if (resourceBytes + file.size > maxResourceBytes) {
        warning('Resource copy byte cap reached near $name');
        continue;
      }
      final bytes = read(file, maxSingleResource);
      if (bytes == null) {
        continue;
      }
      resourcesExported++;
      resourceBytes += bytes.length;
      final storedName = resourcesExported.toString().padLeft(4, '0');
      var decodedPreview = false;
      output.addFile(ArchiveFile.bytes(
          'resources/raw/$storedName.bin', bytes));
      try {
        final decoded = ResourceInspector.previewBytes(name, bytes);
        if (decoded.decodedXml != null) {
          textFile('resources/decoded/$storedName.xml',
              decoded.decodedXml!);
          decodedPreview = true;
        } else if (decoded.textContent != null) {
          textFile('resources/decoded/$storedName.txt',
              decoded.textContent!);
          decodedPreview = true;
        }
      } catch (_) {
        warning('Resource preview failed; raw bytes retained: $name');
      }
      records.add({
        'sourceResource': name,
        'rawPath': 'resources/raw/$storedName.bin',
        'decodedPreview': decodedPreview,
      });
    }
    final kindNotes = switch (detectedFramework) {
      'Flutter' =>
        'Flutter indicators detected. classes.dex often contains only the '
        'Android host. Original Dart source is not recovered from compiled '
        'Flutter AOT snapshots. Native libraries are listed, not decompiled.',
      'React Native' =>
        'React Native indicators detected. DEX can contain Java/Kotlin '
        'bridges. Original TypeScript and JavaScript source maps are not '
        'recovered; small bundled JS assets may appear in resources/raw.',
      'Unity' =>
        'Unity indicators detected. DEX contains Android wrapper code. '
        'Unity C# source and IL2CPP source are not reconstructed.',
      'NativeScript' =>
        'NativeScript indicators detected. DEX can contain Android wrappers. '
        'Original JavaScript or TypeScript source is not guaranteed.',
      _ =>
        'DEX methods are displayed as NON-COMPILABLE Java-like pseudocode '
        'and NON-ASSEMBLABLE Dalvik reports. Original Java/Kotlin source '
        'and comments cannot be guaranteed.',
    };
    textFile('framework/TECHNOLOGY_ANALYSIS.md',
        '# Detected technology: $detectedFramework\n\n'
        '$kindNotes\n\n'
        'Native libraries found: ${nativeLibraries.length}\n'
        '${nativeLibraries.take(100).join('\n')}\n\n'
        'Detection is heuristic, not proof of original project framework.\n'
        'See REPORT.json for decoder coverage and warnings.\n');

    final report = <String, Object?>{
      'schemaVersion': 2,
      'packageName': packageName,
      'detectedFramework': detectedFramework,
      'technologyNote': kindNotes,
      'nativeLibrariesFound': nativeLibraries.length,
      'sourceSha256': sourceSha256,
      'dexFilesFound': dexNames.length,
      'dexOrder': dexNames,
      'startCursor': cursor.toJson(),
      'nextCursor': nextCursor?.toJson(),
      'dexFilesVisited': dexVisited,
      'classesExported': classesExported,
      'methodsExported': methodsExported,
      'tryRegionsExported': tryRegionsExported,
      'referencesExported': referencesExported,
      'annotationTypesExported': annotationTypesExported,
      'debugMethodsRecovered': debugMethodsRecovered,
      'sourcePositionsRecovered': sourcePositionsRecovered,
      'localRangesRecovered': localRangesRecovered,
      'resourcesExported': resourcesExported,
      'partial': partial,
      'warnings': warnings,
      'entries': records,
    };
    textFile('REPORT.json',
        const JsonEncoder.withIndent('  ').convert(report));
    textFile('README.md',
        '# DroidRE Source Recovery Preview\n\n'
        'This is NOT the original Android Studio/Flutter source project.\n'
        'Generated code is also organized by package under source/.\n'
        'The Java-like files are NON-COMPILABLE pseudocode and the Dalvik '
        'files are NON-ASSEMBLABLE inspection reports.\n'
        'Original Kotlin/Java identifiers, comments, assets, configuration '
        'and resource relationships may be incomplete.\n\n'
        'Use REPORT.json for coverage, source mappings and skipped files.\n'
        'All processing occurred offline on user-selected source archives.\n'
        'There is no APK execution, build, signing or uploading.\n');

    final encoded = ZipEncoder().encode(output);
    if (encoded.length > maxOutputBytes) {
      throw const FormatException('Source preview ZIP exceeds 24 MiB limit');
    }
    return SourceRecoveryResult(
      zipBytes: Uint8List.fromList(encoded),
      dexFilesVisited: dexVisited,
      classesExported: classesExported,
      methodsExported: methodsExported,
      warnings: List.unmodifiable(warnings),
      partial: partial,
      nextCursor: nextCursor,
    );
  }
}
