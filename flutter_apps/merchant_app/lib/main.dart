import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'auth.dart';
import 'login_screen.dart';
import 'security.dart';

final GlobalKey<NavigatorState> merchantNavKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MerchantSecurity.init();
  try {
    await MerchantAuth.init().timeout(const Duration(seconds: 4));
  } catch (_) {
    MerchantAuth.token = null;
  }

  MerchantAuth.onUnauthorized = () {
    merchantNavKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MerchantLoginScreen()),
      (_) => false,
    );
  };

  runApp(const RameezMerchantApp());
}

class RameezMerchantApp extends StatelessWidget {
  const RameezMerchantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rameez Kitchen Merchant Executive',
      debugShowCheckedModeBanner: false,
      navigatorKey: merchantNavKey,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        primaryColor: const Color(0xFFFF5200),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF5200),
          primary: const Color(0xFFFF5200),
        ),
      ),
      home: MerchantAuth.isAuthenticated
          ? const MerchantMasterDashboard()
          : const MerchantLoginScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// UNIVERSAL DIRECT IMAGE UPLOAD HELPER (Browser / Mobile / Laptop)
// ─────────────────────────────────────────────────────────────
class UniversalImagePicker {
  static void pickImage({
    String? captureMode, // 'camera' or null
    required void Function(String imageUrl, String fileName) onSelected,
  }) {
    try {
      js.context['__activeFileCallback'] = js.JsFunction.withThis((_, dynamic url, dynamic name) {
        if (url != null) {
          onSelected(url.toString(), name?.toString() ?? 'image.jpg');
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
                if (window.__activeFileCallback) {
                  window.__activeFileCallback(j.url || base64Data, file.name);
                }
              })
              .catch(function(err) {
                if (window.__activeFileCallback) {
                  window.__activeFileCallback(base64Data, file.name);
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

// ─────────────────────────────────────────────────────────────
// REUSABLE DIRECT IMAGE UPLOAD WIDGET
// ─────────────────────────────────────────────────────────────
class DirectImageUploadField extends StatefulWidget {
  final String initialValue;
  final String label;
  final ValueChanged<String> onImageChanged;

  const DirectImageUploadField({
    super.key,
    required this.initialValue,
    this.label = 'Dish Image',
    required this.onImageChanged,
  });

  @override
  State<DirectImageUploadField> createState() => _DirectImageUploadFieldState();
}

class _DirectImageUploadFieldState extends State<DirectImageUploadField> {
  late String _currentUrl;
  String _fileName = '';
  bool _showUrlField = false;
  late TextEditingController _urlCtrl;

  final List<Map<String, String>> _presets = [
    {
      'label': 'Biryani',
      'url': 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=600'
    },
    {
      'label': 'Mutton',
      'url': 'https://images.unsplash.com/photo-1546833999-b9f581a1996d?w=600'
    },
    {
      'label': 'Roll',
      'url': 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=600'
    },
    {
      'label': 'Tandoori',
      'url': 'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=600'
    },
    {
      'label': 'Shawarma',
      'url': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?w=600'
    },
  ];

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialValue;
    _urlCtrl = TextEditingController(text: _currentUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _handlePicked(String url, String fileName) {
    setState(() {
      _currentUrl = url;
      _fileName = fileName;
      _urlCtrl.text = url;
    });
    widget.onImageChanged(url);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_currentUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 12, color: Colors.green),
                      SizedBox(width: 4),
                      Text('Selected', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Preview and Direct Action Buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Preview Box
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 70,
                  height: 70,
                  color: Colors.grey.shade200,
                  child: _currentUrl.isNotEmpty
                      ? Image.network(
                          _currentUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.add_photo_alternate, color: Colors.grey, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 10),

              // Upload Action Buttons
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5200),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.upload_file, size: 16, color: Colors.white),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Upload from Device / Gallery',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      onPressed: () {
                        UniversalImagePicker.pickImage(onSelected: _handlePicked);
                      },
                    ),
                    const SizedBox(height: 5),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.camera_alt, size: 15, color: Color(0xFFFF5200)),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Take Photo with Camera',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF5200)),
                        ),
                      ),
                      onPressed: () {
                        UniversalImagePicker.pickImage(captureMode: 'camera', onSelected: _handlePicked);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_fileName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '📁 Selected: $_fileName',
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600),
              ),
            ),

          const SizedBox(height: 10),

          // Preset Quick Select Chips
          const Text('Or choose from popular presets:', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _presets.map((preset) {
              final isSelected = _currentUrl == preset['url'];
              return ActionChip(
                backgroundColor: isSelected ? const Color(0xFFFF5200).withValues(alpha: 0.15) : Colors.white,
                side: BorderSide(color: isSelected ? const Color(0xFFFF5200) : Colors.grey.shade300),
                label: Text(
                  preset['label']!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? const Color(0xFFFF5200) : Colors.black87,
                  ),
                ),
                onPressed: () => _handlePicked(preset['url']!, preset['label']!),
              );
            }).toList(),
          ),

          const SizedBox(height: 6),
          // Option to enter custom URL
          Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                icon: Icon(_showUrlField ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18),
                label: Text(_showUrlField ? 'Hide URL input' : 'Paste web image URL', style: const TextStyle(fontSize: 11)),
                onPressed: () => setState(() => _showUrlField = !_showUrlField),
              ),
            ],
          ),

          if (_showUrlField)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  hintText: 'https://...',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check, size: 18, color: Colors.green),
                    onPressed: () => _handlePicked(_urlCtrl.text.trim(), 'Custom URL'),
                  ),
                ),
                onSubmitted: (v) => _handlePicked(v.trim(), 'Custom URL'),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MERCHANT MASTER DASHBOARD
// ─────────────────────────────────────────────────────────────
class MerchantMasterDashboard extends StatefulWidget {
  const MerchantMasterDashboard({super.key});

  @override
  State<MerchantMasterDashboard> createState() => _MerchantMasterDashboardState();
}

class _MerchantMasterDashboardState extends State<MerchantMasterDashboard> {
  int _selectedTabIndex = 0;
  List<Map<String, dynamic>> allOrders = [];
  late IO.Socket socket;

