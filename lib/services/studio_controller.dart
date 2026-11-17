import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/apk_report.dart';
import 'apk_analyzer.dart';
import 'source_recovery_folder_service.dart';
import 'saf_source_recovery_service.dart';
import 'source_recovery_bundle.dart';
import 'source_project_import.dart';

class StudioController extends ChangeNotifier {
  final List<ApkReport> _projects = [];
  String? _activeId;
  bool _busy = false;
  String? _error;
  String? _recoveryMessage;
  SafRecoveryDestination? _sourceDestination;
  String? _desktopRecoveryPath;
  bool get desktopRecovery => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  String? get recoveryDestinationLabel => _sourceDestination?.label ?? _desktopRecoveryPath;

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
  SafRecoveryDestination? get sourceDestination => _sourceDestination;

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
      if (SafSourceRecoveryService.supported) {
        try {
          _sourceDestination =
              await SafSourceRecoveryService.selectedFolder();
        } catch (_) {
          // An expired SAF grant must not prevent opening local projects.
        }
      }
      final index = await _indexFile();
      if (!await index.exists()) return;
      final parsed = jsonDecode(await index.readAsString());
      if (parsed is! List) return;
      _projects.clear();
      for (final item in parsed) {
        if (item is Map) {
          final report = ApkReport.fromJson(Map<String, dynamic>.from(item));
          if (report.sourceProject ? await Directory(report.localPath).exists() :
              await File(report.localPath).exists()) {
            _projects.add(report);
          }
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


  /// Requests a public, writable folder through the Android system picker.
  Future<bool> chooseRecoveryDestination() async {
    if ((!SafSourceRecoveryService.supported && !desktopRecovery) || _busy) {
      return false;
    }
    try {
      if (desktopRecovery) {
        final chosen = await FilePicker.platform.getDirectoryPath(
            dialogTitle: 'Choose source recovery folder');
        if (chosen == null) {
          return false;
        }
        _desktopRecoveryPath = await Directory(chosen).resolveSymbolicLinks();
        _recoveryMessage = 'Recovery destination: $_desktopRecoveryPath';
        notifyListeners();
        return true;
      }
      final selected = await SafSourceRecoveryService.chooseFolder();
      if (selected == null) {
        _recoveryMessage = 'Folder selection cancelled. Existing APK '
            'projects are unchanged.';
        notifyListeners();
        return false;
      }
      _sourceDestination = selected;
      _recoveryMessage = 'Recovery destination: ${selected.label}';
      notifyListeners();
      return true;
    } catch (error) {
      _recoveryMessage = 'Cannot select recovery folder: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _generateFor(ApkReport report) async {
    if (SafSourceRecoveryService.supported) {
      var destination = _sourceDestination;
      destination ??= await SafSourceRecoveryService.selectedFolder();
      destination ??= await SafSourceRecoveryService.chooseFolder();
      if (destination == null) {
        _recoveryMessage = 'APK imported. Select a writable folder in Tools '
            'to generate project files outside Android/data.';
        return false;
      }
      _sourceDestination = destination;
      final bundle = await SourceRecoveryBundle.fromProject(report);
      final generated = await SafSourceRecoveryService.writeBundle(
        report: report,
        bundle: bundle,
      );
      final index = _projects.indexWhere((item) => item.id == report.id);
      if (index >= 0) {
        _projects[index] = report.withSafRecovery(
          folderUri: generated.folderUri,
          folderLabel: generated.folderLabel,
          partial: generated.partial,
          fileCount: generated.filesWritten,
        );
        await _save();
      }
      _recoveryMessage = 'Created ${generated.filesWritten} files in '
          '${generated.folderLabel}'
          '${generated.partial ? ' (partial recovery)' : ''}';
    } else {
      // Desktop uses the existing app-owned storage implementation.
      final generated = await SourceRecoveryFolderService.generate(report,
          destination: _desktopRecoveryPath == null ? null : Directory(_desktopRecoveryPath!));
      final index = _projects.indexWhere((item) => item.id == report.id);
      if (index >= 0) {
        _projects[index] = report.withRecovery(
          folderPath: generated.folderPath,
          partial: generated.partial,
          fileCount: generated.filesWritten,
        );
        await _save();
      }
      _recoveryMessage = 'Generated ${generated.filesWritten} local files'
          '${generated.partial ? ' (partial recovery)' : ''}';
    }
    return true;
  }

  /// Generate for an existing APK after choosing a new destination.
  /// Existing project folders are never overwritten.
  Future<bool> generateInSelectedFolder() async {
    final report = active;
    if (report == null || report.sourceProject || _busy) {
      return false;
    }
    _busy = true;
    _error = null;
    _recoveryMessage = 'Generating source files for ${report.fileName}...';
    notifyListeners();
    try {
      return await _generateFor(report);
    } catch (error) {
      _recoveryMessage = 'Source folder generation failed: $error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<Directory> _sourceProjects() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'source-projects')).create(recursive: true);
  }

  Future<bool> importSourceProject({required bool folder}) async {
    if (_busy) {
      return false;
    }
    _busy = true;
    _error = null;
    _recoveryMessage = null;
    notifyListeners();
    Directory? copy;
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final parent = await _sourceProjects();
      final destination = p.join(parent.path, id);
      copy = Directory(destination);
      String name;
      if (folder && Platform.isAndroid) {
        final chosen = await SafSourceRecoveryService.copySourceFolder(id);
        if (chosen == null) {
          return false;
        }
        name = chosen;
      } else if (folder) {
        final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose Android or Flutter source project');
        if (path == null) {
          return false;
        }
        name = p.basename(path);
        await Isolate.run(() => SourceProjectImport.copyFolder(path, destination));
      } else {
        final selected = await FilePicker.platform.pickFiles(type: FileType.custom,
          allowedExtensions: ['zip']);
        if (selected == null) {
          return false;
        }
        final path = selected.files.single.path;
        if (path == null) throw const FormatException('ZIP is not locally readable');
        name = selected.files.single.name;
        await Isolate.run(() => SourceProjectImport.extractZip(path, destination));
      }
      final report = await Isolate.run(() => SourceProjectImport.describe(destination, name, id));
      _projects.insert(0, report);
      _activeId = report.id;
      try {
        await _save();
      } catch (_) {
        _projects.removeWhere((item) => item.id == id);
        _activeId = _projects.isEmpty ? null : _projects.first.id;
        rethrow;
      }
      _recoveryMessage = 'Imported source project: ${report.entryCount} files · ${report.framework}';
      copy = null;
      return true;
    } catch (e) {
      _error = 'Source project import failed: $e';
      return false;
    } finally {
      if (copy != null) {
        try {
          if (await copy.exists()) await copy.delete(recursive: true);
        } catch (_) {
          // Do not mask the import error if staging cleanup fails.
        }
      }
      _busy = false;
      notifyListeners();
    }
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

        // The system SAF picker is shown after indexing, only when needed.
        // Cancelling folder access never invalidates the imported APK.
        try {
          await _generateFor(report);
        } catch (error) {
          _recoveryMessage = 'APK imported, but code generation failed: '
              '$error. Choose a writable folder in Tools and retry.';
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
    if (report.sourceProject) {
      final parent = await (await _sourceProjects()).resolveSymbolicLinks();
      final dir = Directory(report.localPath);
      if (await FileSystemEntity.type(dir.path, followLinks: false) == FileSystemEntityType.directory) {
        final resolved = await dir.resolveSymbolicLinks();
        if (p.equals(p.dirname(resolved), parent) && p.basename(resolved) == report.id) {
          await dir.delete(recursive: true);
        }
      }
      _projects.removeWhere((item) => item.id == report.id);
      _activeId = _projects.isEmpty ? null : _projects.first.id;
      await _save();
      notifyListeners();
      return;
    }
    // Deletion only affects the app's copied artifact, never the user's source.
    final folder = await _projectFolder();
    final canonicalFolder = await folder.resolveSymbolicLinks();
    final artifact = File(report.localPath);
    if (await artifact.exists() &&
        await FileSystemEntity.type(artifact.path, followLinks: false) == FileSystemEntityType.file) {
      final resolved = await artifact.resolveSymbolicLinks();
      if (p.isWithin(canonicalFolder, resolved) &&
          p.equals(p.dirname(resolved), canonicalFolder) &&
          p.basename(resolved).startsWith('${report.id}_')) {
        await artifact.delete();
      }
    }
    _projects.removeWhere((item) => item.id == report.id);
    _activeId = _projects.isEmpty ? null : _projects.first.id;
    await _save();
    notifyListeners();
  }
}
