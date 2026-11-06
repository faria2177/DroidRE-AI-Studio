import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';

/// Google identity only: no Gmail mailbox access and no backend authorization.
/// A Web OAuth client ID is public metadata, not an API secret or token.
class GoogleAccountService extends ChangeNotifier {
  GoogleAccountService._();

  static final GoogleAccountService instance = GoogleAccountService._();
  static const bundledClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const _fileName = 'google_oauth_client.json';

  GoogleSignInAccount? _account;
  String _webClientId = bundledClientId;
  String? _initializedWith;
  bool _loaded = false;

  String get webClientId => _webClientId;
  bool get configured => isValidClientId(_webClientId);
  GoogleSignInAccount? get account => _account;
  bool get requiresRestart =>
      _initializedWith != null && _initializedWith != _webClientId;

  static bool isValidClientId(String value) => RegExp(
    r'^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$',
  ).hasMatch(value.trim());

  Future<File> _configFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<void> loadConfiguration() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final file = await _configFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final saved = json is Map ? json['webClientId'] : null;
        if (saved is String && isValidClientId(saved)) {
          _webClientId = saved;
        }
      }
    } on FileSystemException {
      // A bundle-supplied client ID can still be used if storage fails.
    } on FormatException {
      // Corrupt local configuration does not disable an embedded ID.
    }
    notifyListeners();
  }

  Future<void> saveClientId(String value) async {
    final next = value.trim();
    if (!isValidClientId(next)) {
      throw const FormatException('Enter a valid Web OAuth Client ID ending '
          'in .apps.googleusercontent.com');
    }
    final file = await _configFile();
    await file.writeAsString(jsonEncode({'webClientId': next}), flush: true);
    _webClientId = next;
    notifyListeners();
  }

  Future<void> _initialize() async {
    await loadConfiguration();
    if (!configured) {
      throw StateError('Configure a Google Web OAuth Client ID first');
    }
    if (requiresRestart) {
      throw StateError('Restart the app to apply the updated OAuth Client ID');
    }
    if (_initializedWith != null) {
      return;
    }
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _initializedWith = _webClientId;
  }

  Future<void> restoreSession() async {
    await _initialize();
    _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    notifyListeners();
  }

  Future<GoogleSignInAccount> signIn() async {
    await _initialize();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw UnsupportedError('Interactive Google authentication is not '
          'supported on this platform');
    }
    final selected = await GoogleSignIn.instance.authenticate();
    _account = selected;
    notifyListeners();
    return selected;
  }

  Future<void> signOut() async {
    if (_initializedWith != null) await GoogleSignIn.instance.signOut();
    _account = null;
    notifyListeners();
  }
}