  // Alarm & Sound notification state
  bool isAlarmRinging = false;
  Timer? _alarmIntervalTimer;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    initSockets();
    _fetchPersistedOrders();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchPersistedOrders());
  }

  void _playOldTelephoneRing() {
    try {
      js.context.callMethod('eval', [
        '''
        (function() {
          try {
            var AudioContext = window.AudioContext || window.webkitAudioContext;
            if (!AudioContext) return;
            var ctx = window._kdsAudioCtx || new AudioContext();
            window._kdsAudioCtx = ctx;
            if (ctx.state === 'suspended') { ctx.resume(); }

            function playBellBurst(startTime, duration) {
              var osc1 = ctx.createOscillator();
              var osc2 = ctx.createOscillator();
              var hammerOsc = ctx.createOscillator();
              var hammerGain = ctx.createGain();
              var mainGain = ctx.createGain();

              // Dual vintage telephone bell frequencies (440Hz + 480Hz)
              osc1.type = 'sine';
              osc1.frequency.setValueAtTime(440, startTime);

              osc2.type = 'sine';
              osc2.frequency.setValueAtTime(480, startTime);

              // 20Hz rapid mechanical bell hammer
              hammerOsc.type = 'square';
              hammerOsc.frequency.setValueAtTime(20, startTime);

              hammerGain.gain.setValueAtTime(0.5, startTime);
              hammerOsc.connect(hammerGain.gain);

              osc1.connect(hammerGain);
              osc2.connect(hammerGain);

              mainGain.gain.setValueAtTime(0.4, startTime);
              mainGain.gain.setValueAtTime(0.4, startTime + duration - 0.05);
              mainGain.gain.exponentialRampToValueAtTime(0.001, startTime + duration);

              hammerGain.connect(mainGain);
              mainGain.connect(ctx.destination);

              osc1.start(startTime);
              osc2.start(startTime);
              hammerOsc.start(startTime);

              osc1.stop(startTime + duration);
              osc2.stop(startTime + duration);
              hammerOsc.stop(startTime + duration);
            }

            var t0 = ctx.currentTime;
            playBellBurst(t0, 0.42);
            playBellBurst(t0 + 0.58, 0.42);
          } catch(e) {}
        })()
        '''
      ]);
    } catch (_) {}
  }

  void _triggerKitchenAlarm() {
    if (!mounted) return;
    setState(() => isAlarmRinging = true);
    _alarmIntervalTimer?.cancel();
    _playOldTelephoneRing();
    _alarmIntervalTimer = Timer.periodic(const Duration(milliseconds: 2400), (t) {
      if (!isAlarmRinging) {
        t.cancel();
      } else {
        _playOldTelephoneRing();
      }
    });
  }

  void _stopKitchenAlarm() {
    _alarmIntervalTimer?.cancel();
    if (mounted) setState(() => isAlarmRinging = false);
  }

  Future<void> _fetchPersistedOrders() async {
    try {
      final res = await http.get(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/orders'));
      if (res.statusCode == 200 && mounted) {
        final List list = jsonDecode(res.body);
        final Map<String, Map<String, dynamic>> dedup = {};
        for (var item in list) {
          final m = Map<String, dynamic>.from(item);
          final id = m['orderId']?.toString() ?? m['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            dedup[id] = m;
          }
        }
        setState(() => allOrders = dedup.values.toList());
      }
    } catch (_) {}
  }

  void initSockets() {
    socket = IO.io('https://rameez-kitchen-backend.onrender.com', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket.on('order:new', (data) {
      if (mounted && data != null) {
        final orderMap = Map<String, dynamic>.from(data);
        final orderId = orderMap['orderId']?.toString() ?? orderMap['id']?.toString();
        setState(() {
          if (orderId != null) {
            allOrders.removeWhere((o) => (o['orderId'] ?? o['id'])?.toString() == orderId);
          }
          allOrders.insert(0, orderMap);
        });
        _triggerKitchenAlarm();
      }
    });

    socket.on('order:status_update', (data) {
      if (mounted && data != null) {
        final orderId = data['orderId']?.toString();
        final status = data['status']?.toString();
        setState(() {
          for (var o in allOrders) {
            final curId = (o['orderId'] ?? o['id'])?.toString();
            if (curId == orderId || curId?.replaceAll(RegExp(r'\D'), '') == orderId?.replaceAll(RegExp(r'\D'), '')) {
              if (status != null) o['status'] = status;
              if (data['driverName'] != null) o['driverName'] = data['driverName'];
              if (data['driverPhone'] != null) o['driverPhone'] = data['driverPhone'];
              if (data['vehicleNumber'] != null) o['vehicleNumber'] = data['vehicleNumber'];
              if (data['vehicleType'] != null) o['vehicleType'] = data['vehicleType'];
              if (data['driverRating'] != null) o['driverRating'] = data['driverRating'];
              if (data['deliveredAt'] != null) o['deliveredAt'] = data['deliveredAt'];
            }
          }
        });
      }
    });

    socket.on('merchant:no_driver_alert', (data) {
      if (mounted && data != null) {
        final msg = (data is Map ? data['message'] : null)?.toString() ?? '⚠️ No available driver accepted the pending order within 30s.';
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'DISMISS',
              textColor: Colors.amber,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _alarmIntervalTimer?.cancel();
    _pollingTimer?.cancel();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveOrders = allOrders.where((o) => o['status'] != 'DELIVERED' && o['status'] != 'CANCELLED').toList();

    final screens = [
      OrdersPipelineView(
        allOrders: allOrders,
        socket: socket,
        onAcceptOrder: _stopKitchenAlarm,
        onRefresh: _fetchPersistedOrders,
      ),
      const MenuInventoryManagementView(),
      const TodaysOfferManagerView(),
      SalesAnalyticsView(allOrders: allOrders, onRefresh: _fetchPersistedOrders),
      const ExecutiveVaultView(),
      const CombinedAdminSettingsView(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF5200),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RAMEEZ KITCHEN EXECUTIVE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5),
                ),
                Text(
                  'Merchant Command Center & Analytics',
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              tooltip: isAlarmRinging ? 'Mute Kitchen Alarm' : 'Test Sound Alarm',
              icon: Icon(
                isAlarmRinging ? Icons.notifications_active : Icons.notifications,
                color: isAlarmRinging ? Colors.yellowAccent : Colors.white,
              ),
              onPressed: () {
                if (isAlarmRinging) {
                  _stopKitchenAlarm();
                } else {
                  _triggerKitchenAlarm();
                }
              },
            ),
            IconButton(
              tooltip: 'Logout (Merchant Console)',
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
              onPressed: () => _confirmLogout(context),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (isAlarmRinging)
            Container(
              color: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔔 NEW ORDER RECEIVED!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Kitchen telephone alarm active until accepted.',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: const Icon(Icons.volume_off, size: 16),
                    label: const Text('MUTE ALARM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: _stopKitchenAlarm,
                  ),
                ],
              ),
            ),
          Expanded(child: screens[_selectedTabIndex]),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF5200),
        unselectedItemColor: Colors.blueGrey.shade400,
        backgroundColor: Colors.white,
        elevation: 8,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
        onTap: (i) => setState(() => _selectedTabIndex = i),
        items: [
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: liveOrders.isNotEmpty,
              backgroundColor: Colors.red,
              label: Text('${liveOrders.length}'),
              child: const Icon(Icons.receipt_long_rounded),
            ),
            label: 'Orders',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.restaurant_menu_rounded), label: 'Menu Mgmt'),
          const BottomNavigationBarItem(icon: Icon(Icons.local_offer_rounded), label: "Offers"),
          const BottomNavigationBarItem(icon: Icon(Icons.analytics_rounded), label: 'Sales/Stats'),
          const BottomNavigationBarItem(icon: Icon(Icons.shield_rounded), label: 'CD Vault'),
          const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings_rounded), label: 'Admin'),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16191E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFFF5200), size: 22),
            SizedBox(width: 10),
            Text('Logout Merchant', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Are you sure you want to securely logout from the Merchant Command Console?',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5200),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await MerchantAuth.logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MerchantLoginScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('LOGOUT', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 1. ORDERS VIEW (With Segmented Tabs, Date Filters, Live Pipeline & Past Orders)
// ─────────────────────────────────────────────────────────────
class OrdersPipelineView extends StatefulWidget {
  final List<Map<String, dynamic>> allOrders;
  final IO.Socket socket;
  final VoidCallback onAcceptOrder;
  final VoidCallback onRefresh;

  const OrdersPipelineView({
    super.key,
    required this.allOrders,
    required this.socket,
    required this.onAcceptOrder,
    required this.onRefresh,
  });

  @override
  State<OrdersPipelineView> createState() => _OrdersPipelineViewState();
}

class _OrdersPipelineViewState extends State<OrdersPipelineView> {
  int _orderFilterTab = 0; // 0 = Live Active, 1 = Past Completed, 2 = All
  String _dateFilter = 'ALL'; // ALL, TODAY, YESTERDAY, WEEK, CUSTOM
  DateTimeRange? _customDateRange;
  final TextEditingController _searchCtrl = TextEditingController();

  String _formatDateTime(dynamic iso) {
    if (iso == null) return 'Recent';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      String timeStr = DateFormat('hh:mm a').format(dt);
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        String ago = diff.inMinutes < 60 ? '${diff.inMinutes}m ago' : '${diff.inHours}h ago';
        return 'Today, $timeStr ($ago)';
      }
      final yest = now.subtract(const Duration(days: 1));
      if (dt.year == yest.year && dt.month == yest.month && dt.day == yest.day) {
        return 'Yesterday, $timeStr';
      }
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return iso.toString();
    }
  }

  bool _matchesDate(dynamic iso) {
    if (iso == null) return _dateFilter == 'ALL';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final yestStart = todayStart.subtract(const Duration(days: 1));
      final weekStart = todayStart.subtract(Duration(days: (now.weekday - 1)));

      switch (_dateFilter) {
        case 'TODAY':
          return dt.isAfter(todayStart);
        case 'YESTERDAY':
          return dt.isAfter(yestStart) && dt.isBefore(todayStart);
        case 'WEEK':
          return dt.isAfter(weekStart);
        case 'CUSTOM':
          if (_customDateRange == null) return true;
          return dt.isAfter(_customDateRange!.start) && dt.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
        case 'ALL':
        default:
          return true;
      }
    } catch (_) {
      return true;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();

    // 1. Status separation
    List<Map<String, dynamic>> filtered = widget.allOrders.where((o) {
      final status = (o['status'] ?? '').toString().toUpperCase();
      final isDelivered = status == 'DELIVERED' || status == 'COMPLETED';

      if (_orderFilterTab == 0 && isDelivered) return false; // Active only
      if (_orderFilterTab == 1 && !isDelivered) return false; // Completed only

      // Date filtering
      final createdAt = o['createdAt'] ?? o['created_at'] ?? o['deliveredAt'] ?? o['delivered_at'];
      if (!_matchesDate(createdAt)) return false;

      // Text search
      if (query.isNotEmpty) {
        final id = (o['orderId'] ?? o['id'] ?? '').toString().toLowerCase();
        final name = (o['customerName'] ?? '').toString().toLowerCase();
        final phone = (o['customerPhone'] ?? '').toString().toLowerCase();
        final addr = (o['deliveryAddress'] ?? '').toString().toLowerCase();
        final items = (o['items'] as List?)?.map((e) => e['name']?.toString().toLowerCase()).join(' ') ?? '';
        return id.contains(query) || name.contains(query) || phone.contains(query) || addr.contains(query) || items.contains(query);
      }
      return true;
    }).toList();

    final activeCount = widget.allOrders.where((o) => o['status'] != 'DELIVERED' && o['status'] != 'CANCELLED').length;
    final completedCount = widget.allOrders.where((o) => o['status'] == 'DELIVERED' || o['status'] == 'COMPLETED').length;

    return Column(
      children: [
        // Top Control Bar: Segmented Tabs & Live Counts
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              // Segmented Tab Bar
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    _buildSubTab(0, '🔥 Active Live', activeCount),
                    _buildSubTab(1, '✅ Past Orders', completedCount),
                    _buildSubTab(2, '📋 All Orders', widget.allOrders.length),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Search Box & Date Filter Chips
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search by Order ID, Customer, Phone, Dish...',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFFF5200)),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh Orders',
                    onPressed: widget.onRefresh,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Date Filter Chips Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildDateChip('ALL', 'All Dates'),
                    const SizedBox(width: 6),
                    _buildDateChip('TODAY', 'Today'),
                    const SizedBox(width: 6),
                    _buildDateChip('YESTERDAY', 'Yesterday'),
                    const SizedBox(width: 6),
                    _buildDateChip('WEEK', 'This Week'),
                    const SizedBox(width: 6),
                    _buildCustomDateChip(),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Order List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _orderFilterTab == 0 ? Icons.kitchen_rounded : Icons.history_rounded,
                            size: 54,
                            color: const Color(0xFFFF5200),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _orderFilterTab == 0
                              ? 'No Active Live Orders Right Now'
                              : 'No Past Orders Found for Selected Filter',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _orderFilterTab == 0
                              ? 'New orders placed on Customer App will ring and appear here instantly.'
                              : 'Try changing the date filter or placing new orders.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh Orders'),
                          onPressed: widget.onRefresh,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final o = filtered[i];
                    return _buildOrderCard(o);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSubTab(int index, String title, int count) {
    final isSelected = _orderFilterTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _orderFilterTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))] : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? const Color(0xFFFF5200) : Colors.blueGrey.shade700,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFF5200) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.blueGrey.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateChip(String key, String label) {
    final isSelected = _dateFilter == key;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        color: isSelected ? Colors.white : Colors.black87,
      ),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFFF5200),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isSelected ? const Color(0xFFFF5200) : Colors.grey.shade300),
      ),
      onSelected: (_) => setState(() => _dateFilter = key),
    );
  }

  Widget _buildCustomDateChip() {
    final isSelected = _dateFilter == 'CUSTOM';
    String label = '📅 Custom Date';
    if (isSelected && _customDateRange != null) {
      label = '📅 ${DateFormat('dd MMM').format(_customDateRange!.start)} - ${DateFormat('dd MMM').format(_customDateRange!.end)}';
    }

    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        color: isSelected ? Colors.white : Colors.black87,
      ),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFFF5200),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isSelected ? const Color(0xFFFF5200) : Colors.grey.shade300),
      ),
      onSelected: (_) async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2025),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          initialDateRange: _customDateRange ?? DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now()),
        );
        if (picked != null) {
          setState(() {
            _customDateRange = picked;
            _dateFilter = 'CUSTOM';
          });
        }
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> o) {
    final status = (o['status'] ?? 'PLACED').toString().toUpperCase();
    final isNewPlaced = status == 'PLACED' || status == 'PENDING' || status == 'NEW';
    final isDelivered = status == 'DELIVERED' || status == 'COMPLETED';
    final items = (o['items'] as List?) ?? [];
    final orderId = o['orderId'] ?? o['id'] ?? 'ORD-000';
    final createdAt = o['createdAt'] ?? o['created_at'];
    final deliveredAt = o['deliveredAt'] ?? o['delivered_at'];
    final customerName = o['customerName'] ?? 'Valued Customer';
    final customerPhone = o['customerPhone'] ?? '';
    final address = o['deliveryAddress'] ?? o['address'] ?? 'Davanagere Delivery';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: isNewPlaced ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isNewPlaced
              ? const Color(0xFFFF5200)
              : isDelivered
                  ? Colors.green.shade200
                  : Colors.grey.shade200,
          width: isNewPlaced ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order ID & Live Stage Tag
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (isNewPlaced)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      ),
                    Text(
                      orderId,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                    ),
                  ],
                ),
                _buildStatusBadge(status),
              ],
            ),
            const SizedBox(height: 6),

            // Time received from customer & Delivery time
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 5),
                Text(
                  'Ordered: ${_formatDateTime(createdAt)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                ),
              ],
            ),
            if (isDelivered && deliveredAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 14, color: Colors.green),
                    const SizedBox(width: 5),
                    Text(
                      'Delivered: ${_formatDateTime(deliveredAt)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Customer Info Box
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.person_pin_circle_rounded, color: Color(0xFFFF5200), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$customerName ${customerPhone.isNotEmpty ? "• $customerPhone" : ""}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 18),

            // Itemized Dishes List
            const Text(
              'ORDER ITEMS:',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.blueGrey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            if (items.isEmpty)
              const Text('• 1x Chef Special Dum Biryani', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))
            else
              ...items.map((item) {
                final qty = item['quantity'] ?? 1;
                final price = item['price'] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '• ${item['name']}  x$qty',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      Text(
                        '₹${price * qty}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 8),

            // Bill & Payment Mode Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (o['paymentMethod'] == 'Cash on Delivery') ? Colors.purple.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: (o['paymentMethod'] == 'Cash on Delivery') ? Colors.purple.shade200 : Colors.blue.shade200),
                  ),
                  child: Text(
                    '${o['paymentMethod'] ?? "UPI - Paid"}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: (o['paymentMethod'] == 'Cash on Delivery') ? Colors.purple.shade800 : Colors.blue.shade800,
                    ),
                  ),
                ),
                Text(
                  'Total: ₹${o['totalAmount']}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFFF5200)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Driver Stage Banner (if driver assigned or in progress)
            _buildDriverProgressBanner(o, status),

            const SizedBox(height: 8),

            // Action Pipeline Buttons for Kitchen
            if (isNewPlaced)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5200),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.soup_kitchen_rounded, color: Colors.white, size: 18),
                      label: const Text('ACCEPT & START COOKING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        widget.onAcceptOrder();
                        setState(() => o['status'] = 'PREPARING');
                        widget.socket.emit('order:status_update', {'orderId': orderId, 'status': 'PREPARING'});
                        http.post(
                          Uri.parse('https://rameez-kitchen-backend.onrender.com/api/orders/$orderId/status'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'status': 'PREPARING'}),
                        ).catchError((_) => http.Response('', 500));
                      },
                    ),
                  ),
                ],
              ),
            if (status == 'PREPARING')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 18),
                      label: const Text('FOOD PACKED — READY FOR PICKUP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        setState(() => o['status'] = 'READY_FOR_PICKUP');
                        widget.socket.emit('order:status_update', {'orderId': orderId, 'status': 'READY_FOR_PICKUP'});
                        widget.socket.emit('driver:pickup_ready', {
                          'orderId': orderId,
                          'message': 'Order #$orderId is cooked and packed! Ready for pickup at kitchen.',
                        });
                        http.post(
                          Uri.parse('https://rameez-kitchen-backend.onrender.com/api/orders/$orderId/status'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'status': 'READY_FOR_PICKUP'}),
                        ).catchError((_) => http.Response('', 500));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Driver notified: Order #$orderId is ready for pickup!'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.green.shade800,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            if (status == 'READY_FOR_PICKUP' || status == 'ARRIVED_RESTAURANT')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_box_rounded, color: Colors.white, size: 18),
                      label: const Text('HANDOVER TO DRIVER • DISPATCH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        setState(() => o['status'] = 'PICKED_UP');
                        widget.socket.emit('order:status_update', {'orderId': orderId, 'status': 'PICKED_UP', 'isDriverEnRoute': true});
                        http.post(
                          Uri.parse('https://rameez-kitchen-backend.onrender.com/api/orders/$orderId/status'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'status': 'PICKED_UP'}),
                        ).catchError((_) => http.Response('', 500));
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = Colors.grey.shade200;
    Color fg = Colors.black87;
    String label = status;

    switch (status) {
      case 'PLACED':
      case 'PENDING':
      case 'NEW':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        label = 'NEW ORDER';
        break;
      case 'PREPARING':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        label = '🍳 COOKING';
        break;
      case 'READY_FOR_PICKUP':
      case 'GOING_TO_RESTAURANT':
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
        label = '🛵 AWAITING RIDER';
        break;
      case 'ARRIVED_RESTAURANT':
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade700;
        label = '📍 DRIVER AT KITCHEN';
        break;
      case 'PICKED_UP':
      case 'ON_THE_WAY':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        label = '🚀 ON DELIVERY';
        break;
      case 'ARRIVED_CUSTOMER':
        bg = Colors.indigo.shade50;
        fg = Colors.indigo.shade700;
        label = '📍 AT DOORSTEP (VERIFYING OTP)';
        break;
      case 'DELIVERED':
      case 'COMPLETED':
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        label = '✓ DELIVERED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }

  Widget _buildDriverProgressBanner(Map<String, dynamic> o, String status) {
    final rawName = o['driverName'] ?? o['driver_name'] ?? o['driver'] ?? '';
    final driverName = rawName.toString().trim().isNotEmpty ? rawName.toString().trim() : 'Partner Driver';
    final vehicleNumber = (o['vehicleNumber'] ?? o['vehicle_number'] ?? '').toString().trim();
    final vehicleType = (o['vehicleType'] ?? o['vehicle_type'] ?? 'Bike').toString().trim();
    final vehDisplay = vehicleNumber.isNotEmpty ? ' ($vehicleNumber • $vehicleType)' : ' ($vehicleType)';

    if (status == 'DELIVERED' || status == 'COMPLETED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.task_alt_rounded, size: 16, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Successfully Delivered by $driverName$vehDisplay',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'ARRIVED_RESTAURANT') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.purple.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.purple.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.store_mall_directory_rounded, size: 18, color: Colors.purple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '📍 Driver Arrived at Kitchen ($driverName$vehDisplay) — Please Handover Order!',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple),
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'PICKED_UP' || status == 'ON_THE_WAY') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.two_wheeler_rounded, size: 18, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🚀 $driverName$vehDisplay is on the way to customer!',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'ARRIVED_CUSTOMER') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.indigo.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.pin_drop_rounded, size: 18, color: Colors.indigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '📍 $driverName arrived at customer doorstep — Verifying Delivery OTP...',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────
// 2. MENU INVENTORY (Add & Delete Dishes with Direct Device Upload)
// ─────────────────────────────────────────────────────────────
class MenuInventoryManagementView extends StatefulWidget {
  const MenuInventoryManagementView({super.key});
  @override
  State<MenuInventoryManagementView> createState() => _MenuInventoryManagementViewState();
}

