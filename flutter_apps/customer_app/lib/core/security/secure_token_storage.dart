// File location in your project: lib/core/security/secure_token_storage.dart
//
// Requires the flutter_secure_storage package. Add to pubspec.yaml:
//   dependencies:
//     flutter_secure_storage: ^9.2.2   (use whatever the latest stable is)
//
// Why this exists:
// The old login flow stored nothing after "login" and every later API call
// (menu, orders, profile, feedback) just trusted a customerPhone field the
// client itself supplied in the JSON body. That means anyone could place
// orders or edit profiles as any phone number they typed in. A real session
// token — issued by the server on successful OTP verification, stored here,
// and attached to every authenticated request — is what closes that hole.
// The backend must then identify the caller from this token, never from a
// client-supplied phone/customerId field in the request body.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStorage {
  SecureTokenStorage._();

  static final SecureTokenStorage instance = SecureTokenStorage._();

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';

  static const AndroidOptions _androidOptions = AndroidOptions(
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
    resetOnError: true,
    storageNamespace: 'rameez_kitchen_secure',
  );

  static const IOSOptions _iosOptions = IOSOptions();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iosOptions,
  );

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(
        key: _accessTokenKey,
        value: accessToken,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      ),
      _storage.write(
        key: _refreshTokenKey,
        value: refreshToken,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      ),
    ]);
  }

  Future<String?> getAccessToken() {
    return _storage.read(
      key: _accessTokenKey,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  Future<String?> getRefreshToken() {
    return _storage.read(
      key: _refreshTokenKey,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
  }

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(
        key: _accessTokenKey,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      ),
      _storage.delete(
        key: _refreshTokenKey,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      ),
    ]);
  }

  Future<bool> hasValidSession() async {
    final accessToken = await getAccessToken();
    final refreshToken = await getRefreshToken();

    return accessToken != null &&
        accessToken.isNotEmpty &&
        refreshToken != null &&
        refreshToken.isNotEmpty;
  }
}