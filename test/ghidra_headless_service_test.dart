import 'dart:convert';
import 'package:droidre_ai_studio/services/ghidra_headless_service.dart';
import 'package:flutter_test/flutter_test.dart';

String field(String s) => base64Encode(utf8.encode(s));

void main() {
  test('reads function/call records and pseudocode', () {
    final text = [
      'DROIDRE1\t${field("AARCH64:LE:64:v8A")}',
      'F\t${field("1000")}\t${field("start")}',
      'C\t${field("1000")}\t${field("2000")}\t${field("target")}',
      'P\t${field("1000")}\tobserved\t${field("void start() {}")}',
      'F\t${field("2000")}\t${field("target")}',
      'END\t2\t1\tsampled',
    ].join('\n');
    final report = GhidraHeadlessService.parse(text);
    expect(report.functions.first.calls.single.address, '2000');
    expect(report.functions.first.pseudocode, 'void start() {}');
    expect(() => GhidraHeadlessService.parse(text.replaceFirst('END\t2', 'END\t3')), throwsFormatException);
  });
  test('rejects orphan records', () {
    final text = 'DROIDRE1\t${field("x")}\nP\t${field("1000")}\tobserved\t${field("code")}\nEND\t0\t1\tsampled';
    expect(() => GhidraHeadlessService.parse(text), throwsFormatException);
  });
  test('direct Java args preserve spaced paths and fixed limits', () {
    final args = GhidraHeadlessService.arguments('C:/Ghidra dir/Utility.jar',
      'C:/output dir', 'C:/sample.bin', 'C:/scripts', 'C:/report.tsv', '1000');
    expect(args, containsAllInOrder(['-Xmx1536m', '-cp', 'C:/Ghidra dir/Utility.jar',
      'ghidra.GhidraLauncher', 'ghidra.app.util.headless.AnalyzeHeadless']));
    expect(args, containsAllInOrder(['-max-cpu', '2', '-analysisTimeoutPerFile', '90']));
    expect(() => GhidraHeadlessService.arguments('jar','out','sample','scripts','report','-import evil'), throwsFormatException);
  });
}
