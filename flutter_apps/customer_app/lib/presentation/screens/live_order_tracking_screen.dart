import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../logic/wallet_provider.dart';
import 'package:provider/provider.dart';

// ══════════════════════════════════════════════════════════════════════
//  SECURE ORDER STATUS ENUM
//  Handles all driver-app status codes (GOING_TO_RESTAURANT, ARRIVED_RESTAURANT, etc.)
// ══════════════════════════════════════════════════════════════════════
enum OrderStatus {
  placed,
  confirmed,
  preparing,
  headingToRestaurant,
  atRestaurant,
  outForDelivery,
  atCustomerDoorstep,
  delivered,
  cancelled;

  static OrderStatus fromString(String raw) {
    final normalized = raw.trim().toUpperCase().replaceAll(' ', '_');
    return switch (normalized) {
      'PLACED' => OrderStatus.placed,
      'CONFIRMED' => OrderStatus.confirmed,
      'PREPARING' => OrderStatus.preparing,
      'GOING_TO_RESTAURANT' => OrderStatus.headingToRestaurant,
      'READY_FOR_PICKUP' || 'ARRIVED_RESTAURANT' => OrderStatus.atRestaurant,
      'PICKED_UP' || 'OUT_FOR_DELIVERY' || 'ON_THE_WAY' => OrderStatus.outForDelivery,
      'ARRIVED_CUSTOMER' || 'OTP_VERIFIED' => OrderStatus.atCustomerDoorstep,
      'DELIVERED' || 'COMPLETED' => OrderStatus.delivered,
      'CANCELLED' => OrderStatus.cancelled,
      _ => OrderStatus.placed,
    };
  }

  String get displayLabel => switch (this) {
        OrderStatus.placed => 'Order Placed',
        OrderStatus.confirmed => 'Confirmed by Kitchen',
        OrderStatus.preparing => 'Being Prepared',
        OrderStatus.headingToRestaurant => 'Rider Heading to Kitchen',
        OrderStatus.atRestaurant => 'Rider at Kitchen',
        OrderStatus.outForDelivery => 'Food is on the Way!',
        OrderStatus.atCustomerDoorstep => 'Rider at Your Doorstep',
        OrderStatus.delivered => 'Order Delivered! 🎉',
        OrderStatus.cancelled => 'Order Cancelled',
      };

  String get subLabel => switch (this) {
        OrderStatus.placed => 'Your order has been received by kitchen',
        OrderStatus.confirmed => 'The merchant confirmed your order',
        OrderStatus.preparing => 'Chef is cooking your food fresh',
        OrderStatus.headingToRestaurant => 'Rider is reaching Rameez Kitchen to collect package',
        OrderStatus.atRestaurant => 'Rider is at the kitchen collecting your hot order',
        OrderStatus.outForDelivery => 'Rider picked up your food and is heading to your address',
        OrderStatus.atCustomerDoorstep => 'Rider has arrived! Share your 4-digit secret OTP',
        OrderStatus.delivered => 'Enjoy your delicious meal! 🎉',
        OrderStatus.cancelled => 'We\'re sorry for the inconvenience',
      };

  IconData get icon => switch (this) {
        OrderStatus.placed => Icons.receipt_long_rounded,
        OrderStatus.confirmed => Icons.check_circle_outline_rounded,
        OrderStatus.preparing => Icons.restaurant_rounded,
        OrderStatus.headingToRestaurant => Icons.two_wheeler_rounded,
        OrderStatus.atRestaurant => Icons.store_rounded,
        OrderStatus.outForDelivery => Icons.delivery_dining_rounded,
        OrderStatus.atCustomerDoorstep => Icons.location_on_rounded,
        OrderStatus.delivered => Icons.done_all_rounded,
        OrderStatus.cancelled => Icons.cancel_rounded,
      };

  int get stepIndex => switch (this) {
        OrderStatus.placed => 0,
        OrderStatus.confirmed => 1,
        OrderStatus.preparing => 2,
        OrderStatus.headingToRestaurant => 3,
        OrderStatus.atRestaurant => 4,
        OrderStatus.outForDelivery => 5,
        OrderStatus.atCustomerDoorstep => 6,
        OrderStatus.delivered => 7,
        OrderStatus.cancelled => -1,
      };
}

// ══════════════════════════════════════════════════════════════════════
//  SECURE STEP TIMESTAMP MODEL
// ══════════════════════════════════════════════════════════════════════
class _StepTimestamp {
  final OrderStatus status;
  final DateTime time;
  const _StepTimestamp(this.status, this.time);
}

// ══════════════════════════════════════════════════════════════════════
//  MAIN TRACKING SCREEN
// ══════════════════════════════════════════════════════════════════════
class LiveOrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final int? initialRemainingMinutes;

  const LiveOrderTrackingScreen({
    super.key,
    required this.orderId,
    this.initialRemainingMinutes,
  });

  @override
  State<LiveOrderTrackingScreen> createState() => _LiveOrderTrackingScreenState();
}

