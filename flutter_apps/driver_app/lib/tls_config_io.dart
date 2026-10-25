import 'dart:io';
import 'package:flutter/foundation.dart';

void setupStrictTls() {
  HttpOverrides.global = _StrictHttpOverrides();
}

class _StrictHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 15);

    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (kReleaseMode) {
        return false; // Strict blocking of proxy certificates in release
      }
      return host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
    };

    return client;
  }
}
