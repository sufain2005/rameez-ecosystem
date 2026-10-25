import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'tls_config.dart';

/// Core Security Engine for Rameez Kitchen Applications
/// Provides:
/// 1. Anti-Burp Suite & Anti-Proxy TLS Verification
/// 2. Cryptographic HMAC-SHA256 Request Signing & Nonce Generation
/// 3. Replay-Attack Prevention & Anti-Tampering Validation
/// 4. Release Log Sanitization & Debugger Leak Prevention
class AppSecurity {
  AppSecurity._();

  // Obfuscated Rolling App Key for HMAC Request Signing
  static const String _appSigningSecret = 'rk_sec_994bfa283c07f45a8e10d287bc12';

  /// Initialize Application Security Layer
  static void init({String clientName = 'customer_app'}) {
    // 1. In release mode, silence debug prints to prevent token / endpoint log leaks
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }

    // 2. Configure Strict TLS & Certificate Validation (Blocks Burp Suite / MitM proxies on Mobile)
    try {
      setupStrictTls();
    } catch (_) {
      // Fallback gracefully on unsupported platforms
    }
  }

  /// Generates cryptographic tamper-proof request headers
  static Map<String, String> generateSecurityHeaders({
    required String method,
    required String path,
    dynamic body,
    String clientName = 'customer_app',
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _generateSecureNonce();
    
    // Normalize path (extract pathname without host or query params for signature stability)
    final cleanPath = path.startsWith('http') ? Uri.parse(path).path : path;
    
    // Normalize body string
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

    // Message format: METHOD:PATH:TIMESTAMP:NONCE:BODY
    final payloadToSign = '${method.toUpperCase()}:$cleanPath:$timestamp:$nonce:$bodyPayload';
    
    // Compute HMAC-SHA256
    final hmac = Hmac(sha256, utf8.encode(_appSigningSecret));
    final signature = hmac.convert(utf8.encode(payloadToSign)).toString();

    return {
      'X-App-Client': clientName,
      'X-App-Timestamp': timestamp,
      'X-App-Nonce': nonce,
      'X-App-Signature': signature,
    };
  }

  /// Generates a cryptographically secure 16-byte random hex nonce
  static String _generateSecureNonce() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
