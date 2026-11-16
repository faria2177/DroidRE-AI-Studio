import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/apk_report.dart';
import 'apk_analyzer.dart';
import 'source_recovery_folder_service.dart';

class StudioController extends ChangeNotifier {
  final List<ApkReport> _projects = [];
  String? _activeId;
  bool _busy = false;
  String? _error;
  String? _recoveryMessage;

  List<ApkReport> get projects => List.unmodifiable(_projects);
  ApkReport? get active {
    for (final report in _projects) {
      if (report.id == _activeId) return report;
    }
    return _projects.isEmpty ? null : _projects.first;
  }

  bool get busy => _busy;
  String? get error => _error;
  String? get recoveryMessage => _recoveryMessage;

  Future<Directory> _projectFolder() async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory('${support.path}/artifacts');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<File> _indexFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/projects.json');
  }

  Future<void> load() async {
    try {
      final index = await _indexFile();
      if (!await index.exists()) return;
      final parsed = jsonDecode(await index.readAsString());
      if (parsed is! List) return;
      _projects.clear();
      for (final item in parsed) {
        if (item is Map) {
          final report = ApkReport.fromJson(Map<String, dynamic>.from(item));
          if (await File(report.localPath).exists()) _projects.add(report);
        }
      }
      if (_projects.isNotEmpty) _activeId = _projects.first.id;
      notifyListeners();
    } catch (_) {
      _error = 'Saved project index could not be opened';
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final file = await _indexFile();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(_projects.map((report) => report.toJson()).toList()),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  void select(ApkReport report) {
    _activeId = report.id;
    _error = null;
    _recoveryMessage = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearRecoveryMessage() {
    _recoveryMessage = null;
    notifyListeners();
  }

  Future<bool> importApk() async {
    if (_busy) return false;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'apk', 'aab', 'apks', 'xapk', 'apkm', 'zip',
        ],
      );
      if (result == null || result.files.isEmpty) return false;
      final selected = result.files.first;
      final sourcePath = selected.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        _error = 'The selected file is not locally readable';
        notifyListeners();
        return false;
      }
      _busy = true;
      _error = null;
      notifyListeners();
      final source = File(sourcePath);
      // Refuse oversize archives before making an app-private copy.
      final fileLength = await source.length();
      if (fileLength < 4) {
        throw const FormatException('Selected archive is too small');
      }
      if (fileLength > ApkAnalyzer.maxArchiveBytes) {
        throw const FormatException('Files over 1 GiB need the worker engine');
      }
      final folder = await _projectFolder();
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final safeName = selected.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final localPath = '${folder.path}/${id}_$safeName';
      // Copy failures must also remove partially written artifacts.
      try {
        await source.copy(localPath);
        final report = await Isolate.run(() => ApkAnalyzer.inspect(
          path: localPath,
          displayName: selected.name,
          id: id,
        ));
        _projects.insert(0, report);
        _activeId = id;
        await _save();
        _recoveryMessage = 'Analyzing APK and generating source folder...';
        notifyListeners();

        // Import succeeds even if the optional, bounded recovery cannot
        // decode a method or Android external storage is unavailable.
        try {
          final generated = await SourceRecoveryFolderService.generate(report);
          final index = _projects.indexWhere((item) => item.id == id);
          if (index >= 0) {
            _projects[index] = report.withRecovery(
              folderPath: generated.folderPath,
              partial: generated.partial,
              fileCount: generated.filesWritten,
            );
            await _save();
          }
          _recoveryMessage = 'Source folder created: '
              '${generated.filesWritten} files'
              '${generated.partial ? ' (partial analysis)' : ''}';
        } catch (error) {
          _recoveryMessage =
              'APK imported, but source folder generation failed: $error';
        }
        notifyListeners();
        return true;
      } catch (_) {
        _projects.removeWhere((item) => item.id == id);
        if (_activeId == id) {
          _activeId = _projects.isEmpty ? null : _projects.first.id;
        }
        final copied = File(localPath);
        if (await copied.exists()) await copied.delete();
        rethrow;
      }
    } catch (e) {
      _error = 'Import failed: $e';
      notifyListeners();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> deleteProject(ApkReport report) async {
    // Deletion only affects the app's copied artifact, never the user's source.
    final folder = await _projectFolder();
    final canonicalFolder = await folder.resolveSymbolicLinks();
    final artifact = File(report.localPath);
    if (artifact.path.startsWith('$canonicalFolder/')) {
      if (await artifact.exists()) await artifact.delete();
    }
    _projects.removeWhere((item) => item.id == report.id);
    _activeId = _projects.isEmpty ? null : _projects.first.id;
    await _save();
    notifyListeners();
  }
}
