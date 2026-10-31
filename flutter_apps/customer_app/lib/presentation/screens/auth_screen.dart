import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../logic/auth_provider.dart';
import '../../core/constants/api_constants.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  static const Color _brandOrange = Color(0xFFFF5200);
  static const Color _brandDark = Color(0xFF1E1E22);

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  final _phoneFocusNode = FocusNode();
  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _otpFocusNode = FocusNode();

  bool _isOtpSent = false;
  bool _isLoading = false;
  bool _isOtpObscured = true;
  String _errorMessage = '';

  Timer? _countdownTimer;
  int _resendCountdown = 30;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _fadeController.dispose();
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

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 30);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  void _showError(String msg) {
    HapticFeedback.heavyImpact();
    setState(() {
      _isLoading = false;
      _errorMessage = msg;
    });
  }

  String _normalizedPhone() {
    final raw = _phoneController.text.trim();
    return '+91${raw.replaceAll(RegExp(r'\D'), '')}';
  }

  bool _validatePhone() {
    final phone = _normalizedPhone();
    if (phone.length < 13) {
      _showError('Enter a valid 10-digit Indian mobile number.');
      _phoneFocusNode.requestFocus();
      return false;
    }
    return true;
  }

  bool _validateUserDetails() {
    if (!_formKey.currentState!.validate()) return false;
    return _validatePhone();
  }

  Future<void> _handleSendOtp() async {
    if (_isLoading) return;
    if (!_validateUserDetails()) return;

    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final phone = _normalizedPhone();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final auth = context.read<AuthProvider>();
      final success = await auth.sendOtp(phone);
      if (!mounted) return;

      if (success) {
        setState(() {
          _isLoading = false;
          _isOtpSent = true;
          _otpController.clear();
          _errorMessage = '';
        });
        _startCountdown();
        _otpFocusNode.requestFocus();
      } else {
        _showError(auth.errorMessage ?? 'Unable to send OTP. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('A network error occurred. Please check your connection or start the Node backend.');
    }
  }

  Future<void> _handleVerifyOtp() async {
    if (_isLoading) return;

    final phone = _normalizedPhone();
    final otp = _otpController.text.trim();

    if (!_validatePhone()) return;
    if (!RegExp(r'^\d{4,6}$').hasMatch(otp)) {
      _showError('Enter the verification code sent to your phone.');
      _otpFocusNode.requestFocus();
      return;
    }

    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final auth = context.read<AuthProvider>();
      final success = await auth.verifyOtp(
        phone,
        otp,
        name: _nameController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      );

      if (!mounted) return;

      if (success) {
        HapticFeedback.mediumImpact();
      } else {
        _showError(auth.errorMessage ?? 'The verification code is invalid or expired.');
      }
    } catch (_) {
      if (!mounted) return;
      _showError('Verification failed. Please try again.');
    }
  }

  void _backToDetails() {
    if (_isLoading) return;
    setState(() {
      _isOtpSent = false;
      _errorMessage = '';
      _otpController.clear();
    });
    _countdownTimer?.cancel();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Please enter your name.';
    if (name.length < 2) return 'Name must be at least 2 characters.';
    if (name.length > 80) return 'Name is too long.';
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    final isValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    return isValid ? null : 'Enter a valid email address.';
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
      hintText: hint,
      prefixIcon: Icon(icon, color: _brandOrange.withOpacity(0.8)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brandOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  // ═════════════════════════ UI BUILDERS ═════════════════════════

  Widget _buildBrandHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 50,
        bottom: 60,
      ),
      decoration: const BoxDecoration(
        color: _brandDark,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: const Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 24),
          const Text(
            'RAMEEZ KITCHEN',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: _brandOrange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: _brandOrange.withOpacity(0.4)),
            ),
            child: const Text(
              'Authentic Davanagere Dum Biryani & Rolls',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep() {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Welcome Back',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _brandDark),
                ),
                const SizedBox(width: 10),
                Image.network(
                  'https://raw.githubusercontent.com/Tarikul-Islam-Anik/Animated-Fluent-Emojis/master/Emojis/Hand%20gestures/Waving%20Hand.png',
                  height: 32,
                  width: 32,
                  errorBuilder: (context, error, stackTrace) => const Text('👋', style: TextStyle(fontSize: 28)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in or create an account to get started.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 40),
            TextFormField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              maxLength: 80,
              validator: _validateName,
              decoration: _inputDecoration(
                label: 'Full Name',
                hint: 'e.g., Mohammed Sufain',
                icon: Icons.person_outline_rounded,
              ).copyWith(counterText: ''),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: (_) => null,
              decoration: _inputDecoration(
                label: 'Mobile Number',
                icon: Icons.phone_android_rounded,
                hint: '10-digit number',
              ).copyWith(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 20, right: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_android_rounded, color: _brandOrange.withOpacity(0.8)),
                      const SizedBox(width: 8),
                      const Text(
                        '+91',
                        style: TextStyle(color: _brandDark, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailController,
              focusNode: _emailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              maxLength: 120,
              validator: _validateEmail,
              decoration: _inputDecoration(
                label: 'Email (Optional)',
                icon: Icons.email_outlined,
              ).copyWith(counterText: ''),
            ),
            const SizedBox(height: 24),
            _buildErrorMessage(),
            _buildPrimaryButton(
              text: 'CONTINUE',
              onPressed: _isLoading ? null : _handleSendOtp,
            ),
            const SizedBox(height: 28),
            _buildTermsAndSecurityBox(),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsAndSecurityBox() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
        child: InkWell(
          onTap: _showTermsAndConditionsModal,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '* ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  'Terms & Conditions Apply',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTermsAndConditionsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _brandOrange.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.description_outlined, color: _brandOrange, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Terms & Conditions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _brandDark,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'Welcome to RAMEEZ KITCHEN.\n\n'
                  '1. Account & Security: By logging in with your phone number and OTP, you confirm that the mobile number belongs to you. Each account is secured with end-to-end token verification.\n\n'
                  '2. Orders & Delivery: All orders are freshly prepared upon confirmation. Estimated delivery times may vary based on weather, peak kitchen hours, and road traffic conditions.\n\n'
                  '3. Pricing & Payments: All prices are listed in Indian Rupees (₹) inclusive of applicable taxes. Payment can be made securely via UPI, digital wallets, or Cash on Delivery where permitted.\n\n'
                  '4. Cancellation & Refunds: Orders can be cancelled prior to kitchen preparation. In case of issues with delivery or food quality, prompt resolution and wallet refunds will be processed in accordance with our refund guidelines.\n\n'
                  '5. Privacy: We value your personal privacy. Your personal information, delivery addresses, and contact numbers are encrypted and strictly used solely for fulfillment of your orders.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandOrange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'I UNDERSTAND & AGREE',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpStep() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _isLoading ? null : _backToDetails,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, size: 24, color: _brandDark),
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Verification',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _brandDark),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: TextStyle(color: Colors.grey.shade600, fontSize: 17, height: 1.5, fontWeight: FontWeight.w500),
              children: [
                const TextSpan(text: "We've sent a secure code to\n"),
                TextSpan(
                  text: '+91 ${_normalizedPhone()}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: _brandDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          TextFormField(
            controller: _otpController,
            focusNode: _otpFocusNode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            obscureText: _isOtpObscured,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(
              letterSpacing: 28,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: _brandDark,
            ),
            onFieldSubmitted: (_) => _handleVerifyOtp(),
            decoration: _inputDecoration(
              label: 'Secure OTP Code',
              icon: Icons.lock_outline_rounded,
              hint: '••••••',
              suffixIcon: IconButton(
                tooltip: _isOtpObscured ? 'Show OTP' : 'Hide OTP',
                padding: const EdgeInsets.only(right: 16),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isOtpObscured = !_isOtpObscured);
                },
                icon: Icon(
                  _isOtpObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.grey.shade600,
                  size: 28,
                ),
              ),
            ).copyWith(
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            ),
          ),
          const SizedBox(height: 32),
          _buildErrorMessage(),
          _buildPrimaryButton(
            text: 'VERIFY & ENTER',
            onPressed: _isLoading ? null : _handleVerifyOtp,
          ),
          const SizedBox(height: 28),
          Center(
            child: TextButton.icon(
              onPressed: _resendCountdown == 0 && !_isLoading ? _handleSendOtp : null,
              icon: Icon(
                Icons.refresh_rounded,
                size: 22,
                color: _resendCountdown == 0 ? _brandOrange : Colors.grey.shade500,
              ),
              label: Text(
                _resendCountdown == 0
                    ? 'Resend Code'
                    : 'Resend Code in ${_resendCountdown}s',
                style: TextStyle(
                  color: _resendCountdown == 0 ? _brandOrange : Colors.grey.shade500,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                backgroundColor:
                    _resendCountdown == 0 ? _brandOrange.withOpacity(0.1) : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _errorMessage.isEmpty
          ? const SizedBox.shrink()
          : Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPrimaryButton({required String text, required VoidCallback? onPressed}) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: onPressed == null
            ? null
            : const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFF9F43)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
        color: onPressed == null ? Colors.grey.shade300 : null,
        boxShadow: onPressed == null
            ? []
            : [
                BoxShadow(
                  color: _brandOrange.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Text(
                    text,
                    style: TextStyle(
                      color: onPressed == null ? Colors.grey.shade500 : Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildBrandHeader(),
            FadeTransition(
              opacity: _fadeAnimation,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Container(
                      padding: const EdgeInsets.all(36),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 40,
                            spreadRadius: 8,
                            offset: const Offset(0, 20),
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.05, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: _isOtpSent
                            ? KeyedSubtree(key: const ValueKey(2), child: _buildOtpStep())
                            : KeyedSubtree(key: const ValueKey(1), child: _buildDetailsStep()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}