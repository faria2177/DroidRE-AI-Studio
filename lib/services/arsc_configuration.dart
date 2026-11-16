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
    this.bcp47Locale,
    this.localeScript,
    this.localeVariant,
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
  /// Resource directory locale qualifier, including b+ notation where needed.
  final String? locale;
  /// BCP-47 language tag for valid decoded locale components.
  final String? bcp47Locale;
  final String? localeScript;
  final String? localeVariant;
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

    // AOSP stores 2-letter ASCII or packed 3-letter language/region
    // codes in two bytes. The third packed letter uses the top bit of
    // the first byte. Unsupported/corrupt characters are never guessed.
    String? unpackLocalePair(int first, int second, {
      required int base,
      required bool Function(int code) isValid,
    }) {
      if (first == 0 && second == 0) {
        return null;
      }
      if ((first & 0x80) != 0) {
        final codes = <int>[
          (second & 0x1f) + base,
          (((second & 0xe0) >> 5) | ((first & 0x03) << 3)) + base,
          ((first & 0x7c) >> 2) + base,
        ];
        return codes.every(isValid) ? String.fromCharCodes(codes) : null;
      }
      return isValid(first) && isValid(second)
          ? String.fromCharCodes([first, second])
          : null;
    }

    bool lowercase(int code) => code >= 97 && code <= 122;
    bool uppercase(int code) => code >= 65 && code <= 90;
    bool numeric(int code) => code >= 48 && code <= 57;

    String? language;
    String? region;
    String? locale;
    String? bcp47Locale;
    String? localeScript;
    String? localeVariant;
    if (size >= 12) {
      final langA = byte(8);
      final langB = byte(9);
      final regA = byte(10);
      final regB = byte(11);
      language = unpackLocalePair(
          langA, langB, base: 97, isValid: lowercase);
      region = (regA & 0x80) != 0
          ? unpackLocalePair(regA, regB, base: 48, isValid: numeric)
          : unpackLocalePair(regA, regB, base: 65, isValid: uppercase);
      if (language != null ||
          (langA == 0 && langB == 0)) {
        recognized(8, 10);
      }
      if (region != null ||
          (regA == 0 && regB == 0)) {
        recognized(10, 12);
      }
    }

    // ResTable_config fields introduced after the 36-byte base:
    // script[4] at +36 and variant[8] at +40.
    String? asciiSubtag(int start, int length, {
      required bool Function(int code) valid,
      required int minLength,
    }) {
      if (size < start + length) {
        return null;
      }
      final codes = <int>[
        for (var i = 0; i < length; i++) byte(start + i),
      ];
      if (codes.every((code) => code == 0)) {
        return null;
      }
      final end = codes.indexOf(0);
      final count = end < 0 ? length : end;
      if (count < minLength ||
          !codes.take(count).every(valid) ||
          codes.skip(count).any((code) => code != 0)) {
        return null;
      }
      return String.fromCharCodes(codes.take(count));
    }

    if (language != null) {
      final scriptRaw = asciiSubtag(36, 4,
          valid: (code) => lowercase(code) || uppercase(code),
          minLength: 4);
      if (scriptRaw != null) {
        localeScript = '${scriptRaw.substring(0, 1).toUpperCase()}'
            '${scriptRaw.substring(1).toLowerCase()}';
        recognized(36, 40);
      }
      final variantRaw = asciiSubtag(40, 8,
          valid: (code) => lowercase(code) ||
              uppercase(code) || numeric(code),
          minLength: 4);
      if (variantRaw != null &&
          (variantRaw.length >= 5 ||
              numeric(variantRaw.codeUnitAt(0)))) {
        localeVariant = variantRaw.toLowerCase();
        recognized(40, 48);
      }

      final localeParts = <String>[
        language,
        if (localeScript != null) localeScript,
        if (region != null) region,
        if (localeVariant != null) localeVariant,
      ];
      bcp47Locale = localeParts.join('-');
      locale = localeScript != null || localeVariant != null
          ? 'b+${localeParts.join('+')}'
          : region == null ? language : '$language-r$region';
      qualifiers.add(locale);
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
      bcp47Locale: bcp47Locale,
      localeScript: localeScript,
      localeVariant: localeVariant,
      nightMode: nightMode,
      density: density,
      sdkVersion: sdkVersion,
      smallestWidthDp: smallestWidthDp,
      orientation: orientation,
    );
  }
}
