import 'package:flutter/foundation.dart';

/// Read-only qualifiers from ResTable_config inside a ResTable_type.
/// This does not implement Android device configuration matching.
/// Unrecognized nonzero fields are disclosed instead of called "default".
@immutable
class ArscConfiguration {
  const ArscConfiguration({
    required this.chunkIndex,
    required this.qualifiers,
    required this.isDefault,
    required this.hasAdditionalQualifiers,
    this.locale,
    this.nightMode,
    this.density,
    this.sdkVersion,
    this.smallestWidthDp,
    this.orientation,
  });

  final int chunkIndex;
  final String qualifiers;
  final bool isDefault;
  final bool hasAdditionalQualifiers;
  final String? locale;
  final bool? nightMode;
  final int? density;
  final int? sdkVersion;
  final int? smallestWidthDp;
  final String? orientation;

  String get label => '$qualifiers (config chunk $chunkIndex)';

  /// [start] points to the ResTable_config.size (u32). [end] is the end
  /// of the ResTable_type header, never the end of its value entries.
  static ArscConfiguration parse(
    Uint8List bytes, {
    required int start,
    required int end,
    required int chunkIndex,
  }) {
    if (start < 0 || end > bytes.length ||
        start > end || end - start < 4) {
      throw const FormatException('Incomplete ARSC configuration header');
    }
    final view = ByteData.sublistView(bytes);
    final size = view.getUint32(start, Endian.little);
    if (size < 4 || size > 1024 || size > end - start) {
      throw const FormatException('Invalid ARSC configuration size');
    }
    int byte(int offset) => offset < size ? bytes[start + offset] : 0;
    int word(int offset) => offset + 2 <= size
        ? view.getUint16(start + offset, Endian.little)
        : 0;
    final known = <int>{};
    void recognized(int from, int to) {
      for (var i = from; i < to && i < size; i++) {
        known.add(i);
      }
    }
    recognized(0, 4);

    final qualifiers = <String>[];
    final mcc = word(4);
    final mnc = word(6);
    recognized(4, 8);
    if (mcc != 0) {
      qualifiers.add('mcc$mcc');
    }
    if (mnc != 0) {
      qualifiers.add('mnc$mnc');
    }

    // AOSP also supports packed 3-letter locale codes. Only plain
    // two-letter ASCII forms are decoded here. Other forms remain marked
    // as additional qualifiers rather than being misrepresented.
    String? locale;
    if (size >= 12) {
      final langA = byte(8);
      final langB = byte(9);
      final regA = byte(10);
      final regB = byte(11);
      if (langA >= 97 && langA <= 122 &&
          langB >= 97 && langB <= 122) {
        locale = String.fromCharCodes([langA, langB]);
        recognized(8, 10);
        if (regA >= 65 && regA <= 90 &&
            regB >= 65 && regB <= 90) {
          locale = '$locale-r${String.fromCharCodes([regA, regB])}';
          recognized(10, 12);
        } else if (regA == 0 && regB == 0) {
          recognized(10, 12);
        }
        qualifiers.add(locale);
      } else if (langA == 0 && langB == 0 &&
          regA == 0 && regB == 0) {
        recognized(8, 12);
      }
    }

    String? orientation;
    if (size >= 13) {
      orientation = switch (byte(12)) {
        1 => 'port',
        2 => 'land',
        3 => 'square',
        _ => null,
      };
      if (byte(12) <= 3) {
        recognized(12, 13);
      }
      if (orientation != null) {
        qualifiers.add(orientation);
      }
    }
    int? density;
    if (size >= 16) {
      final value = word(14);
      density = value == 0 ? null : value;
      recognized(14, 16);
      if (density != null) {
        qualifiers.add(switch (density) {
          120 => 'ldpi',
          160 => 'mdpi',
          213 => 'tvdpi',
          240 => 'hdpi',
          320 => 'xhdpi',
          480 => 'xxhdpi',
          640 => 'xxxhdpi',
          0xfffe => 'anydpi',
          0xffff => 'nodpi',
          _ => '${density}dpi',
        });
      }
    }

    int? sdkVersion;
    if (size >= 26) {
      final value = word(24);
      sdkVersion = value == 0 ? null : value;
      recognized(24, 26);
      if (sdkVersion != null) {
        qualifiers.add('v$sdkVersion');
      }
    }

    bool? nightMode;
    if (size >= 30) {
      final uiMode = byte(29);
      nightMode = switch (uiMode & 0x30) {
        0x10 => false,
        0x20 => true,
        _ => null,
      };
      if ((uiMode & ~0x30) == 0) recognized(29, 30);
      if (nightMode != null) {
        qualifiers.add(nightMode ? 'night' : 'notnight');
      }
    }
    int? smallestWidthDp;
    if (size >= 32) {
      final width = word(30);
      smallestWidthDp = width == 0 ? null : width;
      recognized(30, 32);
      if (smallestWidthDp != null) {
        qualifiers.add('sw${smallestWidthDp}dp');
      }
    }
    if (size >= 34) {
      final widthDp = word(32);
      recognized(32, 34);
      if (widthDp != 0) {
        qualifiers.add('w${widthDp}dp');
      }
    }
    if (size >= 36) {
      final heightDp = word(34);
      recognized(34, 36);
      if (heightDp != 0) {
        qualifiers.add('h${heightDp}dp');
      }
    }

    var isDefault = true;
    var hasAdditional = false;
    for (var i = 4; i < size; i++) {
      if (byte(i) == 0) {
        continue;
      }
      isDefault = false;
      if (!known.contains(i)) hasAdditional = true;
    }
    if (hasAdditional) {
      qualifiers.add('additional qualifiers');
    }
    return ArscConfiguration(
      chunkIndex: chunkIndex,
      qualifiers: isDefault
          ? 'default'
          : qualifiers.isEmpty ? 'other qualifiers' : qualifiers.join('-'),
      isDefault: isDefault,
      hasAdditionalQualifiers: hasAdditional,
      locale: locale,
      nightMode: nightMode,
      density: density,
      sdkVersion: sdkVersion,
      smallestWidthDp: smallestWidthDp,
      orientation: orientation,
    );
  }
}
