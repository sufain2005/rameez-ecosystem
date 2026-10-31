import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/services/api_service.dart';
import '../data/services/secure_storage_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({ApiService? api, SecureStorageService? storage})
      : _storage = storage ?? SecureStorageService() {
    _api = api ?? ApiService(storage: _storage);
    // If the server says the session is dead (expired / revoked), log out locally too.
    ApiService.onSessionExpired = _onSessionExpired;
  }

  final SecureStorageService _storage;
  late final ApiService _api;

  // ---------- config ----------
  static const String _defaultAvatar =
      'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400';
  static const int _maxOtpAttempts = 5;
  static const Duration _lockDuration = Duration(minutes: 1);
  static const int _resendSeconds = 30;

  /// DEBUG-ONLY shortcut for testing before the backend is upgraded.
  /// Enabled only with:  flutter run --dart-define=DEV_LOGIN_BYPASS=true
  /// It can never be active in a release build (kDebugMode is false there).
  static const bool _devFlag = bool.fromEnvironment('DEV_LOGIN_BYPASS');
  static bool get devLoginEnabled => kDebugMode && _devFlag;
  static const String _devOtp = '1234';

  // ---------- state ----------
  bool _isAuthenticated = false;
  bool _isDarkMode = false;
  bool _isGoldMember = false; // comes from the server only
  String _customerName = 'Guest';
  String _customerPhone = '';
  String _customerEmail = '';
  String _customerAvatar = _defaultAvatar;
  String _customerAddress = 'Setup Delivery Location'; // New address field

  bool _busy = false;
  String? _errorMessage;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  int _resendSecondsLeft = 0;
  Timer? _cooldownTimer;
  bool _disposed = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isDarkMode => _isDarkMode;
  bool get isGoldMember => _isGoldMember;
  String get customerName => _customerName;
  String get customerPhone => _customerPhone;
  String get phoneNumber => _customerPhone;
  String get customerEmail => _customerEmail;
  String get customerAvatar => _customerAvatar;
  String get customerAddress => _customerAddress;

  /// New: use these in login screens (spinner, error text, resend button).
  bool get isBusy => _busy;
  String? get errorMessage => _errorMessage;
  int get resendSecondsLeft => _resendSecondsLeft;

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notify();
  }

  // ---------- preferences ----------
  void toggleDarkMode(bool value) {
    _isDarkMode = value;
    _notify();
  }

  /// Gold membership must be granted by the server. This only works in debug builds for demos.
  void toggleGoldMembership() {
    if (!kDebugMode) return;
    _isGoldMember = !_isGoldMember;
    _notify();
  }

  // ---------- profile ----------
  /// Validates and cleans everything. The phone number is your login identity,
  /// so it can only change through OTP verification and is ignored here.
  bool updateProfile({String? name, String? phone, String? email, String? avatar, String? address}) {
    final cleanName = name == null ? null : _cleanName(name);
    final cleanEmail = email == null ? null : _cleanEmail(email);
    if (name != null && cleanName == null) return _fail('Please enter a valid name.');
    if (email != null && cleanEmail == null) return _fail('Please enter a valid email address.');
    if (avatar != null && !_isValidAvatar(avatar)) return _fail('Invalid profile picture link.');

    if (cleanName != null) _customerName = cleanName;
    if (cleanEmail != null) _customerEmail = cleanEmail;
    if (avatar != null) _customerAvatar = avatar.trim();
    if (address != null && address.trim().isNotEmpty) _customerAddress = address.trim();
    
    _errorMessage = null;
    _notify();
    unawaited(_saveProfile());
    return true;
  }

  // ---------- login ----------
  Future<bool> sendOtp(String phone) async {
    if (_busy) return false;
    final normalized = _normalizePhone(phone);
    if (normalized == null) return _fail('Enter a valid mobile number.');
    if (_resendSecondsLeft > 0) {
      return _fail('Please wait $_resendSecondsLeft s before requesting another OTP.');
    }

    _setBusy(true);
    try {
      try {
        await _api.sendOtp(normalized);
      } on ApiException {
        if (!devLoginEnabled) rethrow; // debug bypass only
      }
      _errorMessage = null;
      _startCooldown();
      return true;
    } on ApiException catch (e) {
      return _fail(e.message);
    } catch (_) {
      return _fail('Could not send OTP. Please try again.');
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> verifyOtp(String phone, String otp, {String? name, String? email}) async {
    if (_busy) return false;
    final normalized = _normalizePhone(phone);
    if (normalized == null) return _fail('Enter a valid mobile number.');
    final code = otp.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(code)) return _fail('Enter the OTP you received.');

    final lock = _lockedUntil;
    if (lock != null && DateTime.now().isBefore(lock)) {
      final s = lock.difference(DateTime.now()).inSeconds + 1;
      return _fail('Too many wrong attempts. Try again in ${s}s.');
    }

    final cleanName = name == null ? null : _cleanName(name);
    final cleanEmail = (email == null || email.trim().isEmpty) ? null : _cleanEmail(email);

    _setBusy(true);
    try {
      Map<String, dynamic>? data;
      try {
        data = await _api.verifyOtp(normalized, code, name: cleanName, email: cleanEmail);
      } on ApiException {
        // Debug-only local login (see _devFlag). In release builds this always rethrows.
        if (!(devLoginEnabled && code == _devOtp)) rethrow;
      }
      _failedAttempts = 0;
      _lockedUntil = null;
      _applyLogin(normalized, data, cleanName, cleanEmail);
      unawaited(_saveProfile());
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 401) {
        _failedAttempts++;
        if (_failedAttempts >= _maxOtpAttempts) {
          _lockedUntil = DateTime.now().add(_lockDuration);
          _failedAttempts = 0;
        }
      }
      return _fail(e.message);
    } catch (_) {
      return _fail('Could not verify OTP. Please try again.');
    } finally {
      _setBusy(false);
    }
  }

  /// Call once at app start (see Patch C). Restores the login if a token is saved.
  Future<void> restoreSession() async {
    try {
      if (!await _storage.hasSession()) return;
      final raw = await _storage.readProfile();
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map) {
          _customerName = _cleanName(m['name']?.toString()) ?? _customerName;
          _customerPhone = _normalizePhone(m['phone']?.toString() ?? '') ?? '';
          _customerEmail = _cleanEmail(m['email']?.toString() ?? '') ?? '';
          final a = m['avatar']?.toString() ?? '';
          if (_isValidAvatar(a)) _customerAvatar = a;
          final addr = m['address']?.toString() ?? '';
          if (addr.isNotEmpty) _customerAddress = addr;
        }
      }
      _isAuthenticated = true;
      _notify();
    } catch (_) {
      // Unreadable storage: stay logged out.
    }
  }

  Future<void> logout() async {
    await _api.logout(); // revokes on the server (best effort) and wipes secure storage
    _resetUser();
    _notify();
  }

  // ---------- internals ----------
  void _onSessionExpired() {
    _resetUser();
    _errorMessage = 'Your session expired. Please log in again.';
    _notify();
  }

  void _applyLogin(String phone, Map<String, dynamic>? data, String? name, String? email) {
    final raw = data?['user'];
    final user = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _isAuthenticated = true;
    _customerPhone = phone;
    _customerName = _cleanName(user['name']?.toString()) ?? name ?? _customerName;
    _customerEmail = _cleanEmail(user['email']?.toString() ?? '') ?? email ?? _customerEmail;
    _isGoldMember = user['is_gold'] == true;
    final addr = user['address']?.toString() ?? '';
    if (addr.isNotEmpty) _customerAddress = addr;
    _errorMessage = null;
  }

  void _resetUser() {
    _isAuthenticated = false;
    _isGoldMember = false;
    _customerName = 'Guest';
    _customerPhone = '';
    _customerEmail = '';
    _customerAvatar = _defaultAvatar;
    _customerAddress = 'Setup Delivery Location';
    _errorMessage = null;
    _failedAttempts = 0;
    _lockedUntil = null;
    _cooldownTimer?.cancel();
    _resendSecondsLeft = 0;
  }

  Future<void> _saveProfile() async {
    try {
      await _storage.saveProfile(jsonEncode({
        'name': _customerName,
        'phone': _customerPhone,
        'email': _customerEmail,
        'avatar': _customerAvatar,
        'address': _customerAddress,
      }));
    } catch (_) {}
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _resendSecondsLeft = _resendSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _resendSecondsLeft--;
      if (_resendSecondsLeft <= 0) {
        _resendSecondsLeft = 0;
        t.cancel();
      }
      _notify();
    });
  }

  void _setBusy(bool v) {
    _busy = v;
    _notify();
  }

  bool _fail(String message) {
    _errorMessage = message;
    _notify();
    return false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static bool _isValidAvatar(String v) {
    final s = v.trim().toLowerCase();
    return s.startsWith('https://') ||
        s.startsWith('http://') ||
        s.startsWith('data:image/') ||
        s.startsWith('/');
  }

  /// +91XXXXXXXXXX. Accepts 10 digits, 0+10 digits, or a full +country number.
  static String? _normalizePhone(String raw) {
    final s = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (RegExp(r'^\+\d{10,15}$').hasMatch(s)) return s;
    if (RegExp(r'^\d{10}$').hasMatch(s)) return '+91$s';
    if (RegExp(r'^0\d{10}$').hasMatch(s)) return '+91${s.substring(1)}';
    return null;
  }

  static String? _cleanName(String? v) {
    if (v == null) return null;
    final s = v
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length < 2) return null;
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  /// '' means "no email" (allowed). null means invalid.
  static String? _cleanEmail(String v) {
    final s = v.trim().toLowerCase();
    if (s.isEmpty) return '';
    if (s.length > 120 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return null;
    return s;
  }

  @override
  void dispose() {
    _disposed = true;
    _cooldownTimer?.cancel();
    ApiService.onSessionExpired = null;
    super.dispose();
  }
}