import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/dex_class_metadata_inspector.dart';
import 'package:droidre_ai_studio/services/dex_inspector.dart';
import 'package:droidre_ai_studio/services/source_recovery_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/class_metadata_fixture.dart';

void main() {
  test('decodes class hierarchy, source, interfaces and encoded fields', () {
    final dex = makeClassMetadataDex();
    final klass = DexInspector.inspectBytes(dex).classes.single;
    final metadata = DexClassMetadataInspector.inspectBytes(dex, klass);
    expect(metadata.descriptor, 'Lcom/demo/Many;');
    expect(metadata.superDescriptor, 'Ljava/lang/Object;');
    expect(metadata.interfaces, ['Ljava/lang/Object;']);
    expect(metadata.sourceFile, 'Many.java');
    expect(metadata.declaredFieldCount, 2);
    expect(metadata.fields, hasLength(2));
    expect(metadata.fields.first.name, 'counter');
    expect(metadata.fields.first.typeDescriptor, 'I');
    expect(metadata.fields.first.isStatic, isTrue);
    expect(metadata.fields.first.accessFlags, 0x19);
    expect(metadata.fields.last.name, 'isReady');
    expect(metadata.fields.last.isStatic, isFalse);
    expect(metadata.fields.last.accessFlags, 2);
    expect(metadata.truncated, isFalse);

    final preview = DexClassMetadataInspector.structurePreview(metadata);
    expect(preview, contains('.class public abstract Lcom/demo/Many;'));
    expect(preview, contains('.super Ljava/lang/Object;'));
    expect(preview, contains('.implements Ljava/lang/Object;'));
    expect(preview, contains('.field public static final counter:I'));
    expect(preview, contains('.field private isReady:I'));
    expect(preview, contains('NOT assemblable Smali'));
  });

  test('bounded field previews preserve declared counts and partial status', () {
    final dex = makeClassMetadataDex();
    final klass = DexInspector.inspectBytes(dex).classes.single;
    final metadata = DexClassMetadataInspector.inspectBytes(
        dex, klass, fieldLimit: 1);
    expect(metadata.fields, hasLength(1));
    expect(metadata.declaredFieldCount, 2);
    expect(metadata.truncated, isTrue);
    expect(metadata.warnings.single, contains('limited to 1 of 2'));
    expect(metadata.toJson()['decodedFieldCount'], 1);
    expect(() => DexClassMetadataInspector.inspectBytes(
        dex, klass, fieldLimit: 0), throwsFormatException);
  });

  test('rejects invalid superclass indices and incorrect class owners', () {
    final dex = makeClassMetadataDex();
    final klass = DexInspector.inspectBytes(dex).classes.single;
    final badSuper = Uint8List.fromList(dex);
    ByteData.sublistView(badSuper)
        .setUint32(2908, 777, Endian.little);
    expect(() => DexClassMetadataInspector.inspectBytes(badSuper, klass),
        throwsFormatException);

    final badField = Uint8List.fromList(dex);
    ByteData.sublistView(badField)
        .setUint16(960, 2, Endian.little);
    expect(() => DexClassMetadataInspector.inspectBytes(badField, klass),
        throwsFormatException);
  });

  test('source ZIP includes structured metadata and class header preview', () {
    final input = Archive()
      ..addFile(ArchiveFile.bytes('classes.dex', makeClassMetadataDex()));
    final bundle = SourceRecoveryBundle.fromArchive(input);
    expect(bundle.dexFilesVisited, 1);
    expect(bundle.classesExported, 1);
    expect(bundle.methodsExported, 205);
    expect(bundle.partial, isFalse);

    final archive = ZipDecoder().decodeBytes(
        bundle.zipBytes, throwOnError: true);
    String read(String path) => utf8.decode(
      archive.files.singleWhere((file) => file.name == path).readBytes()!,
    );
    final metadataJson = jsonDecode(
        read('recovered/dex_01/CLASS_METADATA.json')) as Map<String, dynamic>;
    expect(metadataJson['classes'], hasLength(1));
    final cls = (metadataJson['classes'] as List).first
        as Map<String, dynamic>;
    expect(cls['metadataAvailable'], true);
    final metadata = cls['metadata'] as Map<String, dynamic>;
    expect(metadata['superDescriptor'], 'Ljava/lang/Object;');
    expect(metadata['decodedFieldCount'], 2);
    expect(metadata['sourceFile'], 'Many.java');

    final classText = read('recovered/dex_01/classes/0001/class.txt');
    expect(classText, contains('.super Ljava/lang/Object;'));
    expect(classText, contains('.field private isReady:I'));
    final dalvik = read('source/dalvik/dex_01/com/demo/Many_0001.dalvik.txt');
    expect(dalvik, contains('.implements Ljava/lang/Object;'));
    expect(dalvik, contains('NOT assemblable Smali'));
    final java = read('source/java_like/dex_01/com/demo/Many_0001.java.txt');
    expect(java, contains('// Field: counter:I'));
    expect(java, contains('not compilable Java'));
  });

  test('corrupt field metadata degrades to partial without dropping methods', () {
    final dex = makeClassMetadataDex();
    ByteData.sublistView(dex).setUint16(960, 2, Endian.little);
    final input = Archive()
      ..addFile(ArchiveFile.bytes('classes.dex', dex));
    final bundle = SourceRecoveryBundle.fromArchive(input);
    expect(bundle.partial, isTrue);
    expect(bundle.methodsExported, 205);
    expect(bundle.warnings.join(' '), contains('class metadata'));
    final archive = ZipDecoder().decodeBytes(
        bundle.zipBytes, throwOnError: true);
    final text = utf8.decode(archive.files.singleWhere(
        (entry) => entry.name == 'recovered/dex_01/CLASS_METADATA.json')
        .readBytes()!);
    expect(text, contains('"metadataAvailable": false'));
  });
}
