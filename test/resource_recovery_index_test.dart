import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/android_binary_xml_decoder.dart';
import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:droidre_ai_studio/services/resource_inspector.dart';
import 'package:droidre_ai_studio/services/resource_recovery_index.dart';
import 'package:droidre_ai_studio/services/source_recovery_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'android_binary_xml_decoder_test.dart' show sampleBinaryXml;
import 'arsc_value_reader_test.dart' show resourceTableWithValue;

Uint8List referenceXml(int id, {int type = 1, bool keepRaw = false}) {
  final bytes = sampleBinaryXml();
  final data = ByteData.sublistView(bytes);
  final start = 8 + data.getUint32(12, Endian.little);
  if (!keepRaw) {
    data.setUint32(start + 44, 0xffffffff, Endian.little);
  }
  bytes[start + 51] = type;
  data.setUint32(start + 52, id, Endian.little);
  return bytes;
}

void main() {
  test('records typed reference while retaining original numeric XML', () {
    final xml = AndroidBinaryXmlDecoder.decode(referenceXml(0x7f010000));
    expect(xml.xml, contains('@0x7f010000'));
    expect(xml.references.single.id, 0x7f010000);
    expect(xml.references.single.rawValuePresent, isFalse);
    final index = ResourceRecoveryIndex(
        ResourceInspector.inspectTableBytes(resourceTableWithValue()));
    final hint = index.reference(xml.references.single);
    expect(hint['status'], 'known-name');
    expect(hint['nameHint'], '@string/title');
  });

  test('keeps raw string and captures its encoded reference separately', () {
    final xml = AndroidBinaryXmlDecoder.decode(
        referenceXml(0x7f010000, keepRaw: true));
    expect(xml.xml, contains('Hello &amp; &lt;world&gt;'));
    expect(xml.references.single.rawValuePresent, isTrue);
  });

  test('does not guess dynamic, missing or conflicting references', () {
    final index = ResourceRecoveryIndex(const ResourceTableSummary(
      packageCount: 1, packages: ['demo'], stringPoolChunks: 1,
      values: [
        ArscValue(0x7f010000, '@string/a', 'A', 1),
        ArscValue(0x7f010000, '@string/b', 'B', 2),
      ],
    ));
    final ref = AndroidBinaryXmlDecoder.decode(referenceXml(0x7f010000))
        .references.single;
    expect(index.reference(ref)['nameHint'], isNull);
    final dynamicRef = AndroidBinaryXmlDecoder.decode(
        referenceXml(0x7f010000, type: 7)).references.single;
    expect(index.reference(dynamicRef)['status'], 'dynamic-unresolved');
    final absent = AndroidBinaryXmlDecoder.decode(referenceXml(0x01010000))
        .references.single;
    expect(index.reference(absent)['status'], 'not-in-preview');
    expect(ResourceRecoveryIndex(null).reference(ref)['status'], 'table-unavailable');
  });

  test('source ZIP includes table values and XML reference sidecar', () {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('resources.arsc', resourceTableWithValue()))
      ..addFile(ArchiveFile.bytes('res/layout/main.xml', referenceXml(0x7f010000)));
    final bundle = SourceRecoveryBundle.fromArchive(archive);
    final zip = ZipDecoder().decodeBytes(bundle.zipBytes, throwOnError: true);
    Map<String, dynamic> read(String path) => jsonDecode(utf8.decode(
      zip.files.singleWhere((entry) => entry.name == path).readBytes()!,
    )) as Map<String, dynamic>;
    final table = read('resources/RESOURCE_TABLE.json');
    expect(table['available'], true);
    expect(table['values'][0]['name'], '@string/title');
    final refs = read('resources/XML_REFERENCES.json');
    expect(refs['documents'][0]['references'][0]['nameHint'], '@string/title');
    expect(read('REPORT.json')['resourceValuesIndexed'], 1);
  });

  test('malformed ARSC does not prevent other source previews', () {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('resources.arsc', Uint8List(8)))
      ..addFile(ArchiveFile.bytes('res/layout/main.xml', referenceXml(0x7f010000)));
    final result = SourceRecoveryBundle.fromArchive(archive);
    expect(result.partial, isTrue);
    expect(result.warnings.join(' '), contains('resource table could not be decoded'));
    final zip = ZipDecoder().decodeBytes(result.zipBytes, throwOnError: true);
    expect(zip.files.map((entry) => entry.name), contains('resources/XML_REFERENCES.json'));
  });
}
