import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Structural evidence only. No certificate or signature is authenticated.
class ApkSignatureEvidence {
  const ApkSignatureEvidence(this.status, this.schemeIds, this.warnings);
  final String status;
  final List<int> schemeIds;
  final List<String> warnings;

  List<String> get schemes => schemeIds.map((id) => switch (id) {
    0x7109871a => 'APK v2',
    0xf05368c0 => 'APK v3',
    0x1b93ad61 => 'APK v3.1',
    _ => 'Other ID 0x${id.toRadixString(16)}',
  }).toList();

  Map<String, Object?> toJson() => {
    'status': status, 'schemes': schemes, 'warnings': warnings,
    'cryptographicallyVerified': false,
  };
}

class ApkSignatureInspector {
  const ApkSignatureInspector._();
  static const maxBlock = 16 * 1024 * 1024;

  static ApkSignatureEvidence inspectFile(String path) {
    final file = File(path).openSync();
    try {
      return _inspect(file.lengthSync(), (offset, size) {
        file.setPositionSync(offset);
        return file.readSync(size);
      });
    } finally {
      file.closeSync();
    }
  }

  static ApkSignatureEvidence inspectBytes(Uint8List bytes) =>
      _inspect(bytes.length, (offset, size) =>
          Uint8List.sublistView(bytes, offset, offset + size));

  static ApkSignatureEvidence _inspect(int length,
      Uint8List Function(int offset, int size) read) {
    Uint8List exact(int offset, int size) {
      if (offset < 0 || size < 0 || offset > length || size > length - offset) {
        throw const FormatException('Signing structure outside file');
      }
      final data = read(offset, size);
      if (data.length != size) {
        throw const FormatException('Truncated signing structure');
      }
      return data;
    }
    try {
      if (length < 22) {
        throw const FormatException('ZIP EOCD missing');
      }
      final tailLength = length.clamp(22, 65557).toInt();
      final tailOffset = length - tailLength;
      final tail = ByteData.sublistView(exact(tailOffset, tailLength));
      int? eocd;
      for (var i = tailLength - 22; i >= 0; i--) {
        if (tail.getUint32(i, Endian.little) == 0x06054b50 &&
            i + 22 + tail.getUint16(i + 20, Endian.little) == tailLength) {
          if (eocd != null) {
            throw const FormatException('Ambiguous ZIP EOCD');
          }
          eocd = i;
        }
      }
      if (eocd == null) {
        throw const FormatException('ZIP EOCD missing');
      }
      final at = eocd;
      final entries = tail.getUint16(at + 10, Endian.little);
      final cdSize = tail.getUint32(at + 12, Endian.little);
      final cd = tail.getUint32(at + 16, Endian.little);
      if (tail.getUint16(at + 4, Endian.little) != 0 ||
          tail.getUint16(at + 6, Endian.little) != 0 ||
          tail.getUint16(at + 8, Endian.little) != entries ||
          entries == 0xffff || cd == 0xffffffff || cdSize == 0xffffffff ||
          cd > tailOffset + at || cdSize != tailOffset + at - cd) {
        throw const FormatException('Unsupported ZIP64, multidisk or central directory layout');
      }
      if (cd < 24) {
        return const ApkSignatureEvidence('no-block-observed', [], []);
      }
      final footer = exact(cd - 24, 24);
      if (ascii.decode(footer.sublist(8), allowInvalid: true) != 'APK Sig Block 42') {
        return const ApkSignatureEvidence('no-block-observed', [], []);
      }
      final size = ByteData.sublistView(footer).getUint64(0, Endian.little);
      if (size < 24 || size > cd - 8 || size > maxBlock) {
        throw const FormatException('Invalid or oversized APK signing block');
      }
      final start = cd - size - 8;
      final block = ByteData.sublistView(exact(start, size + 8));
      if (block.getUint64(0, Endian.little) != size) {
        throw const FormatException('APK signing block sizes disagree');
      }
      final ids = <int>[];
      var pos = 8;
      final end = block.lengthInBytes - 24;
      while (pos < end) {
        if (end - pos < 8 || ids.length >= 256) {
          throw const FormatException('Incomplete or excessive signing block pairs');
        }
        final pairSize = block.getUint64(pos, Endian.little);
        pos += 8;
        if (pairSize < 4 || pairSize > end - pos) {
          throw const FormatException('Invalid signing block pair size');
        }
        final id = block.getUint32(pos, Endian.little);
        if (ids.contains(id)) {
          throw const FormatException('Duplicate signing block ID');
        }
        ids.add(id);
        pos += pairSize;
      }
      return ApkSignatureEvidence('block-observed', List.unmodifiable(ids), const [
        'Block IDs are not proof of a valid signature or signer identity.',
      ]);
    } on FormatException catch (error) {
      return ApkSignatureEvidence('unknown', const [], [error.message]);
    }
  }
}
