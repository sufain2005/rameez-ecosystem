import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'security.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}

class Api {
  // Chrome / Windows: localhost.  Android emulator: change to http://10.0.2.2:5000/api/driver
  // Real phone: use your PC's LAN IP, e.g. http://192.168.1.10:5000/api/driver
  static const String base = 'https://rameez-kitchen-backend.onrender.com/api/driver';

  static String? token;
  static void Function()? onUnauthorized; // set in main.dart

  static Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('driver_token');
  }

  static Future<void> saveToken(String? t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    if (t == null) {
      await p.remove('driver_token');
    } else {
      await p.setString('driver_token', t);
    }
  }

  static Map<String, String> _buildHeaders(String method, String path, [Map<String, dynamic>? body]) {
    final secHeaders = DriverSecurity.generateSecurityHeaders(
      method: method,
      path: Uri.parse('$base$path').path,
      body: body,
    );
    return {
      'Content-Type': 'application/json',
      ...secHeaders,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<dynamic> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$base$path');
    final headers = _buildHeaders(method, path, body);
    http.Response r;
    try {
      switch (method) {
        case 'POST':
          r = await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20));
          break;
        case 'PUT':
          r = await http.put(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20));
          break;
        case 'PATCH':
          r = await http.patch(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20));
          break;
        case 'DELETE':
          r = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 20));
          break;
        default:
          r = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      }
    } catch (_) {
      throw ApiException('Cannot reach server. If the server is spinning up on Render, please retry in a few seconds.', 0);
    }

    dynamic data;
    try {
      data = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      data = null;
    }

    if (r.statusCode == 401 && path != '/login') {
      await saveToken(null);
      onUnauthorized?.call();
    }
    if (r.statusCode >= 400) {
      final msg = (data is Map && (data['error'] != null || data['message'] != null))
          ? (data['error'] ?? data['message']).toString()
          : (r.reasonPhrase != null && r.reasonPhrase!.isNotEmpty)
              ? '${r.reasonPhrase} (${r.statusCode})'
              : 'Error ${r.statusCode}';
      throw ApiException(msg, r.statusCode);
    }
    return data;
  }

  static Future<dynamic> get(String path) => _send('GET', path);
  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body);
  static Future<dynamic> put(String path, [Map<String, dynamic>? body]) => _send('PUT', path, body);
  static Future<dynamic> patch(String path, [Map<String, dynamic>? body]) => _send('PATCH', path, body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

  // ---- auth ----
  static Future<Map<String, dynamic>> login(String login, String password) async {
    final d = await post('/login', {'login': login, 'password': password});
    await saveToken(d['token']);
    return Map<String, dynamic>.from(d['driver']);
  }

  static Future<Map<String, dynamic>> register(Map<String, dynamic> payload) async {
    final d = await post('/register', payload);
    await saveToken(d['token']);
    return Map<String, dynamic>.from(d['driver']);
  }

  static Future<void> logout() async {
    try {
      await post('/logout');
    } catch (_) {}
    await saveToken(null);
  }

  static Future<Map<String, dynamic>> me() async => Map<String, dynamic>.from(await get('/me'));
}
