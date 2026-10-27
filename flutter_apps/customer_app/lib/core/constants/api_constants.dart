import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  /// Set at build time:
  static const String _override = String.fromEnvironment('API_BASE_URL');
  
  /// YOUR LIVE RENDER BACKEND URL:
  static const String _renderProductionUrl = 'https://rameez-kitchen-backend.onrender.com';

  static String get serverHost {
    if (kIsWeb) {
      final host = (Uri.base.host.isNotEmpty && Uri.base.host != '0.0.0.0') ? Uri.base.host : 'localhost';
      return host;
    }
    return 'localhost';
  }

  static String get serverBaseUrl {
    if (kIsWeb) {
      // If deployed on Vercel or public domain, use the live Render backend
      if (serverHost != 'localhost' && serverHost != '127.0.0.1') {
        return _renderProductionUrl;
      }
      return _renderProductionUrl; // Connect directly to live Render backend
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    } else {
      return _renderProductionUrl;
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
      // Automatically use the live Render URL when building for production
      url = _renderProductionUrl;
    } else {
      // Use local environment for debugging
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