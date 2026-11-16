import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/dex_class_annotation_inspector.dart';
import 'package:droidre_ai_studio/services/dex_inspector.dart';
import 'package:droidre_ai_studio/services/source_recovery_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/annotation_types_fixture.dart';

void main() {
  test('reads class, method and parameter annotation type inventory', () {
    final dex = makeDexWithAnnotationTypes();
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final report = DexClassAnnotationInspector.inspectBytes(dex, cls);
    expect(report.partial, isFalse);
    expect(report.targets, hasLength(3));
    expect(report.targets.map((item) => item.kind),
        ['class', 'method', 'parameter']);
    expect(report.targets[1].poolIndex, 204);
    expect(report.targets[2].parameterIndex, 0);
    for (final target in report.targets) {
      expect(target.annotations, hasLength(1));
      expect(target.annotations.single.type, 'Lcom/demo/Many;');
      expect(target.annotations.single.visibility, 'runtime');
      expect(target.annotations.single.elementCount, 0);
      expect(target.annotations.single.toJson()['valuesDecoded'], isFalse);
    }
  });

  test('broken annotation set is partial without pretending to decode', () {
    final dex = makeDexWithAnnotationTypes(invalidSet: true);
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final report = DexClassAnnotationInspector.inspectBytes(dex, cls);
    expect(report.partial, isTrue);
    expect(report.warnings.join(' '), contains('annotation'));
    expect(report.targets, isEmpty);
  });

  test('class without annotations returns empty, non-partial report', () {
    final dex = makeDexWithAnnotationTypes();
    final cls = DexInspector.inspectBytes(dex).classes.single;
    // Change class annotation-directory pointer to the no-annotations value.
    final copy = Uint8List.fromList(dex);
    ByteData.sublistView(copy).setUint32(2920, 0, Endian.little);
    final report = DexClassAnnotationInspector.inspectBytes(copy, cls);
    expect(report.targets, isEmpty);
    expect(report.partial, isFalse);
  });

  test('source bundle exports per-DEX annotation inventory', () {
    final apk = Archive()
      ..addFile(ArchiveFile.bytes(
        'classes.dex', makeDexWithAnnotationTypes(),
      ));
    final bundle = SourceRecoveryBundle.fromArchive(apk);
    final zip = ZipDecoder().decodeBytes(bundle.zipBytes, throwOnError: true);
    String read(String filename) => utf8.decode(
      zip.files.singleWhere((file) => file.name == filename).readBytes()!,
    );
    final decoded = jsonDecode(
      read('recovered/dex_01/ANNOTATIONS_INDEX.json')) as Map<String, dynamic>;
    final classes = decoded['classes'] as List;
    expect(classes, hasLength(1));
    final cls = classes.first as Map<String, dynamic>;
    final inventory = cls['annotations'] as Map<String, dynamic>;
    expect(inventory['partial'], false);
    expect(inventory['targets'], hasLength(3));
    expect(read('recovered/dex_01/classes/0001/annotations.json'),
        contains('Lcom/demo/Many;'));
    final report = jsonDecode(read('REPORT.json')) as Map<String, dynamic>;
    expect(report['annotationTypesExported'], 3);
  });

  test('malformed class annotations do not block independent method export',
      () {
    final apk = Archive()
      ..addFile(ArchiveFile.bytes(
          'classes.dex', makeDexWithAnnotationTypes(invalidSet: true)));
    final bundle = SourceRecoveryBundle.fromArchive(apk);
    expect(bundle.partial, isTrue);
    expect(bundle.methodsExported, 205);
    expect(bundle.warnings.join(' '), contains('annotation'));
  });
}
