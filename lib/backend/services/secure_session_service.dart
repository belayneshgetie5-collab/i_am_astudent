import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureSessionService {
  SecureSessionService._();

  static final SecureSessionService instance = SecureSessionService._();
  static const _accessTokenKey = 'saamep_access_token';
  static const _accountEmailKey = 'saamep_account_email';
  static const _storage = FlutterSecureStorage();

  Future<void> saveAccessToken(String token, {required String email}) async {
    await _storage.write(key: _accessTokenKey, value: token);
    await _storage.write(key: _accountEmailKey, value: email.toLowerCase());
  }

  Future<String?> getAccessToken({required String email}) async {
    final accountEmail = await _storage.read(key: _accountEmailKey);
    if (accountEmail != email.toLowerCase()) return null;
    return _storage.read(key: _accessTokenKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _accountEmailKey);
  }
}
