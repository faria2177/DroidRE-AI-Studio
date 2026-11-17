import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class PagedBinaryFile {
  const PagedBinaryFile(this.path, this.length, this.modified);
  final String path;
  final int length;
  final DateTime modified;
}

class PagedBinaryService {
  const PagedBinaryService._();
  static const maxFile = 1024 * 1024 * 1024;
  static const windowBytes = 64 * 1024 * 1024;
  static const pageBytes = 256;
  static const maxHits = 1000;

  static Future<PagedBinaryFile> open(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) {
      throw const FormatException('Select a regular local file');
    }
    final file = File(path);
    final resolved = await file.resolveSymbolicLinks();
    final stat = await File(resolved).stat();
    if (stat.type != FileSystemEntityType.file || stat.size < 1 || stat.size > maxFile) {
      throw const FormatException('File must contain 1 byte–1 GiB');
    }
    return PagedBinaryFile(resolved, stat.size, stat.modified);
  }

  static Future<void> _check(PagedBinaryFile file) async {
    final stat = await File(file.path).stat();
    if (stat.type != FileSystemEntityType.file || stat.size != file.length ||
        stat.modified != file.modified) {
      throw const FormatException('File changed; reopen it before analysis');
    }
  }

  static Future<Uint8List> page(PagedBinaryFile file, int offset) async {
    if (offset < 0 || offset >= file.length) {
      throw const FormatException('Invalid file offset');
    }
    await _check(file);
    final handle = await File(file.path).open();
    try {
      await handle.setPosition(offset);
      final count = (file.length - offset).clamp(1, pageBytes).toInt();
      final data = await handle.read(count);
      if (data.length != count) {
        throw const FormatException('Truncated read');
      }
      await _check(file);
      return data;
    } finally {
      await handle.close();
    }
  }

  static Future<String> hash(PagedBinaryFile file) => Isolate.run(() async {
    await _check(file);
    final result = await sha256.bind(File(file.path).openRead(0, file.length)).first;
    await _check(file);
    return result.toString();
  });

  /// Stream exact overlapping matches; read extra lookahead at window boundary.
  /// Cursor is the next unexamined candidate start, not the last byte read.
  static Future<(List<int>, int?)> search(PagedBinaryFile file, int start,
      Uint8List needle, {int window = windowBytes}) => Isolate.run(() async {
    if (start < 0 || start >= file.length || needle.isEmpty ||
        needle.length > 256 || window < 1 || window > windowBytes) {
      throw const FormatException('Invalid search range or pattern');
    }
    await _check(file);
    final stop = (start + window).clamp(start, file.length).toInt();
    final end = (stop + needle.length - 1).clamp(stop, file.length).toInt();
    final failure = List<int>.filled(needle.length, 0);
    for (var i = 1, j = 0; i < needle.length; i++) {
      while (j > 0 && needle[i] != needle[j]) {
        j = failure[j - 1];
      }
      if (needle[i] == needle[j]) {
        j++;
      }
      failure[i] = j;
    }
    final hits = <int>[];
    var pos = start, j = 0;
    await for (final chunk in File(file.path).openRead(start, end)) {
      for (final byte in chunk) {
        while (j > 0 && byte != needle[j]) {
          j = failure[j - 1];
        }
        if (byte == needle[j]) {
          j++;
        }
        if (j == needle.length) {
          final at = pos - j + 1;
          if (at < stop) {
            hits.add(at);
            if (hits.length == maxHits) {
              await _check(file);
              return (hits, at + 1 < file.length ? at + 1 : null);
            }
          }
          j = failure[j - 1];
        }
        pos++;
      }
    }
    if (pos != end) {
      throw const FormatException('Truncated search range');
    }
    await _check(file);
    return (hits, stop < file.length ? stop : null);
  });
}
