import 'package:droidre_ai_studio/services/apk_signer_verification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('complete verified signer list and unordered comparison', () {
    final a = List.filled(64, 'a').join();
    final b = List.filled(64, 'b').join();
    final text = 'Number of signers: 2\nSigner #1 certificate SHA-256 digest: $b\nSigner #2 certificate SHA-256 digest: $a\n';
    expect(ApkSignerVerification.parseSigners(text), [a, b]);
    expect(ApkSignerVerification.sameSignerSet([[a,b],[b,a]]), true);
    expect(ApkSignerVerification.sameSignerSet([[a],[b]]), false);
    expect(() => ApkSignerVerification.parseSigners(text.replaceFirst('signers: 2','signers: 3')), throwsFormatException);
    expect(ApkSignerVerification.arguments('tool.jar','file.apk'), ['-jar','tool.jar','verify','--verbose','--print-certs','file.apk']);
  });
}