class _LiveOrderTrackingScreenState extends State<LiveOrderTrackingScreen>
    with TickerProviderStateMixin {

  // ──── Brand colours ────
  static const _orange = AppColors.primaryOrange;
  static const _orangeLight = Color(0xFFFF8A00);

  // ──── Socket ────
  io.Socket? _socket;
  bool _isConnected = false;
  int _reconnectCount = 0;
  static const int _maxReconnectAttempts = 15;

  // ──── Order state ────
  OrderStatus _status = OrderStatus.placed;
  int _remainingMinutes = 25;
  Timer? _etaTimer;
  final List<_StepTimestamp> _timestamps = [];

  // ──── Driver info (from driver-app socket events) ────
  String _driverName = 'Assigning a nearby rider...';
  String _driverPhone = '';
  String _driverCode = '';
  String _vehicleNumber = '';
  String _vehicleType = 'Bike';
  double? _riderLat;
  double? _riderLng;

  // ──── Merchant info ────
  String _merchantName = 'Rameez Kitchen';
  String _merchantPhone = '';
  String _branchName = '60 Feet Ring Road';

  // ──── Animation controllers ────
  late AnimationController _pulseController;
  late AnimationController _heroController;
  late Animation<double> _heroScale;
  late AnimationController _slideController;
  late Animation<Offset> _slideOffset;

  // ──── Delivery OTP & Dynamic Countdown ────
  String _deliveryOtp = '2847';
  int _otpSecondsRemaining = 60;
  Timer? _otpCountdownTimer;
  bool _isRegeneratingOtp = false;
  bool _hasShownRating = false;

  // ──── Polling Timer ────
  Timer? _pollingTimer;

  // ──── Support chat ────
  bool _showSupportMsg = false;

  bool _matchesOrderId(dynamic id1, dynamic id2) {
    if (id1 == null || id2 == null) return false;
    final s1 = id1.toString().trim();
    final s2 = id2.toString().trim();
    if (s1 == s2) return true;
    final n1 = s1.replaceAll(RegExp(r'\D'), '');
    final n2 = s2.replaceAll(RegExp(r'\D'), '');
    if (n1.isNotEmpty && n2.isNotEmpty) {
      return (n1 == n2) || (int.tryParse(n1) == int.tryParse(n2));
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _remainingMinutes = widget.initialRemainingMinutes ?? 25;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heroScale = CurvedAnimation(parent: _heroController, curve: Curves.elasticOut);
    _heroController.forward();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideOffset = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
    _slideController.forward();

    // Record initial timestamp
    _timestamps.add(_StepTimestamp(OrderStatus.placed, DateTime.now()));

    _fetchOrderDetails();
    _initSocket();
    _startEtaCountdown();
    _startOtpCountdown();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchOrderDetails());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _etaTimer?.cancel();
    _otpCountdownTimer?.cancel();
    _pulseController.dispose();
    _heroController.dispose();
    _slideController.dispose();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  void _startOtpCountdown() {
    _otpCountdownTimer?.cancel();
    _otpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_isTerminal) {
        _otpCountdownTimer?.cancel();
        return;
      }
      if (_otpSecondsRemaining > 1) {
        setState(() => _otpSecondsRemaining--);
      } else {
        setState(() => _otpSecondsRemaining = 60);
      }
    });
  }

  Future<void> _regenerateOtp() async {
    if (_isRegeneratingOtp) return;
    setState(() => _isRegeneratingOtp = true);
    HapticFeedback.mediumImpact();
    try {
      final res = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/orders/${widget.orderId}/generate-otp'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted && data['otp'] != null) {
          setState(() {
            _deliveryOtp = data['otp'].toString();
            _otpSecondsRemaining = (data['expiresInSeconds'] as num?)?.toInt() ?? 60;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ New secret handover OTP $_deliveryOtp generated!'),
              backgroundColor: const Color(0xFF0F8A65),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isRegeneratingOtp = false);
    }
  }

  Future<void> _fetchOrderDetails() async {
    try {
      final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/track/${widget.orderId}'));
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        final data = jsonDecode(res.body);
        if (mounted && data is Map) {
          if (data['status'] != null) {
            final fetchedStatus = OrderStatus.fromString(data['status'].toString());
            if (fetchedStatus != _status) {
              _handleStatusChange(data);
              return;
            }
          }
          setState(() {
            if (data['otp'] != null && data['otp'].toString().isNotEmpty) {
              _deliveryOtp = data['otp'].toString();
            }
            if (data['deliveryOtp'] != null && data['deliveryOtp'].toString().isNotEmpty) {
              _deliveryOtp = data['deliveryOtp'].toString();
            }
            if (data['driver_name'] != null && data['driver_name'].toString().isNotEmpty) {
              _driverName = data['driver_name'].toString();
            }
            if (data['driver_phone'] != null && data['driver_phone'].toString().isNotEmpty) {
              _driverPhone = data['driver_phone'].toString();
            }
            if (data['vehicle_number'] != null && data['vehicle_number'].toString().isNotEmpty) {
              _vehicleNumber = data['vehicle_number'].toString();
            }
            if (data['vehicle_type'] != null && data['vehicle_type'].toString().isNotEmpty) {
              _vehicleType = data['vehicle_type'].toString();
            }
          });
        }
      }
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════
  //  SECURE SOCKET SETUP — validates orderId before use
  // ══════════════════════════════════════════════════════

  void _initSocket() {
    final safeOrderId = widget.orderId.trim();
    final rawDigits = safeOrderId.replaceAll(RegExp(r'\D'), '');
    final orderCode = rawDigits.isNotEmpty ? 'ORD-$rawDigits' : safeOrderId;
    final paddedOrderCode = rawDigits.isNotEmpty ? 'ORD-${rawDigits.padLeft(6, '0')}' : safeOrderId;

    final apiBase = ApiConstants.baseUrl;
    final wsUrl = apiBase.endsWith('/api')
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;

    _socket = io.io(
      wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(_maxReconnectAttempts)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .setTimeout(10000)
          .build(),
    );

    _socket!.onConnect((_) {
      if (!mounted) return;
      setState(() {
        _isConnected = true;
        _reconnectCount = 0;
      });
      // Join all order room variations
      _socket!.emit('join:order', {'orderId': safeOrderId});
      _socket!.emit('join:order', {'orderId': orderCode});
      _socket!.emit('join:order', {'orderId': paddedOrderCode});
      if (rawDigits.isNotEmpty) {
        _socket!.emit('join:order', {'orderId': rawDigits});
      }
      debugPrint('✅ Tracking socket connected | Order: $safeOrderId');
    });

    _socket!.onDisconnect((_) {
      if (!mounted) return;
      setState(() => _isConnected = false);
      debugPrint('❌ Tracking socket disconnected');
    });

    _socket!.onReconnectAttempt((attempt) {
      if (!mounted) return;
      setState(() => _reconnectCount = (attempt as int?) ?? 0);
    });

    _socket!.onConnectError((error) {
      debugPrint('Socket connect error: $error');
    });

    _socket!.onError((error) {
      debugPrint('Socket error: $error');
    });

    // ── Global broadcast (order:status_update) ──
    _socket!.on('order:status_update', (data) {
      if (!mounted || data is! Map) return;
      final incomingId = data['orderId']?.toString() ?? data['rawOrderId']?.toString() ?? '';
      if (!_matchesOrderId(incomingId, widget.orderId)) return;
      _handleStatusChange(data);
    });

    // ── Per-order status channel (room-based) ──
    _socket!.on('order:$safeOrderId:status', (data) {
      if (!mounted || data is! Map) return;
      _handleStatusChange(data);
    });
    _socket!.on('order:$orderCode:status', (data) {
      if (!mounted || data is! Map) return;
      _handleStatusChange(data);
    });
    _socket!.on('order:$paddedOrderCode:status', (data) {
      if (!mounted || data is! Map) return;
      _handleStatusChange(data);
    });

    // ── Driver location updates (from driver-app) ──
    _socket!.on('order:$safeOrderId:location', (data) {
      if (!mounted || data is! Map) return;
      _handleLocationUpdate(data);
    });
    _socket!.on('order:$orderCode:location', (data) {
      if (!mounted || data is! Map) return;
      _handleLocationUpdate(data);
    });
    _socket!.on('order:$paddedOrderCode:location', (data) {
      if (!mounted || data is! Map) return;
      _handleLocationUpdate(data);
    });

    // ── Driver assigned notification ──
    _socket!.on('order:$safeOrderId:driver_assigned', (data) {
      if (!mounted || data is! Map) return;
      _handleDriverAssigned(data);
    });
    _socket!.on('order:$orderCode:driver_assigned', (data) {
      if (!mounted || data is! Map) return;
      _handleDriverAssigned(data);
    });
    _socket!.on('order:$paddedOrderCode:driver_assigned', (data) {
      if (!mounted || data is! Map) return;
      _handleDriverAssigned(data);
    });

    // ── Driver unassigned / searching notification (e.g. driver on hold) ──
    _socket!.on('order:$safeOrderId:driver_unassigned', (data) {
      if (!mounted || data is! Map) return;
      _handleDriverUnassigned(data);
    });
    _socket!.on('order:$orderCode:driver_unassigned', (data) {
      if (!mounted || data is! Map) return;
      _handleDriverUnassigned(data);
    });
    _socket!.on('order:$paddedOrderCode:driver_unassigned', (data) {
      if (!mounted || data is! Map) return;
      _handleDriverUnassigned(data);
    });

    // ── Merchant info update ──
    _socket!.on('order:$safeOrderId:merchant_update', (data) {
      if (!mounted || data is! Map) return;
      setState(() {
        final name = data['merchantName']?.toString() ?? '';
        if (name.isNotEmpty && name.length <= 80) _merchantName = name;
        final phone = data['merchantPhone']?.toString() ?? '';
        if (phone.isNotEmpty) _merchantPhone = phone;
        final branch = data['branchName']?.toString() ?? '';
        if (branch.isNotEmpty) _branchName = branch;
      });
    });

    // ── ETA update from driver-app ──
    _socket!.on('order:$safeOrderId:eta_update', (data) {
      if (!mounted || data is! Map) return;
      final mins = (data['remainingMinutes'] as num?)?.toInt();
      if (mins != null && mins > 0 && mins <= 180) {
        setState(() => _remainingMinutes = mins);
      }
    });
    // ── Dynamic Handover OTP updates ──
    _socket!.on('order:otp_generated', (data) {
      if (!mounted || data is! Map) return;
      final incomingId = data['orderId']?.toString() ?? '';
      if (!_matchesOrderId(incomingId, widget.orderId)) return;
      setState(() {
        if (data['deliveryOtp'] != null) _deliveryOtp = data['deliveryOtp'].toString();
        if (data['otp'] != null) _deliveryOtp = data['otp'].toString();
        _otpSecondsRemaining = (data['expiresInSeconds'] as num?)?.toInt() ?? 60;
      });
    });
    _socket!.on('order:$safeOrderId:otp_generated', (data) {
      if (!mounted || data is! Map) return;
      setState(() {
        if (data['deliveryOtp'] != null) _deliveryOtp = data['deliveryOtp'].toString();
        if (data['otp'] != null) _deliveryOtp = data['otp'].toString();
        _otpSecondsRemaining = (data['expiresInSeconds'] as num?)?.toInt() ?? 60;
      });
    });
    _socket!.on('order:$orderCode:otp_generated', (data) {
      if (!mounted || data is! Map) return;
      setState(() {
        if (data['deliveryOtp'] != null) _deliveryOtp = data['deliveryOtp'].toString();
        if (data['otp'] != null) _deliveryOtp = data['otp'].toString();
        _otpSecondsRemaining = (data['expiresInSeconds'] as num?)?.toInt() ?? 60;
      });
    });
  }

  void _handleLocationUpdate(Map data) {
    setState(() {
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
        _riderLat = lat;
        _riderLng = lng;
      }
      final name = data['driverName']?.toString() ?? '';
      if (name.isNotEmpty && name.length <= 60) _driverName = name;
      final phone = data['phone']?.toString() ?? '';
      if (phone.isNotEmpty) _driverPhone = phone;
      final code = data['driverCode']?.toString() ?? '';
      if (code.isNotEmpty) _driverCode = code;
      final veh = data['vehicleNumber']?.toString() ?? '';
      if (veh.isNotEmpty) _vehicleNumber = veh;
      final type = data['vehicleType']?.toString() ?? '';
      if (type.isNotEmpty) _vehicleType = type;
    });
  }

  void _handleDriverAssigned(Map data) {
    setState(() {
      final name = data['driverName']?.toString() ?? '';
      if (name.isNotEmpty) _driverName = name;
      final phone = data['phone']?.toString() ?? data['driverPhone']?.toString() ?? '';
      if (phone.isNotEmpty) _driverPhone = phone;
      final code = data['driverCode']?.toString() ?? '';
      if (code.isNotEmpty) _driverCode = code;
      final veh = data['vehicleNumber']?.toString() ?? '';
      if (veh.isNotEmpty) _vehicleNumber = veh;
      final type = data['vehicleType']?.toString() ?? '';
      if (type.isNotEmpty) _vehicleType = type;
    });
    _showNotificationSnackBar('🏍️ Delivery partner assigned! ${data['driverName'] ?? ''}');
  }

  void _handleDriverUnassigned(Map data) {
    setState(() {
      _driverName = 'Searching for nearby rider...';
      _driverPhone = '';
      _driverCode = '';
      _vehicleNumber = '';
      _vehicleType = 'Bike';
      _riderLat = null;
      _riderLng = null;
    });
    _showNotificationSnackBar('🔍 Finding a new nearby delivery partner for your order...');
  }

  void _handleStatusChange(Map<dynamic, dynamic> data) {
    final newStatus = OrderStatus.fromString(data['status']?.toString() ?? '');
    HapticFeedback.mediumImpact();
    setState(() {
      _status = newStatus;
      if (data['isSearchingDriver'] == true || (data['driverName'] != null && data['driverName'].toString().trim().isEmpty)) {
        _driverName = 'Searching for nearby rider...';
        _driverPhone = '';
        _driverCode = '';
        _vehicleNumber = '';
        _vehicleType = 'Bike';
        _riderLat = null;
        _riderLng = null;
      } else {
        if (data['driverName'] != null && data['driverName'].toString().isNotEmpty) _driverName = data['driverName'].toString();
        if (data['driverPhone'] != null) _driverPhone = data['driverPhone'].toString();
        if (data['vehicleNumber'] != null) _vehicleNumber = data['vehicleNumber'].toString();
        if (data['vehicleType'] != null) _vehicleType = data['vehicleType'].toString();
      }
      if (data['deliveryOtp'] != null && data['deliveryOtp'].toString().isNotEmpty) {
        _deliveryOtp = data['deliveryOtp'].toString();
      }
      if (data['otp'] != null && data['otp'].toString().isNotEmpty) {
        _deliveryOtp = data['otp'].toString();
      }
      if (!_timestamps.any((t) => t.status == newStatus)) {
        _timestamps.add(_StepTimestamp(newStatus, DateTime.now()));
      }
    });

    if (newStatus == OrderStatus.delivered) {
      _etaTimer?.cancel();
      _otpCountdownTimer?.cancel();
      final now = DateTime.now();
      for (final s in OrderStatus.values) {
        if (s != OrderStatus.cancelled && s.stepIndex >= 0 && s.stepIndex <= OrderStatus.delivered.stepIndex) {
          if (!_timestamps.any((t) => t.status == s)) {
            _timestamps.add(_StepTimestamp(s, now));
          }
        }
      }
      if (!_hasShownRating) {
        _hasShownRating = true;
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) _showRatingBottomSheet();
        });
      }
    }

    // Animate hero on status change
    _heroController.reset();
    _heroController.forward();
    _showNotificationSnackBar(_status.subLabel);
  }

  void _startEtaCountdown() {
    _etaTimer?.cancel();
    _etaTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      if (_isTerminal) {
        _etaTimer?.cancel();
        return;
      }
      if (_remainingMinutes > 1) {
        setState(() => _remainingMinutes--);
      }
    });
  }

  void _showNotificationSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: _orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ──── Helpers ────

  static const _stepStatuses = [
    OrderStatus.placed,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.headingToRestaurant,
    OrderStatus.atRestaurant,
    OrderStatus.outForDelivery,
    OrderStatus.atCustomerDoorstep,
    OrderStatus.delivered,
  ];

  String get _etaText {
    if (_status == OrderStatus.delivered) return 'Delivered! Enjoy your meal 🎉';
    if (_status == OrderStatus.cancelled) return 'This order was cancelled';
    if (_remainingMinutes <= 2) return 'Arriving any moment now! 🚀';
    return 'Arrives in $_remainingMinutes min${_remainingMinutes == 1 ? '' : 's'}';
  }

  bool get _isTerminal =>
      _status == OrderStatus.delivered || _status == OrderStatus.cancelled;

  bool get _hasDriver =>
      _driverName != 'Assigning a nearby rider...' &&
      _driverName != 'Searching for nearby rider...' &&
      _driverName.trim().isNotEmpty;

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ══════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgGrey,
      appBar: _buildAppBar(),
      body: SlideTransition(
        position: _slideOffset,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          child: Column(
            children: [
              _buildStatusHeroCard(),
              const SizedBox(height: 20),
              if (!_isTerminal) ...[
                _buildDeliveryOtpCard(),
                const SizedBox(height: 20),
                _buildEtaBadgeRow(),
                const SizedBox(height: 20),
              ],
              _buildVerticalStepper(),
              const SizedBox(height: 20),
              _buildDriverCard(),
              const SizedBox(height: 20),
              _buildPaymentAndQrCard(),
              const SizedBox(height: 20),
              _buildMerchantCard(),
              if (!_isTerminal) ...[
                const SizedBox(height: 20),
                _buildCancelOrderButton(),
              ],
              if (_status == OrderStatus.cancelled) ...[
                const SizedBox(height: 20),
                _buildCancelledBanner(),
              ],
              if (_status == OrderStatus.outForDelivery && _riderLat != null) ...[
                const SizedBox(height: 20),
                _buildLiveLocationCard(),
              ],
              if (!_isConnected && !_isTerminal) ...[
                const SizedBox(height: 20),
                _buildReconnectBanner(),
              ],
              if (_status == OrderStatus.delivered) ...[
                const SizedBox(height: 20),
                _buildDeliveredCard(),
              ],
              const SizedBox(height: 20),
              _buildSupportCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  APP BAR
  // ══════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: AppColors.pureWhite,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order Tracking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(
            '#${widget.orderId}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        GestureDetector(
          onTap: () => _socket?.connect(),
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (_isConnected ? Colors.green : Colors.red).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (_isConnected ? Colors.green : Colors.red).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, child) => Opacity(
                    opacity: _isConnected ? 0.4 + (_pulseController.value * 0.6) : 1.0,
                    child: child,
                  ),
                  child: Icon(
                    Icons.circle,
                    size: 8,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _isConnected ? 'LIVE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: _isConnected ? Colors.green.shade700 : Colors.red.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════
  //  HERO STATUS CARD
  // ══════════════════════════════════════════════════════

  Widget _buildStatusHeroCard() {
    final isCancelled = _status == OrderStatus.cancelled;
    final isDelivered = _status == OrderStatus.delivered;

    final gradient = isCancelled
        ? LinearGradient(colors: [Colors.red.shade600, Colors.red.shade400])
        : isDelivered
            ? const LinearGradient(colors: [Color(0xFF0F8A65), Color(0xFF16B37C)])
            : AppColors.brandGradient;

    final shadowColor = isCancelled ? Colors.red : isDelivered ? const Color(0xFF0F8A65) : _orange;

    return ScaleTransition(
      scale: _heroScale,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // Animated icon
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
                child: child,
              ),
              child: Container(
                key: ValueKey(_status),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(_status.icon, color: Colors.white, size: 42),
              ),
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(
                _status.displayLabel,
                key: ValueKey('label-${_status.name}'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status.subLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (!_isTerminal) ...[
              const SizedBox(height: 20),
              _buildMiniProgressBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniProgressBar() {
    final progress = (_status.stepIndex + 1) / _stepStatuses.length;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Step ${_status.stepIndex + 1} of ${_stepStatuses.length}',
          style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════
  //  DELIVERY CONFIRMATION OTP CARD (Compact 4-Box PIN)
  // ══════════════════════════════════════════════════════

  Widget _buildDeliveryOtpCard() {
    final otpDigits = _deliveryOtp.trim().padRight(4, '•').split('').take(4).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.orange.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.pin_rounded, color: _orange, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Delivery Handover OTP',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFF9A3412),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Clipboard.setData(ClipboardData(text: _deliveryOtp));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Delivery OTP $_deliveryOtp copied to clipboard!'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: const Color(0xFF0F8A65),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.copy_rounded, color: _orange, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'COPY',
                        style: TextStyle(
                          color: _orange,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 4 Compact PIN boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final digit = index < otpDigits.length ? otpDigits[index] : '•';
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 44,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.shade400,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.12),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _orange,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          // Countdown & Refresh Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 12, color: _orange),
                    const SizedBox(width: 4),
                    Text(
                      'Valid for ${_otpSecondsRemaining}s',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _isRegeneratingOtp ? null : _regenerateOtp,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isRegeneratingOtp
                          ? const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: _orange),
                            )
                          : const Icon(Icons.refresh_rounded, size: 12, color: Colors.black87),
                      const SizedBox(width: 4),
                      const Text(
                        'Refresh OTP',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '🔒 Share this 4-digit code with your rider upon arrival to complete delivery handover.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF78350F),
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  DOORSTEP PAYMENT & RESTAURANT QR CARD
  // ══════════════════════════════════════════════════════

  Widget _buildPaymentAndQrCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.payments_rounded, color: _orange, size: 22),
                  SizedBox(width: 8),
                  Text('Doorstep Payment Option', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Cash / Online UPI', style: TextStyle(color: _orange, fontWeight: FontWeight.w800, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'You can pay with Cash on delivery or scan the Restaurant UPI QR Code directly on your phone.',
            style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _orange, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.qr_code_2_rounded, color: _orange),
              label: const Text(
                'PAY ONLINE VIA RESTAURANT UPI QR',
                style: TextStyle(color: _orange, fontWeight: FontWeight.w900, fontSize: 12),
              ),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(height: 18),
                        const Text('Restaurant Direct UPI QR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 4),
                        const Text('Scan with GPay, PhonePe, or Paytm', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.shade300, width: 2),
                          ),
                          child: Image.network(
                            'https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=upi://pay?pa=rameez@okaxis&pn=RameezKitchen',
                            height: 190,
                            width: 190,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('UPI ID: rameez@okaxis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _orange, minimumSize: const Size.fromHeight(46)),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('DONE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  // ══════════════════════════════════════════════════════
  //  ETA BADGE ROW
  // ══════════════════════════════════════════════════════

  Widget _buildEtaBadgeRow() {
    return Row(
      children: [
        Expanded(
          child: _InfoBadge(
            icon: Icons.access_time_rounded,
            label: 'ETA',
            value: _etaText,
            color: _orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoBadge(
            icon: Icons.receipt_long_rounded,
            label: 'Order',
            value: '#${widget.orderId}',
            color: Colors.indigo,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════
  //  VERTICAL STEPPER WITH TIMESTAMPS
  // ══════════════════════════════════════════════════════

  Widget _buildVerticalStepper() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.timeline_rounded, color: _orange, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Order Progress',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ..._stepStatuses.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value;
            final isLast = idx == _stepStatuses.length - 1;
            final timestamp = _timestamps
                .where((t) => t.status == step)
                .firstOrNull;
            return _buildStepRow(step, isLast, timestamp);
          }),
        ],
      ),
    );
  }

  Widget _buildStepRow(OrderStatus step, bool isLast, _StepTimestamp? timestamp) {
    final currentIdx = _status.stepIndex;
    final stepIdx = step.stepIndex;

    final isCompleted = currentIdx > stepIdx;
    final isActive = currentIdx == stepIdx && !_isTerminal;
    final isPending = !isCompleted && !isActive;

    final Color dotColor;
    if (isCompleted) {
      dotColor = Colors.green;
    } else if (isActive) {
      dotColor = _orange;
    } else {
      dotColor = Colors.grey.shade200;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Dot / circle
                Container(
                  width: isActive ? 32 : 24,
                  height: isActive ? 32 : 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    border: isActive
                        ? Border.all(color: _orange.withValues(alpha: 0.35), width: 5)
                        : null,
                    boxShadow: isActive
                        ? [BoxShadow(color: _orange.withValues(alpha: 0.4), blurRadius: 10)]
                        : isCompleted
                            ? [BoxShadow(color: Colors.green.withValues(alpha: 0.35), blurRadius: 8)]
                            : null,
                  ),
                  child: isCompleted
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                      : isActive
                          ? AnimatedBuilder(
                              animation: _pulseController,
                              builder: (_, _) => Icon(
                                Icons.circle,
                                color: Colors.white.withValues(alpha: 0.6 + _pulseController.value * 0.4),
                                size: 8,
                              ),
                            )
                          : null,
                ),
                // Connector line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        gradient: isCompleted
                            ? const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.green, Color(0xFFB8F5D8)],
                              )
                            : null,
                        color: !isCompleted ? Colors.grey.shade100 : null,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Content column
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        step.displayLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isActive || isCompleted ? FontWeight.w800 : FontWeight.w500,
                          color: isPending
                              ? Colors.grey.shade400
                              : isCompleted
                                  ? AppColors.textDark
                                  : _orange,
                        ),
                      ),
                      if (timestamp != null)
                        Text(
                          _formatTime(timestamp.time),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCompleted ? Colors.green.shade600 : _orange,
                          ),
                        ),
                    ],
                  ),
                  if (isActive) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _orange,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'In progress...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  DRIVER CARD — connected to driver-app events
  // ══════════════════════════════════════════════════════

  Widget _buildDriverCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delivery_dining_rounded, color: Colors.indigo, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Delivery Partner',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              if (_hasDriver) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 7, color: Colors.green.shade600),
                      const SizedBox(width: 4),
                      Text('On Route', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (!_hasDriver)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, child) => Transform.scale(
                      scale: 0.88 + _pulseController.value * 0.22,
                      child: child,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.radar_rounded, color: Color(0xFFD97706), size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Searching for Nearby Rider 🔍',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF92400E)),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Auto-dispatching the nearest available delivery partner to your kitchen order.',
                          style: TextStyle(fontSize: 11, color: Color(0xFFB45309), height: 1.25),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                // Avatar
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_orange, _orangeLight]),
                    boxShadow: [BoxShadow(color: _orange.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                  child: Center(
                    child: Text(
                      _driverName.substring(0, math.min(1, _driverName.length)).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
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
                          Flexible(
                            child: Text(
                              _driverName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppColors.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.verified_rounded, size: 16, color: Colors.blue),
                        ],
                      ),
                      if (_driverCode.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'ID: $_driverCode',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                        ),
                      ],
                      if (_vehicleNumber.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.two_wheeler_rounded, size: 13, color: Colors.amber.shade700),
                              const SizedBox(width: 5),
                              Text(
                                _vehicleType.isNotEmpty ? '$_vehicleNumber • $_vehicleType' : _vehicleNumber,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber.shade800,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Call button
                if (_driverPhone.isNotEmpty)
                  _PhoneButton(phone: _driverPhone, label: 'Call Rider'),
              ],
            ),
          if (_riderLat != null && _riderLng != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, child) => Transform.scale(
                      scale: 0.9 + _pulseController.value * 0.2,
                      child: child,
                    ),
                    child: const Icon(Icons.gps_fixed_rounded, size: 16, color: Colors.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Live GPS tracking active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.green)),
                        const SizedBox(height: 2),
                        Text(
                          '${_riderLat!.toStringAsFixed(5)}, ${_riderLng!.toStringAsFixed(5)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
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
    );
  }

  // ══════════════════════════════════════════════════════
  //  MERCHANT CARD — connected to merchant-app events
  // ══════════════════════════════════════════════════════

  Widget _buildMerchantCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.store_rounded, color: _orange, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Restaurant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: AppColors.brandGradient,
                ),
                child: const Center(
                  child: Text('RK', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _merchantName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _branchName,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_merchantPhone.isNotEmpty)
                _PhoneButton(phone: _merchantPhone, label: 'Call Kitchen'),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  LIVE LOCATION MAP PLACEHOLDER
  // ══════════════════════════════════════════════════════

  Widget _buildLiveLocationCard() {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.blue.shade600],
        ),
        boxShadow: [
          BoxShadow(color: Colors.blue.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          // Map grid decoration
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: CustomPaint(
              painter: _MapGridPainter(),
              size: const Size(double.infinity, 160),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, child) => Transform.scale(
                    scale: 0.9 + _pulseController.value * 0.15,
                    child: child,
                  ),
                  child: const Icon(Icons.location_pin, color: Colors.red, size: 42),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Driver is nearby — Live tracking active',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Real-time GPS from driver app 📡',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════
  //  ORDER CANCELLATION & DYNAMIC CHARGES
  // ══════════════════════════════════════════════════════

  double _calculateCancellationFee() {
    return switch (_status) {
      OrderStatus.placed => 0.0,
      OrderStatus.confirmed || OrderStatus.preparing => 50.0,
      OrderStatus.headingToRestaurant ||
      OrderStatus.atRestaurant ||
      OrderStatus.outForDelivery ||
      OrderStatus.atCustomerDoorstep => 100.0,
      _ => 0.0,
    };
  }

  Widget _buildCancelOrderButton() {
    final fee = _calculateCancellationFee();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade700,
          side: BorderSide(color: Colors.red.shade300, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
        label: Text(
          fee > 0
              ? 'CANCEL ORDER (₹${fee.toInt()} Policy Charge Applies)'
              : 'CANCEL ORDER (Free Cancellation)',
          style: TextStyle(
            color: Colors.red.shade800,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        onPressed: _showCancelOrderDialog,
      ),
    );
  }

  void _showCancelOrderDialog() {
    final fee = _calculateCancellationFee();
    final wallet = context.read<WalletProvider>();
    String selectedReason = 'Change in meal plans / ordered elsewhere';
    final reasons = [
      'Change in meal plans / ordered elsewhere',
      'Placed order by mistake',
      'Order is taking longer than expected',
      'Incorrect delivery address entered',
      'Other reason'
    ];
    bool isCancelling = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final balanceAfter = wallet.balance - fee;
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cancel Order Confirmation',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Please review our cancellation policy below',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Cancellation Policy Fee Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: fee > 0 ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: fee > 0 ? Colors.red.shade200 : Colors.green.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              fee > 0 ? 'Cancellation Fee Applied' : 'Free Cancellation',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: fee > 0 ? Colors.red.shade900 : Colors.green.shade900,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              fee > 0 ? '₹${fee.toStringAsFixed(0)}' : '₹0 (FREE)',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: fee > 0 ? Colors.red.shade800 : Colors.green.shade800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          fee == 0
                              ? 'Your order has not yet been accepted by the kitchen. No cancellation charges apply.'
                              : fee == 50
                                  ? 'Kitchen has already begun cooking your fresh order. A ₹50 preparation fee is deducted from your wallet.'
                                  : 'A delivery rider is already dispatched on route. A ₹100 dispatch compensation is deducted from your wallet.',
                          style: TextStyle(
                            fontSize: 12,
                            color: fee > 0 ? Colors.red.shade900 : Colors.green.shade900,
                            height: 1.3,
                          ),
                        ),
                        if (fee > 0) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Rameez Wallet Balance:', style: TextStyle(fontSize: 12, color: Colors.black87)),
                              Text('₹${wallet.balance.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Balance After Deduction:', style: TextStyle(fontSize: 12, color: Colors.black87)),
                              Text(
                                '₹${balanceAfter.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: balanceAfter >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Select Cancellation Reason', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 8),
                  ...reasons.map((r) {
                    final isSelected = selectedReason == r;
                    return InkWell(
                      onTap: () => setModalState(() => selectedReason = r),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: isSelected ? _orange : Colors.grey.shade400,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                r,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? Colors.black87 : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // Actions
                  ElevatedButton(
                    onPressed: isCancelling
                        ? null
                        : () async {
                            setModalState(() => isCancelling = true);
                            try {
                              if (fee > 0) {
                                await wallet.deduct(fee, reason: 'Cancellation Fee for Order #${widget.orderId}');
                              }
                              await http.post(
                                Uri.parse('${ApiConstants.baseUrl}/orders/${widget.orderId}/cancel'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'fee': fee,
                                  'reason': selectedReason,
                                }),
                              );
                              _socket?.emit('order:status_update', {
                                'orderId': widget.orderId,
                                'status': 'CANCELLED',
                                'fee': fee,
                                'reason': selectedReason,
                              });
                            } catch (_) {}

                            if (!mounted) return;
                            setState(() {
                              _status = OrderStatus.cancelled;
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showNotificationSnackBar(
                              fee > 0
                                  ? 'Order cancelled. ₹${fee.toInt()} deducted from your wallet.'
                                  : 'Order cancelled with ₹0 charges.',
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isCancelling
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            fee > 0 ? 'CONFIRM & DEDUCT ₹${fee.toInt()}' : 'CONFIRM CANCELLATION',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('KEEP MY ORDER', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════
  //  DELIVERED CARD & CUSTOMER RATING WITH WALLET TIPS
  // ══════════════════════════════════════════════════════

  void _showRatingBottomSheet() {
    int selectedStars = 5;
    double selectedTip = 0.0;
    final Set<String> selectedTags = {};
    final commentCtrl = TextEditingController();
    bool isSubmitting = false;

    final tags = [
      '⚡ Super Fast',
      '😊 Polite Rider',
      '🍲 Hot & Fresh Food',
      '📦 Sealed & Clean Pack',
      '📍 Followed Map Directions'
    ];

    final tipOptions = [0.0, 10.0, 20.0, 50.0, 100.0];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final wallet = context.watch<WalletProvider>();

            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
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
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Center(
                      child: Text(
                        'Rate Your Delivery Rider',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _driverName.isNotEmpty && _driverName != 'Assigning a nearby rider...'
                            ? 'How was your delivery experience with $_driverName?'
                            : 'How was your delivery experience with Rameez Kitchen?',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 5 Interactive Stars
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        return IconButton(
                          iconSize: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          icon: Icon(
                            starIndex <= selectedStars ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: starIndex <= selectedStars ? const Color(0xFFFFB800) : Colors.grey.shade300,
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            setModalState(() => selectedStars = starIndex);
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 14),

                    // Compliments Tag Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: tags.map((t) {
                        final isSelected = selectedTags.contains(t);
                        return FilterChip(
                          label: Text(
                            t,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? _orange : Colors.black87,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: _orange.withValues(alpha: 0.12),
                          checkmarkColor: _orange,
                          backgroundColor: Colors.grey.shade100,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: isSelected ? _orange : Colors.transparent),
                          ),
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                selectedTags.add(t);
                              } else {
                                selectedTags.remove(t);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // Rider Tip Selection
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.volunteer_activism_rounded, color: _orange, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Add a Tip for Rider',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                ],
                              ),
                              if (selectedTip > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '+₹${selectedTip.toInt()}',
                                    style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: tipOptions.map((tip) {
                              final isSelected = selectedTip == tip;
                              final label = tip == 0 ? 'No Tip' : '₹${tip.toInt()}';
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setModalState(() => selectedTip = tip);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? _orange : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? _orange : Colors.grey.shade300,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: _orange.withValues(alpha: 0.2),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          if (selectedTip > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '💳 Tip of ₹${selectedTip.toInt()} will be paid from your Rameez Wallet (Balance: ₹${wallet.balance.toStringAsFixed(2)})',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: commentCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Add an optional note or compliment for the driver...',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _orange)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              try {
                                if (selectedTip > 0) {
                                  await wallet.deduct(selectedTip, reason: 'Driver Tip for Order #${widget.orderId}');
                                }
                                final payload = {
                                  'orderId': widget.orderId,
                                  'driverName': _driverName,
                                  'driverCode': _driverCode,
                                  'rating': selectedStars,
                                  'tip': selectedTip,
                                  'feedback': commentCtrl.text.trim(),
                                  'tags': selectedTags.toList(),
                                };

                                await http.post(
                                  Uri.parse('${ApiConstants.baseUrl}/driver/ratings'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode(payload),
                                );
                                await http.post(
                                  Uri.parse('${ApiConstants.baseUrl}/driver/rate'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode(payload),
                                );
                                _socket?.emit('driver:rating_received', payload);
                              } catch (_) {}

                              if (!mounted) return;
                              if (ctx.mounted) Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    selectedTip > 0
                                        ? '⭐ Thank you! Your $selectedStars-star rating and ₹${selectedTip.toInt()} tip were sent to $_driverName!'
                                        : '⭐ Thank you for rating $_driverName $selectedStars stars!',
                                  ),
                                  backgroundColor: const Color(0xFF0F8A65),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              );
                              if (mounted && Navigator.canPop(context)) {
                                Navigator.of(context).pop();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isSubmitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(
                              selectedTip > 0
                                  ? 'SUBMIT RATING & TIP (₹${selectedTip.toInt()})'
                                  : 'SUBMIT DRIVER RATING',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
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

  Widget _buildDeliveredCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 52),
          const SizedBox(height: 12),
          const Text(
            'Order Delivered Successfully!',
            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Thank you for ordering from Rameez Kitchen. Enjoy your meal! 🍽️',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showRatingBottomSheet,
            icon: const Icon(Icons.star_rounded),
            label: const Text('Rate Your Delivery Driver & Tip'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  CANCELLED BANNER
  // ══════════════════════════════════════════════════════

  Widget _buildCancelledBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.redAccent, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order Cancelled',
                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.redAccent, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'If you were charged, a refund will be processed within 3–5 business days.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  RECONNECT BANNER
  // ══════════════════════════════════════════════════════

  Widget _buildReconnectBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.amber, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live tracking paused',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.amber.shade900),
                ),
                if (_reconnectCount > 0)
                  Text(
                    'Reconnect attempt $_reconnectCount/$_maxReconnectAttempts...',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade700),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _socket?.connect();
            },
            child: const Text('RETRY', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  SUPPORT CARD
  // ══════════════════════════════════════════════════════

  Widget _buildSupportCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.headset_mic_rounded, color: _orange, size: 20),
              const SizedBox(width: 10),
              const Text('Need Help?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showSupportMsg = !_showSupportMsg),
                child: Icon(
                  _showSupportMsg ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          if (_showSupportMsg) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'If your order is late or you have any issues, please contact our support team. We\'re available 9 AM – 11 PM daily.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                final url = Uri.parse('tel:+918073349233');
                if (await canLaunchUrl(url)) await launchUrl(url);
              },
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Contact Support'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  REUSABLE INFO BADGE
// ══════════════════════════════════════════════════════

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  REUSABLE PHONE BUTTON
// ══════════════════════════════════════════════════════

class _PhoneButton extends StatelessWidget {
  final String phone;
  final String label;

  const _PhoneButton({required this.phone, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        final url = Uri.parse('tel:$phone');
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
        } else {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open phone dialer for $phone'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.phone_rounded, color: Colors.green, size: 22),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  MAP GRID BACKGROUND PAINTER
// ══════════════════════════════════════════════════════

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    const spacing = 24.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}