import 'dart:io';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/paged_binary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streamed search preserves matches crossing scan windows', () async {
    final dir = await Directory.systemTemp.createTemp('paged_binary_');
    try {
      final path = '${dir.path}/data.bin';
      await File(path).writeAsBytes([0, 1, 1, 1, 2, 3]);
      final file = await PagedBinaryService.open(path);
      final first = await PagedBinaryService.search(file, 0,
        Uint8List.fromList([1, 1]), window: 2);
      expect(first.$1, [1]);
      expect(first.$2, 2);
      final second = await PagedBinaryService.search(file, first.$2!,
        Uint8List.fromList([1, 1]), window: 4);
      expect(second.$1, [2]);
      expect(second.$2, isNull);
      expect(await PagedBinaryService.page(file, 4), [2, 3]);
      await File(path).writeAsBytes([0]);
      await expectLater(PagedBinaryService.page(file, 0), throwsFormatException);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