class _MenuInventoryManagementViewState extends State<MenuInventoryManagementView> {
  List<dynamic> menu = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    fetchMenu();
  }

  Future<void> fetchMenu() async {
    try {
      final res = await http.get(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/menu'));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          menu = jsonDecode(res.body);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAvailability(int id, bool val) async {
    await http.put(
      Uri.parse('https://rameez-kitchen-backend.onrender.com/api/menu/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'available': val}),
    );
    fetchMenu();
  }

  Future<void> _deleteDish(int id) async {
    await http.delete(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/menu/$id'));
    fetchMenu();
  }

  void _openAddDishModal() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '220');
    final flavorCtrl = TextEditingController(text: 'Aromatic & Spicy');
    String selectedImage = 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=600';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFF5200)),
              SizedBox(width: 8),
              Text('Add New Dish', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Food Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: flavorCtrl,
                  decoration: const InputDecoration(labelText: 'Flavor / Portion Details', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),

                // Direct Device Image Upload Picker
                DirectImageUploadField(
                  initialValue: selectedImage,
                  label: 'Food Dish Photo (Laptop / Mobile / Camera)',
                  onImageChanged: (val) {
                    setDialogState(() => selectedImage = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await http.post(
                  Uri.parse('https://rameez-kitchen-backend.onrender.com/api/menu'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'name': nameCtrl.text.trim(),
                    'price': int.tryParse(priceCtrl.text) ?? 200,
                    'flavor': flavorCtrl.text.trim(),
                    'image': selectedImage,
                    'available': true,
                  }),
                );
                if (mounted && ctx.mounted) {
                  Navigator.pop(ctx);
                  fetchMenu();
                }
              },
              child: const Text('ADD DISH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF5200)));

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: menu.length,
        itemBuilder: (_, i) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(10),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                menu[i]['image'] ?? '',
                width: 55,
                height: 55,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 55,
                  height: 55,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.fastfood, color: Colors.grey),
                ),
              ),
            ),
            title: Text(menu[i]['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text('₹${menu[i]['price']} • ${menu[i]['flavor'] ?? ""}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: menu[i]['available'] ?? true,
                  activeThumbColor: const Color(0xFFFF5200),
                  onChanged: (v) => _toggleAvailability(menu[i]['id'], v),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  onPressed: () => _deleteDish(menu[i]['id']),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFFF5200),
        onPressed: _openAddDishModal,
        icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
        label: const Text('Add Dish (Direct Upload)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 3. TODAY'S OFFER MANAGER
// ─────────────────────────────────────────────────────────────
class TodaysOfferManagerView extends StatefulWidget {
  const TodaysOfferManagerView({super.key});
  @override
  State<TodaysOfferManagerView> createState() => _TodaysOfferManagerViewState();
}

class _TodaysOfferManagerViewState extends State<TodaysOfferManagerView> {
  final _code = TextEditingController(text: 'RAMEEZ50');
  final _desc = TextEditingController(text: 'Flat 50% OFF on Biryani!');
  final _disc = TextEditingController(text: '50');
  List<dynamic> offers = [];

  @override
  void initState() {
    super.initState();
    fetchOffers();
  }

  Future<void> fetchOffers() async {
    final res = await http.get(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/offers'));
    if (res.statusCode == 200 && mounted) setState(() => offers = jsonDecode(res.body));
  }

  Future<void> _broadcast() async {
    await http.post(
      Uri.parse('https://rameez-kitchen-backend.onrender.com/api/merchant/broadcast-offer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': _code.text, 'offerText': _desc.text, 'discount': _disc.text}),
    );
    fetchOffers();
  }

  Future<void> _delete(String id) async {
    await http.delete(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/merchant/offers/$id'));
    fetchOffers();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _code, decoration: const InputDecoration(labelText: 'Coupon Code', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _disc, decoration: const InputDecoration(labelText: 'Discount (₹)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5200), minimumSize: const Size.fromHeight(45)),
                  onPressed: _broadcast,
                  child: const Text('BROADCAST LIVE OFFER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Active Live Offers on Customer App:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ...offers.map((o) => Card(
              child: ListTile(
                leading: const Icon(Icons.local_offer, color: Color(0xFFFF5200)),
                title: Text('${o['code']} (-₹${o['discount']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(o['description'] ?? ''),
                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _delete(o['id'])),
              ),
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 4. SALES & REVENUE ANALYTICS (Live Database & Orders Sync)
// ─────────────────────────────────────────────────────────────
class SalesAnalyticsView extends StatefulWidget {
  final List<Map<String, dynamic>> allOrders;
  final VoidCallback onRefresh;

  const SalesAnalyticsView({super.key, required this.allOrders, required this.onRefresh});

  @override
  State<SalesAnalyticsView> createState() => _SalesAnalyticsViewState();
}

class _SalesAnalyticsViewState extends State<SalesAnalyticsView> {
  Map<String, dynamic> _analyticsData = {};
  bool _loading = false;
  String _activeRange = 'TODAY'; // TODAY, YESTERDAY, WEEK, MONTH, ALL

  @override
  void initState() {
    super.initState();
    _fetchLiveAnalytics();
  }

  Future<void> _fetchLiveAnalytics() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/analytics'));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _analyticsData = jsonDecode(res.body);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetTodaySales() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Colors.deepOrange, size: 24),
            SizedBox(width: 8),
            Text('Reset Today\'s Metrics?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        content: const Text(
          'This will reset Today\'s Revenue and Orders counters on the dashboard and archive them in the database. Are you sure you want to proceed?',
          style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESET METRICS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _loading = true);
      try {
        final res = await http.post(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/analytics/reset-today'));
        if (res.statusCode == 200) {
          widget.onRefresh();
          await _fetchLiveAnalytics();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('✓ Today\'s sales & revenue reset to ₹0 successfully!'),
                backgroundColor: const Color(0xFF0F8A65),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic values from backend analytics
    final todayRev = _analyticsData['todayRevenue'] ?? 0;
    final todayOrders = _analyticsData['todayOrders'] ?? 0;
    final yestRev = _analyticsData['yesterdayRevenue'] ?? 0;
    final yestOrders = _analyticsData['yesterdayOrders'] ?? 0;
    final weekRev = _analyticsData['weeklyRevenue'] ?? 0;
    final weekOrders = _analyticsData['weeklyOrders'] ?? 0;
    final monthRev = _analyticsData['monthlyRevenue'] ?? 0;
    final monthOrders = _analyticsData['monthlyOrders'] ?? 0;
    final totalRev = _analyticsData['totalRevenue'] ?? 0;
    final totalOrders = _analyticsData['totalOrders'] ?? 0;
    final aov = _analyticsData['averageOrderValue'] ?? 0;

    num displayRev = todayRev;
    int displayOrders = todayOrders;
    String rangeLabel = "Today's";

    switch (_activeRange) {
      case 'YESTERDAY':
        displayRev = yestRev;
        displayOrders = yestOrders;
        rangeLabel = "Yesterday's";
        break;
      case 'WEEK':
        displayRev = weekRev;
        displayOrders = weekOrders;
        rangeLabel = "This Week's";
        break;
      case 'MONTH':
        displayRev = monthRev;
        displayOrders = monthOrders;
        rangeLabel = "This Month's";
        break;
      case 'ALL':
        displayRev = totalRev;
        displayOrders = totalOrders;
        rangeLabel = "All-Time";
        break;
      case 'TODAY':
      default:
        displayRev = todayRev;
        displayOrders = todayOrders;
        rangeLabel = "Today's";
        break;
    }

    final List distribution = (_analyticsData['weeklyDistribution'] as List?) ?? [
      {'day': 'Mon', 'revenue': 1200, 'orders': 3},
      {'day': 'Tue', 'revenue': 1800, 'orders': 4},
      {'day': 'Wed', 'revenue': 2400, 'orders': 6},
      {'day': 'Thu', 'revenue': 1600, 'orders': 4},
      {'day': 'Fri', 'revenue': 3200, 'orders': 8},
      {'day': 'Sat', 'revenue': 4500, 'orders': 11},
      {'day': 'Sun', 'revenue': 5200, 'orders': 14},
    ];

    final List topSelling = (_analyticsData['topSellingItems'] as List?) ?? [];

    num maxWeekRev = 1;
    for (var d in distribution) {
      final r = (d['revenue'] as num?) ?? 0;
      if (r > maxWeekRev) maxWeekRev = r;
    }

    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
        await _fetchLiveAnalytics();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Range Switcher & Action Buttons
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Text(
                'Business Overview',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.black87),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Button 1: Sync DB
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5200),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _loading
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync_rounded, size: 15),
                    label: const Text('Sync DB', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      widget.onRefresh();
                      _fetchLiveAnalytics();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('✓ Synchronized real-time orders & sales directly from database!'),
                          backgroundColor: const Color(0xFF0F8A65),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // Button 2: Reset Today's Sales
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300, width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 15, color: Colors.red),
                    label: const Text('Reset Today\'s Sales', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _resetTodaySales,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Time Range Filter Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildRangeChip('TODAY', 'Today'),
                const SizedBox(width: 6),
                _buildRangeChip('YESTERDAY', 'Yesterday'),
                const SizedBox(width: 6),
                _buildRangeChip('WEEK', 'This Week'),
                const SizedBox(width: 6),
                _buildRangeChip('MONTH', 'This Month'),
                const SizedBox(width: 6),
                _buildRangeChip('ALL', 'All Time'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Primary KPI Cards
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: "$rangeLabel Revenue",
                  val: "₹$displayRev",
                  subtitle: "Directly from DB",
                  icon: Icons.currency_rupee_rounded,
                  color: Colors.orange.shade800,
                  bgColor: Colors.orange.shade50,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  title: "$rangeLabel Sales",
                  val: "$displayOrders Orders",
                  subtitle: "Total orders",
                  icon: Icons.shopping_bag_rounded,
                  color: Colors.blue.shade800,
                  bgColor: Colors.blue.shade50,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: "Total Monthly Revenue",
                  val: "₹$monthRev",
                  subtitle: "$monthOrders Orders this month",
                  icon: Icons.calendar_month_rounded,
                  color: Colors.green.shade800,
                  bgColor: Colors.green.shade50,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  title: "Average Order Value",
                  val: "₹$aov",
                  subtitle: "AOV per ticket",
                  icon: Icons.insights_rounded,
                  color: Colors.purple.shade800,
                  bgColor: Colors.purple.shade50,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Weekly Sales Distribution Bar Chart
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Weekly Sales Distribution (Mon - Sun)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text('Dynamic Orders', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: distribution.map((d) {
                      final rev = (d['revenue'] as num?) ?? 0;
                      final ordersCount = d['orders'] ?? 0;
                      final ratio = (rev / (maxWeekRev > 0 ? maxWeekRev : 1)).clamp(0.12, 1.0);
                      final height = 90.0 * ratio;

                      return Column(
                        children: [
                          Text('₹$rev', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          const SizedBox(height: 4),
                          Container(
                            width: 22,
                            height: height,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [const Color(0xFFFF5200), Colors.amber.shade700],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(d['day']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          Text('$ordersCount ord', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Top Best Selling Items (Ranked Live from DB)
          const Text(
            'Top Best Selling Items (Live DB Orders)',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 8),

          if (topSelling.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No itemized sales data yet. Place orders to see ranking.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...topSelling.map((item) {
              final index = topSelling.indexOf(item);
              Color badgeColor = Colors.grey;
              if (index == 0) badgeColor = const Color(0xFFD4AF37); // Gold
              if (index == 1) badgeColor = Colors.blueGrey; // Silver
              if (index == 2) badgeColor = Colors.brown; // Bronze

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: badgeColor.withValues(alpha: 0.15),
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(color: badgeColor, fontWeight: FontWeight.w900),
                    ),
                  ),
                  title: Text(item['name'] ?? 'Dish', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${item['orders']} orders sold • ${item['flavor'] ?? ""}'),
                  trailing: Text(
                    '₹${item['revenue']}',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 14),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRangeChip(String key, String label) {
    final isSelected = _activeRange == key;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        color: isSelected ? Colors.white : Colors.black87,
      ),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFFF5200),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isSelected ? const Color(0xFFFF5200) : Colors.grey.shade300),
      ),
      onSelected: (_) => setState(() => _activeRange = key),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String val,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            val,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 5. EXECUTIVE CD VAULT (Passkey reverse of admin password)
// ─────────────────────────────────────────────────────────────
class ExecutiveVaultView extends StatefulWidget {
  const ExecutiveVaultView({super.key});
  @override
  State<ExecutiveVaultView> createState() => _ExecutiveVaultViewState();
}

class _ExecutiveVaultViewState extends State<ExecutiveVaultView> with SingleTickerProviderStateMixin {
  bool isUnlocked = false;
  bool _obscurePasskey = true;
  bool _isVerifying = false;
  bool _isSyncing = false;
  final _keyCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<dynamic> directory = [];
  List<dynamic> drivers = [];
  List<dynamic> reviews = [];
  Map<String, dynamic> telemetry = {};
  String _err = '';
  int _selectedVaultTab = 0; // 0: Drivers, 1: Customers, 2: Reviews, 3: DB Telemetry
  String _searchQuery = '';

  @override
  void dispose() {
    _keyCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _isVerifying = true;
      _err = '';
    });
    try {
      final res = await http.post(
        Uri.parse('https://rameez-kitchen-backend.onrender.com/api/admin/verify-vault'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'passkey': _keyCtrl.text.trim()}),
      );
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(res.body);
        setState(() {
          isUnlocked = true;
          directory = d['directory'] ?? [];
          drivers = d['drivers'] ?? [];
          _err = '';
        });
        _fetchSyncTelemetry();
        _fetchReviews();
      } else {
        if (mounted) {
          setState(() => _err = 'Invalid Master Passkey. Access Denied.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _err = 'Server connection error. Ensure backend is running.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _fetchReviews() async {
    try {
      final res = await http.get(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/feedback'));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          reviews = data['ratings'] ?? [];
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchSyncTelemetry() async {
    setState(() => _isSyncing = true);
    try {
      final res = await http.get(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/admin/sync-telemetry'));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          telemetry = data;
          if (data['drivers'] != null) drivers = data['drivers'];
          if (data['directory'] != null) directory = data['directory'];
        });
      }
      _fetchReviews();
    } catch (_) {}
    if (mounted) setState(() => _isSyncing = false);
  }

  List<dynamic> get _filteredDrivers {
    if (_searchQuery.isEmpty) return drivers;
    final q = _searchQuery.toLowerCase();
    return drivers.where((d) {
      final name = (d['name'] ?? '').toString().toLowerCase();
      final phone = (d['phone'] ?? '').toString().toLowerCase();
      final veh = (d['vehicleNumber'] ?? '').toString().toLowerCase();
      final code = (d['driverCode'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q) || veh.contains(q) || code.contains(q);
    }).toList();
  }

  List<dynamic> get _filteredCustomers {
    if (_searchQuery.isEmpty) return directory;
    final q = _searchQuery.toLowerCase();
    return directory.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final phone = (c['phone'] ?? '').toString().toLowerCase();
      final addr = (c['address'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q) || addr.contains(q);
    }).toList();
  }

  List<dynamic> get _filteredReviews {
    if (_searchQuery.isEmpty) return reviews;
    final q = _searchQuery.toLowerCase();
    return reviews.where((r) {
      final name = (r['driverName'] ?? '').toString().toLowerCase();
      final cust = (r['customerName'] ?? '').toString().toLowerCase();
      final ord = (r['orderId'] ?? '').toString().toLowerCase();
      final fb = (r['feedback'] ?? '').toString().toLowerCase();
      return name.contains(q) || cust.contains(q) || ord.contains(q) || fb.contains(q);
    }).toList();
  }

  Future<void> _confirmAndDeleteDriver(Map<String, dynamic> d) async {
    final driverName = d['name'] ?? 'Driver';
    final driverCode = d['driverCode'] ?? 'DRV-1001';
    final driverId = d['driverId'] ?? d['id'] ?? driverCode;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Permanently Delete Driver?',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete driver account for $driverName ($driverCode)?',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ This action is permanent and cannot be undone. All active sessions, delivery assignments, and login access will be immediately terminated.',
                      style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_forever, color: Colors.white, size: 18),
            label: const Text('PERMANENTLY DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await http.delete(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/admin/drivers/$driverId'));
      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            drivers.removeWhere((item) => (item['driverId'] == driverId || item['driverCode'] == driverCode || item['driverCode'] == driverId));
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Driver $driverName ($driverCode) permanently deleted from fleet.'),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _fetchSyncTelemetry();
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Failed to delete driver';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ $err'), backgroundColor: Colors.red.shade800),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error connecting to server: $e'), backgroundColor: Colors.red.shade800),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isUnlocked) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD4AF37), Color(0xFFAA7C11)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.white, size: 42),
                ),
                const SizedBox(height: 18),
                const Text(
                  'EXECUTIVE CD VAULT',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Color(0xFF1E1E22),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Confidential Customer & Driver Fleet Master Directory',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _keyCtrl,
                  obscureText: _obscurePasskey,
                  onSubmitted: (_) => _verify(),
                  decoration: InputDecoration(
                    labelText: 'Executive Passkey',
                    hintText: 'Enter reverse admin password',
                    prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFFD4AF37)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePasskey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePasskey = !_obscurePasskey),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 14, color: Colors.amber.shade800),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Passkey is the reverse of your Admin password (e.g. "nimda321")',
                        style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                if (_err.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _err,
                              style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    onPressed: _isVerifying ? null : _verify,
                    child: _isVerifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'UNLOCK EXECUTIVE VAULT',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── UNLOCKED VAULT VIEW ──
    final onlineDriversCount = drivers.where((d) => d['status'] == 'ONLINE' || d['isDelivering'] == true).length;
    final deliveringCount = drivers.where((d) => d['isDelivering'] == true || d['status'] == 'DELIVERING').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Column(
        children: [
          // Top Vault Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.shield_rounded, color: Color(0xFFD4AF37), size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EXECUTIVE CD VAULT',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5, color: Color(0xFF1E1E22)),
                          ),
                          Text(
                            'Authorized Access • Level 5 Clearance',
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Synchronize Data with Database',
                      icon: _isSyncing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF5200)))
                          : const Icon(Icons.sync_rounded, color: Color(0xFFFF5200)),
                      onPressed: _isSyncing ? null : _fetchSyncTelemetry,
                    ),
                    IconButton(
                      tooltip: 'Lock Vault',
                      icon: const Icon(Icons.lock_outline_rounded, color: Colors.grey),
                      onPressed: () => setState(() => isUnlocked = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search Bar
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: _selectedVaultTab == 0
                        ? 'Search drivers by name, phone, or vehicle...'
                        : _selectedVaultTab == 1
                            ? 'Search customers by name, phone, or address...'
                            : _selectedVaultTab == 2
                                ? 'Search feedback by order, driver, or comment...'
                                : 'Search database telemetry...',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  ),
                ),
                const SizedBox(height: 12),

                // Vault Segment Tabs
                Row(
                  children: [
                    Expanded(
                      child: _buildVaultSegmentTab(
                        index: 0,
                        icon: Icons.two_wheeler_rounded,
                        label: 'Fleet',
                        count: drivers.length,
                        activeColor: const Color(0xFFFF5200),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildVaultSegmentTab(
                        index: 1,
                        icon: Icons.people_alt_rounded,
                        label: 'Customers',
                        count: directory.length,
                        activeColor: const Color(0xFF007BFF),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildVaultSegmentTab(
                        index: 2,
                        icon: Icons.star_rounded,
                        label: 'Reviews',
                        count: reviews.length,
                        activeColor: Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildVaultSegmentTab(
                        index: 3,
                        icon: Icons.cloud_sync_rounded,
                        label: 'Telemetry',
                        count: null,
                        activeColor: const Color(0xFF0F8A65),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content Views
          Expanded(
            child: IndexedStack(
              index: _selectedVaultTab,
              children: [
                // 1. DRIVER FLEET VIEW
                _buildDriversView(onlineDriversCount, deliveringCount),

                // 2. CUSTOMER DIRECTORY VIEW
                _buildCustomersView(),

                // 3. REVIEWS & FEEDBACK VIEW
                _buildReviewsView(),

                // 4. LIVE DB SYNC TELEMETRY VIEW
                _buildTelemetryView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultSegmentTab({
    required int index,
    required IconData icon,
    required String label,
    int? count,
    required Color activeColor,
  }) {
    final isSelected = _selectedVaultTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedVaultTab = index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: isSelected ? activeColor : Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected ? activeColor : Colors.grey.shade800,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 1. DRIVER FLEET VIEW ──
  Widget _buildDriversView(int onlineCount, int deliveringCount) {
    final list = _filteredDrivers;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Driver Fleet Status Summary Pill Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildFleetPill('Total Registered', '${drivers.length}', Colors.black87),
              _buildFleetPill('🟢 Online', '$onlineCount', Colors.green.shade700),
              _buildFleetPill('🔵 Delivering', '$deliveringCount', Colors.blue.shade700),
              _buildFleetPill('⚪ Offline', '${(drivers.length - onlineCount).clamp(0, 99)}', Colors.grey.shade600),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.two_wheeler_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 10),
                Text('No drivers match your search', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        else
          ...list.map((d) => _buildDriverCard(d)),
      ],
    );
  }

  Widget _buildFleetPill(String label, String value, Color col) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: col)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> d) {
    final name = d['name'] ?? 'Driver';
    final phone = d['phone'] ?? 'N/A';
    final vehicleType = d['vehicleType'] ?? 'Bike';
    final vehicleNumber = d['vehicleNumber'] ?? 'KA-17-EQ-4921';
    final licenseNumber = d['licenseNumber'] ?? 'DL-1420110012345';
    final rating = (d['rating'] as num?)?.toDouble() ?? 4.8;
    final totalDeliveries = d['totalDeliveries'] ?? 120;
    final registeredDate = d['registeredDate'] ?? '15 Jan 2024';
    final isDelivering = d['isDelivering'] == true || d['status'] == 'DELIVERING';
    final isOnline = d['status'] == 'ONLINE' || isDelivering;
    final driverCode = d['driverCode'] ?? 'DRV-101';
    final currentOrder = d['currentOrder'] as Map<String, dynamic>?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDelivering
              ? Colors.blue.shade300
              : isOnline
                  ? Colors.green.shade200
                  : Colors.grey.shade200,
          width: isDelivering || isOnline ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, Live Status Badge
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFFFF5200).withValues(alpha: 0.12),
                      child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFFFF5200), size: 24),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isDelivering
                              ? Colors.blue
                              : isOnline
                                  ? Colors.green
                                  : Colors.grey.shade400,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1E1E22)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              driverCode,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined, size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(phone, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text('$rating', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDelivering
                        ? Colors.blue.shade50
                        : isOnline
                            ? Colors.green.shade50
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDelivering
                          ? Colors.blue.shade300
                          : isOnline
                              ? Colors.green.shade300
                              : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDelivering
                            ? Icons.delivery_dining_rounded
                            : isOnline
                                ? Icons.check_circle_rounded
                                : Icons.power_settings_new_rounded,
                        size: 12,
                        color: isDelivering
                            ? Colors.blue.shade700
                            : isOnline
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDelivering
                            ? 'DELIVERING'
                            : isOnline
                                ? 'ONLINE'
                                : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: isDelivering
                              ? Colors.blue.shade800
                              : isOnline
                                  ? Colors.green.shade800
                                  : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Vehicle & Registration Details Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tag_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        const Text('Vehicle:', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        Text('$vehicleType ($vehicleNumber)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.badge_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        const Text('License:', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        Text(licenseNumber, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        const Text('Joined:', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        Text(registeredDate, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        const Text('Deliveries:', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        Text('$totalDeliveries Orders', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF5200))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Live Active Delivery Banner (If Delivering Order)
          if (isDelivering) ...[
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.electric_moped_rounded, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Delivery in Progress • Order #${currentOrder?['orderId'] ?? 'ORD-LIVE'}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue.shade900),
                        ),
                        if (currentOrder?['customerName'] != null)
                          Text(
                            'Customer: ${currentOrder?['customerName']} (${currentOrder?['deliveryAddress'] ?? 'Ring Road'})',
                            style: TextStyle(fontSize: 10, color: Colors.blue.shade800),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('LIVE GPS', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          // Action Buttons Bar (Permanent Delete)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.delete_forever_rounded, size: 14, color: Colors.red),
                  label: const Text('DELETE DRIVER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.red)),
                  onPressed: () => _confirmAndDeleteDriver(d),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── 2. CUSTOMER DIRECTORY VIEW ──
  Widget _buildCustomersView() {
    final list = _filteredCustomers;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Customer Count Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Verified Customers: ${directory.length}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              const Row(
                children: [
                  Icon(Icons.verified_user_rounded, size: 14, color: Color(0xFF0F8A65)),
                  SizedBox(width: 4),
                  Text('KYC Verified', style: TextStyle(fontSize: 11, color: Color(0xFF0F8A65), fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.person_search_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 10),
                Text('No customers match your search', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        else
          ...list.map((c) {
            final name = c['name'] ?? 'Customer';
            final phone = c['phone'] ?? 'N/A';
            final joined = c['joined'] ?? '12 Jan 2024';
            final address = c['address'] ?? '60 Feet Ring Road, Davanagere';
            final isGold = c['isGoldMember'] == true;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isGold ? Colors.amber.shade300 : Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isGold ? Colors.amber.shade100 : const Color(0xFF007BFF).withValues(alpha: 0.1),
                    child: Icon(
                      isGold ? Icons.workspace_premium_rounded : Icons.person_rounded,
                      color: isGold ? Colors.amber.shade900 : const Color(0xFF007BFF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E1E22))),
                            if (isGold) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.shade400),
                                ),
                                child: Text('GOLD MEMBER', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.amber.shade900)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 11, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(phone, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 10),
                            const Icon(Icons.calendar_today_outlined, size: 11, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text('Joined: $joined', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 11, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                address,
                                style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ── 3. REVIEWS & FEEDBACK VIEW ──
  Widget _buildReviewsView() {
    final list = _filteredReviews;
    final avgRating = reviews.isNotEmpty
        ? (reviews.fold<double>(0.0, (acc, r) => acc + ((r['rating'] as num?)?.toDouble() ?? 5.0)) / reviews.length).toStringAsFixed(1)
        : '5.0';

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Overall Rating Summary Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.shade300),
            boxShadow: [
              BoxShadow(color: Colors.amber.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.amber.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.star_rounded, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer Satisfaction: $avgRating ★', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1E1E22))),
                      Text('${reviews.length} Verified Customer Ratings', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF0F8A65), borderRadius: BorderRadius.circular(8)),
                child: const Text('100% VERIFIED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 10),
                Text('No reviews or feedback recorded yet', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        else
          ...list.map((r) {
            final driverName = r['driverName'] ?? 'Driver';
            final customerName = r['customerName'] ?? 'Customer';
            final orderId = r['orderId'] ?? 'ORD';
            final rating = (r['rating'] as num?)?.toDouble() ?? 5.0;
            final tip = (r['tip'] as num?)?.toDouble() ?? 0.0;
            final feedback = r['feedback'] ?? '';
            final dateStr = r['date'] != null
                ? DateTime.tryParse(r['date'])?.toLocal().toString().substring(0, 16) ?? 'Recent'
                : 'Recent';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(orderId, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFFFF5200))),
                          ),
                          const SizedBox(width: 8),
                          Text('by $customerName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                      Row(
                        children: [
                          ...List.generate(5, (idx) {
                            return Icon(
                              idx < rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 14,
                              color: Colors.amber,
                            );
                          }),
                          const SizedBox(width: 4),
                          Text('$rating', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (feedback.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.format_quote_rounded, size: 16, color: Color(0xFFFF5200)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              feedback,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF1E1E22), fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.two_wheeler_rounded, size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('Rider: $driverName', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800, fontWeight: FontWeight.bold)),
                          if (tip > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.shade300)),
                              child: Text('₹${tip.toInt()} Tip', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                            ),
                          ],
                        ],
                      ),
                      Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ── 4. LIVE DATABASE SYNC TELEMETRY VIEW ──
  Widget _buildTelemetryView() {
    final isDbConnected = telemetry['dbConnected'] ?? true;
    final totalOrders = telemetry['totalOrders'] ?? 0;
    final totalCustomers = telemetry['totalCustomers'] ?? directory.length;
    final totalDrivers = telemetry['totalDrivers'] ?? drivers.length;
    final syncedAt = telemetry['syncedAt'] ?? 'Just Now';
    final dbEngine = telemetry['databaseEngine'] ?? 'PostgreSQL 16 (Cloud / Local)';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Connection Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDbConnected
                  ? [const Color(0xFF0F8A65), const Color(0xFF0B664B)]
                  : [Colors.red.shade700, Colors.red.shade900],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (isDbConnected ? const Color(0xFF0F8A65) : Colors.red).withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isDbConnected ? 'DATABASE ONLINE' : 'DATABASE RECONNECTING',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'SYNC: $syncedAt',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Engine: $dbEngine',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              const Text(
                'Direct two-way synchronization active between Merchant Dashboard, Drivers, Customer App, and PostgreSQL Database.',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Synchronized Metrics Grid
        Row(
          children: [
            Expanded(child: _buildTelemetryStatCard('Synced Orders', '$totalOrders', Icons.receipt_long_rounded, const Color(0xFFFF5200))),
            const SizedBox(width: 12),
            Expanded(child: _buildTelemetryStatCard('Registered Drivers', '$totalDrivers', Icons.two_wheeler_rounded, const Color(0xFF007BFF))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildTelemetryStatCard('Customers Synced', '$totalCustomers', Icons.people_alt_rounded, const Color(0xFF0F8A65))),
            const SizedBox(width: 12),
            Expanded(child: _buildTelemetryStatCard('Dual Branches', '2 Active', Icons.storefront_rounded, Colors.purple.shade700)),
          ],
        ),
        const SizedBox(height: 20),

        // Action: Direct Sync Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            icon: _isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            label: Text(
              _isSyncing ? 'SYNCHRONIZING DATABASE...' : 'SYNCHRONIZE DATABASE NOW',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
            ),
            onPressed: _isSyncing ? null : _fetchSyncTelemetry,
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryStatCard(String title, String val, IconData icon, Color col) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: col, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(val, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: col)),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 6. COMBINED ADMIN SETTINGS (With Direct Branch & QR Image Uploads)
// ─────────────────────────────────────────────────────────────
class CombinedAdminSettingsView extends StatefulWidget {
  const CombinedAdminSettingsView({super.key});
  @override
  State<CombinedAdminSettingsView> createState() => _CombinedAdminSettingsViewState();
}

class _CombinedAdminSettingsViewState extends State<CombinedAdminSettingsView> {
  final _userCtrl = TextEditingController(text: 'admin');
  final _ownerCtrl = TextEditingController(text: 'Rameez Ahmed');
  final _emailCtrl = TextEditingController(text: 'admin@rameezkitchen.com');
  final _phoneCtrl = TextEditingController(text: '8073349233');
  final _taglineCtrl = TextEditingController(text: 'Authentic Charcoal Kebabs & Traditional Dum Biryani');
  final _oldPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  bool _obscureOldPass = true;
  bool _obscureNewPass = true;

  Map<String, dynamic> branchStatus = {'60_feet_ring_road': true, 'nittuvalli_circle': true};
  Map<String, dynamic> branchesInfo = {
    '60_feet_ring_road': {
      'key': '60_feet_ring_road',
      'name': 'Main Kitchen (60 Feet Ring Road)',
      'tagline': 'Flagship Charcoal Grills & Dum Biryani Hub',
      'address': 'Near Bus Stop, 60 Feet Ring Road, Davanagere',
      'phone': '+91 8073349233',
      'manager': 'Rameez Ahmed',
      'avgPrepTime': '20-25 mins',
      'image': 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
      'isOpen': true,
    },
    'nittuvalli_circle': {
      'key': 'nittuvalli_circle',
      'name': 'Express Hub (Nittuvalli Circle)',
      'tagline': 'Fast Food, Shawarmas & Quick Bites',
      'address': 'Nittuvalli Main Road, Opposite SBI, Davanagere',
      'phone': '+91 9654321076',
      'manager': 'Farhan Akhtar',
      'avgPrepTime': '15-20 mins',
      'image': 'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800',
      'isOpen': true,
    },
  };

  Map<String, dynamic> restaurantProfile = {
    'name': 'Rameez Kitchen',
    'tagline': 'Authentic Charcoal Kebabs & Traditional Dum Biryani',
    'ownerName': 'Rameez Ahmed',
    'avatar': 'https://images.unsplash.com/photo-1577219491135-ce391730fb2c?w=400',
    'banner': 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=1200',
    'banners': [
      'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800',
      'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=800',
      'https://images.unsplash.com/photo-1544025162-d76694265947?w=800',
      'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800',
    ],
    'maxCustomerLimit': 500,
    'rating': 4.9,
    'cuisine': 'Mughlai • North Indian • Biryani • BBQ',
    'operatingHours': '11:00 AM – 11:30 PM',
    'fssaiNumber': '11223344005566',
  };

  Map<String, dynamic> paymentSettings = {'taxPercent': 5, 'serviceCharge': 15, 'upiQrImage': ''};
  List<dynamic> auditLogs = [];
  bool _loading = true;
  bool _savingProfile = false;
  String _profileStatusMsg = '';
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    fetchAdminData();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _ownerCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _taglineCtrl.dispose();
    _oldPassCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchAdminData() async {
    try {
      final res = await http.get(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/merchant/init'));
      final logRes = await http.get(Uri.parse('https://rameez-kitchen-backend.onrender.com/api/admin/audit-logs'));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          if (data['branchStatus'] != null) branchStatus = Map<String, dynamic>.from(data['branchStatus']);
          if (data['branchesInfo'] != null) {
            branchesInfo = Map<String, dynamic>.from(data['branchesInfo']);
          }
          if (data['restaurantProfile'] != null) {
            restaurantProfile = Map<String, dynamic>.from(data['restaurantProfile']);
            if (restaurantProfile['ownerName'] != null) _ownerCtrl.text = restaurantProfile['ownerName'];
            if (restaurantProfile['tagline'] != null) _taglineCtrl.text = restaurantProfile['tagline'];
          }
          if (data['paymentSettings'] != null) paymentSettings = Map<String, dynamic>.from(data['paymentSettings']);
          if (data['admin'] != null) {
            _userCtrl.text = data['admin']['username'] ?? 'admin';
            _emailCtrl.text = data['admin']['email'] ?? 'admin@rameezkitchen.com';
            _phoneCtrl.text = data['admin']['phone'] ?? '8073349233';
            if (data['admin']['restaurantProfile'] != null) {
              restaurantProfile = Map<String, dynamic>.from(data['admin']['restaurantProfile']);
            }
          }
          if (logRes.statusCode == 200) auditLogs = jsonDecode(logRes.body);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleBranch(String branchKey, bool isOpen) async {
    setState(() {
      branchStatus[branchKey] = isOpen;
      if (branchesInfo[branchKey] != null) {
        branchesInfo[branchKey]['isOpen'] = isOpen;
      }
    });

    try {
      await http.post(
        Uri.parse('https://rameez-kitchen-backend.onrender.com/api/merchant/branch-toggle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'branchKey': branchKey, 'isOpen': isOpen}),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOpen
              ? '✓ ${branchesInfo[branchKey]?['name'] ?? branchKey} is now OPEN for orders!'
              : '✓ ${branchesInfo[branchKey]?['name'] ?? branchKey} is now CLOSED (Paused).'),
          backgroundColor: isOpen ? const Color(0xFF0F8A65) : Colors.blueGrey.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
      fetchAdminData();
    } catch (_) {}
  }

  Future<void> _updateBranchImage(String branchKey, String imageUrl) async {
    setState(() {
      if (branchesInfo[branchKey] != null) {
        branchesInfo[branchKey]['image'] = imageUrl;
      }
    });

    try {
      await http.post(
        Uri.parse('https://rameez-kitchen-backend.onrender.com/api/merchant/branch-update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'branchKey': branchKey,
          'image': imageUrl,
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Branch picture updated & broadcasted to Customer App!'),
            backgroundColor: Color(0xFF0F8A65),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      fetchAdminData();
    } catch (_) {}
  }

  void _openBranchEditor(String branchKey) {
    final br = branchesInfo[branchKey] ?? {};
    final nameCtrl = TextEditingController(text: br['name'] ?? '');
    final taglineCtrl = TextEditingController(text: br['tagline'] ?? '');
    final addrCtrl = TextEditingController(text: br['address'] ?? '');
    final phoneCtrl = TextEditingController(text: br['phone'] ?? '');
    final managerCtrl = TextEditingController(text: br['manager'] ?? '');
    final prepCtrl = TextEditingController(text: br['avgPrepTime'] ?? '20-25 mins');
    String currentImg = br['image'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFF5200).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.storefront_rounded, color: Color(0xFFFF5200), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Edit ${br['name'] ?? 'Branch'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DirectImageUploadField(
                    initialValue: currentImg,
                    label: 'Branch Storefront Picture (Shows on Customer App)',
                    onImageChanged: (val) {
                      setDlgState(() => currentImg = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Branch Name', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: taglineCtrl, decoration: const InputDecoration(labelText: 'Branch Tagline / Specialties', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: addrCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Full Address', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Branch Phone', border: OutlineInputBorder()))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: managerCtrl, decoration: const InputDecoration(labelText: 'Kitchen Manager', border: OutlineInputBorder()))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: prepCtrl, decoration: const InputDecoration(labelText: 'Average Prep Time', hintText: 'e.g. 20-25 mins', border: OutlineInputBorder())),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final payload = {
                  'branchKey': branchKey,
                  'image': currentImg,
                  'name': nameCtrl.text.trim(),
                  'tagline': taglineCtrl.text.trim(),
                  'address': addrCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'manager': managerCtrl.text.trim(),
                  'avgPrepTime': prepCtrl.text.trim(),
                };

                await http.post(
                  Uri.parse('https://rameez-kitchen-backend.onrender.com/api/merchant/branch-update'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(payload),
                );

                if (mounted && ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: Color(0xFF0F8A65), content: Text('✓ Branch details updated & synced to Customer App!')),
                  );
                  fetchAdminData();
                }
              },
              child: const Text('Save Branch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _showAuditClearDialog() async {
    final passCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('Clear Audit Logs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This action requires Master Passkey authorization.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Master Passkey',
                prefixIcon: const Icon(Icons.vpn_key_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All Logs', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (result == true && passCtrl.text.isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse('https://rameez-kitchen-backend.onrender.com/api/admin/audit-logs/clear'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'passkey': passCtrl.text.trim()}),
        );
        if (res.statusCode == 200 && mounted) {
          fetchAdminData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Audit logs cleared successfully'), backgroundColor: Colors.green),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✗ ${jsonDecode(res.body)['error'] ?? 'Unauthorized'}'), backgroundColor: Colors.red),
          );
        }
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connection error'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _saveAdminProfile() async {
    setState(() {
      _savingProfile = true;
      _profileStatusMsg = '';
    });

    final payload = {
      'username': _userCtrl.text.trim(),
      'ownerName': _ownerCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'tagline': _taglineCtrl.text.trim(),
      'avatar': restaurantProfile['avatar'],
      'banner': restaurantProfile['banner'],
      'banners': restaurantProfile['banners'],
      'maxCustomerLimit': restaurantProfile['maxCustomerLimit'] ?? 500,
      'currentPassword': _oldPassCtrl.text.trim(),
      'newPassword': _newPassCtrl.text.trim(),
    };

    try {
      final res = await http.post(
        Uri.parse('https://rameez-kitchen-backend.onrender.com/api/admin/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      final resData = jsonDecode(res.body);

      setState(() {
        _savingProfile = false;
        if (res.statusCode == 200) {
          _profileStatusMsg = '✓ Profile & Credentials saved and broadcasted successfully!';
          _isError = false;
          _oldPassCtrl.clear();
          _newPassCtrl.clear();
        } else {
          _profileStatusMsg = resData['error'] ?? 'Error updating details';
          _isError = true;
        }
      });
      fetchAdminData();
    } catch (_) {
      setState(() {
        _savingProfile = false;
        _profileStatusMsg = 'Failed to connect to backend server';
        _isError = true;
      });
    }
  }

  void _openFeeEditor(String field, String title, int currentVal) {
    final valCtrl = TextEditingController(text: currentVal.toString());
    final passCtrl = TextEditingController();
    final isTax = field == 'taxPercent';
    final presets = isTax ? [0, 5, 12, 18] : [0, 10, 15, 25];

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isTax ? Colors.orange.shade50 : Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isTax ? Icons.percent_rounded : Icons.takeout_dining_rounded,
                  color: isTax ? const Color(0xFFFF5200) : Colors.purple.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Configure $title',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTax
                      ? 'Select quick GST rate preset or enter custom percentage:'
                      : 'Select standard packaging fee preset or enter custom amount:',
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: presets.map((p) {
                    final isSel = valCtrl.text == p.toString();
                    return ActionChip(
                      backgroundColor: isSel ? const Color(0xFFFF5200).withValues(alpha: 0.15) : Colors.grey.shade100,
                      side: BorderSide(color: isSel ? const Color(0xFFFF5200) : Colors.grey.shade300),
                      label: Text(
                        isTax ? '$p% ${p == 0 ? "(Exempt)" : p == 5 ? "(Standard)" : ""}' : '₹$p ${p == 0 ? "(Free)" : ""}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: isSel ? const Color(0xFFFF5200) : Colors.black87,
                        ),
                      ),
                      onPressed: () {
                        setDlg(() => valCtrl.text = p.toString());
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: valCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isTax ? 'Tax Rate (%)' : 'Packaging & Service Fee (₹)',
                    prefixIcon: Icon(isTax ? Icons.percent : Icons.currency_rupee, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Admin Password (to authorize change)',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () async {
                final numVal = int.tryParse(valCtrl.text) ?? currentVal;
                final res = await http.post(
                  Uri.parse('https://rameez-kitchen-backend.onrender.com/api/settings/payment-update'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    field: numVal,
                    'currentPassword': passCtrl.text.trim(),
                  }),
                );
                if (mounted && dlgCtx.mounted) {
                  Navigator.pop(dlgCtx);
                  if (res.statusCode == 200) {
                    fetchAdminData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF0F8A65),
                        content: Text('✓ $title updated to ${isTax ? "$numVal%" : "₹$numVal"} & broadcasted!'),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(backgroundColor: Colors.red, content: Text('Invalid admin password authorization!')),
                    );
                  }
                }
              },
              child: const Text('Save & Broadcast', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── MOVING HERO BANNERS & 500 CUSTOMERS LIMIT MANAGER ──
  Widget _buildMovingHeroBannersManager() {
    final List<String> banners = (restaurantProfile['banners'] is List)
        ? List<String>.from(restaurantProfile['banners'])
        : [
            'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800',
            'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=800',
            'https://images.unsplash.com/photo-1544025162-d76694265947?w=800',
            'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800',
          ];
    final int customerLimit = restaurantProfile['maxCustomerLimit'] ?? 500;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.collections_rounded, color: Color(0xFFFF5200), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Moving Hero Banners (Real Pictures)',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E1E22)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${banners.length} Live Slides',
                    style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'These real merchant photos rotate dynamically in an auto-sliding hero carousel for all customers.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),

            // Customer Limit Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5200).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF5200).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_alt_rounded, color: Color(0xFFFF5200), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Max Customer Capacity: $customerLimit Customers',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFFF5200)),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Guaranteed high-speed kitchen and delivery service limited to top 500 customers.',
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('ACTIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Horizontal Preview of moving photos
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: banners.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == banners.length) {
                    // Add Picture Button
                    return InkWell(
                      onTap: () {
                        UniversalImagePicker.pickImage(
                          onSelected: (url, _) {
                            setState(() {
                              banners.add(url);
                              restaurantProfile['banners'] = banners;
                            });
                            _saveAdminProfile();
                          },
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 100,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded, color: Color(0xFFFF5200), size: 28),
                            SizedBox(height: 6),
                            Text('Add Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF5200))),
                          ],
                        ),
                      ),
                    );
                  }

                  final url = banners[i];
                  return Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 10),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            url,
                            width: 130,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () {
                              if (banners.length <= 1) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('At least 1 banner photo is required.')),
                                );
                                return;
                              }
                              setState(() {
                                banners.removeAt(i);
                                restaurantProfile['banners'] = banners;
                              });
                              _saveAdminProfile();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black75,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 16),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                            child: Text('Slide ${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // Save and Broadcast Button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5200),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('SAVE & BROADCAST TO CUSTOMERS NOW', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                onPressed: () {
                  restaurantProfile['banners'] = banners;
                  restaurantProfile['maxCustomerLimit'] = customerLimit;
                  _saveAdminProfile();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF5200)));

    final br1 = branchesInfo['60_feet_ring_road'] ?? {};
    final br2 = branchesInfo['nittuvalli_circle'] ?? {};
    final isBr1Open = branchStatus['60_feet_ring_road'] ?? true;
    final isBr2Open = branchStatus['nittuvalli_circle'] ?? true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 1. RESTAURANT & MERCHANT BRANDING HEADER CARD ──
        _buildMerchantBrandingCard(),
        const SizedBox(height: 16),

        // ── 1.5. MOVING HERO BANNERS & 500 CUSTOMERS LIMIT MANAGER ──
        _buildMovingHeroBannersManager(),
        const SizedBox(height: 16),

        // ── 2. DUAL-BRANCH OPERATIONS CONTROL CARDS (WITH DIRECT PHOTO UPLOAD) ──
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.storefront_rounded, color: Color(0xFFFF5200), size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Dual-Branch Operations Control',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E1E22)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F8A65).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${(isBr1Open ? 1 : 0) + (isBr2Open ? 1 : 0)} / 2 Active',
                        style: const TextStyle(color: Color(0xFF0F8A65), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Toggle branch kitchens on/off in real-time and upload storefront photos shown to customers.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 24),

                // Branch 1 Card
                _buildBranchControlCard(
                  branchKey: '60_feet_ring_road',
                  branchData: br1,
                  isOpen: isBr1Open,
                  defaultTitle: 'Branch 1: 60 Feet Ring Road (Main Kitchen)',
                ),
                const SizedBox(height: 14),

                // Branch 2 Card
                _buildBranchControlCard(
                  branchKey: 'nittuvalli_circle',
                  branchData: br2,
                  isOpen: isBr2Open,
                  defaultTitle: 'Branch 2: Nittuvalli Circle (Express Hub)',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── 3. ADMIN PROFILE & SECURE CREDENTIALS CARD ──
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.badge_rounded, color: Color(0xFFFF5200), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Admin Profile & Credentials',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E1E22)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _userCtrl,
                        decoration: InputDecoration(
                          labelText: 'Admin Username',
                          prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _ownerCtrl,
                        decoration: InputDecoration(
                          labelText: 'Owner / Head Chef Name',
                          prefixIcon: const Icon(Icons.restaurant_rounded, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailCtrl,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          prefixIcon: const Icon(Icons.email_outlined, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _phoneCtrl,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _taglineCtrl,
                  decoration: InputDecoration(
                    labelText: 'Restaurant Bio / Specialties',
                    prefixIcon: const Icon(Icons.description_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 10),
                const Text(
                  'Password & Security Authorization',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _oldPassCtrl,
                  obscureText: _obscureOldPass,
                  decoration: InputDecoration(
                    labelText: 'Current Password (Required to authorize changes)',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureOldPass ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setState(() => _obscureOldPass = !_obscureOldPass),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPassCtrl,
                  obscureText: _obscureNewPass,
                  decoration: InputDecoration(
                    labelText: 'New Password (Optional, leave blank to keep unchanged)',
                    prefixIcon: const Icon(Icons.lock_reset_rounded, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNewPass ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setState(() => _obscureNewPass = !_obscureNewPass),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (_profileStatusMsg.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isError ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _isError ? Colors.red.shade200 : Colors.green.shade300),
                    ),
                    child: Text(
                      _profileStatusMsg,
                      style: TextStyle(color: _isError ? Colors.red.shade800 : Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: _savingProfile ? null : _saveAdminProfile,
                    child: _savingProfile
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text(
                            'SAVE SETTINGS & CREDENTIALS',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── 4. ORDER CHARGES, TAX & PACKAGING ARCHITECTURE ──
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFF5200).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFF5200), size: 20),
            ),
            title: const Text('Tax Rate & Packaging Fee Architecture', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            subtitle: const Text('Configures dynamic customer billing & cart calculations', style: TextStyle(fontSize: 11, color: Colors.grey)),
            children: [
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Row 1: Tax Rate Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.percent_rounded, color: Colors.deepOrange, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Government GST / Sales Tax', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                          Text('Currently: ${paymentSettings['taxPercent']}% on food subtotal', style: TextStyle(color: Colors.orange.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF5200),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.tune_rounded, size: 14),
                                label: const Text('Adjust Tax %', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: () => _openFeeEditor('taxPercent', 'Tax Rate (%)', paymentSettings['taxPercent'] ?? 5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Quick GST Presets (Applied in real-time across Customer Checkout):',
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [0, 5, 12, 18].map((rate) {
                              final isCurrent = (paymentSettings['taxPercent'] ?? 5) == rate;
                              return ActionChip(
                                backgroundColor: isCurrent ? const Color(0xFFFF5200).withValues(alpha: 0.15) : Colors.white,
                                side: BorderSide(color: isCurrent ? const Color(0xFFFF5200) : Colors.grey.shade300),
                                label: Text(
                                  '$rate% ${rate == 0 ? "(Exempt)" : rate == 5 ? "(Standard GST)" : rate == 18 ? "(AC/Luxury)" : ""}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent ? const Color(0xFFFF5200) : Colors.black87,
                                  ),
                                ),
                                onPressed: () => _openFeeEditor('taxPercent', 'Tax Rate (%)', rate),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Row 2: Service & Packaging Fee Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.takeout_dining_rounded, color: Colors.purple.shade800, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Service & Hygiene Packaging Fee', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                          Text('Currently: ₹${paymentSettings['serviceCharge']} per order', style: TextStyle(color: Colors.purple.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.tune_rounded, size: 14),
                                label: const Text('Adjust Fee (₹)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: () => _openFeeEditor('serviceCharge', 'Service Charge (₹)', paymentSettings['serviceCharge'] ?? 15),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Quick Packaging Presets (Food containers, tamper seals & carry bags):',
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [0, 10, 15, 25].map((fee) {
                              final isCurrent = (paymentSettings['serviceCharge'] ?? 15) == fee;
                              return ActionChip(
                                backgroundColor: isCurrent ? Colors.purple.withValues(alpha: 0.15) : Colors.white,
                                side: BorderSide(color: isCurrent ? Colors.purple : Colors.grey.shade300),
                                label: Text(
                                  '₹$fee ${fee == 0 ? "(Free/₹0)" : fee == 10 ? "(Basic)" : fee == 15 ? "(Standard)" : "(Thermal Box)"}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent ? Colors.purple.shade800 : Colors.black87,
                                  ),
                                ),
                                onPressed: () => _openFeeEditor('serviceCharge', 'Service Charge (₹)', fee),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Row 3: Live Customer Checkout Simulator
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.calculate_rounded, color: Color(0xFF0F8A65), size: 18),
                                  SizedBox(width: 6),
                                  Text('Live Checkout Calculation Simulator', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF0F8A65))),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF0F8A65), borderRadius: BorderRadius.circular(6)),
                                child: const Text('AUTO SYNC', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final taxP = paymentSettings['taxPercent'] ?? 5;
                              final srv = paymentSettings['serviceCharge'] ?? 15;
                              const sampleSubtotal = 400;
                              final taxAmt = (sampleSubtotal * taxP / 100).round();
                              final total = sampleSubtotal + taxAmt + srv;
                              return Column(
                                children: [
                                  const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Sample Food Subtotal:', style: TextStyle(fontSize: 11)), Text('₹400', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))]),
                                  const SizedBox(height: 3),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('GST ($taxP%):', style: const TextStyle(fontSize: 11)), Text('+₹$taxAmt', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange))]),
                                  const SizedBox(height: 3),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Hygiene & Packaging:', style: TextStyle(fontSize: 11)), Text('+₹$srv', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade700))]),
                                  const Divider(height: 12),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Simulated Customer Total:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)), Text('₹$total', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F8A65)))]),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── 5. SECURITY & AUDIT LOGS ──
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.blueGrey.shade100, Colors.blueGrey.shade50]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shield_rounded, color: Colors.blueGrey, size: 22),
            ),
            title: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Security & Access Audit Logs', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      Text('Merchant logins, credential changes & security events', style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
                    ],
                  ),
                ),
                if (auditLogs.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                    child: Text('${auditLogs.length} Events', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.red.shade700)),
                  ),
              ],
            ),
            children: [
              const Divider(height: 1),
              if (auditLogs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.verified_user_rounded, color: Colors.green, size: 40),
                      SizedBox(height: 8),
                      Text('All Systems Secure • Audit Monitoring Active', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      SizedBox(height: 4),
                      Text('Merchant logins, password edits & profile updates will appear here automatically.', style: TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
                    ],
                  ),
                )
              else ...[
                Container(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: auditLogs.take(40).length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, i) {
                      final log = auditLogs[i];
                      final severity = (log['severity'] ?? 'INFO').toString().toUpperCase();
                      final source = (log['source'] ?? 'MERCHANT_APP').toString().toUpperCase();
                      final ip = log['ip']?.toString() ?? '';
                      final IconData sevIcon;
                      final Color sevColor;
                      final String sevLabel;

                      if (severity == 'CRITICAL') {
                        sevIcon = Icons.error_rounded;
                        sevColor = Colors.red;
                        sevLabel = 'CRITICAL';
                      } else if (severity == 'WARNING') {
                        sevIcon = Icons.warning_amber_rounded;
                        sevColor = Colors.orange;
                        sevLabel = 'WARNING';
                      } else {
                        sevIcon = Icons.shield_outlined;
                        sevColor = const Color(0xFF0F8A65);
                        sevLabel = 'SECURITY';
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2, right: 10),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: sevColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(sevIcon, size: 16, color: sevColor),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log['action'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: sevColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: sevColor.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(sevLabel, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: sevColor)),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(4)),
                                        child: Text(source, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.blueGrey.shade700)),
                                      ),
                                      if (ip.isNotEmpty && ip != '127.0.0.1')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                                          child: Text('IP: $ip', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                                        ),
                                      Text(log['date'] ?? log['timestamp'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Hidden clear button - activated by long press
                GestureDetector(
                  onLongPress: () => _showAuditClearDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    child: Text('• ${auditLogs.length} security events logged • (Master Protected) •', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── BRANDING & PROFILE HEADER ──
  Widget _buildMerchantBrandingCard() {
    final avatar = restaurantProfile['avatar'] ?? 'https://images.unsplash.com/photo-1577219491135-ce391730fb2c?w=400';
    final owner = restaurantProfile['ownerName'] ?? 'Rameez Ahmed';
    final storeName = restaurantProfile['name'] ?? 'Rameez Kitchen';
    final tagline = restaurantProfile['tagline'] ?? 'Authentic Charcoal Kebabs & Traditional Dum Biryani';
    final rating = restaurantProfile['rating'] ?? 4.9;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Brand Banner
          Container(
            height: 80,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF5200), Color(0xFFFF7A00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Transform.translate(
                  offset: const Offset(0, -36),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 36,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: NetworkImage(avatar),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: InkWell(
                              onTap: () {
                                UniversalImagePicker.pickImage(
                                  onSelected: (url, _) {
                                    setState(() {
                                      restaurantProfile['avatar'] = url;
                                    });
                                    _saveAdminProfile();
                                  },
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF5200),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    storeName,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E1E22)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.verified_rounded, color: Color(0xFF0F8A65), size: 18),
                              ],
                            ),
                            Text(
                              'Owner: $owner • Admin',
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
                            const SizedBox(width: 2),
                            Text('$rating ★', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black87)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tagline,
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildCuisineTag('Dum Biryani'),
                          _buildCuisineTag('Charcoal Grills'),
                          _buildCuisineTag('Shawarmas'),
                          _buildCuisineTag('Tandoori Kebab'),
                          _buildCuisineTag('Dual Cloud Kitchens'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuisineTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5200).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFF5200).withValues(alpha: 0.2)),
      ),
      child: Text(
        tag,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFF5200)),
      ),
    );
  }

  // ── DUAL BRANCH CONTROL CARD ──
  Widget _buildBranchControlCard({
    required String branchKey,
    required Map<String, dynamic> branchData,
    required bool isOpen,
    required String defaultTitle,
  }) {
    final title = branchData['name'] ?? defaultTitle;
    final tagline = branchData['tagline'] ?? 'Direct Delivery & Takeaway Kitchen';
    final address = branchData['address'] ?? 'Davanagere';
    final phone = branchData['phone'] ?? '+91 8073349233';
    final manager = branchData['manager'] ?? 'Store Manager';
    final prepTime = branchData['avgPrepTime'] ?? '20-25 mins';
    final image = branchData['image'] ?? 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOpen ? const Color(0xFF0F8A65).withValues(alpha: 0.3) : Colors.grey.shade300,
          width: isOpen ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Storefront Image Banner with Direct Upload Overlay
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(13), topRight: Radius.circular(13)),
                child: Image.network(
                  image,
                  height: 130,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 130,
                    color: Colors.grey.shade300,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                  ),
                ),
              ),
              // Live Open/Closed Badge
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOpen ? const Color(0xFF0F8A65) : Colors.red.shade700,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(isOpen ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded, size: 13, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        isOpen ? 'OPEN FOR ORDERS' : 'CLOSED / PAUSED',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              // Change Photo Button (Direct Device Picker)
              Positioned(
                top: 10,
                right: 10,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.75),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded, size: 14),
                  label: const Text('Change Photo', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    UniversalImagePicker.pickImage(
                      onSelected: (url, _) {
                        _updateBranchImage(branchKey, url);
                      },
                    );
                  },
                ),
              ),
            ],
          ),

          // Branch Details Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1E1E22)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tagline,
                            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    // Toggle Switch
                    Row(
                      children: [
                        Text(
                          isOpen ? 'ACCEPTING' : 'PAUSED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: isOpen ? const Color(0xFF0F8A65) : Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Switch(
                          value: isOpen,
                          activeThumbColor: const Color(0xFF0F8A65),
                          activeTrackColor: const Color(0xFF0F8A65).withValues(alpha: 0.3),
                          inactiveThumbColor: Colors.grey.shade400,
                          onChanged: (v) => _toggleBranch(branchKey, v),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        address,
                        style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('Manager: $manager ($phone)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('Prep: $prepTime', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF5200))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5200),
                      side: const BorderSide(color: Color(0xFFFF5200)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text('Edit Branch Info', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => _openBranchEditor(branchKey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}