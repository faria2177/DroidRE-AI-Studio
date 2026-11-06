import 'package:droidre_ai_studio/services/google_account_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts public Web OAuth client IDs, not secrets or random strings', () {
    expect(GoogleAccountService.isValidClientId(
        '123456789-abcdefgh.apps.googleusercontent.com'), isTrue);
    expect(GoogleAccountService.isValidClientId('my-gmail@gmail.com'), isFalse);
    expect(GoogleAccountService.isValidClientId('client-secret'), isFalse);
    expect(GoogleAccountService.isValidClientId(''), isFalse);
  });
}
