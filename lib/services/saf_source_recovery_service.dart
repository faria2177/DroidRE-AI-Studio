import 'dart:io';

import 'package:flutter/services.dart';

import '../models/apk_report.dart';
import 'source_recovery_bundle.dart';

/// Android Storage Access Framework interface. No unrestricted file access.
class SafRecoveryDestination {
  const SafRecoveryDestination(this.uri, this.label);

  final String uri;
  final String label;

  factory SafRecoveryDestination.fromMap(Map<dynamic, dynamic> value) =>
      SafRecoveryDestination(
        value['uri'] as String,
        value['label'] as String,
      );
}

class SafRecoveryWriteResult {
  const SafRecoveryWriteResult({
    required this.folderUri,
    required this.folderLabel,
    required this.filesWritten,
    required this.partial,
  });

  final String folderUri;
  final String folderLabel;
  final int filesWritten;
  final bool partial;
}

class SafSourceRecoveryService {
  const SafSourceRecoveryService._();

  static const channelName = 'com.jahid.droidreai/recovery_folder';
  static const channel = MethodChannel(channelName);

  static bool get supported => Platform.isAndroid;

  static Future<String?> copySourceFolder(String id) async {
    if (!supported) return null;
    return channel.invokeMethod<String>('copySourceFolder', {'id': id});
  }

  static Future<SafRecoveryDestination?> selectedFolder() async {
    if (!supported) {
      return null;
    }
    final value = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'selectedDirectory');
    return value == null ? null : SafRecoveryDestination.fromMap(value);
  }

  /// First-time destination selection is prompted during import. Android 11+
  /// disallows selecting internal-storage roots, Downloads root and Android/data.
  static Future<SafRecoveryDestination?> chooseFolder() async {
    if (!supported) {
      return null;
    }
    final value = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'chooseDirectory');
    return value == null ? null : SafRecoveryDestination.fromMap(value);
  }

  static Future<SafRecoveryWriteResult> writeBundle({
    required ApkReport report,
    required SourceRecoveryResult bundle,
  }) async {
    if (!supported) {
      throw const FormatException('SAF recovery requires Android');
    }
    final value = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'writeRecoveryZip',
      {
        'zipBytes': bundle.zipBytes,
        'packageName': report.manifest.packageName.isNotEmpty
            ? report.manifest.packageName
            : report.fileName,
        'projectId': report.id,
      },
    );
    if (value == null) {
      throw const FormatException('Android did not confirm folder creation');
    }
    return SafRecoveryWriteResult(
      folderUri: value['folderUri'] as String,
      folderLabel: value['folderLabel'] as String,
      filesWritten: value['filesWritten'] as int,
      partial: bundle.partial,
    );
  }

  static Future<List<String>> listFiles(String folderUri) async {
    final paths = await channel.invokeListMethod<String>(
      'listRecoveredFiles', {'folderUri': folderUri},
    );
    return paths ?? const [];
  }

  static Future<String> readFile(
      String folderUri, String relativePath) async {
    final content = await channel.invokeMethod<String>(
      'readRecoveredFile',
      {'folderUri': folderUri, 'path': relativePath},
    );
    if (content == null) {
      throw const FormatException('Recovered file preview unavailable');
    }
    return content;
  }
}
