import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  /// Set at build time:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5000/api
  ///   flutter build apk --dart-define=API_BASE_URL=https://api.yourdomain.com/api
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get serverHost {
    if (kIsWeb) {
      final host = (Uri.base.host.isNotEmpty && Uri.base.host != '0.0.0.0') ? Uri.base.host : 'localhost';
      return host;
    }
    return 'localhost';
  }

  static String get serverBaseUrl {
    if (kIsWeb) {
      return 'http://$serverHost:5000';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    } else {
      return 'http://localhost:5000';
    }
  }

  static String get baseUrl {
    String url = '';
    if (_override.isNotEmpty) {
      if (kReleaseMode && !_override.startsWith('https://')) {
        throw StateError('Release builds must use an https:// API_BASE_URL.');
      }
      url = _override;
    } else if (kReleaseMode) {
      throw StateError('API_BASE_URL is required for release builds.');
    } else {
      url = serverBaseUrl;
    }

    // Fix forever: Ensure it always points to the /api namespace
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/api')) {
      url += '/api';
    }
    return url;
  }

  static const Duration requestTimeout = Duration(seconds: 12);

  static String get menuEndpoint => '$baseUrl/menu';
  static String get ordersEndpoint => '$baseUrl/orders';
  static String get sendOtpEndpoint => '$baseUrl/auth/send-otp';
  static String get verifyOtpEndpoint => '$baseUrl/auth/verify-otp';
  static String get refreshEndpoint => '$baseUrl/auth/refresh';
  static String get logoutEndpoint => '$baseUrl/auth/logout';

  static String orderEndpoint(Object id) => '$ordersEndpoint/${Uri.encodeComponent('$id')}';
  static String trackEndpoint(Object orderId) =>
      '$baseUrl/delivery/track/${Uri.encodeComponent('$orderId')}';
}