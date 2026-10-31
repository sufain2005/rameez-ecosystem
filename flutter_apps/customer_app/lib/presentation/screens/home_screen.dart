import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/universal_image_picker.dart';
import '../../logic/wallet_provider.dart';
import '../../logic/auth_provider.dart';
import 'login_screen.dart';
import 'live_order_tracking_screen.dart';
import 'wallet_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final int currentTabIndex;
  final ValueChanged<int>? onTabChanged;
  final String initialName;
  final String initialPhone;
  final String initialEmail;
  final String initialAvatar;

  const HomeScreen({
    super.key,
    this.currentTabIndex = 0,
    this.onTabChanged,
    this.initialName = "Valued Customer",
    this.initialPhone = "",
    this.initialEmail = "",
    this.initialAvatar = "",
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late int _selectedTab;
  bool isDarkMode = false;
  bool isGoldMember = false;

  // Address
  String houseNo = "Flat 204";
  String streetName = "Near Bus Stop";
  String areaName = "60 Feet Ring Road";
  String deliveryAddress = "Flat 204, Near Bus Stop, 60 Feet Ring Road";

  // Customer Profile Information
  late String customerName;
  late String customerPhone;
  late String customerEmail;
  String customerAvatar = "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400";
  Map<String, dynamic> branchStatus = {'60_feet_ring_road': true, 'nittuvalli_circle': true};
  Map<String, dynamic> branchesInfo = {
    '60_feet_ring_road': {
      'name': '60 Feet Ring Road',
      'tagline': 'Flagship Main Kitchen',
      'image': 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
      'isOpen': true,
    },
    'nittuvalli_circle': {
      'name': 'Nittuvalli Circle',
      'tagline': 'Express Hub',
      'image': 'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800',
      'isOpen': true,
    },
  };
  Map<String, dynamic> globalStatus = {'state': 'ACCEPTING_ORDERS', 'pauseReason': ''};
  Map<String, dynamic> paymentSettings = {'taxPercent': 5, 'serviceCharge': 15, 'upiQrImage': ''};

  List<String> savedPaymentMethods = [
    'UPI: rameez@okaxis (Primary)',
    'Debit Card: HDFC Bank •••• 4821',
    'Cash on Delivery (COD)'
  ];

  final Map<int, int> cartQuantities = {};
  String selectedPaymentMethod = 'UPI (GPay)';
  String? appliedCoupon;
  int discountAmount = 0;
  int pendingCancellationFee = 0;

  List<dynamic> dynamicOffers = [];
  List<Map<String, dynamic>> activeOrdersList = [];
  List<Map<String, dynamic>> pastOrdersList = [
    {
      'orderId': 'ORD-984210',
      'items': [
        {'name': 'Chicken Dum Biryani', 'price': 220, 'quantity': 1, 'portion': 'Single'}
      ],
      'totalAmount': 230,
      'savings': 50,
      'date': 'Yesterday, 8:45 PM',
      'paymentMethod': 'UPI (GPay)',
      'status': 'DELIVERED',
    }
  ];

  List<dynamic> allFoods = [];
  List<dynamic> filteredFoods = [];
  String _selectedCategory = 'All';
  int _currentOfferPage = 0;
  bool _menuLoading = false;
  final PageController _offerPageCtrl = PageController(viewportFraction: 0.92);
  final ScrollController _deliveryScrollCtrl = ScrollController();
  bool _showStickySearch = false;
  Timer? _flashTimer;
  int _flashSecondsLeft = 3600; // 1 hour countdown

  final TextEditingController _searchCtrl = TextEditingController();
  final PageController _midBannerCtrl = PageController();
  late IO.Socket socket;
  Timer? _minuteTimer;
  Timer? _bannerTimer;

  final Set<String> _ratedOrders = {};
  bool _isRatingModalOpen = false;

  late AnimationController _cartBounceController;
  late Animation<double> _cartBounceAnim;

  Future<void> _launchDirectUpi({String? appName, required int amount}) async {
    final upiId = 'rameezkitchen@okaxis';
    final name = 'Rameez Kitchen';
    final note = 'Rameez Food Order';
    
    String uriStr;
    if (appName == 'gpay') {
      uriStr = 'tez://upi/pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amount&cu=INR&tn=${Uri.encodeComponent(note)}';
    } else if (appName == 'phonepe') {
      uriStr = 'phonepe://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amount&cu=INR&tn=${Uri.encodeComponent(note)}';
    } else if (appName == 'paytm') {
      uriStr = 'paytmmp://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amount&cu=INR&tn=${Uri.encodeComponent(note)}';
    } else {
      uriStr = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amount&cu=INR&tn=${Uri.encodeComponent(note)}';
    }

    try {
      final uri = Uri.parse(uriStr);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        final fallbackUri = Uri.parse('upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amount&cu=INR&tn=${Uri.encodeComponent(note)}');
        final fallbackLaunched = await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        if (!fallbackLaunched) {
          Clipboard.setData(ClipboardData(text: upiId));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ UPI ID copied ($upiId)! Open ${appName?.toUpperCase() ?? "your UPI app"} to pay ₹$amount.'),
                backgroundColor: const Color(0xFF0F8A65),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      }
    } catch (e) {
      Clipboard.setData(ClipboardData(text: upiId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ UPI ID copied ($upiId)! Open your UPI app to pay ₹$amount.'),
            backgroundColor: const Color(0xFF0F8A65),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _processCheckoutAndPlaceOrder({
    required String paymentMethod,
    String? upiApp,
    required int finalPayableRupees,
    required BuildContext sheetContext,
  }) async {
    final wallet = context.read<WalletProvider>();
    if (paymentMethod.contains('Wallet')) {
      if (wallet.balance < finalPayableRupees) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Insufficient Wallet Balance. Please choose UPI or Cash on Delivery.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await wallet.debit(finalPayableRupees.toDouble(), 'Food Order Payment');
    } else if (upiApp != null || paymentMethod.contains('UPI')) {
      await _launchDirectUpi(appName: upiApp, amount: finalPayableRupees);
    }

    final payload = {
      'orderId': 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      'totalAmount': finalPayableRupees,
      'savings': discountAmount,
      'paymentMethod': paymentMethod,
      'status': 'PLACED',
      'remainingMinutes': 25,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'deliveryAddress': deliveryAddress,
      'items': cartQuantities.entries.map((e) {
        final item = allFoods.firstWhere(
          (f) => f['id'] == e.key || f['id']?.toString() == e.key.toString(),
          orElse: () => {'id': e.key, 'name': 'Dish Item', 'price': 100},
        );
        return {
          'id': e.key,
          'quantity': e.value,
          'price': (item['price'] as num?)?.toInt() ?? 0,
          'name': item['name']?.toString() ?? 'Dish Item',
        };
      }).toList()
    };

    socket.emit('order:new', payload);
    try {
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      activeOrdersList.insert(0, payload);
      cartQuantities.clear();
      pendingCancellationFee = 0;
      appliedCoupon = null;
      discountAmount = 0;
      _selectedTab = 1;
      widget.onTabChanged?.call(1);
    });

    if (Navigator.canPop(sheetContext)) {
      Navigator.pop(sheetContext);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🎉 Order ${payload['orderId']} placed via $paymentMethod!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F8A65),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.currentTabIndex;
    customerName = widget.initialName.isNotEmpty ? widget.initialName : "Valued Customer";
    customerPhone = widget.initialPhone;
    customerEmail = widget.initialEmail;
    if (widget.initialAvatar.isNotEmpty) {
      customerAvatar = _sanitizeImageUrl(widget.initialAvatar, isRestaurant: false);
    }

    _cartBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _cartBounceAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _cartBounceController, curve: Curves.easeOutBack),
    );

    fetchInitialData();
    initSocketConnection();
    _requestAndEnableLiveLocation(showNotification: false);

    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_midBannerCtrl.hasClients && dynamicOffers.isNotEmpty) {
        int nextPage = (_midBannerCtrl.page?.toInt() ?? 0) + 1;
        if (nextPage >= dynamicOffers.length) {
          nextPage = 0;
          _midBannerCtrl.jumpToPage(0);
        } else {
          _midBannerCtrl.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      }
    });

    _minuteTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (activeOrdersList.isNotEmpty && mounted) {
        setState(() {
          for (var o in activeOrdersList) {
            int mins = o['remainingMinutes'] ?? 20;
            if (mins > 2) o['remainingMinutes'] = mins - 1;
          }
        });
      }
    });

    _deliveryScrollCtrl.addListener(() {
      final show = _deliveryScrollCtrl.hasClients && _deliveryScrollCtrl.offset > 140;
      if (show != _showStickySearch && mounted) {
        setState(() => _showStickySearch = show);
      }
    });

    _flashTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_flashSecondsLeft > 0 && mounted) {
        setState(() => _flashSecondsLeft--);
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentTabIndex != _selectedTab) {
      setState(() => _selectedTab = widget.currentTabIndex);
    }
    if (widget.initialName.isNotEmpty && widget.initialName != oldWidget.initialName) {
      setState(() => customerName = widget.initialName);
    }
    if (widget.initialPhone.isNotEmpty && widget.initialPhone != oldWidget.initialPhone) {
      setState(() => customerPhone = widget.initialPhone);
    }
    if (widget.initialEmail.isNotEmpty && widget.initialEmail != oldWidget.initialEmail) {
      setState(() => customerEmail = widget.initialEmail);
    }
    if (widget.initialAvatar.isNotEmpty && widget.initialAvatar != oldWidget.initialAvatar) {
      setState(() => customerAvatar = _sanitizeImageUrl(widget.initialAvatar, isRestaurant: false));
    }
  }

  Future<void> fetchInitialData() async {
    try {
      final resMenu = await http.get(Uri.parse('${ApiConstants.baseUrl}/menu'));
      final resInit = await http.get(Uri.parse('${ApiConstants.baseUrl}/merchant/init'));
      final resOffer = await http.get(Uri.parse('${ApiConstants.baseUrl}/offers'));
      final resOrders = await http.get(Uri.parse('${ApiConstants.baseUrl}/orders'));
      final profileUri = Uri.parse('${ApiConstants.baseUrl}/customer/profile').replace(
        queryParameters: customerPhone.isNotEmpty ? {'phone': customerPhone} : null,
      );
      final resProfile = await http.get(profileUri);

      if (mounted) {
        setState(() {
          if (resMenu.statusCode == 200) {
            allFoods = jsonDecode(resMenu.body);
            _applyMenuFilters();
          }
          if (resInit.statusCode == 200) {
            final data = jsonDecode(resInit.body);
            if (data['paymentSettings'] != null) paymentSettings = Map<String, dynamic>.from(data['paymentSettings']);
            if (data['branchStatus'] != null) branchStatus = Map<String, dynamic>.from(data['branchStatus']);
            if (data['branchesInfo'] != null) branchesInfo = Map<String, dynamic>.from(data['branchesInfo']);
            if (data['globalStatus'] != null) globalStatus = Map<String, dynamic>.from(data['globalStatus']);
          }
          if (resOffer.statusCode == 200) dynamicOffers = jsonDecode(resOffer.body);
          if (resOrders.statusCode == 200) {
            final List list = jsonDecode(resOrders.body);
            activeOrdersList = list
                .where((o) => o['status'] == 'PLACED' || o['status'] == 'PREPARING')
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          if (resProfile.statusCode == 200) {
            final prof = jsonDecode(resProfile.body);
            if (prof['name'] != null && prof['name'].toString().isNotEmpty && prof['name'] != 'Customer') {
              customerName = prof['name'];
            }
            if (prof['phone'] != null && prof['phone'].toString().isNotEmpty) {
              customerPhone = prof['phone'];
            }
            if (prof['email'] != null && prof['email'].toString().isNotEmpty) {
              customerEmail = prof['email'];
            }
            if (prof['avatar'] != null && prof['avatar'].toString().isNotEmpty) {
              customerAvatar = _sanitizeImageUrl(prof['avatar']?.toString(), isRestaurant: false);
            }
            if (prof['isGoldMember'] != null) {
              isGoldMember = prof['isGoldMember'] == true;
            }
            if (prof['address'] != null && prof['address'].toString().isNotEmpty) {
              deliveryAddress = prof['address'];
              final parts = deliveryAddress.split(',');
              if (parts.isNotEmpty) houseNo = parts[0].trim();
              if (parts.length > 1) streetName = parts[1].trim();
              if (parts.length > 2) areaName = parts[2].trim();
            }
          }
          _menuLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch initial data: $e');
      if (mounted) {
        setState(() => _menuLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text('Connection error. Pull to refresh.', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );
      }
    }
  }

  void initSocketConnection() {
    socket = IO.io(ApiConstants.serverBaseUrl, <String, dynamic>{'transports': ['websocket'], 'autoConnect': true});

    socket.on('kitchen:status_changed', (data) {
      if (mounted) {
        setState(() {
          if (data['branchStatus'] != null) branchStatus = Map<String, dynamic>.from(data['branchStatus']);
          if (data['branchesInfo'] != null) branchesInfo = Map<String, dynamic>.from(data['branchesInfo']);
          if (data['globalStatus'] != null) globalStatus = Map<String, dynamic>.from(data['globalStatus']);
        });
      }
    });

    socket.on('branch:updated', (data) {
      if (mounted && data is Map) {
        setState(() {
          branchesInfo = Map<String, dynamic>.from(data);
        });
      }
    });

    socket.on('menu:updated', (data) {
      if (mounted && data is List) {
        setState(() {
          allFoods = List.from(data);
          _applyMenuFilters();
        });
      }
    });

    socket.on('offers:updated', (data) {
      if (mounted) setState(() => dynamicOffers = List.from(data));
    });

    socket.on('settings:updated', (data) {
      if (mounted) setState(() => paymentSettings = Map<String, dynamic>.from(data));
    });

    socket.on('order:status_update', (data) {
      if (mounted && data is Map) {
        final incomingId = data['orderId']?.toString() ?? '';
        final rawIncoming = incomingId.replaceAll(RegExp(r'\D'), '');
        final newStatus = data['status']?.toString() ?? '';
        setState(() {
          for (var o in activeOrdersList) {
            final orderIdStr = o['orderId']?.toString() ?? '';
            final rawOrderId = orderIdStr.replaceAll(RegExp(r'\D'), '');
            if (orderIdStr == incomingId || (rawIncoming.isNotEmpty && rawOrderId == rawIncoming)) {
              o['status'] = newStatus;
              if (data['driverName'] != null) o['driverName'] = data['driverName'];
              if (data['driverPhone'] != null) o['driverPhone'] = data['driverPhone'];
              if (data['vehicleNumber'] != null) o['vehicleNumber'] = data['vehicleNumber'];
              if (data['vehicleType'] != null) o['vehicleType'] = data['vehicleType'];
              if (data['driverRating'] != null) o['driverRating'] = data['driverRating'];
              if (data['driverCode'] != null) o['driverCode'] = data['driverCode'];
              if (data['deliveryOtp'] != null) o['deliveryOtp'] = data['deliveryOtp'];
            }
          }
        });

        if (newStatus == 'DELIVERED') {
          if (!_ratedOrders.contains(incomingId) && !_isRatingModalOpen) {
            _showDriverRatingModal(
              incomingId,
              data['driverName']?.toString() ?? 'Delivery Hero',
              data['driverCode']?.toString() ?? 'DRV-1001',
            );
          }
        }
      }
    });

    socket.on('driver:location_update', (data) {
      if (mounted && data is Map) {
        final incomingId = data['orderId']?.toString() ?? '';
        final rawIncoming = incomingId.replaceAll(RegExp(r'\D'), '');
        setState(() {
          for (var o in activeOrdersList) {
            final orderIdStr = o['orderId']?.toString() ?? '';
            final rawOrderId = orderIdStr.replaceAll(RegExp(r'\D'), '');
            if (orderIdStr == incomingId || (rawIncoming.isNotEmpty && rawOrderId == rawIncoming)) {
              o['riderLat'] = data['latitude'];
              o['riderLng'] = data['longitude'];
              if (data['driverName'] != null) o['driverName'] = data['driverName'];
              if (data['phone'] != null) o['driverPhone'] = data['phone'];
              if (data['vehicleNumber'] != null) o['vehicleNumber'] = data['vehicleNumber'];
            }
          }
        });
      }
    });

    socket.on('driver:assigned', (data) {
      if (mounted && data is Map) {
        final incomingId = data['orderId']?.toString() ?? '';
        final rawIncoming = incomingId.replaceAll(RegExp(r'\D'), '');
        setState(() {
          for (var o in activeOrdersList) {
            final orderIdStr = o['orderId']?.toString() ?? '';
            final rawOrderId = orderIdStr.replaceAll(RegExp(r'\D'), '');
            if (orderIdStr == incomingId || (rawIncoming.isNotEmpty && rawOrderId == rawIncoming)) {
              if (data['driverName'] != null) o['driverName'] = data['driverName'];
              if (data['phone'] != null) o['driverPhone'] = data['phone'];
              if (data['vehicleNumber'] != null) o['vehicleNumber'] = data['vehicleNumber'];
            }
          }
        });
      }
    });

    socket.on('driver:eta_update', (data) {
      if (mounted && data is Map) {
        final incomingId = data['orderId']?.toString() ?? '';
        final rawIncoming = incomingId.replaceAll(RegExp(r'\D'), '');
        final mins = data['remainingMinutes'];
        if (mins != null) {
          setState(() {
            for (var o in activeOrdersList) {
              final orderIdStr = o['orderId']?.toString() ?? '';
              final rawOrderId = orderIdStr.replaceAll(RegExp(r'\D'), '');
              if (orderIdStr == incomingId || (rawIncoming.isNotEmpty && rawOrderId == rawIncoming)) {
                o['remainingMinutes'] = mins;
              }
            }
          });
        }
      }
    });
  }

  int get totalCartItemsCount => cartQuantities.values.fold(0, (s, q) => s + q);

  int get subtotalRupees => cartQuantities.entries.fold(0, (sum, e) {
        final item = allFoods.firstWhere((f) => f['id'] == e.key || f['id']?.toString() == e.key.toString(), orElse: () => {'price': 0});
        return sum + ((item['price'] as num?)?.toInt() ?? 0) * e.value;
      });

  int get calculatedTax => (subtotalRupees * (((paymentSettings['taxPercent'] as num?) ?? 5) / 100)).round();

  int get serviceCharge => isGoldMember ? 0 : (((paymentSettings['serviceCharge'] as num?)?.toInt()) ?? 15);

  int get finalPayableRupees => (subtotalRupees + calculatedTax + serviceCharge + pendingCancellationFee - discountAmount).clamp(0, 99999);

  Future<void> _syncProfileWithServer() async {
    try {
      try {
        context.read<AuthProvider>().updateProfile(
          name: customerName,
          phone: customerPhone,
          email: customerEmail,
          avatar: customerAvatar,
          address: deliveryAddress,
        );
      } catch (_) {}
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/customer/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': customerName,
          'phone': customerPhone,
          'email': customerEmail,
          'avatar': customerAvatar,
          'address': deliveryAddress, // Saving to Database automatically
          'isGoldMember': isGoldMember,
        }),
      );
    } catch (e) {
      debugPrint('Profile sync failed: $e');
    }
  }

  Future<void> _requestAndEnableLiveLocation({bool showNotification = false}) async {
    try {
      if (showNotification && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('Fetching your precise live location... 🛰️'),
              ],
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFFFF5200),
          ),
        );
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (showNotification && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable GPS / Location services on your device to share address.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (showNotification && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission was denied. Please allow location access to auto-fill your address.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (showNotification && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied. Please allow in browser / app settings.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final lat = position.latitude;
      final lng = position.longitude;

      String capturedHouse = 'Flat/Door';
      String capturedStreet = 'Near GPS ($lat, $lng)';
      String capturedArea = 'Davanagere';
      String locText = 'Live GPS: $lat, $lng';

      // Capture real address via OpenStreetMap Nominatim reverse geocoding
      try {
        final geoUrl = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1');
        final res = await http.get(geoUrl, headers: {
          'Accept': 'application/json',
          'User-Agent': 'RameezKitchenCustomerApp/1.0',
        }).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map && data['address'] is Map) {
            final addr = data['address'] as Map;
            final house = addr['house_number'] ?? addr['building'] ?? addr['commercial'] ?? 'Door No';
            final street = addr['road'] ?? addr['residential'] ?? addr['neighbourhood'] ?? addr['suburb'] ?? 'Main Road';
            final area = addr['suburb'] ?? addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? 'Davanagere';
            final postcode = addr['postcode'] != null ? ' - ${addr['postcode']}' : '';

            capturedHouse = house.toString();
            capturedStreet = street.toString();
            capturedArea = '$area$postcode';
            locText = '$capturedHouse, $capturedStreet, $capturedArea';
          }
        }
      } catch (geoErr) {
        debugPrint('[GEOCODE ERROR] $geoErr');
        if ((lat >= 14.3 && lat <= 14.6) && (lng >= 75.8 && lng <= 76.1)) {
          capturedHouse = '104P/P-78';
          capturedStreet = '60 Feet Ring Road';
          capturedArea = 'Davanagere';
          locText = 'Near 60 Feet Ring Road, Davanagere';
        } else {
          capturedHouse = 'My Location';
          capturedStreet = 'Lat: ${lat.toStringAsFixed(4)}';
          capturedArea = 'Lng: ${lng.toStringAsFixed(4)}';
          locText = 'GPS (${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)})';
        }
      }

      if (mounted) {
        setState(() {
          houseNo = capturedHouse;
          streetName = capturedStreet;
          areaName = capturedArea;
          deliveryAddress = locText;
        });

        _syncProfileWithServer();

        if (showNotification) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Live address captured: $locText 📍',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF0F8A65),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[LOCATION] Error enabling live location: $e');
      if (showNotification && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not fetch location: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _openAddressModal() {
    final h = TextEditingController(text: houseNo);
    final s = TextEditingController(text: streetName);
    final a = TextEditingController(text: areaName);
    final formKey = GlobalKey<FormState>();
    bool showManualForm = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.location_on_rounded, color: Color(0xFFFF5200), size: 26),
                    ),
                    const SizedBox(width: 16),
                    const Text('Delivery Address', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 24),

                if (!showManualForm) ...[
                  // Option 1: Live Location
                  InkWell(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context); // close bottom sheet
                      await _requestAndEnableLiveLocation(showNotification: true);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green.shade300, width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.green.withValues(alpha: 0.05),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                            child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Enable Live Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.green)),
                                SizedBox(height: 4),
                                Text('Automatically fetch & save your current location', style: TextStyle(fontSize: 13, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Option 2: Add Manually
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setModalState(() => showManualForm = true);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                            child: const Icon(Icons.edit_location_alt_outlined, color: Colors.black87, size: 20),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Add Address Manually', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87)),
                                SizedBox(height: 4),
                                Text('Type in your exact house/flat and street', style: TextStyle(fontSize: 13, color: Colors.grey)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Manual Entry Form
                  Form(
                    key: formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: h,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          decoration: InputDecoration(
                            labelText: 'Flat / House No',
                            prefixIcon: const Icon(Icons.home_outlined, color: Color(0xFFFF5200)),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FA),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF5200), width: 2)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: s,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          decoration: InputDecoration(
                            labelText: 'Street Name',
                            prefixIcon: const Icon(Icons.signpost_outlined, color: Color(0xFFFF5200)),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FA),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF5200), width: 2)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: a,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          decoration: InputDecoration(
                            labelText: 'Area / Landmark',
                            prefixIcon: const Icon(Icons.place_outlined, color: Color(0xFFFF5200)),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FA),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF5200), width: 2)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(colors: [Color(0xFFFF5200), Color(0xFFFF7A00)]),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFFFF5200).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6)),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                            label: const Text('SAVE CHANGES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
                            onPressed: () {
                              if (!formKey.currentState!.validate()) return;
                              HapticFeedback.lightImpact();
                              setState(() {
                                houseNo = h.text.trim();
                                streetName = s.text.trim();
                                areaName = a.text.trim();
                                deliveryAddress = "$houseNo, $streetName, $areaName";
                              });
                              
                              _syncProfileWithServer(); // Save to Database Automatically
                              
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Address successfully saved! 📍'), backgroundColor: Colors.green),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showOffersPicker(Function(String, int) onApply, [BuildContext? callerContext]) {
    final effectiveContext = callerContext ?? context;
    final List<Map<String, dynamic>> offersList = dynamicOffers.isNotEmpty
        ? dynamicOffers.map((o) => Map<String, dynamic>.from(o as Map)).toList()
        : [
            {'code': 'RAMEEZ50', 'discount': 50, 'description': 'Flat ₹50 OFF on Charcoal Biryani!'},
            {'code': 'GOLD20', 'discount': 20, 'description': 'Special ₹20 discount on all orders'},
            {'code': 'WELCOME30', 'discount': 30, 'description': 'Welcome ₹30 OFF on your meal'},
            {'code': 'FESTIVE100', 'discount': 100, 'description': 'Mega ₹100 OFF on orders above ₹499'},
          ];

    showModalBottomSheet(
      context: effectiveContext,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 580,
              maxHeight: MediaQuery.of(effectiveContext).size.height * 0.85,
            ),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.local_offer_rounded, color: Color(0xFFFF5200), size: 22),
                    SizedBox(width: 8),
                    Text('Available Offers & Coupons', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: offersList.map((o) {
                          final code = o['code']?.toString() ?? 'OFFER';
                          final disc = (o['discount'] as num?)?.toInt() ?? 20;
                          final desc = o['description']?.toString() ?? 'Special discount';
                          final isThisApplied = appliedCoupon == code;

                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isThisApplied ? const Color(0xFFFF5200) : (isDarkMode ? Colors.white12 : Colors.grey.shade300),
                                width: isThisApplied ? 2 : 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  if (isThisApplied) {
                                    onApply('', 0);
                                  } else {
                                    onApply(code, disc);
                                  }
                                  Navigator.of(dialogCtx).pop();
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF5200).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(Icons.confirmation_number_outlined, color: Color(0xFFFF5200), size: 24),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    code,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.8),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    'SAVE ₹$disc',
                                                    style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w900),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              desc,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
                                                fontSize: 12,
                                                height: 1.25,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        height: 36,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isThisApplied ? Colors.green : const Color(0xFFFF5200),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                          ),
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            if (isThisApplied) {
                                              onApply('', 0);
                                            } else {
                                              onApply(code, disc);
                                            }
                                            Navigator.of(dialogCtx).pop();
                                          },
                                          child: Text(
                                            isThisApplied ? 'APPLIED' : 'APPLY',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => Theme(
          data: isDarkMode ? ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
          ) : ThemeData.light(),
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Checkout (${totalCartItemsCount} items)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  ...cartQuantities.entries.map((e) {
                    final food = allFoods.firstWhere((f) => f['id'] == e.key || f['id']?.toString() == e.key.toString(), orElse: () => {'name': 'Item', 'price': 0});
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${food['name']} x ${e.value}'),
                          Text('₹${((food['price'] as num?) ?? 0) * e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // Coupon / Offer Row (Interactive Picker)
                  InkWell(
                    onTap: () {
                      _showOffersPicker((code, disc) {
                        if (code.isEmpty) {
                          setSheet(() { appliedCoupon = null; discountAmount = 0; });
                          setState(() { appliedCoupon = null; discountAmount = 0; });
                        } else {
                          setSheet(() { appliedCoupon = code; discountAmount = disc; });
                          setState(() { appliedCoupon = code; discountAmount = disc; });
                        }
                      }, context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: appliedCoupon != null
                            ? Colors.green.withValues(alpha: 0.08)
                            : (isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFFFF4EE)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: appliedCoupon != null ? Colors.green.shade300 : const Color(0xFFFF5200).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  appliedCoupon != null ? Icons.check_circle_rounded : Icons.local_offer_rounded,
                                  color: appliedCoupon != null ? Colors.green : const Color(0xFFFF5200),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    appliedCoupon == null ? 'Apply Coupon & Save' : 'Applied: $appliedCoupon (-₹$discountAmount)',
                                    style: TextStyle(
                                      color: appliedCoupon != null ? Colors.green.shade800 : const Color(0xFFFF5200),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (appliedCoupon != null)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.cancel, color: Colors.grey, size: 18),
                                  onPressed: () {
                                    setSheet(() { appliedCoupon = null; discountAmount = 0; });
                                    setState(() { appliedCoupon = null; discountAmount = 0; });
                                  },
                                ),
                              const SizedBox(width: 6),
                              Text(
                                appliedCoupon == null ? 'SELECT >' : 'CHANGE',
                                style: const TextStyle(color: Color(0xFFFF5200), fontWeight: FontWeight.w900, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  // Bill Details Summary Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDarkMode ? Colors.white12 : Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Item Subtotal', style: TextStyle(color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700, fontSize: 13)),
                            Text('₹$subtotalRupees', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('GST & Taxes (${paymentSettings['taxPercent']}%)', style: TextStyle(color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700, fontSize: 13)),
                            Text('₹$calculatedTax', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text('Packaging & Delivery', style: TextStyle(color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700, fontSize: 13)),
                                if (isGoldMember) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('GOLD', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 9)),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              isGoldMember ? 'FREE' : '₹$serviceCharge',
                              style: TextStyle(
                                color: isGoldMember ? Colors.green : (isDarkMode ? Colors.white : Colors.black87),
                                fontWeight: isGoldMember ? FontWeight.w900 : FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        if (discountAmount > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Coupon Discount', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('-₹$discountAmount', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 13)),
                            ],
                          ),
                        ],
                        if (pendingCancellationFee > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.receipt_long_outlined, color: Colors.deepOrange, size: 14),
                                  SizedBox(width: 4),
                                  Text('Previous Cancellation Charge', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                              Text('₹$pendingCancellationFee', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w900, fontSize: 13)),
                            ],
                          ),
                        ],
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('To Pay Total:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            Text('₹$finalPayableRupees', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFFF5200))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const SizedBox(height: 20),

                  // Single prominent PLACE ORDER button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5200),
                        elevation: 3,
                        shadowColor: const Color(0xFFFF5200).withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 22),
                      label: Text(
                        'PLACE ORDER • ₹$finalPayableRupees',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showPaymentMethodPicker(
                          finalPayableRupees: finalPayableRupees,
                          appliedCoupon: appliedCoupon,
                          discountAmount: discountAmount,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPaymentMethodPicker({
    required int finalPayableRupees,
    String? appliedCoupon,
    int discountAmount = 0,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (pCtx) {
        final isDarkMode = Theme.of(pCtx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.payment_rounded, color: Color(0xFFFF5200), size: 24),
                      SizedBox(width: 8),
                      Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('₹$finalPayableRupees', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFFFF5200))),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how you would like to pay to confirm your order',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 18),

              // Option 1: Google Pay (GPay)
              _buildPaymentOptionTile(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Google Pay (GPay)',
                subtitle: 'Instant 1-Tap UPI Pay & Confirm Order',
                badgeText: '₹$finalPayableRupees >',
                onTap: () {
                  Navigator.pop(pCtx);
                  _processCheckoutAndPlaceOrder(
                    paymentMethod: 'UPI (Google Pay)',
                    upiApp: 'gpay',
                    finalPayableRupees: finalPayableRupees,
                    sheetContext: context,
                  );
                },
              ),

              // Option 2: PhonePe UPI
              _buildPaymentOptionTile(
                icon: Icons.payment_rounded,
                title: 'PhonePe UPI',
                subtitle: 'Instant 1-Tap UPI Pay & Confirm Order',
                badgeText: '₹$finalPayableRupees >',
                onTap: () {
                  Navigator.pop(pCtx);
                  _processCheckoutAndPlaceOrder(
                    paymentMethod: 'UPI (PhonePe)',
                    upiApp: 'phonepe',
                    finalPayableRupees: finalPayableRupees,
                    sheetContext: context,
                  );
                },
              ),

              // Option 3: Rameez Digital Wallet
              Builder(
                builder: (wCtx) {
                  final walletBal = wCtx.watch<WalletProvider>().balance;
                  final hasFunds = walletBal >= finalPayableRupees;
                  return _buildPaymentOptionTile(
                    icon: Icons.wallet_rounded,
                    title: 'Rameez Digital Wallet',
                    subtitle: hasFunds
                        ? 'Balance: ₹${walletBal.toInt()} • Instant Pay'
                        : 'Available: ₹${walletBal.toInt()} (Insufficient funds)',
                    badgeText: hasFunds ? '₹$finalPayableRupees >' : 'LOW BAL',
                    isEnabled: hasFunds,
                    onTap: hasFunds
                        ? () {
                            Navigator.pop(pCtx);
                            _processCheckoutAndPlaceOrder(
                              paymentMethod: 'Rameez Digital Wallet',
                              finalPayableRupees: finalPayableRupees,
                              sheetContext: context,
                            );
                          }
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Insufficient wallet balance. Please top up or choose UPI/Cash.')),
                            );
                          },
                  );
                },
              ),

              // Option 4: Cash on Delivery (COD)
              _buildPaymentOptionTile(
                icon: Icons.handshake_rounded,
                title: 'Cash on Delivery (COD)',
                subtitle: 'Pay cash or scan driver QR at doorstep',
                badgeText: 'CONFIRM >',
                onTap: () {
                  Navigator.pop(pCtx);
                  _processCheckoutAndPlaceOrder(
                    paymentMethod: 'Cash on Delivery (COD)',
                    finalPayableRupees: finalPayableRupees,
                    sheetContext: context,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String badgeText,
    required VoidCallback onTap,
    bool isEnabled = true,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    const brandOrange = Color(0xFFFF5200);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2A2A2E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDarkMode ? const Color(0xFF38383E) : const Color(0xFFE5E7EB),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: brandOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: brandOrange, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isEnabled ? brandOrange : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAvatarEditor() {
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
                Icon(Icons.add_a_photo_rounded, color: Color(0xFFFF5200), size: 24),
                SizedBox(width: 8),
                Text(
                  'Change Profile Picture',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Upload directly from your device camera, gallery, or choose a culinary avatar.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 18),

            // Option 1: Direct Camera Upload
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Colors.orange.shade50,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.camera_alt_rounded, color: Color(0xFFFF5200)),
              ),
              title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: const Text('Use device camera directly', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                _uploadAvatarFromDevice(captureMode: 'camera');
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
                _uploadAvatarFromDevice(captureMode: null);
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

  void _uploadAvatarFromDevice({String? captureMode}) {
    UniversalImagePicker.pickImage(
      captureMode: captureMode,
      onSelected: (imageUrl, fileName) {
        final safeUrl = _sanitizeImageUrl(imageUrl, isRestaurant: false);
        setState(() => customerAvatar = safeUrl);
        try {
          context.read<AuthProvider>().updateProfile(avatar: safeUrl);
        } catch (_) {}
        _syncProfileWithServer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('✓ Profile picture updated successfully ($fileName)!'),
          ),
        );
      },
    );
  }

  void _openPresetAvatarsSheet() {
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
            const Text('Choose Your Avatar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
                    final safeUrl = item['url']!;
                    setState(() => customerAvatar = safeUrl);
                    try {
                      context.read<AuthProvider>().updateProfile(avatar: safeUrl);
                    } catch (_) {}
                    _syncProfileWithServer();
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
    final ctrl = TextEditingController(text: customerAvatar);
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
              backgroundColor: const Color(0xFFFF5200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                final safeUrl = _sanitizeImageUrl(val, isRestaurant: false);
                setState(() => customerAvatar = safeUrl);
                try {
                  context.read<AuthProvider>().updateProfile(avatar: safeUrl);
                } catch (_) {}
                _syncProfileWithServer();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openAccountEditor() {
    final nameCtrl = TextEditingController(text: customerName);
    final phoneCtrl = TextEditingController(text: customerPhone);
    final emailCtrl = TextEditingController(text: customerEmail);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Account Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
              const SizedBox(height: 8),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Address')),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text('Delete Account', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Confirm Deletion?'),
                      content: const Text('This will delete your address, orders history, and rewards. This action is irreversible.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const CustomerLoginScreen()),
                            );
                          },
                          child: const Text('Confirm Delete', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5200)),
            onPressed: () {
              setState(() {
                customerName = nameCtrl.text.trim();
                customerPhone = phoneCtrl.text.trim();
                customerEmail = emailCtrl.text.trim();
              });
              _syncProfileWithServer();
              Navigator.pop(context);
            },
            child: const Text('Save Details', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openPaymentMethodsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Manage Payment Methods', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              ...savedPaymentMethods.map((pm) => ListTile(
                    leading: Icon(pm.contains('Card') ? Icons.credit_card : pm.contains('UPI') ? Icons.qr_code_2 : Icons.money, color: const Color(0xFFFF5200)),
                    title: Text(pm),
                    trailing: const Icon(Icons.check, color: Colors.green),
                  )),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5200)),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Add Debit / Credit Card or UPI ID', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.pop(context);
                  final cardCtrl = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Add New Payment Method'),
                      content: TextField(controller: cardCtrl, decoration: const InputDecoration(labelText: 'Card (XXXX-XXXX) or UPI ID')),
                      actions: [
                        ElevatedButton(
                          onPressed: () {
                            if (cardCtrl.text.isNotEmpty) {
                              setState(() => savedPaymentMethods.insert(0, cardCtrl.text.trim()));
                            }
                            Navigator.pop(context);
                          },
                          child: const Text('Add'),
                        )
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPastOrdersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Past Delivered Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView(
                children: pastOrdersList.map((po) {
                  return Card(
                    child: ListTile(
                      title: Text('${po['orderId']} • ₹${po['totalAmount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${po['date']} • ${po['paymentMethod']}'),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5200)),
                        onPressed: () {
                          setState(() {
                            cartQuantities[1] = 1;
                            _selectedTab = 0;
                            widget.onTabChanged?.call(0);
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Re-order', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFeedbackModal() {
    int rating = 5;
    final commentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setFState) => AlertDialog(
          title: const Text('Send Feedback to Restaurant'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) => IconButton(
                  icon: Icon(index < rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 28),
                  onPressed: () => setFState(() => rating = index + 1),
                )),
              ),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Write your thoughts on food, taste & speed...', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5200)),
              onPressed: () async {
                await http.post(
                  Uri.parse('${ApiConstants.baseUrl}/feedback'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'customerName': customerName,
                    'customerPhone': customerPhone,
                    'rating': rating,
                    'comment': commentCtrl.text.trim(),
                  }),
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(backgroundColor: Colors.green, content: Text('✓ Thank you! Review submitted to restaurant manager.')),
                );
              },
              child: const Text('Submit Review', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  Widget _dynamicOfferBannerCard(Map<String, dynamic> offer) {
    final code = offer['code'] ?? 'SPECIAL';
    final desc = offer['description'] ?? 'Limited time deal!';
    final discount = offer['discount'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5200), Color(0xFFFF7A00), Color(0xFFFF9E00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5200).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'USE CODE: $code',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Flat ₹$discount OFF on your order',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFFF5200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () {
              setState(() {
                appliedCoupon = code;
                discountAmount = (discount as num).toInt();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text('✓ Applied coupon $code (-₹$discount)'),
                ),
              );
            },
            child: Text(
              appliedCoupon == code ? 'APPLIED' : 'APPLY',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _branchCard(String title, String img, {String? tagline, bool isOpen = true}) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        image: DecorationImage(
          image: NetworkImage(img),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: isOpen ? 0.45 : 0.75), BlendMode.darken),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isOpen ? const Color(0xFF0F8A65) : Colors.red.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isOpen ? 'OPEN' : 'CLOSED',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
              const Icon(Icons.storefront_rounded, color: Colors.white70, size: 16),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.2)),
              if (tagline != null && tagline.isNotEmpty)
                Text(tagline, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            ],
          ),
        ],
      ),
    );
  }

  Widget _foodCard(Map<String, dynamic> item) {
    final qty = cartQuantities[item['id']] ?? 0;
    final isVeg = item['isVeg'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2A2A2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                _sanitizeImageUrl(item['image']?.toString(), isRestaurant: false),
                width: 80, height: 80, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.restaurant_rounded, color: Color(0xFFFF5200), size: 32),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 16, height: 16,
                        decoration: BoxDecoration(
                          border: Border.all(color: isVeg ? Colors.green : Colors.red, width: 1.5),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Center(child: Icon(Icons.circle, size: 8, color: isVeg ? Colors.green : Colors.red)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (item['flavor'] != null && item['flavor'].toString().isNotEmpty)
                    Text(item['flavor'], style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('₹${item['price']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF1E1E22))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            qty == 0
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [Color(0xFFFF5200), Color(0xFFFF7A00)]),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFFF5200).withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => cartQuantities[item['id']] = 1);
                          _cartBounceController.forward().then((_) => _cartBounceController.reverse());
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: Text('ADD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5)),
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5200).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFF5200).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (qty > 1) {
                                cartQuantities[item['id']] = qty - 1;
                              } else {
                                cartQuantities.remove(item['id']);
                              }
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.remove_rounded, color: Color(0xFFFF5200), size: 20),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFFF5200))),
                        ),
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => cartQuantities[item['id']] = qty + 1);
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.add_rounded, color: Color(0xFFFF5200), size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // The categories come from the menu. Older menu records without a category
  // are grouped by their names, so the screen works with the existing API.
  String _categoryFor(dynamic food) {
    if (food is! Map) return 'Other';
    final category = food['category']?.toString().trim() ?? '';
    if (category.isNotEmpty) return category;
    final name = (food['name'] ?? '').toString().toLowerCase();
    if (name.contains('biryani')) return 'Biryani';
    if (name.contains('roll') || name.contains('wrap')) return 'Rolls';
    if (name.contains('starter') || name.contains('kebab') || name.contains('tikka')) return 'Starters';
    if (name.contains('drink') || name.contains('juice')) return 'Drinks';
    return 'Other';
  }

  List<String> get _menuCategories => [
        'All',
        ...allFoods.whereType<Map>().map(_categoryFor).toSet(),
      ];

  void _applyMenuFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (_selectedCategory != 'All' && !_menuCategories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }
    filteredFoods = allFoods.where((food) {
      if (food is! Map) return false;
      final matchesCategory = _selectedCategory == 'All' || _categoryFor(food) == _selectedCategory;
      final matchesSearch = (food['name'] ?? '').toString().toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  Widget _featuredFoodCard(Map<String, dynamic> item) {
    final id = item['id'];
    final quantity = id is int ? (cartQuantities[id] ?? 0) : 0;
    final rawImage = _sanitizeImageUrl(item['image']?.toString(), isRestaurant: false);
    final imageUri = Uri.tryParse(rawImage);
    final safeImage = imageUri != null &&
        (imageUri.scheme == 'https' || imageUri.scheme == 'http') && imageUri.host.isNotEmpty && imageUri.userInfo.isEmpty;
    final canOrder = globalStatus['state'] != 'PAUSED' && id is int;

    return Container(
      width: 210,
      margin: const EdgeInsets.only(right: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2A2A2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 100,
            width: double.infinity,
            child: safeImage
                ? Image.network(rawImage, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.restaurant, color: Color(0xFFFF5200), size: 36)))
                : const Center(child: Icon(Icons.restaurant, color: Color(0xFFFF5200), size: 36)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((item['name'] ?? 'Dish').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(child: Text('₹${item['price'] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                    SizedBox(
                      height: 32,
                      child: FilledButton(
                        onPressed: canOrder ? () {
                          HapticFeedback.lightImpact();
                          setState(() => cartQuantities[id] = quantity + 1);
                          _cartBounceController.forward().then((_) {
                            if (mounted) _cartBounceController.reverse();
                          });
                        } : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5200),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 32),
                        ),
                        child: Text(quantity == 0 ? 'ADD' : 'ADD +1', style: const TextStyle(fontSize: 11)),
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
  }

  // 1. DELIVERY TAB (Full Zomato-Level Delivery Tab)
  Widget _buildDeliveryTab() {
    final categories = _menuCategories;
    final filtered = filteredFoods.whereType<Map<String, dynamic>>().where((f) => f['available'] != false).toList();

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121214) : const Color(0xFFF8F8F8),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _deliveryScrollCtrl,
            slivers: [
              // ── Hero Restaurant Banner ──
              SliverToBoxAdapter(child: _buildHeroBanner()),

              // ── Address + Search Row ──
              SliverToBoxAdapter(child: _buildAddressSearchRow()),

              // ── Flash Sale Countdown ──
              if (_flashSecondsLeft > 0)
                SliverToBoxAdapter(child: _buildFlashBanner()),

              // ── "What's on your mind?" Quick Category Icons ──
              SliverToBoxAdapter(child: _buildMindSection()),

              // ── Offer Banner Carousel ──
              if (dynamicOffers.isNotEmpty)
                SliverToBoxAdapter(child: _buildOfferCarousel()),

              // ── Reorder Section ──
              if (pastOrdersList.isNotEmpty)
                SliverToBoxAdapter(child: _buildReorderSection()),

              // ── Featured Dishes (Horizontal Scroll) ──
              if (filtered.isNotEmpty)
                SliverToBoxAdapter(child: _buildFeaturedHorizontal(filtered.take(5).toList())),

              // ── Category Chips ──
              SliverPersistentHeader(
                pinned: true,
                delegate: _CategoryHeaderDelegate(
                  categories: categories,
                  selected: _selectedCategory,
                  isDarkMode: isDarkMode,
                  onSelect: (cat) {
                    setState(() {
                      _selectedCategory = cat;
                      _applyMenuFilters();
                    });
                  },
                ),
              ),

              // ── Section Header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedCategory == 'All' ? 'Full Menu' : _selectedCategory,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text('${filtered.length} items',
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              ),

              // ── Menu List ──
              _menuLoading
                  ? SliverToBoxAdapter(child: _buildSkeleton())
                  : filtered.isEmpty
                      ? SliverToBoxAdapter(child: _buildEmptyState())
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _buildFoodCard(filtered[i]),
                            childCount: filtered.length,
                          ),
                        ),

              // ── Branch Cards ──
              SliverToBoxAdapter(child: _buildBranchSection()),

              // ── Bottom Padding for Cart Bar ──
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),

          // ── Sticky Search (appears after scroll) ──
          if (_showStickySearch)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildStickySearchBar(),
            ),

          // ── Floating Cart Button ──
          if (totalCartItemsCount > 0)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildFloatingCartBar(),
            ),
        ],
      ),
    );
  }

  // ── Hero Restaurant Banner ────────────────────────────────────────────────────
  Widget _buildHeroBanner() {
    final isOpen = globalStatus['state'] != 'PAUSED';
    return Stack(
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: Image.network(
            'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 220,
              color: const Color(0xFF1A1A1A),
              child: const Center(child: Icon(Icons.restaurant, color: Colors.white38, size: 60)),
            ),
          ),
        ),
        Container(
          height: 220,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Color(0xCC000000)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.3, 1.0],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOpen ? const Color(0xFF4CAF50) : Colors.red.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isOpen ? 'OPEN NOW' : 'PAUSED',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('⚡ FASTEST', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Rameez Kitchen',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Authentic Davanagere Dum Biryani & Charcoal Rolls',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _infoPill(Icons.star_rounded, '4.8', Colors.amber),
                    const SizedBox(width: 8),
                    _infoPill(Icons.timer_outlined, '25–35 min', Colors.white),
                    const SizedBox(width: 8),
                    _infoPill(Icons.delivery_dining_outlined, isGoldMember ? 'Free for Gold' : 'Fast Delivery', const Color(0xFFFF5200)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Address + Search Row ──────────────────────────────────────────────────────
  Widget _buildAddressSearchRow() {
    return Container(
      color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          GestureDetector(
            onTap: _openAddressModal,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on, color: Color(0xFFFF5200), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Deliver to', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
                      Text(
                        deliveryAddress.isNotEmpty ? deliveryAddress : 'Select delivery location',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, color: Color(0xFFFF5200)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: (q) {
              setState(_applyMenuFilters);
            },
            decoration: InputDecoration(
              hintText: 'Search for biryani, rolls, starters...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFFF5200), size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(_applyMenuFilters);
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFF5F5F5),
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Flash Sale Countdown ──────────────────────────────────────────────────────
  Widget _buildFlashBanner() {
    final h = (_flashSecondsLeft ~/ 3600);
    final m = ((_flashSecondsLeft % 3600) ~/ 60);
    final s = (_flashSecondsLeft % 60);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('⚡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Flash Sale — Ends in', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text('FLAT ₹50 OFF on orders above ₹199',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
          Row(
            children: [
              _countdownBox(h.toString().padLeft(2, '0')),
              const Text(':', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              _countdownBox(m.toString().padLeft(2, '0')),
              const Text(':', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              _countdownBox(s.toString().padLeft(2, '0')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countdownBox(String val) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
    );
  }

  // ── "What's on your mind?" Quick Icons ───────────────────────────────────────
  Widget _buildMindSection() {
    final items = [
      {'icon': '🍚', 'label': 'Biryani'},
      {'icon': '🌯', 'label': 'Rolls'},
      {'icon': '🍗', 'label': 'Starters'},
      {'icon': '🥤', 'label': 'Drinks'},
      {'icon': '🍛', 'label': 'All'},
    ];

    return Container(
      color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("What's on your mind?",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: isDarkMode ? Colors.white : Colors.black87)),
          const SizedBox(height: 14),
          SizedBox(
            height: 85,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                final isSelected = _selectedCategory == item['label'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCategory = item['label']!;
                      _applyMenuFilters();
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFF5200) : (isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFFFF3EE)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? const Color(0xFFFF5200) : const Color(0xFFFFD6C2)),
                          ),
                          child: Center(
                            child: Text(item['icon']!, style: const TextStyle(fontSize: 26)),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item['label']!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? const Color(0xFFFF5200) : (isDarkMode ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Offer Carousel ────────────────────────────────────────────────────────────
  Widget _buildOfferCarousel() {
    final sampleOffers = dynamicOffers.isNotEmpty
        ? dynamicOffers
        : [
            {'code': 'RAMEEZ50', 'description': 'Flat ₹50 OFF on Charcoal Biryani!', 'discount': 50, 'color1': 0xFFFF5200, 'color2': 0xFFFF8C00},
            {'code': 'NEWUSER', 'description': '60% OFF up to ₹120 on first order', 'discount': 120, 'color1': 0xFF6C3483, 'color2': 0xFF9B59B6},
            {'code': 'FREEROLL', 'description': 'Buy 2 Biryanis, Get 1 Roll FREE', 'discount': 140, 'color1': 0xFF1A5276, 'color2': 0xFF2E86C1},
          ];

    return Container(
      color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Offers for you',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: isDarkMode ? Colors.white : Colors.black87)),
                GestureDetector(
                  onTap: () {
                    _showOffersPicker((code, disc) {
                      setState(() {
                        appliedCoupon = code;
                        discountAmount = disc;
                      });
                    });
                  },
                  child: const Text('See all', style: TextStyle(color: Color(0xFFFF5200), fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: PageView.builder(
              controller: _offerPageCtrl,
              itemCount: sampleOffers.length,
              onPageChanged: (i) {
                setState(() => _currentOfferPage = i);
              },
              itemBuilder: (ctx, i) {
                final o = sampleOffers[i];
                final c1 = o['color1'] != null ? Color(o['color1'] as int) : const Color(0xFFFF5200);
                final c2 = o['color2'] != null ? Color(o['color2'] as int) : const Color(0xFFFF8C00);
                final code = o['code']?.toString() ?? 'OFFER';
                final desc = o['description']?.toString() ?? 'Special discount for you';
                final discount = (o['discount'] as num?)?.toInt() ?? 50;

                return Container(
                  margin: const EdgeInsets.only(right: 10, left: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [c1, c2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text('USE: $code',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                              ),
                              const SizedBox(height: 6),
                              Text(desc,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, height: 1.3)),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFFF5200),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              appliedCoupon = code;
                              discountAmount = discount;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Coupon $code applied! ₹$discount OFF'),
                                backgroundColor: const Color(0xFF0F8A65),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: const Text('APPLY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(sampleOffers.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _currentOfferPage ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _currentOfferPage ? const Color(0xFFFF5200) : (isDarkMode ? Colors.white24 : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
          ),
        ],
      ),
    );
  }

  // ── Reorder Section ───────────────────────────────────────────────────────────
  Widget _buildReorderSection() {
    return Container(
      color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order again',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: isDarkMode ? Colors.white : Colors.black87)),
                GestureDetector(
                  onTap: _openPastOrdersModal,
                  child: const Text('See history', style: TextStyle(color: Color(0xFFFF5200), fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 135,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _reorderCard('Chicken Dum Biryani', '₹220', Icons.rice_bowl_outlined, 1),
                _reorderCard('Chicken Tikka Roll', '₹140', Icons.lunch_dining_outlined, 2),
                _reorderCard('Mutton Dum Biryani', '₹280', Icons.rice_bowl_outlined, 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reorderCard(String name, String price, IconData icon, int fallbackId) {
    return Container(
      width: 145,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDarkMode ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFF5200).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFFF5200), size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: isDarkMode ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(price, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    cartQuantities[fallbackId] = (cartQuantities[fallbackId] ?? 0) + 1;
                  });
                  _cartBounceController.forward().then((_) {
                    if (mounted) _cartBounceController.reverse();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added $name to cart!'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('↺', style: TextStyle(color: Color(0xFFFF5200), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Featured Dishes Horizontal Scroll ────────────────────────────────────────
  Widget _buildFeaturedHorizontal(List<dynamic> items) {
    return Container(
      color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Featured dishes',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: isDarkMode ? Colors.white : Colors.black87)),
          const SizedBox(height: 4),
          const Text('Fresh picks from the kitchen', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(
            height: 215,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                final id = item['id'];
                final qty = id is int ? (cartQuantities[id] ?? 0) : 0;
                final bool isBestseller = item['bestseller'] ?? (i == 0);
                return _featuredCard(item, qty, isBestseller);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _featuredCard(Map<String, dynamic> item, int qty, bool isBestseller) {
    final id = item['id'];
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2A2A2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDarkMode ? Colors.white12 : Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.network(
                  item['image'] ?? '',
                  height: 115,
                  width: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 115,
                    width: 160,
                    color: const Color(0xFFFFF3EE),
                    child: const Icon(Icons.fastfood, color: Color(0xFFFFCBAA), size: 40),
                  ),
                ),
              ),
              if (isBestseller)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5200),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text('⭐ TOP PICK',
                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: isDarkMode ? Colors.white : Colors.black87)),
                const SizedBox(height: 2),
                Text(item['flavor'] ?? item['category'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('₹${item['price']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A))),
                    qty == 0
                        ? GestureDetector(
                            onTap: id is int
                                ? () {
                                    HapticFeedback.lightImpact();
                                    setState(() => cartQuantities[id] = 1);
                                    _cartBounceController.forward().then((_) {
                                      if (mounted) _cartBounceController.reverse();
                                    });
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFFF5200), width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('ADD',
                                  style: TextStyle(color: Color(0xFFFF5200), fontWeight: FontWeight.w800, fontSize: 11)),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _miniStepBtn(Icons.remove, () {
                                if (id is int) {
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    if (qty <= 1) {
                                      cartQuantities.remove(id);
                                    } else {
                                      cartQuantities[id] = qty - 1;
                                    }
                                  });
                                }
                              }),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text('$qty',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFF5200))),
                              ),
                              _miniStepBtn(Icons.add, () {
                                if (id is int) {
                                  HapticFeedback.lightImpact();
                                  setState(() => cartQuantities[id] = qty + 1);
                                  _cartBounceController.forward().then((_) {
                                    if (mounted) _cartBounceController.reverse();
                                  });
                                }
                              }),
                            ],
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFFFF5200),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }

  // ── Full Menu Food Card (Vertical List) ───────────────────────────────────────
  Widget _buildFoodCard(Map<String, dynamic> item) {
    final id = item['id'];
    final qty = id is int ? (cartQuantities[id] ?? 0) : 0;
    final bool isVeg = item['isVeg'] ?? item['veg'] ?? false;
    final bool isBestseller = item['bestseller'] ?? false;
    final double rating = ((item['rating'] ?? 4.2) as num).toDouble();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 1),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
        border: Border(bottom: BorderSide(color: isDarkMode ? Colors.white12 : const Color(0xFFF0F0F0))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isVeg ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isVeg ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      if (isBestseller) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3EE),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFFCBAA)),
                          ),
                          child: const Text('Bestseller',
                              style: TextStyle(color: Color(0xFFFF5200), fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(item['name'] ?? '',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: isDarkMode ? Colors.white : Colors.black87)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFF4CAF50), size: 14),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(1),
                          style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 6),
                      const Text('•', style: TextStyle(color: Colors.grey)),
                      const SizedBox(width: 6),
                      const Icon(Icons.timer_outlined, size: 12, color: Colors.grey),
                      const SizedBox(width: 3),
                      Text(item['prepTime'] ?? '20 min', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(item['flavor'] ?? item['description'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 10),
                  Text('₹${item['price']}',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDarkMode ? Colors.white : Colors.black87)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        item['image'] ?? '',
                        width: 110,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 110,
                          height: 100,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3EE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.fastfood_outlined, color: Color(0xFFFFCBAA), size: 36),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                qty == 0
                    ? GestureDetector(
                        onTap: id is int
                            ? () {
                                HapticFeedback.lightImpact();
                                setState(() => cartQuantities[id] = 1);
                                _cartBounceController.forward().then((_) {
                                  if (mounted) _cartBounceController.reverse();
                                });
                              }
                            : null,
                        child: Container(
                          width: 110,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF2A2A2E) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFF5200), width: 1.5),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFFFF5200).withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2))
                            ],
                          ),
                          child: const Center(
                            child: Text('ADD',
                                style: TextStyle(color: Color(0xFFFF5200), fontWeight: FontWeight.w900, fontSize: 13)),
                          ),
                        ),
                      )
                    : Container(
                        width: 110,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5200),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            InkWell(
                              onTap: () {
                                if (id is int) {
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    if (qty <= 1) {
                                      cartQuantities.remove(id);
                                    } else {
                                      cartQuantities[id] = qty - 1;
                                    }
                                  });
                                }
                              },
                              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.remove, color: Colors.white, size: 16)),
                            ),
                            Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            InkWell(
                              onTap: () {
                                if (id is int) {
                                  HapticFeedback.lightImpact();
                                  setState(() => cartQuantities[id] = qty + 1);
                                  _cartBounceController.forward().then((_) {
                                    if (mounted) _cartBounceController.reverse();
                                  });
                                }
                              },
                              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.add, color: Colors.white, size: 16)),
                            ),
                          ],
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Branch Section ────────────────────────────────────────────────────────────
  Widget _buildBranchSection() {
    final b60 = branchesInfo['60_feet_ring_road'] ?? {};
    final bNit = branchesInfo['nittuvalli_circle'] ?? {};
    final b60Name = b60['name'] ?? '60 Feet Ring Rd';
    final b60Img = b60['image'] ?? 'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=400';
    final bNitName = bNit['name'] ?? 'Nittuvalli Circle';
    final bNitImg = bNit['image'] ?? 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=400';

    return Container(
      color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Our kitchens',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: isDarkMode ? Colors.white : Colors.black87)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _branchTile(b60Name, '9AM – 11PM', '4.8 ★', b60Img)),
              const SizedBox(width: 10),
              Expanded(child: _branchTile(bNitName, '10AM – 10PM', '4.7 ★', bNitImg)),
            ],
          ),
        ],
      ),
    );
  }

  String _sanitizeImageUrl(String? rawUrl, {bool isRestaurant = true}) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return isRestaurant
          ? 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800'
          : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400';
    }
    String url = rawUrl.trim();
    if (url.startsWith('/')) {
      url = 'https://rameez-kitchen-backend.onrender.com$url';
    } else {
      url = url.replaceAll(RegExp(r'https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?'), 'https://rameez-kitchen-backend.onrender.com');
      if (url.startsWith('http://rameez-kitchen-backend.onrender.com')) {
        url = url.replaceFirst('http://', 'https://');
      }
    }
    return url;
  }

  ImageProvider _getAvatarImageProvider(String? rawUrl) {
    final url = _sanitizeImageUrl(rawUrl, isRestaurant: false);
    if (url.startsWith('data:image')) {
      try {
        final commaIdx = url.indexOf(',');
        if (commaIdx != -1) {
          final b64 = url.substring(commaIdx + 1);
          return MemoryImage(base64Decode(b64));
        }
      } catch (_) {}
    }
    return NetworkImage(url);
  }

  Widget _branchTile(String name, String hours, String rating, String img) {
    final safeImg = _sanitizeImageUrl(img, isRestaurant: true);
    final fallbackImg = name.toLowerCase().contains('express') || name.toLowerCase().contains('nittuvalli')
        ? 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=600'
        : 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=600';
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2A2A2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDarkMode ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Image.network(
              safeImg,
              height: 80,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.network(
                fallbackImg,
                height: 80,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: isDarkMode ? Colors.white : Colors.black87)),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(hours, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    Text(rating, style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Skeleton Loader ───────────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 1),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
            border: Border(bottom: BorderSide(color: isDarkMode ? Colors.white12 : const Color(0xFFF0F0F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmer(height: 12, width: 80),
                    const SizedBox(height: 8),
                    _shimmer(height: 16, width: 160),
                    const SizedBox(height: 6),
                    _shimmer(height: 12, width: 120),
                    const SizedBox(height: 10),
                    _shimmer(height: 18, width: 60),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _shimmer(height: 100, width: 110, radius: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmer({required double height, required double width, double radius = 6}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white12 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3EE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 40))),
          ),
          const SizedBox(height: 16),
          Text('Nothing here right now',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDarkMode ? Colors.white : Colors.black87)),
          const SizedBox(height: 6),
          const Text('Try a different category or check back soon',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  // ── Sticky Search Bar (appears on scroll) ─────────────────────────────────────
  Widget _buildStickySearchBar() {
    return Container(
      color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (q) {
          setState(_applyMenuFilters);
        },
        decoration: InputDecoration(
          hintText: 'Search menu...',
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Color(0xFFFF5200), size: 20),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(_applyMenuFilters);
                  },
                )
              : null,
          filled: true,
          fillColor: isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFF5F5F5),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  // ── Floating Cart Bar ─────────────────────────────────────────────────────────
  Widget _buildFloatingCartBar() {
    final itemCount = totalCartItemsCount;
    final total = finalPayableRupees;

    return GestureDetector(
      onTap: _openCartSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5200),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: const Color(0xFFFF5200).withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$itemCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('View cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            Text('₹$total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  // 2. OFFERS TAB
  Widget _buildOffersTab() {
    if (dynamicOffers.isEmpty) return const Center(child: Text('There is no offer today', style: TextStyle(fontSize: 18, color: Colors.grey)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: dynamicOffers.map((o) => Card(
        child: ListTile(
          leading: const Icon(Icons.discount, color: Color(0xFFFF5200)),
          title: Text(o['code'] ?? ''),
          subtitle: Text(o['description'] ?? ''),
          trailing: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: appliedCoupon == o['code'] ? Colors.green : const Color(0xFFFF5200)),
            onPressed: () {
              setState(() { appliedCoupon = o['code']; discountAmount = (o['discount'] as num).toInt(); });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✓ Coupon ${o['code']} applied!')));
            },
            child: Text(appliedCoupon == o['code'] ? 'APPLIED' : 'APPLY', style: const TextStyle(color: Colors.white)),
          ),
        ),
      )).toList(),
    );
  }

  // ──── Helper: Launch Phone Call ────
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  // ──── Helper: Show Restaurant UPI QR Modal ────
  void _showRestaurantQrModal(String amount, String orderId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFFFF5200), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Restaurant UPI Direct QR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                      Text('Pay directly at delivery for #$orderId', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFF5200).withValues(alpha: 0.3), width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Image.network(
                    'https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=upi://pay?pa=rameez@okaxis&pn=RameezKitchen&am=$amount',
                    height: 190,
                    width: 190,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 190,
                      width: 190,
                      color: Colors.orange.shade50,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_2, size: 70, color: Color(0xFFFF5200)),
                            SizedBox(height: 6),
                            Text('rameez@okaxis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      'Pay Amount: ₹$amount • UPI ID: rameez@okaxis',
                      style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Supported: Google Pay • PhonePe • Paytm • Cred • BHIM',
              style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('COPY UPI ID', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: 'rameez@okaxis'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✓ UPI ID rameez@okaxis copied to clipboard!')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('DONE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ──── Helper: Show Driver Rating & Tip Modal ────
  void _showDriverRatingModal(String orderId, String driverName, String driverCode) {
    if (_isRatingModalOpen || _ratedOrders.contains(orderId)) return;
    _isRatingModalOpen = true;

    int rating = 5;
    int tip = 0;
    final feedbackCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Grab handle and close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 32),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 22),
                      onPressed: () {
                        _ratedOrders.add(orderId);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('🎉 Order Delivered!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('How was your experience with $driverName?', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 16),

                // Star rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (idx) {
                    final starNum = idx + 1;
                    return IconButton(
                      iconSize: 38,
                      icon: Icon(
                        starNum <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: Colors.amber,
                      ),
                      onPressed: () => setModalState(() => rating = starNum),
                    );
                  }),
                ),
                const SizedBox(height: 12),

                // Tip Rider
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tip your delivery hero (Optional):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [0, 10, 20, 50].map((amt) {
                    final isSel = tip == amt;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text(amt == 0 ? 'No Tip' : '₹$amt', style: TextStyle(fontWeight: FontWeight.bold, color: isSel ? Colors.white : Colors.black87, fontSize: 12)),
                          selected: isSel,
                          selectedColor: const Color(0xFFFF5200),
                          onSelected: (_) => setModalState(() => tip = amt),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: feedbackCtrl,
                  decoration: InputDecoration(
                    hintText: 'Write a compliment or note (e.g. Fast delivery, hot food!)...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    filled: true,
                    fillColor: isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFF9FAFB),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            setModalState(() => isSubmitting = true);
                            _ratedOrders.add(orderId);
                            try {
                              await http.post(
                                Uri.parse('${ApiConstants.baseUrl}/driver/rate'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'orderId': orderId,
                                  'driverName': driverName,
                                  'driverCode': driverCode,
                                  'customerName': customerName,
                                  'rating': rating,
                                  'tip': tip,
                                  'feedback': feedbackCtrl.text.trim(),
                                }),
                              );
                              if (tip > 0) {
                                await http.post(
                                  Uri.parse('${ApiConstants.baseUrl}/driver/tip'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({
                                    'orderId': orderId,
                                    'amount': tip,
                                  }),
                                );
                              }
                            } catch (_) {}
                            if (mounted && ctx.mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(tip > 0
                                      ? '✓ Thank you! ⭐ Rating & ₹$tip tip sent to $driverName!'
                                      : '✓ Thank you! ⭐ Feedback submitted successfully!'),
                                  backgroundColor: const Color(0xFF0F8A65),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('SUBMIT FEEDBACK & RATING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () {
                    _ratedOrders.add(orderId);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Skip for Now', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      _isRatingModalOpen = false;
    });
  }

  bool _isLegitimateCancellationReason(String reason, String orderStatus, DateTime? orderCreatedAt) {
    final lower = reason.toLowerCase().trim();
    if (lower.isEmpty) return false;

    // 1. Legitimate reasons: delays, errors, duplicate orders, kitchen requests
    final legitKeywords = [
      'delay',
      'late',
      'taking too long',
      'excessive',
      'wrong address',
      'incorrect address',
      'mistake',
      'accident',
      'duplicate',
      'restaurant requested',
      'kitchen asked',
      'emergency',
      'unresponsive',
      'rider not moving',
      'stuck',
      'illness',
      'closed',
    ];
    if (legitKeywords.any((kw) => lower.contains(kw))) {
      return true;
    }

    // 2. Early cancellation within 2 minutes of placement is always legitimate
    if (orderCreatedAt != null) {
      final diff = DateTime.now().difference(orderCreatedAt).inMinutes;
      if (diff <= 2) return true;
    }

    // 3. If order status is still PLACED (not yet started cooking), cancellation is legitimate
    if (orderStatus == 'PLACED') return true;

    return false;
  }

  void _showCancelOrderDialog(String orderId, Map<String, dynamic> order) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final orderStatus = (order['status']?.toString() ?? 'PLACED').toUpperCase();
    
    DateTime? orderCreatedAt;
    if (order['createdAt'] != null) {
      try {
        orderCreatedAt = DateTime.parse(order['createdAt'].toString()).toLocal();
      } catch (_) {}
    }

    String selectedReason = 'Order is taking much longer than estimated (Preparation Delay)';
    final customReasonCtrl = TextEditingController();
    bool isSubmitting = false;

    final reasons = [
      'Order is taking much longer than estimated (Preparation Delay)',
      'Entered incorrect delivery address by mistake',
      'Placed duplicate order accidentally',
      'Rameez Kitchen requested to cancel order',
      'Change of mind / No longer needed',
      'Other reason (type custom explanation below)',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final effectiveReason = selectedReason.startsWith('Other') && customReasonCtrl.text.trim().isNotEmpty
              ? customReasonCtrl.text.trim()
              : selectedReason;

          final bool isLegit = _isLegitimateCancellationReason(effectiveReason, orderStatus, orderCreatedAt);
          final int cancellationFee = isLegit ? 0 : 50;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580),
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4)),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), shape: BoxShape.circle),
                            child: const Icon(Icons.cancel_rounded, color: Colors.red, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Text('Cancel Order #$orderId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Terms Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFFFF7F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF5200).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.policy_outlined, size: 16, color: Color(0xFFFF5200)),
                                SizedBox(width: 6),
                                Text('Cancellation Policy & Terms', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFFFF5200))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '• If you cancel due to preparation delay or genuine error, charges are 100% WAIVED (₹0 Fee).\n• For late cancellations after cooking has begun, a ₹50 fee will be included on your next order.',
                              style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white70 : Colors.black87, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      const Text('Why are you cancelling?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      const SizedBox(height: 8),

                      ...reasons.map((r) {
                        final isSel = selectedReason == r;
                        return InkWell(
                          onTap: () {
                            setModalState(() => selectedReason = r);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFFF5200).withValues(alpha: 0.08) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSel ? const Color(0xFFFF5200) : Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: isSel ? const Color(0xFFFF5200) : Colors.grey,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                      color: isSel ? const Color(0xFFFF5200) : (isDarkMode ? Colors.white : Colors.black87),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                      if (selectedReason.startsWith('Other')) ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: customReasonCtrl,
                          onChanged: (_) => setModalState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Please describe the reason for cancellation...',
                            hintStyle: const TextStyle(fontSize: 12),
                            filled: true,
                            fillColor: isDarkMode ? const Color(0xFF2A2A2E) : Colors.grey.shade100,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Fee Calculation Result Banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isLegit ? Colors.green.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isLegit ? Colors.green.shade300 : Colors.amber.shade600),
                        ),
                        child: Row(
                          children: [
                            Icon(isLegit ? Icons.verified_user_rounded : Icons.info_rounded, color: isLegit ? Colors.green : Colors.amber.shade800, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isLegit ? 'Valid Reason Verified: ₹0 Fee (Waived!)' : 'Cancellation Fee: ₹50 on Next Order',
                                    style: TextStyle(
                                      color: isLegit ? Colors.green.shade800 : Colors.amber.shade900,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isLegit
                                        ? 'No cancellation charge will be billed. Order will be cancelled free of charge.'
                                        : 'Standard ₹50 fee will be automatically included in your next food order checkout.',
                                    style: TextStyle(
                                      color: isLegit ? Colors.green.shade900 : Colors.amber.shade900,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.pop(dialogCtx),
                              child: const Text('KEEP ORDER', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isLegit ? Colors.green.shade700 : Colors.red.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      setModalState(() => isSubmitting = true);
                                      try {
                                        final cancelUrl = Uri.parse('${ApiConstants.baseUrl}/orders/$orderId/cancel');
                                        await http.post(
                                          cancelUrl,
                                          headers: {'Content-Type': 'application/json'},
                                          body: jsonEncode({
                                            'fee': cancellationFee,
                                            'reason': effectiveReason,
                                            'phone': customerPhone,
                                            'chargeNextOrder': cancellationFee > 0,
                                          }),
                                        ).timeout(const Duration(seconds: 6));
                                      } catch (err) {
                                        debugPrint('[CANCEL ORDER ERROR] $err');
                                      }

                                      if (mounted) {
                                        setState(() {
                                          order['status'] = 'CANCELLED';
                                          order['cancellationFee'] = cancellationFee;
                                          order['cancellationReason'] = effectiveReason;
                                          if (cancellationFee > 0) {
                                            pendingCancellationFee = cancellationFee;
                                          }
                                        });

                                        Navigator.pop(dialogCtx);

                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              cancellationFee > 0
                                                  ? 'Order cancelled. ₹$cancellationFee will be included on your next order.'
                                                  : 'Order cancelled with ₹0 charges (Fee Waived).',
                                            ),
                                            backgroundColor: cancellationFee > 0 ? Colors.deepOrange : Colors.green,
                                          ),
                                        );
                                      }
                                    },
                              child: isSubmitting
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(
                                      isLegit ? 'CONFIRM CANCEL (FREE)' : 'CANCEL (₹50 ON NEXT ORDER)',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 3. FULL LIVE ORDERS TRACKER & DASHBOARD
  Widget _buildLiveOrdersTab() {
    if (activeOrdersList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.moped_rounded, size: 72, color: Color(0xFFFF5200)),
              ),
              const SizedBox(height: 20),
              const Text('No Active Orders', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text(
                'You have no ongoing delivery right now. Explore our delicious Dum Biryani and Charcoal specials!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5200),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.restaurant_menu, color: Colors.white),
                label: const Text('BROWSE MENU & ORDER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                onPressed: () {
                  setState(() => _selectedTab = 0);
                  widget.onTabChanged?.call(0);
                },
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: activeOrdersList.length,
      itemBuilder: (ctx, i) {
        final order = activeOrdersList[i];
        final orderId = order['orderId']?.toString() ?? 'ORD-1001';
        final status = (order['status']?.toString() ?? 'PLACED').toUpperCase();
        final minutes = order['remainingMinutes'] ?? 20;
        final totalAmount = order['totalAmount'] ?? '220';
        final deliveryOtp = order['deliveryOtp']?.toString() ?? '1234';
        final driverName = order['driverName']?.toString() ?? 'Manjunath Gowda';
        final driverPhone = order['driverPhone']?.toString() ?? '8073349233';
        final vehicleNumber = order['vehicleNumber']?.toString() ?? 'KA-17-EQ-4421';
        final vehicleType = order['vehicleType']?.toString() ?? 'Bike';
        final driverRating = order['driverRating']?.toString() ?? '4.8';
        final driverCode = order['driverCode']?.toString() ?? 'DRV-1001';
        final items = (order['items'] as List?) ?? [];
        final paymentMethod = order['paymentMethod']?.toString() ?? 'Cash on Delivery (COD)';
        final isCod = paymentMethod.toLowerCase().contains('cash') || paymentMethod.toLowerCase().contains('cod');

        // Status mapping and progress
        double progress = 0.2;
        String statusTitle = 'Order Placed';
        String statusSub = 'Kitchen received your order and is queuing ingredients.';
        Color statusColor = const Color(0xFFFF5200);

        if (status == 'PREPARING') {
          progress = 0.4;
          statusTitle = 'Kitchen Cooking Fresh';
          statusSub = 'Chef is preparing authentic Dum Biryani with fresh masala.';
          statusColor = Colors.amber.shade800;
        } else if (status == 'READY_FOR_PICKUP' || status == 'GOING_TO_RESTAURANT' || status == 'ARRIVED_RESTAURANT') {
          progress = 0.6;
          statusTitle = 'Rider Heading to Kitchen';
          statusSub = '$driverName is reaching Rameez Kitchen to collect package.';
          statusColor = Colors.blue.shade700;
        } else if (status == 'PICKED_UP' || status == 'ON_THE_WAY') {
          progress = 0.8;
          statusTitle = 'Out for Delivery • On the Way';
          statusSub = '$driverName picked up hot food and is heading to your doorstep.';
          statusColor = Colors.deepPurple;
        } else if (status == 'ARRIVED_CUSTOMER') {
          progress = 0.95;
          statusTitle = 'Rider at Your Doorstep!';
          statusSub = 'Rider is outside. Provide your 4-digit OTP to collect food.';
          statusColor = Colors.teal.shade700;
        } else if (status == 'DELIVERED') {
          progress = 1.0;
          statusTitle = 'Delivered! 🎉';
          statusSub = 'Food handed over successfully. Enjoy your delicious meal!';
          statusColor = Colors.green.shade700;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2A2A2E) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Bar ──
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [statusColor, statusColor.withValues(alpha: 0.85)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
                              child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 16),
                            ),
                            const SizedBox(width: 8),
                            Text(orderId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined, color: statusColor, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                status == 'DELIVERED' ? 'DELIVERED' : '$minutes mins left',
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(statusTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(statusSub, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. PROMINENT DELIVERY VERIFICATION OTP BADGE ──
                    if (status != 'DELIVERED')
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFF7ED), Color(0xFFFEF3C7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.orange.shade300, width: 1.5),
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
                                      decoration: BoxDecoration(color: const Color(0xFFFF5200), borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'DELIVERY CONFIRMATION OTP',
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF9A3412), letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.copy_rounded, color: Color(0xFFFF5200), size: 18),
                                  tooltip: 'Copy OTP',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: deliveryOtp));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('✓ Delivery OTP $deliveryOtp copied!')),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.orange.shade400, width: 2),
                                  boxShadow: [
                                    BoxShadow(color: Colors.orange.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Text(
                                  deliveryOtp.split('').join('   '),
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFFF5200),
                                    letterSpacing: 4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Center(
                              child: Text(
                                '🔒 Share this 4-digit secret code with your rider when they reach your doorstep to complete handover.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, color: Color(0xFF78350F), height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── 2. LIVE ORDER JOURNEY & REAL-TIME STATUS BANNER ──
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            statusColor.withValues(alpha: 0.12),
                            statusColor.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  status == 'DELIVERED'
                                      ? Icons.task_alt_rounded
                                      : status == 'ARRIVED_CUSTOMER'
                                          ? Icons.doorbell_rounded
                                          : (status == 'PICKED_UP' || status == 'ON_THE_WAY')
                                              ? Icons.delivery_dining_rounded
                                              : (status == 'ARRIVED_RESTAURANT' || status == 'READY_FOR_PICKUP' || status == 'GOING_TO_RESTAURANT')
                                                  ? Icons.two_wheeler_rounded
                                                  : Icons.outdoor_grill_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (status == 'PICKED_UP' || status == 'ON_THE_WAY')
                                          ? '🚀 Order Picked Up • Food is On the Way!'
                                          : status == 'ARRIVED_CUSTOMER'
                                              ? '📍 Rider Arrived at Doorstep!'
                                              : status == 'ARRIVED_RESTAURANT'
                                                  ? '🥘 Rider at Rameez Kitchen'
                                                  : (status == 'GOING_TO_RESTAURANT' || status == 'READY_FOR_PICKUP')
                                                      ? '🛵 Rider Heading to Restaurant'
                                                      : status == 'DELIVERED'
                                                          ? '🎉 Order Delivered!'
                                                          : '👨‍🍳 Cooking Fresh on Charcoal',
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      (status == 'PICKED_UP' || status == 'ON_THE_WAY')
                                          ? 'Your order is picked up from Rameez Kitchen and fresh hot food is on the way to your address!'
                                          : status == 'ARRIVED_CUSTOMER'
                                              ? 'Your delivery hero is right outside! Please share your 4-digit OTP below with the rider.'
                                              : status == 'ARRIVED_RESTAURANT'
                                                  ? 'Rider is at Rameez Kitchen collecting your freshly cooked dishes.'
                                                  : (status == 'GOING_TO_RESTAURANT' || status == 'READY_FOR_PICKUP')
                                                      ? 'Rider assigned and heading to Rameez Kitchen to collect your order.'
                                                      : status == 'DELIVERED'
                                                          ? 'Food handed over successfully. Enjoy your delicious meal!'
                                                          : 'Our chefs are preparing your authentic biryani dishes fresh.',
                                      style: TextStyle(
                                        color: isDarkMode ? Colors.white70 : Colors.black87,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Live Trip Route summary
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF1E1E24) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.storefront_rounded, color: Color(0xFFFF5200), size: 16),
                                const SizedBox(width: 6),
                                const Text(
                                  'Rameez Kitchen',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey),
                                ),
                                const Icon(Icons.location_on_rounded, color: Colors.green, size: 16),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    deliveryAddress.isNotEmpty ? deliveryAddress : (houseNo.isNotEmpty ? houseNo : 'Your Home'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── 3. DELIVERY HERO CARD ──
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF1E1E22) : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFFFF5200).withValues(alpha: 0.15),
                            child: const Icon(Icons.motorcycle, color: Color(0xFFFF5200), size: 26),
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
                                        driverName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star, color: Colors.amber, size: 12),
                                          const SizedBox(width: 2),
                                          Text(driverRating, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.amber.shade900)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('$vehicleType • $vehicleNumber', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: Colors.green),
                            icon: const Icon(Icons.phone, color: Colors.white, size: 18),
                            onPressed: () => _makePhoneCall(driverPhone),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── 4. ORDER PROGRESS TIMELINE (Embedded Tracker) ──
                    _buildEmbeddedOrderProgressTimeline(status, order['createdAt']?.toString()),

                    const SizedBox(height: 14),

                    // ── 5. PAYMENT STATUS CARD ──
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF1E1E22) : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDarkMode ? Colors.white12 : Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isCod ? Icons.payments_outlined : Icons.check_circle_rounded,
                                    color: isCod ? const Color(0xFFFF5200) : Colors.green.shade700,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isCod ? 'Cash on Delivery (COD)' : 'Paid Online (UPI / Digital)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          color: isCod ? (isDarkMode ? Colors.white : Colors.black87) : Colors.green.shade800,
                                        ),
                                      ),
                                      Text(
                                        isCod ? 'Pay cash or scan driver QR at doorstep' : 'Payment Confirmed & Verified',
                                        style: TextStyle(
                                          color: isCod ? Colors.grey : Colors.green.shade600,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Text('₹$totalAmount', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFFFF5200))),
                            ],
                          ),
                          if (isCod) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFFF5200), width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.qr_code_2, color: Color(0xFFFF5200), size: 20),
                                label: const Text('PAY ONLINE VIA RESTAURANT UPI QR', style: TextStyle(color: Color(0xFFFF5200), fontWeight: FontWeight.w900, fontSize: 12)),
                                onPressed: () => _showRestaurantQrModal(totalAmount.toString(), orderId),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── 6. ITEM SUMMARY ACCORDION ──
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        leading: const Icon(Icons.shopping_bag_outlined, color: Color(0xFFFF5200)),
                        title: Text('Order Items (${items.isNotEmpty ? items.length : 1})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        children: [
                          if (items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('1x Dum Biryani Special', style: TextStyle(fontSize: 13)),
                                  Text('Included in Total', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            )
                          else
                            ...items.map((item) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('• ${item['name']} x ${item['quantity'] ?? 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text('₹${(item['price'] ?? 0) * (item['quantity'] ?? 1)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                )),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Deliver To:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              Expanded(
                                child: Text(
                                  deliveryAddress,
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── 7. POST DELIVERY RATING BUTTON (When DELIVERED) ──
                    if (status == 'DELIVERED') ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.star, color: Colors.white),
                          label: const Text('RATE YOUR FOOD & DELIVERY HERO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                          onPressed: () => _showDriverRatingModal(orderId, driverName, driverCode),
                        ),
                      ),
                    ],

                    // ── 8. CANCEL ORDER BUTTON & STATUS BANNER ──
                    if (status != 'DELIVERED' && status != 'CANCELLED') ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade300, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
                          label: const Text('CANCEL ORDER', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                          onPressed: () => _showCancelOrderDialog(orderId, order),
                        ),
                      ),
                    ] else if (status == 'CANCELLED') ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cancel_rounded, color: Colors.red, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Order Cancelled', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(
                                    order['cancellationReason'] != null
                                        ? '${order['cancellationReason']}'
                                        : 'Cancelled by customer',
                                    style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87, fontSize: 11),
                                  ),
                                  if (order['cancellationFee'] != null && (order['cancellationFee'] as num) > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Policy charge: ₹${order['cancellationFee']} (included on next order)',
                                        style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmbeddedOrderProgressTimeline(String status, String? createdAtStr) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final stepIndex = _getStatusStepIndex(status);

    DateTime orderTime = DateTime.now();
    if (createdAtStr != null && createdAtStr.isNotEmpty) {
      try {
        orderTime = DateTime.parse(createdAtStr).toLocal();
      } catch (_) {}
    }

    final steps = [
      {'title': 'Order Placed', 'min': 0},
      {'title': 'Confirmed by Kitchen', 'min': 2},
      {'title': 'Being Prepared', 'min': 5},
      {'title': 'Rider Heading to Kitchen', 'min': 10},
      {'title': 'Rider at Kitchen', 'min': 14},
      {'title': 'Food is on the Way!', 'min': 18},
      {'title': 'Rider at Your Doorstep', 'min': 24},
      {'title': 'Order Delivered! 🎉', 'min': 28},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E22) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDarkMode ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5200).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.timeline_rounded, color: Color(0xFFFF5200), size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Order Progress',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key;
            final s = entry.value;
            final isLast = idx == steps.length - 1;

            final isCompleted = stepIndex > idx || (stepIndex == 7 && idx == 7);
            final isActive = stepIndex == idx && stepIndex < 7;
            final isPending = stepIndex < idx;

            final stepTime = orderTime.add(Duration(minutes: s['min'] as int));
            final hour = stepTime.hour == 0 ? 12 : (stepTime.hour > 12 ? stepTime.hour - 12 : stepTime.hour);
            final minute = stepTime.minute.toString().padLeft(2, '0');
            final ampm = stepTime.hour >= 12 ? 'PM' : 'AM';
            final timeStr = '$hour:$minute $ampm';

            final Color dotColor = isCompleted
                ? Colors.green
                : isActive
                    ? const Color(0xFFFF5200)
                    : (isDarkMode ? Colors.white12 : Colors.grey.shade300);

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Container(
                          width: isActive ? 24 : 18,
                          height: isActive ? 24 : 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dotColor,
                            border: isActive
                                ? Border.all(color: const Color(0xFFFF5200).withValues(alpha: 0.35), width: 3)
                                : null,
                            boxShadow: isActive
                                ? [BoxShadow(color: const Color(0xFFFF5200).withValues(alpha: 0.35), blurRadius: 6)]
                                : isCompleted
                                    ? [BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 6)]
                                    : null,
                          ),
                          child: isCompleted
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 11)
                              : isActive
                                  ? const Icon(Icons.circle, color: Colors.white, size: 6)
                                  : null,
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2.5,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              color: isCompleted ? Colors.green : (isDarkMode ? Colors.white12 : Colors.grey.shade200),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 16, top: 1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              s['title'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive || isCompleted ? FontWeight.w800 : FontWeight.w500,
                                color: isPending
                                    ? Colors.grey.shade400
                                    : isCompleted
                                        ? (isDarkMode ? Colors.white : Colors.black87)
                                        : const Color(0xFFFF5200),
                              ),
                            ),
                          ),
                          if (isCompleted || isActive)
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isCompleted ? Colors.green.shade600 : const Color(0xFFFF5200),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  int _getStatusStepIndex(String status) {
    switch (status.toUpperCase()) {
      case 'PLACED':
      case 'NEW':
      case 'PENDING':
        return 0;
      case 'CONFIRMED':
        return 1;
      case 'PREPARING':
      case 'COOKING':
      case 'READY':
      case 'READY_FOR_PICKUP':
        return 2;
      case 'GOING_TO_RESTAURANT':
      case 'ACCEPTED':
        return 3;
      case 'ARRIVED_RESTAURANT':
      case 'ARRIVED_AT_REST':
        return 4;
      case 'PICKED_UP':
      case 'ON_THE_WAY':
      case 'OUT_FOR_DELIVERY':
        return 5;
      case 'ARRIVED_CUSTOMER':
      case 'ARRIVED_AT_CUST':
        return 6;
      case 'DELIVERED':
      case 'COMPLETED':
        return 7;
      default:
        return 0;
    }
  }

  Widget _buildGoldPerkRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFD4AF37), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSelectionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2A2A2E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF5200) : (isDarkMode ? Colors.white12 : Colors.grey.shade300),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF5200).withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Text(badgeText, style: TextStyle(color: badgeColor, fontWeight: FontWeight.w900, fontSize: 10)),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? const Color(0xFFFF5200) : Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGoldCelebrationModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFAA7C11)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stars_rounded, color: Colors.white, size: 54),
            ),
            const SizedBox(height: 18),
            const Text(
              '🎉 Welcome to Rameez Gold!',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your VIP membership is now active. Enjoy ₹0 Service Fee on every order, exclusive discounts, and priority kitchen preparation!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedTab = 0);
                  widget.onTabChanged?.call(0);
                },
                child: const Text(
                  'START ORDERING WITH ₹0 SERVICE FEE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openGoldMembershipModal() {
    if (isGoldMember) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Row(
            children: [
              Icon(Icons.stars, color: Colors.amber, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text('Rameez Gold Active', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You are currently enjoying VIP Rameez Gold Membership benefits:',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              _buildGoldPerkRow(Icons.check_circle, '₹0 Service & Packaging Charge on all orders'),
              _buildGoldPerkRow(Icons.check_circle, 'Special discounts with code GOLD20'),
              _buildGoldPerkRow(Icons.check_circle, 'VIP Priority Kitchen Preparation'),
              _buildGoldPerkRow(Icons.check_circle, 'Express Delivery Driver Allocation'),
              const SizedBox(height: 14),
              Text(
                'Plan: Monthly VIP Pass • Active & Verified',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => isGoldMember = false);
                _syncProfileWithServer();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rameez Gold membership paused.')),
                );
              },
              child: const Text('CANCEL MEMBERSHIP', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    String selectedMethod = 'WALLET';
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final walletBalance = context.watch<WalletProvider>().balance;
          final isWalletSufficient = walletBalance >= 99.0;

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E1E22), Color(0xFF2C2C34)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFD4AF37), Color(0xFFAA7C11)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.stars_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'RAMEEZ GOLD',
                                    style: TextStyle(
                                      color: Color(0xFFD4AF37),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.verified, color: Colors.amber, size: 16),
                                ],
                              ),
                              SizedBox(height: 2),
                              Text(
                                'VIP Foodie Pass • ₹99 / month',
                                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '₹99/MO',
                            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('VIP Membership Benefits:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF2A2A2E) : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDarkMode ? Colors.white12 : Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        _buildGoldPerkRow(Icons.check_circle_rounded, '₹0 Service & Packaging Charge on every order'),
                        const SizedBox(height: 8),
                        _buildGoldPerkRow(Icons.local_offer_rounded, 'Extra ₹20-50 OFF with code GOLD20'),
                        const SizedBox(height: 8),
                        _buildGoldPerkRow(Icons.restaurant_rounded, 'Priority Chef Queuing & VIP Packaging'),
                        const SizedBox(height: 8),
                        _buildGoldPerkRow(Icons.electric_moped_rounded, 'Express Delivery Driver Allocation'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Select Payment Method:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 10),

                  // Option 1: Rameez E-Wallet
                  _buildPaymentSelectionTile(
                    icon: Icons.account_balance_wallet_rounded,
                    iconColor: Colors.green,
                    title: 'Rameez E-Wallet',
                    subtitle: 'Balance: ₹${walletBalance.toStringAsFixed(2)} ${isWalletSufficient ? '• Instant 1-Click' : '• (Insufficient)'}',
                    badgeText: isWalletSufficient ? 'RECOMMENDED' : 'TOP UP',
                    badgeColor: isWalletSufficient ? Colors.green : Colors.amber.shade800,
                    isSelected: selectedMethod == 'WALLET',
                    onTap: () {
                      setModalState(() => selectedMethod = 'WALLET');
                    },
                  ),

                  // Option 2: Google Pay
                  _buildPaymentSelectionTile(
                    icon: Icons.account_balance_rounded,
                    iconColor: const Color(0xFF1A73E8),
                    title: 'Google Pay (GPay UPI)',
                    subtitle: 'Instant UPI Intent Approval',
                    badgeText: 'FAST',
                    badgeColor: const Color(0xFF1A73E8),
                    isSelected: selectedMethod == 'GPAY',
                    onTap: () {
                      setModalState(() => selectedMethod = 'GPAY');
                    },
                  ),

                  // Option 3: PhonePe
                  _buildPaymentSelectionTile(
                    icon: Icons.mobile_friendly_rounded,
                    iconColor: const Color(0xFF5F259F),
                    title: 'PhonePe UPI',
                    subtitle: 'Pay directly via PhonePe App',
                    badgeText: 'POPULAR',
                    badgeColor: const Color(0xFF5F259F),
                    isSelected: selectedMethod == 'PHONEPE',
                    onTap: () {
                      setModalState(() => selectedMethod = 'PHONEPE');
                    },
                  ),

                  // Option 4: Paytm / Any UPI
                  _buildPaymentSelectionTile(
                    icon: Icons.qr_code_2_rounded,
                    iconColor: const Color(0xFF002E6E),
                    title: 'Paytm / Any UPI App',
                    subtitle: 'Pay via Paytm, BHIM, Cred, or Card',
                    badgeText: 'UPI',
                    badgeColor: const Color(0xFF002E6E),
                    isSelected: selectedMethod == 'PAYTM',
                    onTap: () {
                      setModalState(() => selectedMethod = 'PAYTM');
                    },
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 3,
                      ),
                      onPressed: isProcessing
                          ? null
                          : () async {
                              if (selectedMethod == 'WALLET' && !isWalletSufficient) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('⚠️ Insufficient wallet balance. Please top up your wallet or choose UPI.')),
                                );
                                return;
                              }

                              setModalState(() => isProcessing = true);

                              try {
                                if (selectedMethod == 'WALLET') {
                                  await context.read<WalletProvider>().deduct(
                                    99.0,
                                    reason: 'Rameez Gold 1-Month Membership',
                                  );
                                }

                                await http.post(
                                  Uri.parse('${ApiConstants.baseUrl}/customer/membership/subscribe'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({
                                    'phone': customerPhone,
                                    'paymentMethod': selectedMethod,
                                    'amount': 99,
                                    'transactionId': 'TX_GOLD_${DateTime.now().millisecondsSinceEpoch}',
                                  }),
                                );

                                if (!mounted) return;
                                setState(() => isGoldMember = true);
                                _syncProfileWithServer();

                                if (mounted && Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                }

                                _showGoldCelebrationModal();
                              } catch (e) {
                                if (mounted) {
                                  setModalState(() => isProcessing = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error activating membership: $e')),
                                  );
                                }
                              }
                            },
                      child: isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.lock_rounded, size: 18, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'PAY ₹99 & ACTIVATE GOLD',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 4. FULL CUSTOMER PROFILE TAB
  Widget _buildProfileTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundImage: _getAvatarImageProvider(customerAvatar),
                      onBackgroundImageError: (_, _) => const Icon(Icons.person, size: 36),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 13,
                        backgroundColor: const Color(0xFFFF5200),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                          onPressed: _openAvatarEditor,
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
                          Text(customerName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          if (isGoldMember) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified, color: Colors.amber, size: 18),
                          ]
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(customerPhone, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                      Text(customerEmail, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note, color: Color(0xFFFF5200)),
                  onPressed: _openAccountEditor,
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: isGoldMember ? Colors.amber.shade50 : const Color(0xFF1E1E22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: Icon(Icons.stars, color: isGoldMember ? Colors.amber.shade800 : const Color(0xFFD4AF37), size: 32),
            title: Text(
              isGoldMember ? 'Rameez Gold Active' : 'Get Rameez Gold Membership',
              style: TextStyle(fontWeight: FontWeight.bold, color: isGoldMember ? Colors.black : Colors.white),
            ),
            subtitle: Text(
              isGoldMember ? 'Enjoy ₹0 Service Charge on all orders' : '₹0 Service Charge + Extra Discounts for ₹99/mo',
              style: TextStyle(color: isGoldMember ? Colors.black87 : Colors.white70, fontSize: 12),
            ),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: isGoldMember ? Colors.green : const Color(0xFFFF5200)),
              onPressed: _openGoldMembershipModal,
              child: Text(isGoldMember ? 'ACTIVE' : 'JOIN', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SwitchListTile(
            secondary: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode, color: const Color(0xFFFF5200)),
            title: const Text('Appearance Mode', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(isDarkMode ? 'Dark Mode Active' : 'Light Mode Active'),
            value: isDarkMode,
            activeThumbColor: const Color(0xFFFF5200),
            onChanged: (v) => setState(() => isDarkMode = v),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined, color: Color(0xFFFF5200)),
            title: const Text('Saved Address', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(deliveryAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openAddressModal,
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_rounded, color: Colors.green),
            title: const Text('Rameez Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Builder(
              builder: (ctx) {
                final bal = ctx.watch<WalletProvider>().balance;
                return Text('Balance: ₹${bal.toStringAsFixed(2)} • Fast 1-Click Pay');
              },
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WalletScreen()),
              );
            },
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.credit_card, color: Color(0xFFFF5200)),
            title: const Text('Payment Methods', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Manage Cards, UPI IDs, and Defaults'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openPaymentMethodsModal,
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.history, color: Color(0xFFFF5200)),
            title: const Text('Past Orders History', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${pastOrdersList.length} completed orders'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openPastOrdersModal,
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.star_half, color: Colors.amber),
            title: const Text('Send Your Feedback', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Review food & service directly to manager'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openFeedbackModal,
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.shield, color: Colors.red),
            title: const Text('Safety Emergency SOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            subtitle: const Text('+91 8073349233 • 24/7 Helpline'),
            trailing: const Icon(Icons.phone, color: Colors.red),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Safety Emergency Assistance'),
                  content: const Text('Direct kitchen manager helpline: +91 8073349233\nAmbulance: 108 | Police: 112'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                ),
              );
            },
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.blueGrey),
            title: const Text('About Rameez Kitchen'),
            subtitle: const Text('Version 2.4 • Authenticated Davanagere Special'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Rameez Kitchen',
                applicationVersion: '2.4.0',
                children: [
                  const Text('Serving authentic charcoal dum biryanis, barbecue rolls, and starters in Davanagere.'),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('LOG OUT', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              try {
                await context.read<AuthProvider>().logout();
              } catch (_) {}
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const CustomerLoginScreen()),
              );
            },
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _bannerTimer?.cancel();
    _flashTimer?.cancel();
    _midBannerCtrl.dispose();
    _offerPageCtrl.dispose();
    _deliveryScrollCtrl.dispose();
    _searchCtrl.dispose();
    _cartBounceController.dispose();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPaused = globalStatus['state'] == 'PAUSED';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (isPaused)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade800,
                        boxShadow: [
                          BoxShadow(color: Colors.red.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'KITCHEN PAUSED: ${globalStatus['pauseReason']}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedTab,
                      children: [
                        _buildDeliveryTab(),
                        _buildLiveOrdersTab(),
                        _buildProfileTab(),
                      ],
                    ),
                  ),
                ],
              ),
              if (totalCartItemsCount > 0 && _selectedTab == 0 && !isPaused)
                Positioned(
                  bottom: 12, left: 16, right: 16,
                  child: ScaleTransition(
                    scale: _cartBounceAnim,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _openCartSheet();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFF5200), Color(0xFFFF7A00)]),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFFFF5200).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('$totalCartItemsCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                ),
                                const SizedBox(width: 12),
                                Text('₹$finalPayableRupees', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                              ],
                            ),
                            const Row(
                              children: [
                                Text('VIEW CART', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5)),
                                SizedBox(width: 4),
                                Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 20),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4)),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedTab,
            selectedItemColor: const Color(0xFFFF5200),
            unselectedItemColor: Colors.grey.shade400,
            selectedFontSize: 12,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            onTap: (i) {
              HapticFeedback.selectionClick();
              setState(() => _selectedTab = i);
              widget.onTabChanged?.call(i);
            },
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.restaurant_menu_outlined), activeIcon: Icon(Icons.restaurant_menu_rounded, size: 28), label: 'Menu'),
              BottomNavigationBarItem(
                icon: Badge(
                  isLabelVisible: activeOrdersList.isNotEmpty,
                  backgroundColor: const Color(0xFFFF5200),
                  label: Text('${activeOrdersList.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  child: const Icon(Icons.delivery_dining_outlined),
                ),
                activeIcon: Badge(
                  isLabelVisible: activeOrdersList.isNotEmpty,
                  backgroundColor: const Color(0xFFFF5200),
                  label: Text('${activeOrdersList.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  child: const Icon(Icons.delivery_dining_rounded, size: 28),
                ),
                label: 'Live Orders',
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), activeIcon: Icon(Icons.person_rounded, size: 28), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pinned Category Header Delegate ──────────────────────────────────────────
class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool isDarkMode;

  _CategoryHeaderDelegate({
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.isDarkMode = false,
  });

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  bool shouldRebuild(_CategoryHeaderDelegate old) =>
      old.selected != selected || old.categories != categories || old.isDarkMode != isDarkMode;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDarkMode ? const Color(0xFF1E1E22) : Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          final isSelected = cat == selected;
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFF5200) : (isDarkMode ? const Color(0xFF2A2A2E) : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFF5200) : (isDarkMode ? Colors.white24 : Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    const Icon(Icons.check, color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                  ],
                  Text(cat,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : (isDarkMode ? Colors.white70 : Colors.grey.shade700),
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

