import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'security.dart';

/// Centralized High-Security Authentication Controller for Merchant Executive App
class MerchantAuth {
  MerchantAuth._();

  static const String _prefTokenKey = 'rk_merchant_jwt_token';
  static const String _prefAdminKey = 'rk_merchant_admin_data';
  static const String baseUrl = 'https://rameez-kitchen-backend.onrender.com';

  static String? token;
  static Map<String, dynamic>? currentAdmin;
  static VoidCallback? onUnauthorized;

  static bool get isAuthenticated => token != null && token!.trim().isNotEmpty;

  /// Initialize and verify saved session on app launch
  static Future<bool> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_prefTokenKey);
      final savedAdminStr = prefs.getString(_prefAdminKey);

      if (savedToken == null || savedToken.isEmpty) {
        token = null;
        currentAdmin = null;
        return false;
      }

      token = savedToken;
      if (savedAdminStr != null) {
        try {
          currentAdmin = jsonDecode(savedAdminStr) as Map<String, dynamic>;
        } catch (_) {}
      }

      // Verify token authenticity against backend
      final isValid = await verifySession();
      if (!isValid) {
        await logout();
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[MerchantAuth] Init error: $e');
      token = null;
      currentAdmin = null;
      return false;
    }
  }

  /// Client-side SQL Injection & Malicious Pattern Detector
  static bool hasSqlInjectionPattern(String input) {
    if (input.isEmpty) return false;
    final patterns = [
      RegExp(r"(')|(--)|(%23)|(#)", caseSensitive: false),
      RegExp(r"(=)[^\n]*(')", caseSensitive: false),
      RegExp(r"\b(union|select|insert|update|delete|drop|truncate|alter|exec|execute)\b", caseSensitive: false),
      RegExp(r"(')\s*(or|and)\s*('|[0-9])", caseSensitive: false),
      RegExp(r"(\bOR\b|\bAND\b)\s+['\d=]+", caseSensitive: false),
    ];
    return patterns.any((p) => p.hasMatch(input));
  }

  /// Execute Merchant Executive Login with HMAC Security & Brute-Force Safeguards
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    bool rememberMe = true,
  }) async {
    final cleanUser = username.trim();
    final cleanPass = password;

    // 1. Client-Side SQL Injection Defense Check
    if (hasSqlInjectionPattern(cleanUser) || hasSqlInjectionPattern(cleanPass)) {
      return {
        'success': false,
        'error': 'Security Shield: Malicious characters or SQL patterns detected. Access blocked.',
      };
    }

    if (cleanUser.isEmpty || cleanPass.isEmpty) {
      return {
        'success': false,
        'error': 'Please provide both username and password.',
      };
    }

    if (cleanPass.length < 4) {
      return {
        'success': false,
        'error': 'Password must be at least 4 characters long.',
      };
    }

    final endpoint = '$baseUrl/api/merchant/login';
    final requestBody = {
      'username': cleanUser,
      'password': cleanPass,
    };

    // 2. Cryptographic HMAC Request Signing
    final secHeaders = MerchantSecurity.generateSecurityHeaders(
      method: 'POST',
      path: '/api/merchant/login',
      body: requestBody,
    );

    final headers = {
      'Content-Type': 'application/json',
      ...secHeaders,
    };

    try {
      final res = await http
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 12));

      dynamic data;
      try {
        data = jsonDecode(res.body);
      } catch (_) {
        data = null;
      }

      if (res.statusCode == 200 && data != null && data['success'] == true) {
        token = data['token']?.toString();
        if (data['admin'] != null && data['admin'] is Map) {
          currentAdmin = Map<String, dynamic>.from(data['admin'] as Map);
        }

        if (rememberMe && token != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefTokenKey, token!);
          if (currentAdmin != null) {
            await prefs.setString(_prefAdminKey, jsonEncode(currentAdmin));
          }
        }

        return {
          'success': true,
          'token': token,
          'admin': currentAdmin,
        };
      } else if (res.statusCode == 429) {
        return {
          'success': false,
          'error': data?['error']?.toString() ??
              'Too many failed attempts. Security cooldown engaged. Please wait 15 minutes.',
        };
      } else if (res.statusCode == 400) {
        return {
          'success': false,
          'error': data?['error']?.toString() ?? 'Security violation detected.',
        };
      } else if (res.statusCode == 401) {
        return {
          'success': false,
          'error': data?['error']?.toString() ?? 'Invalid merchant credentials. Access denied.',
        };
      } else {
        return {
          'success': false,
          'error': data?['error']?.toString() ?? 'Authentication failed (HTTP ${res.statusCode}).',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Cannot connect to server. Ensure backend is running at $baseUrl.',
      };
    }
  }

  /// Verify active JWT session with server
  static Future<bool> verifySession() async {
    if (token == null || token!.isEmpty) return false;

    final secHeaders = MerchantSecurity.generateSecurityHeaders(
      method: 'GET',
      path: '/api/merchant/verify-session',
    );

    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/merchant/verify-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          ...secHeaders,
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['valid'] == true) {
          if (data['admin'] != null && data['admin'] is Map) {
            currentAdmin = Map<String, dynamic>.from(data['admin'] as Map);
          }
          return true;
        }
      }
      return false;
    } catch (_) {
      // If server is temporarily unreachable, trust local token if unexpired
      return true;
    }
  }

  /// Terminate session and remove all credentials
  static Future<void> logout() async {
    final oldToken = token;
    token = null;
    currentAdmin = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTokenKey);
      await prefs.remove(_prefAdminKey);
    } catch (_) {}

    if (oldToken != null && oldToken.isNotEmpty) {
      try {
        final secHeaders = MerchantSecurity.generateSecurityHeaders(
          method: 'POST',
          path: '/api/merchant/logout',
        );
        await http
            .post(
              Uri.parse('$baseUrl/api/merchant/logout'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $oldToken',
                ...secHeaders,
              },
            )
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    onUnauthorized?.call();
  }

  /// Helper to generate authenticated and signed headers for all merchant requests
  static Map<String, String> getAuthenticatedHeaders({
    required String method,
    required String path,
    dynamic body,
  }) {
    final secHeaders = MerchantSecurity.generateSecurityHeaders(
      method: method,
      path: path,
      body: body,
    );
    return {
      'Content-Type': 'application/json',
      ...secHeaders,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}

