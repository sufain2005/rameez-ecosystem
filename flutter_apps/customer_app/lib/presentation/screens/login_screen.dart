import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../../logic/auth_provider.dart';
import '../../core/constants/api_constants.dart';
import 'home_screen.dart';

const bool _devBypass = bool.fromEnvironment(
  'DEV_LOGIN_BYPASS',
  defaultValue: false,
);

class CustomerLoginScreen extends StatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _otpFocusNode = FocusNode();

  bool _isOtpSent = false;
  bool _isLoading = false;
  String _errorMessage = '';
  int _resendTimer = 30;
  Timer? _timer;

  String get _phoneDigits => _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');

  bool get _canResend => _resendTimer == 0;

  void _clearError() {
    if (_errorMessage.isEmpty) return;
    setState(() => _errorMessage = '');
  }

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Please enter your full name.';
    if (name.length < 2) return 'Name must be at least 2 characters.';
    if (name.length > 80) return 'Name is too long.';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) return 'Phone number is required.';
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      return 'Enter a valid 10-digit mobile number.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return null;
    if (!RegExp(r'^[\w.+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _sendOtp() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      _clearError();
      return;
    }

    final phone = _phoneDigits;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (phone.length != 10) {
      setState(() => _errorMessage = 'Please enter a valid 10-digit mobile number.');
      _phoneFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    FocusScope.of(context).unfocus();

    try {
      final response = await http
          .post(
            Uri.parse(ApiConstants.sendOtpEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'phone': '+91$phone',
              'name': name,
              'email': email.isEmpty ? null : email,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      final body = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      final isSuccess = response.statusCode >= 200 && response.statusCode < 300;

      if (isSuccess) {
        setState(() {
          _isOtpSent = true;
          _isLoading = false;
          _errorMessage = '';
        });
        _startTimer();
        _otpController.text = (kDebugMode || _devBypass) ? '1234' : '';
        _otpFocusNode.requestFocus();
      } else {
        final message = body['message'] ?? body['error'] ?? 'Could not send OTP. Please try again.';
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
      }
    } catch (_) {
      if (!mounted) return;

      if (_devBypass || kDebugMode) {
        setState(() {
          _isOtpSent = true;
          _otpController.text = '1234';
          _isLoading = false;
          _errorMessage = '';
        });
        _startTimer();
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error — unable to reach the server. Please try again.';
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    final phone = _phoneDigits;

    if (phone.length != 10) {
      setState(() => _errorMessage = 'Invalid phone number.');
      _phoneFocusNode.requestFocus();
      return;
    }

    if (!RegExp(r'^\d{4,6}$').hasMatch(otp)) {
      setState(() => _errorMessage = 'Please enter a valid OTP.');
      _otpFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    FocusScope.of(context).unfocus();

    try {
      final response = await http
          .post(
            Uri.parse(ApiConstants.verifyOtpEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'phone': '+91$phone',
              'otp': otp,
              'name': _nameController.text.trim(),
              'email': _emailController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      final body = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      final isSuccess = response.statusCode >= 200 && response.statusCode < 300;

      if (isSuccess) {
        final customer = body['customer'] as Map<String, dynamic>?;

        final displayName =
            (customer?['name'] as String?) ?? _nameController.text.trim();
        final displayEmail =
            (customer?['email'] as String?) ?? _emailController.text.trim();

        _updateProviderAndNavigate(
          name: displayName.isNotEmpty ? displayName : 'Valued Customer',
          phone: '+91$phone',
          email: displayEmail,
        );
      } else if (response.statusCode == 401 || response.statusCode == 400) {
        setState(() {
          _isLoading = false;
          _errorMessage = body['error'] ?? body['message'] ?? 'Invalid OTP. Please check and try again.';
        });
        _otpController.clear();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = body['message'] ?? body['error'] ?? 'Verification failed. Please try again.';
        });
      }
    } catch (_) {
      if (!mounted) return;

      if (_devBypass || kDebugMode) {
        _updateProviderAndNavigate(
          name: _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : 'Valued Customer',
          phone: '+91$phone',
          email: _emailController.text.trim(),
        );
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error — unable to verify OTP. Please try again.';
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _resendTimer = 30;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendTimer > 0) {
        setState(() => _resendTimer--);
      } else {
        timer.cancel();
      }
    });
  }

  void _updateProviderAndNavigate({
    required String name,
    required String phone,
    required String email,
  }) async {
    try {
      final auth = context.read<AuthProvider>();
      auth.updateProfile(
        name: name,
        phone: phone,
        email: email,
      );
    } catch (_) {
      // Provider may not exist in some flows; ignore safely.
    }

    // Proactively request location permission on login
    try {
      await Geolocator.requestPermission();
    } catch (_) {}

    if (!mounted) return;

    setState(() => _isLoading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          initialName: name,
          initialPhone: phone,
          initialEmail: email,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required IconData icon,
    String? hintText,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: const Color(0xFFF8F8F8),
      prefixIcon: prefix ??
          Icon(
            icon,
            color: const Color(0xFFFF5200),
          ),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFFFF5200),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.3),
      ),
      errorStyle: const TextStyle(fontSize: 12),
    );
  }

  Widget _buildDetailsForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            inputFormatters: [
              LengthLimitingTextInputFormatter(80),
            ],
            validator: _validateName,
            decoration: _buildInputDecoration(
              label: 'Your Full Name',
              hintText: 'e.g., Mohammed Sufain',
              icon: Icons.person_outline_rounded,
            ),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            validator: _validatePhone,
            decoration: _buildInputDecoration(
              label: 'Mobile Number',
              hintText: '9654321076',
              icon: Icons.phone_android_rounded,
              prefix: Container(
                width: 62,
                alignment: Alignment.center,
                child: const Text(
                  '+91',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFF5200),
                  ),
                ),
              ),
            ),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            autofillHints: const [AutofillHints.email],
            inputFormatters: [
              LengthLimitingTextInputFormatter(120),
            ],
            validator: _validateEmail,
            decoration: _buildInputDecoration(
              label: 'Email Address (Optional)',
              icon: Icons.mail_outline_rounded,
              hintText: 'name@example.com',
            ),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 22),

          if (_errorMessage.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                border: Border.all(color: Colors.red.withOpacity(0.25)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5200),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'SEND OTP',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _isOtpSent = false;
                        _errorMessage = '';
                        _otpController.clear();
                      });
                    },
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Verify OTP',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B1B1B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F2EE),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFE0D0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.sms_rounded, color: Color(0xFFFF5200)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'OTP sent to +91 ${_phoneController.text.trim()}',
                  style: const TextStyle(
                    color: Color(0xFF3E3E3E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        TextFormField(
          controller: _otpController,
          focusNode: _otpFocusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          validator: (value) {
            final otp = (value ?? '').trim();
            if (!RegExp(r'^\d{4,6}$').hasMatch(otp)) {
              return 'Enter valid OTP';
            }
            return null;
          },
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 10,
            color: Color(0xFF1B1B1B),
          ),
          decoration: _buildInputDecoration(
            label: 'OTP',
            icon: Icons.lock_outline_rounded,
            hintText: '••••',
          ),
        ),
        const SizedBox(height: 18),

        if (_errorMessage.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              border: Border.all(color: Colors.red.withOpacity(0.25)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5200),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'VERIFY & CONTINUE',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 18),

        Center(
          child: TextButton(
            onPressed: _isLoading || !_canResend ? null : _sendOtp,
            child: Text(
              _canResend ? 'Resend OTP' : 'Resend OTP in ${_resendTimer}s',
              style: TextStyle(
                color: _canResend ? const Color(0xFFFF5200) : Colors.grey,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _phoneFocusNode.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF5200), Color(0xFFFF7A00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF5200).withOpacity(0.25),
                          blurRadius: 18,
                          spreadRadius: 0,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.delivery_dining_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'RAMEEZ KITCHEN',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Authentic Davanagere Dum Biryani & Rolls',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  Text(
                    _isOtpSent ? 'Secure Verification' : 'Welcome Back',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1B1B1B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isOtpSent
                        ? 'Enter the one-time password sent to your phone.'
                        : 'Sign in to continue with your order.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _isOtpSent ? _buildOtpForm() : _buildDetailsForm(),

                  const SizedBox(height: 22),
                  const Center(
                    child: Text(
                      'By continuing, you agree to the Terms & Privacy Policy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}