import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService();

  static const _accessKey = 'rk_access_token';
  static const _refreshKey = 'rk_refresh_token';
  static const _profileKey = 'rk_profile';

   static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // Corrupted / unreadable secure store: wipe it and force a fresh login.
      try {
        await _storage.deleteAll();
      } catch (_) {}
      return null;
    }
  }

  Future<void> _write(String key, String value) => _storage.write(key: key, value: value);

  // Backwards compatible with your old code
  Future<void> saveToken(String token) => _write(_accessKey, token);
  Future<String?> getToken() => _read(_accessKey);

  Future<void> clearAuth() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _profileKey);
  }

  // Session with refresh token
  Future<void> saveSession({required String accessToken, String? refreshToken}) async {
    await _write(_accessKey, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _write(_refreshKey, refreshToken);
    }
  }

  Future<String?> getRefreshToken() => _read(_refreshKey);

  Future<bool> hasSession() async => (await getToken()) != null;

  // Saved profile (name, phone, email, avatar) so the app reopens logged in
  Future<void> saveProfile(String json) => _write(_profileKey, json);
  Future<String?> readProfile() => _read(_profileKey);
}