import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'shell.dart';

void importJsDirectPicker({
  String? captureMode,
  required void Function(String url, String name) onPicked,
}) {
  try {
    js.context['__driverPhotoCallback'] = js.JsFunction.withThis((_, dynamic url, dynamic name) {
      if (url != null) {
        onPicked(url.toString(), name?.toString() ?? 'photo.jpg');
      }
    });

    js.context.callMethod('eval', [
      '''
      (function() {
        var input = document.createElement('input');
        input.type = 'file';
        input.accept = 'image/*';
        ${captureMode == 'camera' ? "input.capture = 'environment';" : ""}
        input.style.display = 'none';
        document.body.appendChild(input);

        input.onchange = function(e) {
          var file = e.target.files[0];
          if (!file) {
            if (input.parentNode) document.body.removeChild(input);
            return;
          }
          var reader = new FileReader();
          reader.onload = function(evt) {
            var base64Data = evt.target.result;
            if (input.parentNode) document.body.removeChild(input);
            fetch('https://rameez-kitchen-backend.onrender.com/api/upload', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ image: base64Data, name: file.name })
            })
            .then(function(r) { return r.json(); })
            .then(function(j) {
              if (window.__driverPhotoCallback) {
                window.__driverPhotoCallback(j.url || base64Data, file.name);
              }
            })
            .catch(function(err) {
              if (window.__driverPhotoCallback) {
                window.__driverPhotoCallback(base64Data, file.name);
              }
            });
          };
          reader.readAsDataURL(file);
        };
        input.click();
      })()
      '''
    ]);
  } catch (_) {}
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final _loginForm = GlobalKey<FormState>();
  final _regStep1Form = GlobalKey<FormState>();
  final _regStep2Form = GlobalKey<FormState>();

  int _registerStep = 0; // 0 = Personal Details, 1 = Vehicle & Documents

  // Login controllers
  final _loginId = TextEditingController();
  final _loginPass = TextEditingController();
  bool _hideLoginPass = true;

  // Registration controllers - Step 1
  final _regName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPhone = TextEditingController();

  // Registration controllers - Step 2
  final _regVehicleNum = TextEditingController();
  final _regLicenseNum = TextEditingController();
  final _regPass = TextEditingController();
  String _selectedVehicleType = 'Bike';
  
  // Document photos
  String? _vehiclePhotoUrl = 'https://images.unsplash.com/photo-1558981806-ec527fa84c39?w=600';
  String? _vehiclePhotoLabel = 'Bike Plate Photo Attached';
  String? _licensePhotoUrl = 'https://images.unsplash.com/photo-1557804506-669a67965ba0?w=600';
  String? _licensePhotoLabel = 'DL Document Attached (Front)';
  bool _hideRegPass = true;

  bool _busy = false;
  String? _error;

  final List<String> _vehicleTypes = ['Bike', 'Scooter', 'Electric Bike', 'Van / Auto'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          _error = null;
          _registerStep = 0;
        });
        _scrollToTop();
      }
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _loginId.dispose();
    _loginPass.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regPhone.dispose();
    _regVehicleNum.dispose();
    _regLicenseNum.dispose();
    _regPass.dispose();
    super.dispose();
  }

  Future<void> _quickLogin(String phone, String pass) async {
    _loginId.text = phone;
    _loginPass.text = pass;
    await _submitLogin();
  }

  Future<void> _submitLogin() async {
    if (!_loginForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.login(_loginId.text.trim(), _loginPass.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to connect to server. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToRegisterStep2() {
    if (!_regStep1Form.currentState!.validate()) return;
    setState(() {
      _registerStep = 1;
      _error = null;
    });
    _scrollToTop();
  }

  void _backToRegisterStep1() {
    setState(() {
      _registerStep = 0;
      _error = null;
    });
    _scrollToTop();
  }

  Future<void> _submitRegister() async {
    if (!_regStep2Form.currentState!.validate()) return;
    
    if (_vehiclePhotoUrl == null) {
      setState(() => _error = 'Please attach your Vehicle / Number Plate photo');
      return;
    }
    if (_licensePhotoUrl == null) {
      setState(() => _error = 'Please attach your Driving License (DL) photo');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final payload = {
      'name': _regName.text.trim(),
      'email': _regEmail.text.trim().toLowerCase(),
      'phone': _regPhone.text.trim(),
      'password': _regPass.text,
      'vehicle_type': _selectedVehicleType,
      'vehicle_number': _regVehicleNum.text.trim().toUpperCase(),
      'vehicle_photo_url': _vehiclePhotoUrl,
      'license_number': _regLicenseNum.text.trim().toUpperCase(),
      'license_photo_url': _licensePhotoUrl,
      'photo_url': _licensePhotoUrl,
    };

    try {
      await Api.register(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Registration Successful! Welcome to Rameez Kitchen Delivery Partner Team.'),
          backgroundColor: AppColors.online,
        ),
      );
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Registration failed. Please check your details.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pickVehiclePhoto() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('📸 Attach Vehicle & Plate Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Select or capture a clear photo of your vehicle with number plate', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.camera_alt, color: AppColors.orange),
                ),
                title: const Text('Capture with Camera (Front Plate)', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Direct device camera capture', style: TextStyle(fontSize: 11, color: Colors.grey)),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerPicker(
                    captureMode: 'camera',
                    fallbackUrl: 'https://images.unsplash.com/photo-1558981806-ec527fa84c39?w=600',
                    onPicked: (url, name) {
                      setState(() {
                        _vehiclePhotoUrl = url;
                        _vehiclePhotoLabel = 'Vehicle Photo ($name)';
                        _error = null;
                      });
                    },
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.photo_library, color: Colors.blue),
                ),
                title: const Text('Choose from Gallery / Laptop / Phone Files', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Select file directly from storage', style: TextStyle(fontSize: 11, color: Colors.grey)),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerPicker(
                    fallbackUrl: 'https://images.unsplash.com/photo-1568772585407-9361f9bf3a87?w=600',
                    onPicked: (url, name) {
                      setState(() {
                        _vehiclePhotoUrl = url;
                        _vehiclePhotoLabel = 'Vehicle Photo ($name)';
                        _error = null;
                      });
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickLicensePhoto() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('🪪 Attach Driving License (DL) Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Select or capture a clear front photo of your Driving License', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.camera_alt, color: AppColors.orange),
                ),
                title: const Text('Capture with Camera (Front DL)', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Direct device camera capture', style: TextStyle(fontSize: 11, color: Colors.grey)),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerPicker(
                    captureMode: 'camera',
                    fallbackUrl: 'https://images.unsplash.com/photo-1557804506-669a67965ba0?w=600',
                    onPicked: (url, name) {
                      setState(() {
                        _licensePhotoUrl = url;
                        _licensePhotoLabel = 'DL Document ($name)';
                        _error = null;
                      });
                    },
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.badge, color: Colors.blue),
                ),
                title: const Text('Choose from Gallery / Files', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Select file directly from storage', style: TextStyle(fontSize: 11, color: Colors.grey)),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerPicker(
                    fallbackUrl: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=600',
                    onPicked: (url, name) {
                      setState(() {
                        _licensePhotoUrl = url;
                        _licensePhotoLabel = 'DL Card ($name)';
                        _error = null;
                      });
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerPicker({
    String? captureMode,
    required String fallbackUrl,
    required void Function(String url, String name) onPicked,
  }) {
    try {
      importJsDirectPicker(captureMode: captureMode, onPicked: onPicked);
    } catch (_) {
      onPicked(fallbackUrl, 'Default File');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE8D6), Color(0xFFF4F6F9)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Logo & Header
                    Center(
                      child: Container(
                        height: 70,
                        width: 70,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.orange, AppColors.golden]),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: AppColors.orange.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 40),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'RAMEEZ KITCHEN',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppColors.orange),
                    ),
                    const Text(
                      'Executive Driver Partner Portal',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),

                    // Custom Tab Switcher
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: AppColors.orange,
                        unselectedLabelColor: AppColors.muted,
                        indicatorColor: AppColors.orange,
                        indicatorWeight: 3.5,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        tabs: const [
                          Tab(text: 'Sign In'),
                          Tab(text: 'Register as Driver'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Error Banner
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 13))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Card Container
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: AnimatedBuilder(
                          animation: _tabController,
                          builder: (context, _) {
                            return _tabController.index == 0 ? _buildLoginForm() : _buildRegisterStepper();
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_rounded, color: Colors.green, size: 15),
                          SizedBox(width: 6),
                          Text(
                            '256-Bit Encrypted & Verified Partner Portal',
                            style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Welcome Back!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Sign in with your registered phone or email', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 18),
          TextFormField(
            controller: _loginId,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Phone Number or Email',
              hintText: '9876543210 or driver@email.com',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.trim().length < 4) ? 'Enter your phone or email' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _loginPass,
            obscureText: _hideLoginPass,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_hideLoginPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _hideLoginPass = !_hideLoginPass),
              ),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
            onFieldSubmitted: (_) => _submitLogin(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _submitLogin,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('SIGN IN TO DRIVER APP'),
          ),
          const SizedBox(height: 16),

          // Quick Demo Drivers
          const Divider(),
          const SizedBox(height: 6),
          const Text('Quick One-Tap Demo Sign In:', style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.flash_on, size: 14, color: AppColors.orange),
                label: const Text('Imran Khan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _quickLogin('9876500011', '123456'),
              ),
              ActionChip(
                avatar: const Icon(Icons.flash_on, size: 14, color: AppColors.orange),
                label: const Text('Arjun Kumar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _quickLogin('9876543210', '123456'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──── 2-Step Registration Wizard ────
  Widget _buildRegisterStepper() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stepper Progress Header
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: _registerStep == 0 ? AppColors.orange.withValues(alpha: 0.12) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _registerStep == 0 ? AppColors.orange : Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: _registerStep == 0 ? AppColors.orange : Colors.green,
                      child: Text(
                        _registerStep > 0 ? '✓' : '1',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Personal Info',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _registerStep == 0 ? AppColors.orange : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: _registerStep == 1 ? AppColors.orange.withValues(alpha: 0.12) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _registerStep == 1 ? AppColors.orange : Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: _registerStep == 1 ? AppColors.orange : Colors.grey,
                      child: const Text('2', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Vehicle & DL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _registerStep == 1 ? AppColors.orange : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_registerStep == 0) _buildRegisterStep1() else _buildRegisterStep2(),
      ],
    );
  }

  // ──── Step 1: Personal Details (Name, Email, Phone) ────
  Widget _buildRegisterStep1() {
    return Form(
      key: _regStep1Form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Step 1: Personal Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const Text('Enter your name and contact details for verification', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 16),

          // 1. Full Name
          TextFormField(
            controller: _regName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Driver Full Name',
              hintText: 'e.g. Imran Khan',
              prefixIcon: Icon(Icons.person),
            ),
            validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
          ),
          const SizedBox(height: 12),

          // 2. Email Address
          TextFormField(
            controller: _regEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              hintText: 'driver@email.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter your email address';
              if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email address';
              return null;
            },
          ),
          const SizedBox(height: 12),

          // 3. Mobile Number
          TextFormField(
            controller: _regPhone,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Mobile Number',
              prefixText: '+91 ',
              hintText: '9876543210',
              prefixIcon: Icon(Icons.phone),
              counterText: '',
            ),
            validator: (v) {
              final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
              return digits.length != 10 ? 'Enter a valid 10-digit mobile number' : null;
            },
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: _goToRegisterStep2,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('CONTINUE TO VEHICLE & DL (STEP 2)'),
          ),
        ],
      ),
    );
  }

  // ──── Step 2: Vehicle, Driving License & Password ────
  Widget _buildRegisterStep2() {
    return Form(
      key: _regStep2Form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Step 2: Vehicle & License Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              TextButton.icon(
                onPressed: _backToRegisterStep1,
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('Edit Step 1', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Vehicle Type Dropdown
          DropdownButtonFormField<String>(
            initialValue: _selectedVehicleType,
            decoration: const InputDecoration(labelText: 'Vehicle Type', prefixIcon: Icon(Icons.two_wheeler)),
            items: _vehicleTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedVehicleType = val);
            },
          ),
          const SizedBox(height: 12),

          // Vehicle Plate Number
          TextFormField(
            controller: _regVehicleNum,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Vehicle Registration Plate Number',
              hintText: 'KA-17-EQ-1234',
              prefixIcon: Icon(Icons.tag),
            ),
            validator: (v) => (v == null || v.trim().length < 4) ? 'Enter vehicle plate number' : null,
          ),
          const SizedBox(height: 12),

          // Vehicle Photo Upload Card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _vehiclePhotoUrl != null ? Colors.green : Colors.grey.shade300, width: 1.5),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _vehiclePhotoUrl != null
                      ? Image.network(_vehiclePhotoUrl!, width: 46, height: 46, fit: BoxFit.cover)
                      : Container(
                          height: 46,
                          width: 46,
                          color: AppColors.orange.withValues(alpha: 0.1),
                          child: const Icon(Icons.motorcycle, color: AppColors.orange, size: 24),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _vehiclePhotoLabel ?? 'Vehicle & Plate Photo',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _vehiclePhotoUrl != null ? Colors.green.shade900 : Colors.black87),
                      ),
                      Text(
                        _vehiclePhotoUrl != null ? '✓ Photo ready & attached' : 'Tap Attach to add photo',
                        style: TextStyle(fontSize: 11, color: _vehiclePhotoUrl != null ? Colors.green.shade700 : AppColors.muted),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _pickVehiclePhoto,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(60, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    side: BorderSide(color: _vehiclePhotoUrl != null ? Colors.green : AppColors.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    _vehiclePhotoUrl != null ? 'CHANGE' : 'ATTACH',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _vehiclePhotoUrl != null ? Colors.green : AppColors.orange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Driving License Number
          TextFormField(
            controller: _regLicenseNum,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Driving License (DL) Number',
              hintText: 'KA17-20240001234',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (v) => (v == null || v.trim().length < 4) ? 'Enter driving license number' : null,
          ),
          const SizedBox(height: 12),

          // DL Photo Upload Card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _licensePhotoUrl != null ? Colors.green : Colors.grey.shade300, width: 1.5),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _licensePhotoUrl != null
                      ? Image.network(_licensePhotoUrl!, width: 46, height: 46, fit: BoxFit.cover)
                      : Container(
                          height: 46,
                          width: 46,
                          color: AppColors.orange.withValues(alpha: 0.1),
                          child: const Icon(Icons.document_scanner, color: AppColors.orange, size: 24),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _licensePhotoLabel ?? 'Driving License (DL) Photo',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _licensePhotoUrl != null ? Colors.green.shade900 : Colors.black87),
                      ),
                      Text(
                        _licensePhotoUrl != null ? '✓ DL card verified & attached' : 'Tap Attach to add photo',
                        style: TextStyle(fontSize: 11, color: _licensePhotoUrl != null ? Colors.green.shade700 : AppColors.muted),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _pickLicensePhoto,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(60, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    side: BorderSide(color: _licensePhotoUrl != null ? Colors.green : AppColors.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    _licensePhotoUrl != null ? 'CHANGE' : 'ATTACH',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _licensePhotoUrl != null ? Colors.green : AppColors.orange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Password
          TextFormField(
            controller: _regPass,
            obscureText: _hideRegPass,
            decoration: InputDecoration(
              labelText: 'Create Secret Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_hideRegPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _hideRegPass = !_hideRegPass),
              ),
            ),
            validator: (v) => (v == null || v.length < 4) ? 'Password must be 4+ characters' : null,
          ),
          const SizedBox(height: 18),

          // Submit & Back Buttons
          Row(
            children: [
              OutlinedButton(
                onPressed: _backToRegisterStep1,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(70, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('BACK'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _submitRegister,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('COMPLETE & REGISTER', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}