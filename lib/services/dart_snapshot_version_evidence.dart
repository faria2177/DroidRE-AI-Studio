import 'dart:convert';
import 'dart:typed_data';

class DartSnapshotVersionEvidence {
  const DartSnapshotVersionEvidence._();

  /// Classic snapshot prefix: magic, length excluding magic, raw kind,
  /// then a candidate 32-character version hash. No VM object decoding.
  static Map<String, Object?> inspect(Uint8List sample, int regionBytes) {
    if (sample.length < 52 || regionBytes < 52) {
      return {'status': 'insufficient-sized-region'};
    }
    final data = ByteData.sublistView(sample);
    if (data.getUint32(0, Endian.little) != 0xdcdcf5f5) {
      return {'status': 'magic-not-observed'};
    }
    final length = data.getInt64(4, Endian.little);
    if (length < 48 || length > regionBytes - 4) {
      return {'status': 'unsupported-length'};
    }
    final hash = ascii.decode(sample.sublist(20, 52), allowInvalid: true);
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hash)) {
      return {'status': 'version-pattern-not-observed'};
    }
    return {'status': 'candidate-version-hash',
      'hash': hash.toLowerCase(), 'declaredSnapshotBytes': length + 4,
      'rawKind': data.getInt64(12, Endian.little),
      'note': 'Compare against a trusted SDK snapshot hash; match alone does not validate VM features or object layout.'};
  }
}
