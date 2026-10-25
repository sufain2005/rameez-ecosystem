import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/universal_image_picker.dart';
import '../../logic/auth_provider.dart';
import '../../logic/wallet_provider.dart';
import 'login_screen.dart';
import 'wallet_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploadingPhoto = false;
  bool _isLoadingOrders = false;
  List<Map<String, dynamic>> _fetchedOrders = [];

  // Default address presets
  List<Map<String, String>> savedAddresses = [
    {'title': 'Home', 'address': 'Flat 204, Near Bus Stop, 60 Feet Ring Road, Davanagere', 'isDefault': 'true'},
    {'title': 'Work', 'address': 'Tech Hub, 3rd Floor, PB Road, Davanagere', 'isDefault': 'false'},
  ];

  // Default payment methods
  List<String> savedPaymentMethods = [
    'UPI: rameez@okaxis (Primary)',
    'Google Pay (Connected)',
    'PhonePe (Connected)',
    'Debit Card: HDFC Bank •••• 4821',
    'Cash on Delivery (COD)',
  ];

  @override
  void initState() {
    super.initState();
    _fetchPastOrders();
  }

  Future<void> _fetchPastOrders() async {
    setState(() => _isLoadingOrders = true);
    try {
      final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/orders'));
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _fetchedOrders = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingOrders = false);
  }

  Future<void> _syncProfileWithServer({
    required String name,
    required String phone,
    required String email,
    required String avatar,
    required String address,
    required bool isGold,
  }) async {
    try {
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/customer/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'email': email,
          'avatar': avatar,
          'address': address,
          'isGoldMember': isGold,
        }),
      );
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // 1. DIRECT DEVICE PHOTO UPLOAD & AVATAR PICKER
  // ─────────────────────────────────────────────────────────────
  void _openAvatarEditorModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.add_a_photo_rounded, color: AppColors.primaryOrange, size: 24),
                SizedBox(width: 8),
                Text(
                  'Change Profile Picture',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload directly from your device camera, gallery, or choose a culinary avatar.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 18),

            // Option 1: Direct Camera Upload
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Colors.orange.shade50,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.camera_alt_rounded, color: AppColors.primaryOrange),
              ),
              title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: const Text('Use device camera directly', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                _uploadFromDevice(captureMode: 'camera');
              },
            ),
            const SizedBox(height: 10),

            // Option 2: Upload from Device Files / Gallery
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Colors.blue.shade50,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.photo_library_rounded, color: Colors.blue),
              ),
              title: const Text('Upload from Device / Gallery', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: const Text('Select image file from Mobile or Laptop', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                _uploadFromDevice(captureMode: null);
              },
            ),
            const SizedBox(height: 10),

            // Option 3: Pick Foodie Avatars
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Colors.purple.shade50,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.face_retouching_natural_rounded, color: Colors.purple),
              ),
              title: const Text('Choose Foodie Avatar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: const Text('Biryani lover, Chef, Gourmet Foodie presets', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                _openPresetAvatarsSheet();
              },
            ),
            const SizedBox(height: 10),

            // Option 4: Custom Image URL
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Colors.grey.shade100,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.link_rounded, color: Colors.grey),
              ),
              title: const Text('Enter Image Web Link (URL)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Paste https link', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                _openCustomUrlDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _uploadFromDevice({String? captureMode}) {
    setState(() => _isUploadingPhoto = true);
    UniversalImagePicker.pickImage(
      captureMode: captureMode,
      onSelected: (imageUrl, fileName) {
        final auth = context.read<AuthProvider>();
        auth.updateProfile(avatar: imageUrl);
        _syncProfileWithServer(
          name: auth.customerName,
          phone: auth.customerPhone,
          email: auth.customerEmail,
          avatar: imageUrl,
          address: auth.customerAddress,
          isGold: auth.isGoldMember,
        );
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('✓ Profile picture updated successfully from device ($fileName)!'),
          ),
        );
      },
    );
  }

  void _openPresetAvatarsSheet() {
    final auth = context.read<AuthProvider>();
    final presets = [
      {'name': 'Biryani Lover', 'url': 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400'},
      {'name': 'Master Chef', 'url': 'https://images.unsplash.com/photo-1577219491135-ce391730fb2c?w=400'},
      {'name': 'Gourmet Foodie', 'url': 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=400'},
      {'name': 'Royal Guest', 'url': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400'},
      {'name': 'Spicy Connoisseur', 'url': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400'},
      {'name': 'Davanagere Hero', 'url': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Choose Your Avatar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              itemCount: presets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (c, idx) {
                final item = presets[idx];
                return InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    auth.updateProfile(avatar: item['url']);
                    _syncProfileWithServer(
                      name: auth.customerName,
                      phone: auth.customerPhone,
                      email: auth.customerEmail,
                      avatar: item['url']!,
                      address: auth.customerAddress,
                      isGold: auth.isGoldMember,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: Colors.green.shade700, content: Text('✓ Selected ${item['name']} avatar!')),
                    );
                  },
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundImage: NetworkImage(item['url']!),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['name']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openCustomUrlDialog() {
    final auth = context.read<AuthProvider>();
    final ctrl = TextEditingController(text: auth.customerAvatar);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enter Image URL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Web Image URL (https://...)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                auth.updateProfile(avatar: val);
                _syncProfileWithServer(
                  name: auth.customerName,
                  phone: auth.customerPhone,
                  email: auth.customerEmail,
                  avatar: val,
                  address: auth.customerAddress,
                  isGold: auth.isGoldMember,
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. EDIT PROFILE INFO MODAL (Name, Phone, Email, Address)
  // ─────────────────────────────────────────────────────────────
  void _openEditProfileModal() {
    final auth = context.read<AuthProvider>();
    final nameCtrl = TextEditingController(text: auth.customerName);
    final phoneCtrl = TextEditingController(text: auth.customerPhone.isNotEmpty ? auth.customerPhone : '+91 8073349233');
    final emailCtrl = TextEditingController(text: auth.customerEmail);
    final addressCtrl = TextEditingController(text: auth.customerAddress);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.edit_note_rounded, color: AppColors.primaryOrange, size: 26),
                    SizedBox(width: 8),
                    Text('Edit Customer Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Update your personal details for order delivery updates.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 18),

                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: const Icon(Icons.person_rounded, color: AppColors.primaryOrange),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.primaryOrange),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: const Icon(Icons.email_rounded, color: AppColors.primaryOrange),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: addressCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Default Delivery Address',
                    prefixIcon: const Icon(Icons.location_on_rounded, color: AppColors.primaryOrange),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 20),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: const Text('SAVE PROFILE CHANGES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  onPressed: () {
                    final newName = nameCtrl.text.trim();
                    final newPhone = phoneCtrl.text.trim();
                    final newEmail = emailCtrl.text.trim();
                    final newAddress = addressCtrl.text.trim();

                    if (newName.isNotEmpty) {
                      auth.updateProfile(
                        name: newName,
                        phone: newPhone,
                        email: newEmail,
                        address: newAddress,
                      );
                      _syncProfileWithServer(
                        name: newName,
                        phone: newPhone,
                        email: newEmail,
                        avatar: auth.customerAvatar,
                        address: newAddress,
                        isGold: auth.isGoldMember,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Colors.green,
                          content: Text('✓ Profile updated and synchronized with server successfully!'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. SAVED ADDRESSES MANAGER
  // ─────────────────────────────────────────────────────────────
  void _openAddressesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setAddrState) => Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on_rounded, color: AppColors.primaryOrange, size: 24),
                      SizedBox(width: 8),
                      Text('Saved Addresses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryOrange),
                    onPressed: () {
                      _openAddAddressDialog(setAddrState);
                    },
                  ),
                ],
              ),
              const Divider(),
              ...savedAddresses.map((addr) {
                final isDefault = addr['isDefault'] == 'true';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDefault ? Colors.orange.shade50 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isDefault ? Colors.orange.shade200 : Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        addr['title'] == 'Home' ? Icons.home_rounded : Icons.work_rounded,
                        color: isDefault ? AppColors.primaryOrange : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(addr['title']!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                if (isDefault) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.primaryOrange, borderRadius: BorderRadius.circular(8)),
                                    child: const Text('DEFAULT', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                  ),
                                ]
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(addr['address']!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        color: isDefault ? AppColors.primaryOrange : Colors.grey.shade300,
                        onPressed: () {
                          setAddrState(() {
                            for (var a in savedAddresses) {
                              a['isDefault'] = 'false';
                            }
                            addr['isDefault'] = 'true';
                          });
                          context.read<AuthProvider>().updateProfile(address: addr['address']);
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddAddressDialog(StateSetter parentSetState) {
    final titleCtrl = TextEditingController(text: 'Home');
    final fullAddrCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add New Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Tag (Home / Work / Other)')),
            const SizedBox(height: 10),
            TextField(controller: fullAddrCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Complete Address & Landmark')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (fullAddrCtrl.text.isNotEmpty) {
                parentSetState(() {
                  savedAddresses.add({
                    'title': titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : 'Other',
                    'address': fullAddrCtrl.text.trim(),
                    'isDefault': 'false',
                  });
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add Address', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 4. PAYMENT METHODS MANAGER
  // ─────────────────────────────────────────────────────────────
  void _openPaymentMethodsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setPState) => Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.payment_rounded, color: AppColors.primaryOrange, size: 24),
                  SizedBox(width: 8),
                  Text('Payment Methods & UPI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Manage your default payment options and UPI VPAs.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const Divider(height: 20),

              ...savedPaymentMethods.map((pm) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.primaryOrange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: Icon(
                        pm.contains('UPI') || pm.contains('Pay') ? Icons.qr_code_2_rounded : Icons.credit_card_rounded,
                        color: AppColors.primaryOrange,
                        size: 20,
                      ),
                    ),
                    title: Text(pm, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    trailing: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                  )),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                label: const Text('OPEN RAMEEZ WALLET', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 5. PAST ORDERS HISTORY MODAL
  // ─────────────────────────────────────────────────────────────
  void _openPastOrdersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history_rounded, color: AppColors.primaryOrange, size: 24),
                    SizedBox(width: 8),
                    Text('Past Orders History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _fetchPastOrders,
                ),
              ],
            ),
            const Divider(),

            Expanded(
              child: _isLoadingOrders
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
                  : _fetchedOrders.isEmpty
                      ? const Center(child: Text('No orders found yet.', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _fetchedOrders.length,
                          itemBuilder: (c, idx) {
                            final ord = _fetchedOrders[idx];
                            final id = ord['orderId'] ?? ord['id'] ?? 'ORD-$idx';
                            final total = ord['totalAmount'] ?? ord['total'] ?? 280;
                            final status = ord['status'] ?? 'DELIVERED';
                            final isDelivered = status == 'DELIVERED';
                            final isCancelled = status == 'CANCELLED';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        id.toString(),
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.textDark),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDelivered ? Colors.green.shade50 : isCancelled ? Colors.red.shade50 : Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status.toString(),
                                          style: TextStyle(
                                            color: isDelivered ? Colors.green.shade700 : isCancelled ? Colors.red.shade700 : const Color(0xFFFF5200),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Total: ₹$total • Davanagere Special Dum Kitchen',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        icon: const Icon(Icons.receipt_long_rounded, size: 16),
                                        label: const Text('View Bill', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        onPressed: () {
                                          _showBillDialog(ord);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBillDialog(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.receipt_rounded, color: AppColors.primaryOrange),
            const SizedBox(width: 8),
            Text('Invoice • ${order['orderId'] ?? order['id']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rameez Kitchen Davanagere Special', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Text('GSTIN: 29AABCR8810M1Z5', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Amount Paid:'),
                Text('₹${order['totalAmount'] ?? order['total'] ?? 280}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFFF5200))),
              ],
            ),
            const SizedBox(height: 6),
            Text('Status: ${order['status'] ?? "COMPLETED"}', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 6. SEND FEEDBACK & REVIEW TO MANAGER
  // ─────────────────────────────────────────────────────────────
  void _openFeedbackSheet() {
    int rating = 5;
    final commentCtrl = TextEditingController();
    final selectedTags = <String>{'Delicious Food 😋', 'Super Fast ⚡'};

    final availableTags = [
      'Delicious Food 😋',
      'Super Fast ⚡',
      'Polite Driver 🚴',
      'Great Packaging 📦',
      'Fresh & Hot 🔥',
      'Extra Spicy 🌶️',
      'Value for Money 💰',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setFState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.star_half_rounded, color: Colors.amber, size: 24),
                      SizedBox(width: 8),
                      Text('Send Feedback to Manager', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Rate your dining experience and share feedback directly.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 16),

                  // Rating Stars
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starIndex = index + 1;
                      return IconButton(
                        icon: Icon(
                          starIndex <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: Colors.amber,
                          size: 34,
                        ),
                        onPressed: () => setFState(() => rating = starIndex),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Tag chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: availableTags.map((tag) {
                      final isSelected = selectedTags.contains(tag);
                      return FilterChip(
                        label: Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                        selected: isSelected,
                        selectedColor: const Color(0xFFFF5200),
                        backgroundColor: Colors.grey.shade100,
                        onSelected: (val) {
                          setFState(() {
                            if (val) {
                              selectedTags.add(tag);
                            } else {
                              selectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Write your thoughts on food, taste & speed...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5200),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('SUBMIT FEEDBACK', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    onPressed: () async {
                      final auth = context.read<AuthProvider>();
                      final comment = commentCtrl.text.trim();
                      final fullFeedback = "${selectedTags.join(', ')} - $comment".trim();

                      await http.post(
                        Uri.parse('${ApiConstants.baseUrl}/feedback'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'customerName': auth.customerName,
                          'customerPhone': auth.customerPhone,
                          'rating': rating,
                          'feedback': fullFeedback,
                        }),
                      );

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.green,
                            content: Text('🎉 Thank you! Your feedback has been delivered directly to the kitchen manager.'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 7. SAFETY SOS DIALOG
  // ─────────────────────────────────────────────────────────────
  void _openSafetyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Safety & 24/7 Helpline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Need urgent help with your live order or emergency assistance?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Direct Manager Helpline: +91 8073349233', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('• Emergency Ambulance: 108', style: TextStyle(fontSize: 12)),
                  SizedBox(height: 4),
                  Text('• Emergency Police: 112', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 18),
            label: const Text('CALL HELPLINE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse('tel:+918073349233');
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 8. LOGOUT CONFIRMATION
  // ─────────────────────────────────────────────────────────────
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out of Account?'),
        content: const Text('Are you sure you want to log out from Rameez Kitchen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final authProvider = context.read<AuthProvider>();
              Navigator.pop(ctx);
              await authProvider.logout();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerLoginScreen()),
                );
              }
            },
            child: const Text('LOG OUT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final wallet = context.watch<WalletProvider>();
    final isGold = auth.isGoldMember;
    final isDark = auth.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8F8F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        foregroundColor: isDark ? Colors.white : AppColors.textDark,
        centerTitle: true,
        title: Text(
          'Customer Profile',
          style: TextStyle(
            color: isDark ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Profile Card with Photo & Camera Upload
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Photo Avatar with Camera Button
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: AppColors.primaryOrange.withValues(alpha: 0.1),
                        backgroundImage: (auth.customerAvatar.isNotEmpty && auth.customerAvatar.startsWith('http'))
                            ? NetworkImage(auth.customerAvatar)
                            : null,
                        child: (auth.customerAvatar.isEmpty || !auth.customerAvatar.startsWith('http'))
                            ? const Icon(Icons.person_rounded, size: 36, color: AppColors.primaryOrange)
                            : null,
                      ),
                      if (_isUploadingPhoto)
                        const Positioned.fill(
                          child: CircularProgressIndicator(color: AppColors.primaryOrange, strokeWidth: 3),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: _openAvatarEditorModal,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF5200),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // Name & Badges
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                auth.customerName.isNotEmpty ? auth.customerName : 'Rameez Guest',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : AppColors.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isGold) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified_rounded, color: Colors.amber, size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          auth.customerPhone.isNotEmpty ? auth.customerPhone : '+91 8073349233',
                          style: TextStyle(
                            color: isDark ? Colors.grey.shade400 : AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (auth.customerEmail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            auth.customerEmail,
                            style: TextStyle(color: isDark ? Colors.grey.shade400 : AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primaryOrange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Verified Customer',
                                style: TextStyle(
                                  color: AppColors.primaryOrange,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isGold ? Colors.amber.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isGold ? '👑 Rameez Gold' : 'Davanagere Member',
                                style: TextStyle(
                                  color: isGold ? Colors.amber.shade900 : Colors.grey.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Edit Profile Button
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Color(0xFFFF5200)),
                    tooltip: 'Edit Profile Info',
                    onPressed: _openEditProfileModal,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Rameez Gold Membership Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isGold
                      ? [const Color(0xFFFFDF00), const Color(0xFFDAA520)]
                      : [const Color(0xFF232526), const Color(0xFF414345)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (isGold ? Colors.amber : Colors.black).withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.stars_rounded,
                    color: isGold ? Colors.black87 : const Color(0xFFFFD700),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGold ? 'Rameez Gold Member Active' : 'Rameez Gold Membership',
                          style: TextStyle(
                            color: isGold ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isGold ? '₹0 Service Charge + 10% Extra Cashback' : '₹0 Service Charge + Extra Discounts for ₹99/mo',
                          style: TextStyle(
                            color: isGold ? Colors.black87 : Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isGold ? Colors.green.shade700 : const Color(0xFFFF5200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      auth.toggleGoldMembership();
                      _syncProfileWithServer(
                        name: auth.customerName,
                        phone: auth.customerPhone,
                        email: auth.customerEmail,
                        avatar: auth.customerAvatar,
                        address: auth.customerAddress,
                        isGold: !isGold,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.green.shade700,
                          content: Text(!isGold ? '🎉 Welcome to Rameez Gold Club!' : 'Gold membership deactivated.'),
                        ),
                      );
                    },
                    child: Text(
                      isGold ? 'ACTIVE' : 'UPGRADE',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Rameez Wallet Quick Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: wallet.balance < 0
                      ? [Colors.red.shade700, Colors.red.shade900]
                      : [const Color(0xFFFF5200), const Color(0xFFFF7A00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (wallet.balance < 0 ? Colors.red : const Color(0xFFFF5200)).withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rameez Wallet Balance',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          wallet.balance < 0
                              ? '-₹${wallet.balance.abs().toStringAsFixed(2)}'
                              : '₹${wallet.balance.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: wallet.balance < 0 ? Colors.red.shade800 : const Color(0xFFFF5200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                    },
                    child: const Text('MANAGE / TOP-UP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Profile Section: Quick Actions
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'ACCOUNT PREFERENCES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.grey.shade400 : AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            // Appearance Mode Switch
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
              ),
              child: SwitchListTile(
                secondary: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: AppColors.primaryOrange),
                ),
                title: Text(
                  'Appearance Mode',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                subtitle: Text(
                  isDark ? 'Dark Theme Active' : 'Light Theme Active',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : AppColors.textMuted),
                ),
                value: isDark,
                activeThumbColor: const Color(0xFFFF5200),
                onChanged: (v) => auth.toggleDarkMode(v),
              ),
            ),

            // Saved Addresses
            _ProfileTile(
              isDark: isDark,
              icon: Icons.location_on_rounded,
              title: 'Saved Delivery Addresses',
              subtitle: auth.customerAddress.isNotEmpty ? auth.customerAddress : 'Manage home, work & other locations',
              onTap: _openAddressesSheet,
            ),

            // Payment Methods & UPI
            _ProfileTile(
              isDark: isDark,
              icon: Icons.payment_rounded,
              title: 'Payment Methods & UPI VPAs',
              subtitle: 'Manage GPay, PhonePe, Paytm & Cards',
              onTap: _openPaymentMethodsSheet,
            ),

            // Past Orders History
            _ProfileTile(
              isDark: isDark,
              icon: Icons.receipt_long_rounded,
              title: 'Past Orders & Invoices',
              subtitle: '${_fetchedOrders.length} orders placed on Rameez Kitchen',
              onTap: _openPastOrdersSheet,
            ),

            // Send Feedback to Manager
            _ProfileTile(
              isDark: isDark,
              icon: Icons.star_rate_rounded,
              title: 'Send Feedback & Review',
              subtitle: 'Rate food taste & delivery speed to manager',
              onTap: _openFeedbackSheet,
            ),

            // Safety SOS Helpline
            _ProfileTile(
              isDark: isDark,
              icon: Icons.health_and_safety_rounded,
              title: 'Safety Emergency SOS',
              subtitle: '+91 8073349233 • 24/7 Kitchen Assistance',
              onTap: _openSafetyDialog,
            ),

            const SizedBox(height: 14),

            // Security Badge Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '256-Bit SSL Protected Vault',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your profile, transactions, and addresses are secured with end-to-end encryption.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey.shade400 : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Logout Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('LOG OUT FROM ACCOUNT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              onPressed: _confirmLogout,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primaryOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primaryOrange),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey.shade400 : AppColors.textMuted,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: isDark ? Colors.grey.shade400 : AppColors.textMuted,
        ),
        onTap: onTap,
      ),
    );
  }
}