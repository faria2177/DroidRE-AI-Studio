import 'dart:convert';
import 'dart:typed_data';

class FrameworkVersionMapping {
  const FrameworkVersionMapping._();
  static const hermesLegacyVersions = {59, 62, 74, 76};

  static String compareSnapshotHash(String observed, String reference) {
    final pattern = RegExp(r'^[a-fA-F0-9]{32}$');
    if (!pattern.hasMatch(observed) || !pattern.hasMatch(reference.trim())) {
      throw const FormatException('Expected two 32-hex snapshot hashes');
    }
    return observed.toLowerCase() == reference.trim().toLowerCase()
      ? 'match' : 'different';
  }

  /// Classic IL2CPP metadata string-literal table: length/dataIndex pairs.
  /// Caller must first validate header version and all prefix ranges.
  static Map<String, Object?> literals(Uint8List bytes, int table,
      int tableBytes, int blob, int blobBytes) {
    if (table < 0 || tableBytes < 0 || table > bytes.length ||
        tableBytes > bytes.length - table || tableBytes % 8 != 0 ||
        blob < 0 || blobBytes < 0 || blob > bytes.length ||
        blobBytes > bytes.length - blob ||
        (tableBytes > 0 && blobBytes > 0 && table < blob + blobBytes && blob < table + tableBytes)) {
      throw const FormatException('Invalid literal table or data range');
    }
    final data = ByteData.sublistView(bytes);
    final count = tableBytes ~/ 8;
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < count && i < 200; i++) {
      final at = table + i * 8;
      final length = data.getUint32(at, Endian.little);
      final index = data.getInt32(at + 4, Endian.little);
      if (index < 0 || index > blobBytes || length > blobBytes - index) {
        rows.add({'index': i, 'status': 'invalid-range'});
        continue;
      }
      final size = length.clamp(0, 512).toInt();
      final sample = bytes.sublist(blob + index, blob + index + size);
      rows.add({'index': i, 'fileOffset': blob + index, 'bytes': length,
        'utf8Preview': utf8.decode(sample, allowMalformed: true),
        'clipped': size != length});
    }
    return {'declaredCount': count, 'rows': rows, 'partial': true,
      'note': 'Indexed literal payloads only; no method or native address mapping.'};
  }
}
