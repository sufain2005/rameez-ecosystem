import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'tls_config.dart';

/// Core Security Engine for Rameez Kitchen Driver App
class DriverSecurity {
  DriverSecurity._();

  static const String _appSigningSecret = 'rk_sec_994bfa283c07f45a8e10d287bc12';

  static void init() {
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }

    try {
      setupStrictTls();
    } catch (_) {}
  }

  static Map<String, String> generateSecurityHeaders({
    required String method,
    required String path,
    dynamic body,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _generateSecureNonce();
    final cleanPath = path.startsWith('http') ? Uri.parse(path).path : path;
    
    String bodyPayload = '';
    if (body != null) {
      if (body is String) {
        bodyPayload = body;
      } else {
        try {
          bodyPayload = jsonEncode(body);
        } catch (_) {
          bodyPayload = '';
        }
      }
    }

    final payloadToSign = '${method.toUpperCase()}:$cleanPath:$timestamp:$nonce:$bodyPayload';
    final hmac = Hmac(sha256, utf8.encode(_appSigningSecret));
    final signature = hmac.convert(utf8.encode(payloadToSign)).toString();

    return {
      'X-App-Client': 'driver_app',
      'X-App-Timestamp': timestamp,
      'X-App-Nonce': nonce,
      'X-App-Signature': signature,
    };
  }

  static String _generateSecureNonce() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
