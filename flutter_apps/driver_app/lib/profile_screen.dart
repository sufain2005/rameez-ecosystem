import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'theme.dart';
import 'login_screen.dart';

// ─────────────────────────────────────────────────────────────
// UNIVERSAL DIRECT IMAGE UPLOAD HELPER (Mobile / Laptop / Browser)
// ─────────────────────────────────────────────────────────────
class UniversalImagePicker {
  static void pickImage({
    String? captureMode,
    required void Function(String imageUrl, String fileName) onSelected,
  }) {
    try {
      js.context['__activeDriverPhotoCallback'] = js.JsFunction.withThis((_, dynamic url, dynamic name) {
        if (url != null) {
          onSelected(url.toString(), name?.toString() ?? 'driver_avatar.jpg');
        }
      });

      js.context.callMethod('eval', [
        '''
        (function() {
          var input = document.createElement('input');
          input.type = 'file';
          input.accept = 'image/*';
          ${captureMode == 'camera' ? "input.capture = 'user';" : ""}
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
                if (window.__activeDriverPhotoCallback) {
                  window.__activeDriverPhotoCallback(j.url || base64Data, file.name);
                }
              })
              .catch(function(err) {
                if (window.__activeDriverPhotoCallback) {
                  window.__activeDriverPhotoCallback(base64Data, file.name);
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
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  String? _errorMessage;
  Map<String, dynamic>? _profileData;
  bool _isDarkMode = false;

  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _fetchProfile();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await Api.get('/me');
      if (!mounted) return;

      if (res is Map<String, dynamic>) {
        setState(() {
          _profileData = res;
          _isLoading = false;
        });
        _animController.forward(from: 0.0);
      } else {
        setState(() {
          _errorMessage = 'Invalid response received from server.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load profile. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) return 'DR';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final first = parts[0].isNotEmpty ? parts[0][0] : '';
      final second = parts[1].isNotEmpty ? parts[1][0] : '';
      return (first + second).toUpperCase();
    }
    return name.trim().substring(0, name.trim().length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _handleLogout() async {
    HapticFeedback.mediumImpact();
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.logout_rounded, color: AppColors.danger, size: 24),
              const SizedBox(width: 10),
              Text(
                'Log Out',
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : AppColors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to log out of your driver account?',
            style: TextStyle(
              color: _isDarkMode ? Colors.white70 : AppColors.muted,
              fontSize: 14,
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: _isDarkMode ? Colors.white60 : AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                elevation: 0,
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true && mounted) {
      try {
        await Api.logout();
      } catch (_) {
        // Proceed even if API logout call fails
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isDarkMode ? const Color(0xFF121212) : AppColors.cream;
    final cardColor = _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final primaryTextColor = _isDarkMode ? Colors.white : AppColors.text;
    final secondaryTextColor = _isDarkMode ? Colors.white60 : AppColors.muted;
    final dividerColor = _isDarkMode ? Colors.white10 : Colors.black.withOpacity(0.06);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Driver Profile',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: primaryTextColor),
            onPressed: () {
              HapticFeedback.lightImpact();
              _fetchProfile();
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildBody(bgColor, cardColor, primaryTextColor, secondaryTextColor, dividerColor),
      ),
    );
  }

  Widget _buildBody(Color bgColor, Color cardColor, Color primaryTextColor, Color secondaryTextColor, Color dividerColor) {
    if (_isLoading) {
      return Center(
        key: const ValueKey('loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.orange),
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading driver details...',
              style: TextStyle(color: secondaryTextColor, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        key: const ValueKey('error'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: TextStyle(color: primaryTextColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: secondaryTextColor, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _fetchProfile();
                },
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    final data = _profileData ?? {};
    final String name = (data['name'] ?? 'Driver').toString();
    final String phone = (data['phone'] ?? 'N/A').toString();
    final String email = (data['email'] ?? 'N/A').toString();
    final String driverCode = (data['driver_code'] ?? 'N/A').toString();
    final String vehicleNumber = (data['vehicle_number'] ?? 'N/A').toString();
    final String vehicleType = (data['vehicle_type'] ?? 'Bike / Scooter').toString();
    final String upiId = (data['upi_id'] ?? '').toString();
    final String photoUrl = (data['photo_url'] ?? data['license_photo_url'] ?? '').toString();
    final dynamic ratingRaw = data['rating'] ?? 5.0;
    final double rating = (ratingRaw is num) ? ratingRaw.toDouble() : 5.0;
    final String status = (data['status'] ?? 'OFFLINE').toString().toUpperCase();
    final dynamic earnings = data['today_earnings'] ?? 0;
    final dynamic deliveries = data['today_deliveries'] ?? 0;

    return RefreshIndicator(
      color: AppColors.orange,
      backgroundColor: cardColor,
      onRefresh: _fetchProfile,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Avatar & Header with Direct Photo Upload & Edit Profile
              _buildAvatarCard(name, driverCode, status, photoUrl, data, cardColor, primaryTextColor, secondaryTextColor),
              const SizedBox(height: 16),

              // Today's Performance
              _buildPerformanceMetrics(earnings, deliveries, rating, cardColor, primaryTextColor, secondaryTextColor),
              const SizedBox(height: 16),

              // Driver Info
              _buildInfoSection(phone, email, vehicleNumber, vehicleType, upiId, driverCode, data, cardColor, primaryTextColor, secondaryTextColor, dividerColor),
              const SizedBox(height: 16),

              // Preferences
              _buildPreferencesCard(cardColor, primaryTextColor, secondaryTextColor),
              const SizedBox(height: 24),

              // Logout
              _buildLogoutButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarCard(
    String name,
    String driverCode,
    String status,
    String photoUrl,
    Map<String, dynamic> data,
    Color cardColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    final initials = _getInitials(name);
    final isOnline = status == 'ONLINE' || status == 'ACTIVE';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              GestureDetector(
                onTap: _pickAndUploadPhoto,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: photoUrl.isEmpty
                        ? const LinearGradient(colors: [AppColors.orange, AppColors.golden], begin: Alignment.topLeft, end: Alignment.bottomRight)
                        : null,
                    boxShadow: const [BoxShadow(color: Color(0x40F57C00), blurRadius: 12, offset: Offset(0, 6))],
                  ),
                  child: ClipOval(
                    child: _isUploadingPhoto
                        ? const Center(child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 3))
                        : photoUrl.isNotEmpty
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                ),
                              ),
                  ),
                ),
              ),
              // Camera Upload Overlay Button
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _pickAndUploadPhoto,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
                      border: Border.all(color: cardColor, width: 2.5),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)],
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
              // Status Indicator Dot
              Positioned(
                bottom: 0,
                left: 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.online : AppColors.offline,
                    shape: BoxShape.circle,
                    border: Border.all(color: cardColor, width: 3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(name, style: TextStyle(color: primaryTextColor, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'ID: $driverCode',
                  style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(status),
            ],
          ),
          const SizedBox(height: 14),
          // Edit Profile Action Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.orange, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            ),
            icon: const Icon(Icons.edit_rounded, size: 16, color: AppColors.orange),
            label: const Text(
              'EDIT PROFILE & DETAILS',
              style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: () => _showEditProfileSheet(data),
          ),
        ],
      ),
    );
  }

  void _pickAndUploadPhoto() {
    HapticFeedback.lightImpact();
    UniversalImagePicker.pickImage(
      onSelected: (imageUrl, fileName) async {
        setState(() => _isUploadingPhoto = true);
        try {
          await Api.put('/profile', {'photo_url': imageUrl});
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Profile picture updated successfully!'),
              backgroundColor: Color(0xFF0F8A65),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await _fetchProfile();
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update profile picture.')),
          );
        } finally {
          if (mounted) setState(() => _isUploadingPhoto = false);
        }
      },
    );
  }

  Widget _buildPerformanceMetrics(dynamic earnings, dynamic deliveries, double rating, Color cardColor, Color primaryTextColor, Color secondaryTextColor) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: "Today's Pay", value: rupees(earnings as num), icon: Icons.account_balance_wallet_rounded,
            iconColor: AppColors.orange, cardColor: cardColor, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Deliveries', value: '$deliveries', icon: Icons.delivery_dining_rounded,
            iconColor: AppColors.golden, cardColor: cardColor, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Rating', value: '⭐ ${rating.toStringAsFixed(1)}', icon: Icons.star_rounded,
            iconColor: Colors.amber, cardColor: cardColor, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title, required String value, required IconData icon,
    required Color iconColor, required Color cardColor, required Color primaryTextColor, required Color secondaryTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          FittedBox(child: Text(value, style: TextStyle(color: primaryTextColor, fontSize: 16, fontWeight: FontWeight.bold))),
          const SizedBox(height: 2),
          Text(title, style: TextStyle(color: secondaryTextColor, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
    String phone,
    String email,
    String vehicleNumber,
    String vehicleType,
    String upiId,
    String driverCode,
    Map<String, dynamic> data,
    Color cardColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color dividerColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('ACCOUNT & VEHICLE DETAILS', style: TextStyle(color: secondaryTextColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 14, color: AppColors.orange),
                label: const Text('Edit', style: TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _showEditProfileSheet(data),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildInfoRow(icon: Icons.phone_rounded, iconBg: const Color(0xFFE8F5E9), iconColor: const Color(0xFF2E7D32), title: 'Phone Number', subtitle: phone, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow(icon: Icons.email_rounded, iconBg: const Color(0xFFE3F2FD), iconColor: const Color(0xFF1565C0), title: 'Email Address', subtitle: email, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow(icon: Icons.two_wheeler_rounded, iconBg: const Color(0xFFFFF3E0), iconColor: AppColors.orange, title: 'Vehicle Plate / Reg No.', subtitle: vehicleNumber, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow(icon: Icons.electric_moped_rounded, iconBg: const Color(0xFFF1F8E9), iconColor: const Color(0xFF558B2F), title: 'Vehicle Type', subtitle: vehicleType, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor),
          if (upiId.isNotEmpty) ...[
            Divider(color: dividerColor, height: 16),
            _buildInfoRow(icon: Icons.account_balance_wallet_rounded, iconBg: const Color(0xFFFFF8E1), iconColor: const Color(0xFFF57F17), title: 'UPI Payout ID', subtitle: upiId, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor),
          ],
          Divider(color: dividerColor, height: 16),
          _buildInfoRow(icon: Icons.badge_rounded, iconBg: const Color(0xFFF3E5F5), iconColor: const Color(0xFF7B1FA2), title: 'Driver Code', subtitle: driverCode, primaryTextColor: primaryTextColor, secondaryTextColor: secondaryTextColor),
        ],
      ),
    );
  }

  void _showEditProfileSheet(Map<String, dynamic> data) {
    final nameCtrl = TextEditingController(text: data['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: data['phone']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: data['email']?.toString() ?? '');
    final vehicleNumCtrl = TextEditingController(text: data['vehicle_number']?.toString() ?? '');
    String selectedVehicleType = data['vehicle_type']?.toString() ?? 'Bike / Scooter';
    final upiCtrl = TextEditingController(text: data['upi_id']?.toString() ?? '');

    bool isSaving = false;
    String? formError;

    final vehicleTypes = [
      'Bike / Scooter',
      'Motorcycle',
      'Electric EV Scooter',
      'Bicycle',
      'Auto Rickshaw',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isDark = _isDarkMode;
            final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
            final textColor = isDark ? Colors.white : AppColors.text;
            final inputBg = isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade50;
            final inputBorder = isDark ? Colors.white24 : Colors.grey.shade300;

            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.edit_note_rounded, color: AppColors.orange, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Edit Driver Profile',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: textColor.withOpacity(0.6)),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (formError != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          formError!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),

                    // Full Name
                    _buildFieldLabel('Full Name', isDark),
                    TextField(
                      controller: nameCtrl,
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: _inputDecoration('e.g. Syed Rameez', inputBg, inputBorder, Icons.person_outline_rounded),
                    ),
                    const SizedBox(height: 14),

                    // Phone Number
                    _buildFieldLabel('Phone Number', isDark),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: _inputDecoration('10-digit mobile number', inputBg, inputBorder, Icons.phone_outlined),
                    ),
                    const SizedBox(height: 14),

                    // Email Address
                    _buildFieldLabel('Email Address', isDark),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: _inputDecoration('e.g. driver@rameezkitchen.com', inputBg, inputBorder, Icons.email_outlined),
                    ),
                    const SizedBox(height: 14),

                    // Vehicle Plate Number
                    _buildFieldLabel('Vehicle Plate / Registration No.', isDark),
                    TextField(
                      controller: vehicleNumCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                      decoration: _inputDecoration('e.g. KA-17-EQ-8842', inputBg, inputBorder, Icons.pin_outlined),
                    ),
                    const SizedBox(height: 14),

                    // Vehicle Type Dropdown
                    _buildFieldLabel('Vehicle Type', isDark),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: inputBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: vehicleTypes.contains(selectedVehicleType) ? selectedVehicleType : vehicleTypes.first,
                          dropdownColor: sheetBg,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.orange),
                          items: vehicleTypes.map((t) {
                            return DropdownMenuItem<String>(
                              value: t,
                              child: Row(
                                children: [
                                  Icon(
                                    t.contains('EV') ? Icons.electric_bike_rounded : Icons.two_wheeler_rounded,
                                    size: 18,
                                    color: AppColors.orange,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(t, style: TextStyle(color: textColor, fontSize: 13)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setSheetState(() => selectedVehicleType = v);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // UPI ID for settlements
                    _buildFieldLabel('UPI ID (For Daily Payouts & Tips)', isDark),
                    TextField(
                      controller: upiCtrl,
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: _inputDecoration('e.g. 9876543210@paytm / name@oksbi', inputBg, inputBorder, Icons.account_balance_wallet_outlined),
                    ),
                    const SizedBox(height: 22),

                    // Save Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final phone = phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
                              final email = emailCtrl.text.trim();
                              final vehNum = vehicleNumCtrl.text.trim().toUpperCase();
                              final upi = upiCtrl.text.trim();

                              if (name.isEmpty) {
                                setSheetState(() => formError = 'Please enter your full name.');
                                return;
                              }
                              if (phone.length < 10) {
                                setSheetState(() => formError = 'Please enter a valid 10-digit mobile number.');
                                return;
                              }

                              setSheetState(() {
                                isSaving = true;
                                formError = null;
                              });

                              try {
                                final payload = {
                                  'name': name,
                                  'phone': phone,
                                  if (email.isNotEmpty) 'email': email,
                                  if (vehNum.isNotEmpty) 'vehicle_number': vehNum,
                                  'vehicle_type': selectedVehicleType,
                                  if (upi.isNotEmpty) 'upi_id': upi,
                                };

                                await Api.put('/profile', payload);
                                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✓ Driver profile updated successfully!'),
                                    backgroundColor: Color(0xFF0F8A65),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                _fetchProfile();
                              } on ApiException catch (e) {
                                setSheetState(() {
                                  isSaving = false;
                                  formError = e.message;
                                });
                              } catch (e) {
                                setSheetState(() {
                                  isSaving = false;
                                  formError = 'Failed to update profile. Check connection.';
                                });
                              }
                            },
                      child: isSaving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text(
                              'SAVE CHANGES',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFieldLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white70 : Colors.grey.shade700,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, Color bg, Color border, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
      prefixIcon: Icon(icon, size: 18, color: AppColors.orange),
      filled: true,
      fillColor: bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
    );
  }

  Widget _buildInfoRow({
    required IconData icon, required Color iconBg, required Color iconColor,
    required String title, required String subtitle,
    required Color primaryTextColor, required Color secondaryTextColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: secondaryTextColor, fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: primaryTextColor, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard(Color cardColor, Color primaryTextColor, Color secondaryTextColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('APP PREFERENCES', style: TextStyle(color: secondaryTextColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isDarkMode ? Colors.amber.withOpacity(0.15) : const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: _isDarkMode ? Colors.amber : const Color(0xFF512DA8),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dark Mode', style: TextStyle(color: primaryTextColor, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_isDarkMode ? 'Dark theme active' : 'Light theme active', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isDarkMode,
                activeTrackColor: AppColors.orange,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  setState(() => _isDarkMode = val);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return InkWell(
      onTap: _handleLogout,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.danger.withOpacity(0.3), width: 1.2),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 10),
            Text('Sign Out', style: TextStyle(color: AppColors.danger, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}