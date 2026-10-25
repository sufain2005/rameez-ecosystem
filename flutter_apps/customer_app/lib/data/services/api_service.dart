import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/security/app_security.dart';
import '../models/cart_item.dart';
import '../models/menu_item.dart';
import 'secure_storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, [this.statusCode = 0]);
  @override
  String toString() => message;
}

class ApiService {
  ApiService({SecureStorageService? storage, http.Client? client})
      : _storage = storage ?? SecureStorageService(),
        _client = client ?? http.Client();

  final SecureStorageService _storage;
  final http.Client _client;

  /// Set once (AuthProvider does this) to send the user back to login.
  static void Function()? onSessionExpired;

  static Future<bool>? _refreshing; // one refresh at a time

  // ---------------- public API ----------------

  Future<List<MenuItem>> fetchMenu() async {
    final data = await _request('GET', ApiConstants.menuEndpoint, auth: false);
    if (data is! List) throw ApiException('Unexpected response from server.');
    return data.map((j) => MenuItem.fromJson(Map<String, dynamic>.from(j))).toList();
  }

  Future<void> sendOtp(String phone) async {
    final p = phone.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\+?\d{8,15}$').hasMatch(p)) {
      throw ApiException('Enter a valid phone number.');
    }
    final url = ApiConstants.sendOtpEndpoint;
    await _request('POST', url, body: {'phone': p}, auth: false);
  }

  /// Saves the session automatically. Server may return `token`, `refresh_token` and `user`.
  Future<Map<String, dynamic>> verifyOtp(String phone, String otp,
      {String? name, String? email}) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(otp)) throw ApiException('Enter the OTP you received.');
    final url = ApiConstants.verifyOtpEndpoint;
    final data = await _request('POST', url,
        body: {
          'phone': phone.replaceAll(RegExp(r'[\s-]'), ''),
          'otp': otp,
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
        auth: false);
    final map = Map<String, dynamic>.from(data as Map);
    final access = (map['token'] ?? map['access_token'])?.toString();
    if (access == null) throw ApiException('Login failed. Please try again.');
    await _storage.saveSession(
        accessToken: access, refreshToken: map['refresh_token']?.toString());
    return map;
  }

  /// Ready for the upgraded backend. The idempotency key stops double orders
  /// if the customer taps twice or the network retries.
  Future<Map<String, dynamic>> placeOrder({
    required List<CartItem> items,
    required String addressText,
    String? notes,
    int tip = 0,
    required String idempotencyKey,
  }) async {
    if (items.isEmpty) throw ApiException('Your cart is empty.');
    if (tip < 0 || tip > 500) throw ApiException('Tip must be between 0 and 500.');
    final data = await _request('POST', ApiConstants.ordersEndpoint,
        body: {
          'items': items.map((c) => c.toOrderJson()).toList(),
          'address': addressText,
          'notes': notes,
          'tip': tip,
        },
        extraHeaders: {'Idempotency-Key': idempotencyKey});
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>?> trackDelivery(Object orderId) async {
    final data = await _request('GET', ApiConstants.trackEndpoint(orderId));
    return data == null ? null : Map<String, dynamic>.from(data as Map);
  }

  Future<void> logout() async {
    try {
      await _request('POST', ApiConstants.logoutEndpoint, retry: false);
    } catch (_) {
      // Even if the server is unreachable, clear the local session.
    }
    await _storage.clearAuth();
  }

  static String newIdempotencyKey() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // ---------------- internals ----------------

  Future<dynamic> _request(
    String method,
    String url, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool retry = true,
    Map<String, String>? extraHeaders,
  }) async {
    final secHeaders = AppSecurity.generateSecurityHeaders(
      method: method,
      path: url,
      body: body,
      clientName: 'customer_app',
    );
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...secHeaders,
      ...?extraHeaders,
    };
    if (auth) {
      final token = await _storage.getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }

    final uri = Uri.parse(url);
    http.Response res;
    try {
      if (method == 'POST') {
        res = await _client
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(ApiConstants.requestTimeout);
      } else {
        res = await _client.get(uri, headers: headers).timeout(ApiConstants.requestTimeout);
      }
    } on TimeoutException {
      throw ApiException('The server is taking too long. Please try again.');
    } catch (_) {
      throw ApiException('No connection. Check your internet and try again.');
    }

    // Expired access token: try one silent refresh, then repeat the request once.
    if (res.statusCode == 401 && auth && retry) {
      final ok = await _refreshSession();
      if (ok) {
        return _request(method, url,
            body: body, auth: auth, retry: false, extraHeaders: extraHeaders);
      }
      await _storage.clearAuth();
      onSessionExpired?.call();
      throw ApiException('Session expired. Please log in again.', 401);
    }

    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }

    if (res.statusCode >= 400) {
      String msg = (data is Map ? (data['error'] ?? data['message']) : null)?.toString() ?? '';
      if (msg.isEmpty) {
        if (res.statusCode == 429) {
          msg = 'Too many attempts. Please wait a moment and try again.';
        } else if (res.statusCode >= 500) {
          msg = 'Something went wrong on our side. Please try again shortly.';
        } else {
          msg = 'Request failed (${res.statusCode}).';
        }
      }
      throw ApiException(msg, res.statusCode);
    }
    return data;
  }

  Future<bool> _refreshSession() {
    return _refreshing ??= () async {
      try {
        final refresh = await _storage.getRefreshToken();
        if (refresh == null) return false;
        final res = await _client
            .post(Uri.parse(ApiConstants.refreshEndpoint),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'refresh_token': refresh}))
            .timeout(ApiConstants.requestTimeout);
        if (res.statusCode != 200) return false;
        final m = jsonDecode(res.body) as Map;
        final access = (m['token'] ?? m['access_token'])?.toString();
        if (access == null) return false;
        await _storage.saveSession(
            accessToken: access, refreshToken: m['refresh_token']?.toString());
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }
}