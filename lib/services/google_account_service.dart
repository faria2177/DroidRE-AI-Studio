import 'package:google_sign_in/google_sign_in.dart';

/// Google account selection is optional. A production backend must verify ID
/// tokens before treating this as authorization for remote user data.
class GoogleAccountService {
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  bool _initialized = false;
  GoogleSignInAccount? _account;

  bool get configured => webClientId.isNotEmpty;
  GoogleSignInAccount? get account => _account;

  Future<GoogleSignInAccount> signIn() async {
    if (!configured) {
      throw StateError('Configure GOOGLE_WEB_CLIENT_ID first');
    }
    if (!_initialized) {
      await GoogleSignIn.instance.initialize(serverClientId: webClientId);
      _initialized = true;
    }
    _account = await GoogleSignIn.instance.authenticate();
    return _account!;
  }

  Future<void> signOut() async {
    if (_initialized) await GoogleSignIn.instance.signOut();
    _account = null;
  }
}
