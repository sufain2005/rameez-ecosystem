import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'theme.dart';
import 'shell.dart';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> with SingleTickerProviderStateMixin {
  bool isLoading = true;
  Map<String, dynamic>? delivery;
  String currentStatus = 'ACCEPTED';
  IO.Socket? socket;
  Timer? locationTimer;
  Map<String, dynamic> driverInfo = {};
  late AnimationController _pulseController;

  final List<String> statusProgression = [
    'ACCEPTED',
    'GOING_TO_RESTAURANT',
    'ARRIVED_RESTAURANT',
    'PICKED_UP',
    'ON_THE_WAY',
    'ARRIVED_CUSTOMER',
    'OTP_VERIFIED',
    'DELIVERED'
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    loadDelivery();
    initSocket();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    locationTimer?.cancel();
    socket?.disconnect();
    socket?.dispose();
    super.dispose();
  }

  Future<void> loadDelivery() async {
    try {
      final res = await Api.get('/home');
      if (res != null) {
        if (mounted) {
          setState(() {
            driverInfo = {
              'driverName': res['name'] ?? 'Driver',
              'driverCode': res['driver_code'] ?? 'D001',
              'phone': '9876543210',
              'vehicleNumber': 'KA-01-AB-1234',
              'vehicleType': 'Bike'
            };
            if (res['active_delivery'] != null) {
              delivery = res['active_delivery'];
              currentStatus = delivery!['status'] ?? 'ACCEPTED';
              if (!statusProgression.contains(currentStatus)) {
                currentStatus = 'ACCEPTED';
              }
              startLocationUpdates(delivery!['delivery_id']?.toString() ?? delivery!['_id']?.toString() ?? '1');
            }
            isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading delivery: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  void initSocket() {
    try {
      socket = IO.io('https://rameez-kitchen-backend.onrender.com', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      });
      socket?.connect();
    } catch (e) {
      debugPrint('Socket init error: $e');
    }
  }

  void startLocationUpdates(String orderId) {
    locationTimer?.cancel();
    locationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      final random = Random();
      final lat = 14.4644 + (random.nextDouble() * 0.01 - 0.005);
      final lng = 75.9218 + (random.nextDouble() * 0.01 - 0.005);

      final rawDigits = orderId.replaceAll(RegExp(r'\D'), '');
      final orderCode = rawDigits.isNotEmpty ? 'ORD-$rawDigits' : orderId;
      final paddedOrderCode = rawDigits.isNotEmpty ? 'ORD-${rawDigits.padLeft(6, '0')}' : orderId;

      final locData = {
        'orderId': orderCode,
        'latitude': lat,
        'longitude': lng,
        'driverName': driverInfo['driverName'],
        'driverCode': driverInfo['driverCode'],
        'phone': driverInfo['phone'],
        'vehicleNumber': driverInfo['vehicleNumber'],
        'vehicleType': driverInfo['vehicleType'],
      };

      socket?.emit('driver:location_update', locData);
      socket?.emit('driver:location_update', {'orderId': paddedOrderCode, ...locData});
      if (rawDigits.isNotEmpty) {
        socket?.emit('driver:location_update', {'orderId': rawDigits, ...locData});
      }
    });
  }

  void emitEta(String orderId, int minutes) {
    final rawDigits = orderId.replaceAll(RegExp(r'\D'), '');
    final orderCode = rawDigits.isNotEmpty ? 'ORD-$rawDigits' : orderId;
    final paddedOrderCode = rawDigits.isNotEmpty ? 'ORD-${rawDigits.padLeft(6, '0')}' : orderId;

    socket?.emit('driver:eta_update', {'orderId': orderCode, 'remainingMinutes': minutes});
    socket?.emit('driver:eta_update', {'orderId': paddedOrderCode, 'remainingMinutes': minutes});
    if (rawDigits.isNotEmpty) {
      socket?.emit('driver:eta_update', {'orderId': rawDigits, 'remainingMinutes': minutes});
    }
  }

  Future<void> updateStatus(String newStatus) async {
    HapticFeedback.mediumImpact();
    setState(() {
      currentStatus = newStatus;
    });

    if (delivery != null) {
      final deliveryId = delivery!['delivery_id']?.toString() ?? delivery!['_id']?.toString() ?? '';
      final rawOrderId = delivery!['order_id']?.toString() ?? deliveryId;
      final rawDigits = rawOrderId.replaceAll(RegExp(r'\D'), '');
      final orderCode = delivery!['order_code']?.toString() ?? (rawDigits.isNotEmpty ? 'ORD-$rawDigits' : 'ORD-$rawOrderId');
      final paddedOrderCode = rawDigits.isNotEmpty ? 'ORD-${rawDigits.padLeft(6, '0')}' : orderCode;

      final statusPayload = {
        'orderId': orderCode,
        'rawOrderId': rawDigits,
        'paddedOrderId': paddedOrderCode,
        'deliveryId': deliveryId,
        'status': newStatus,
        'driverName': driverInfo['driverName'],
        'driverCode': driverInfo['driverCode'],
        'driverPhone': driverInfo['phone'],
        'vehicleNumber': driverInfo['vehicleNumber'],
        'vehicleType': driverInfo['vehicleType'],
      };

      // Broadcast globally to all channels
      socket?.emit('order:status_update', statusPayload);
      socket?.emit('order:status_update', {'orderId': paddedOrderCode, ...statusPayload});
      if (rawDigits.isNotEmpty) {
        socket?.emit('order:status_update', {'orderId': rawDigits, ...statusPayload});
      }

      int eta = 15;
      if (newStatus == 'ARRIVED_RESTAURANT') eta = 10;
      if (newStatus == 'PICKED_UP') eta = 8;
      if (newStatus == 'ON_THE_WAY') eta = 5;
      if (newStatus == 'ARRIVED_CUSTOMER') eta = 1;
      if (newStatus == 'DELIVERED') eta = 0;

      emitEta(orderCode, eta);

      try {
        if (deliveryId.isNotEmpty) {
          await Api.post('/deliveries/$deliveryId/advance', {});
        }
        await Api.post('/orders/$orderCode/status', {'status': newStatus, ...statusPayload});
        await Api.post('/orders/$paddedOrderCode/status', {'status': newStatus, ...statusPayload});
      } catch (_) {}
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Future<void> _openGoogleMapsEasiestRoute(String destAddress) async {
    final origin = Uri.encodeComponent('Rameez Kitchen, 60 Feet Ring Road');
    final destination = Uri.encodeComponent(destAddress.isNotEmpty ? destAddress : 'Customer Location');
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&travelmode=driving');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening Navigation Route...')),
        );
      }
    }
  }

  Future<void> _openGoogleMapsNavigation({required String phase}) async {
    final d = delivery;
    if (d == null) return;
    
    double? destLat, destLng;
    String fallbackAddress;
    
    if (phase == 'pickup') {
      destLat = (d['pickup_lat'] as num?)?.toDouble();
      destLng = (d['pickup_lng'] as num?)?.toDouble();
      fallbackAddress = d['pickup_address']?.toString() ?? 'Rameez Kitchen';
    } else {
      destLat = (d['delivery_lat'] as num?)?.toDouble();
      destLng = (d['delivery_lng'] as num?)?.toDouble();
      fallbackAddress = d['delivery_address']?.toString() ?? 'Customer Location';
    }
    
    String destination;
    if (destLat != null && destLng != null && destLat != 0 && destLng != 0) {
      destination = '$destLat,$destLng';
    } else {
      destination = Uri.encodeComponent(fallbackAddress);
    }
    
    // Don't set origin - let Google Maps use driver's current GPS
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$destination'
      '&travelmode=driving'
      '&dir_action=navigate'
    );
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open Google Maps. Please install Google Maps app.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Navigation error: ${e.toString().substring(0, 50)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRestaurantQrDialog({String amount = '220', String customerName = 'Customer'}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.orange, size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Restaurant UPI Direct QR',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Show this QR code to the customer to collect online payment directly to Rameez Kitchen account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade200, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Image.network(
                    'https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=upi://pay?pa=rameez@okaxis&pn=RameezKitchen',
                    height: 180,
                    width: 180,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 180,
                      width: 180,
                      color: Colors.orange.shade50,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_2, size: 64, color: AppColors.orange),
                            SizedBox(height: 4),
                            Text('rameez@okaxis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: const Text(
                      'UPI ID: rameez@okaxis',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Accepted Apps: ', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                const Text('GPay • PhonePe • Paytm • BHIM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: 'rameez@okaxis'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('UPI ID copied: rameez@okaxis')),
              );
            },
            child: const Text('COPY UPI ID', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.online),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✓ Payment marked collected via Restaurant QR! Now verify OTP to finish.'),
                  backgroundColor: AppColors.online,
                ),
              );
            },
            child: const Text('DONE / CONFIRMED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _showOtpDialog() async {
    final orderId = delivery!['delivery_id']?.toString() ?? delivery!['_id']?.toString() ?? delivery!['order_id']?.toString() ?? '';
    final ctrl = TextEditingController();
    bool isVerifying = false;
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: AppColors.orange, size: 24),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Customer Handover OTP',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ask the customer for the 4-digit verification code shown on their Live Tracking Screen.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    autofocus: true,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 14),
                    decoration: InputDecoration(
                      hintText: '••••',
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      errorText: errorText,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.orange, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, size: 14, color: AppColors.muted),
                      SizedBox(width: 4),
                      Text('Ensures accurate delivery verification', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL', style: TextStyle(color: AppColors.muted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final inputOtp = ctrl.text.trim();
                          if (inputOtp.length != 4) {
                            setDialogState(() => errorText = 'Please enter 4 digits');
                            return;
                          }

                          setDialogState(() {
                            isVerifying = true;
                            errorText = null;
                          });

                          try {
                            final verifyRes = await Api.post(
                              '/deliveries/$orderId/verify-otp',
                              {'otp': inputOtp},
                            );

                            if (mounted) {
                              Navigator.pop(dialogContext);
                              await updateStatus('DELIVERED');

                              final baseEarn = verifyRes?['base_earning'] ?? 25;
                              final tipEarn = verifyRes?['tip_amount'] ?? 0;
                              final totalEarn = verifyRes?['total_earning'] ?? (baseEarn + tipEarn);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.white),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '🎉 Delivery Verified & Completed! ₹$totalEarn Credited to Wallet',
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: AppColors.online,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              );
                              goToTab(context, 0);
                            }
                          } on ApiException catch (e) {
                            setDialogState(() {
                              isVerifying = false;
                              errorText = e.message;
                            });
                          } catch (e) {
                            setDialogState(() {
                              isVerifying = false;
                              errorText = 'Verification failed. Try again.';
                            });
                          }
                        },
                  child: isVerifying
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('VERIFY & COMPLETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleNextStep() {
    final currentIndex = statusProgression.indexOf(currentStatus);
    if (currentIndex < statusProgression.length - 1) {
      final nextStatus = statusProgression[currentIndex + 1];
      if (nextStatus == 'OTP_VERIFIED') {
        _showOtpDialog();
      } else {
        updateStatus(nextStatus);
      }
    }
  }

  String _getActionText() {
    switch (currentStatus) {
      case 'ACCEPTED':
        return '🏍️  HEAD TO RESTAURANT';
      case 'GOING_TO_RESTAURANT':
        return '📍  I ARRIVED AT RESTAURANT';
      case 'ARRIVED_RESTAURANT':
        return '📦  CONFIRM PICKUP';
      case 'PICKED_UP':
        return '🚀  START DELIVERY';
      case 'ON_THE_WAY':
        return '🏠  ARRIVED AT CUSTOMER';
      case 'ARRIVED_CUSTOMER':
        return '🔑  VERIFY OTP & DELIVER';
      case 'OTP_VERIFIED':
        return '⏳  COMPLETING...';
      case 'DELIVERED':
        return '✅  DELIVERED';
      default:
        return 'NEXT STEP';
    }
  }

  IconData _getStepIcon(String status) {
    switch (status) {
      case 'ACCEPTED': return Icons.check_circle_rounded;
      case 'GOING_TO_RESTAURANT': return Icons.directions_bike_rounded;
      case 'ARRIVED_RESTAURANT': return Icons.store_rounded;
      case 'PICKED_UP': return Icons.takeout_dining_rounded;
      case 'ON_THE_WAY': return Icons.delivery_dining_rounded;
      case 'ARRIVED_CUSTOMER': return Icons.location_on_rounded;
      case 'OTP_VERIFIED': return Icons.pin_rounded;
      case 'DELIVERED': return Icons.done_all_rounded;
      default: return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.orange));
    }

    if (delivery == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delivery_dining_rounded, size: 64, color: AppColors.orange),
              ),
              const SizedBox(height: 20),
              const Text('No Active Delivery', style: TextStyle(fontSize: 20, color: AppColors.text, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('Accept an incoming delivery request to start navigation', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => goToTab(context, 0),
                icon: const Icon(Icons.home_rounded),
                label: const Text('GO TO HOME SCREEN'),
              ),
            ],
          ),
        ),
      );
    }

    final currentIndex = statusProgression.indexOf(currentStatus);
    final orderId = delivery!['order_id']?.toString() ?? delivery!['_id']?.toString() ?? 'ORD';
    final customerName = delivery!['customer_name']?.toString() ?? 'Customer';
    final customerPhone = delivery!['customer_phone']?.toString() ?? '9876543210';
    final deliveryAddress = delivery!['delivery_address']?.toString() ?? 'Flat 302, Green Meadows';
    final pickupAddress = delivery!['pickup_address']?.toString() ?? '60 Feet Ring Road';
    final distanceKm = delivery!['distance_km'] != null ? '${delivery!['distance_km']} km' : '3.5 km';
    final estMinutes = delivery!['est_minutes'] != null ? '${delivery!['est_minutes']} mins' : '15 mins';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: Column(
          children: [
            // ──── Gradient Header ────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.orange, AppColors.golden],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (Navigator.canPop(context))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ORDER #ORD-$orderId',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                            ),
                            const Text(
                              'LIVE NAVIGATION & ROUTE',
                              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel(currentStatus),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (currentIndex + 1) / statusProgression.length,
                      minHeight: 6,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // ──── Scrollable Map & Content ────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. VISUAL ROUTE MAP CANVAS
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // Map Graphic Area
                        Container(
                          height: 190,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E293B), // Dark stylish Map Theme
                          ),
                          child: Stack(
                            children: [
                              // Custom Animated Route Painter
                              CustomPaint(
                                size: const Size(double.infinity, 190),
                                painter: _InteractiveRoutePainter(
                                  progress: (currentIndex + 1) / statusProgression.length,
                                  pulse: _pulseController.value,
                                ),
                              ),

                              // Map Badges & Overlay Chips
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.75),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.green.shade400, width: 1.2),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.bolt, color: Colors.greenAccent, size: 14),
                                      SizedBox(width: 4),
                                      Text('EASIEST ROUTE (VIA RING ROAD)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                    ],
                                  ),
                                ),
                              ),

                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6)],
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.timer, color: Colors.white, size: 14),
                                      const SizedBox(width: 4),
                                      Text('$distanceKm • $estMinutes', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Launch Google Maps Button
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              // Navigate to Pickup button (shown before pickup)
                              if (['ACCEPTED', 'GOING_TO_RESTAURANT', 'ARRIVED_RESTAURANT'].contains(currentStatus))
                                ElevatedButton.icon(
                                  onPressed: () => _openGoogleMapsNavigation(phase: 'pickup'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1B5E20),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    minimumSize: const Size(double.infinity, 48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 4,
                                  ),
                                  icon: const Icon(Icons.store_rounded, color: Colors.white, size: 22),
                                  label: const Text(
                                    '🧭 NAVIGATE TO PICKUP POINT',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                                  ),
                                ),
                              // Navigate to Customer button (shown after pickup)
                              if (['PICKED_UP', 'ON_THE_WAY', 'ARRIVED_CUSTOMER'].contains(currentStatus))
                                ElevatedButton.icon(
                                  onPressed: () => _openGoogleMapsNavigation(phase: 'delivery'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF5200),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    minimumSize: const Size(double.infinity, 48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 4,
                                  ),
                                  icon: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 22),
                                  label: const Text(
                                    '📍 NAVIGATE TO CUSTOMER',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                                  ),
                                ),
                              const SizedBox(height: 6),
                              // Generic Google Maps button always visible
                              OutlinedButton.icon(
                                onPressed: () => _openGoogleMapsEasiestRoute(
                                  ['PICKED_UP', 'ON_THE_WAY', 'ARRIVED_CUSTOMER'].contains(currentStatus)
                                    ? (deliveryAddress)
                                    : (pickupAddress)
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF1E293B), width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  minimumSize: const Size(double.infinity, 40),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.map_rounded, color: Color(0xFF1E293B), size: 18),
                                label: const Text(
                                  'OPEN IN GOOGLE MAPS (TEXT ADDRESS)',
                                  style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w700, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. ROUTE WAYPOINTS CARD (Pickup & Drop-off)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.alt_route, color: AppColors.orange, size: 20),
                            SizedBox(width: 8),
                            Text('Navigation Route Addresses', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Step 1: Restaurant Pickup
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
                              child: const Icon(Icons.store, color: AppColors.orange, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('STEP 1: PICKUP POINT', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                  const Text('Rameez Kitchen', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                  Text(pickupAddress, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),

                        Padding(
                          padding: const EdgeInsets.only(left: 17, top: 4, bottom: 4),
                          child: Container(
                            height: 28,
                            width: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.orange, Colors.green.shade600],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),

                        // Step 2: Customer Drop-off
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
                              child: Icon(Icons.location_on, color: Colors.green.shade700, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('STEP 2: DELIVERY DESTINATION', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                  Text(customerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                  Text(deliveryAddress, style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. CUSTOMER CONTACT & DOORSTEP ARRIVAL CARD
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: currentStatus == 'ARRIVED_CUSTOMER' ? AppColors.online : Colors.grey.shade200,
                        width: currentStatus == 'ARRIVED_CUSTOMER' ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (currentStatus == 'ARRIVED_CUSTOMER' ? AppColors.online : Colors.black).withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (currentStatus == 'ARRIVED_CUSTOMER')
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.location_on, color: AppColors.online, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'YOU ARE AT CUSTOMER LOCATION',
                                  style: TextStyle(color: AppColors.online, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: AppColors.orange.withOpacity(0.12),
                              child: const Icon(Icons.person, color: AppColors.orange, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(customerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(Icons.phone_android_rounded, size: 14, color: AppColors.muted),
                                      const SizedBox(width: 4),
                                      Text(
                                        '+91 $customerPhone',
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.online,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                                icon: const Icon(Icons.call, size: 18),
                                label: const Text('CALL CUSTOMER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                onPressed: () => _makePhoneCall(customerPhone),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.orange, width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.copy, size: 16, color: AppColors.orange),
                                label: const Text('COPY', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800, fontSize: 12)),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: customerPhone));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('✓ Phone number +91 $customerPhone copied!'),
                                      backgroundColor: AppColors.online,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 4. DOORSTEP PAYMENT & QR COLLECTION CARD
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.shade200, width: 1.5),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.payments_rounded, color: AppColors.orange, size: 22),
                                SizedBox(width: 8),
                                Text('Doorstep Collection', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('Cash on Delivery / UPI', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800, fontSize: 11)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'If customer wants to pay online at doorstep, show them the restaurant QR code. Otherwise, collect cash directly.',
                          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.orange, width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.qr_code_2, color: AppColors.orange),
                                label: const Text('SHOW RESTAURANT QR', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900, fontSize: 12)),
                                onPressed: () => _showRestaurantQrDialog(customerName: customerName),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.online,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.attach_money, color: Colors.white),
                                label: const Text('CASH COLLECTED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✓ Cash payment marked as received. Now ask customer for 4-digit OTP.'),
                                      backgroundColor: AppColors.online,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100), // spacing for sticky action button
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, -4))],
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: currentIndex >= statusProgression.length - 1 ? null : _handleNextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: Text(
              _getActionText(),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ──── Interactive Route Painter ────
class _InteractiveRoutePainter extends CustomPainter {
  final double progress;
  final double pulse;

  _InteractiveRoutePainter({required this.progress, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Grid lines for modern map styling
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 30) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double j = 0; j < size.height; j += 30) {
      canvas.drawLine(Offset(0, j), Offset(size.width, j), gridPaint);
    }

    // Waypoints
    final pStart = Offset(size.width * 0.18, size.height * 0.72);
    final pMid1 = Offset(size.width * 0.38, size.height * 0.48);
    final pMid2 = Offset(size.width * 0.65, size.height * 0.58);
    final pEnd = Offset(size.width * 0.85, size.height * 0.28);

    final path = Path()
      ..moveTo(pStart.dx, pStart.dy)
      ..cubicTo(pMid1.dx, pMid1.dy, pMid2.dx, pMid2.dy, pEnd.dx, pEnd.dy);

    // Outer road glow
    final roadGlow = Paint()
      ..color = const Color(0xFFFF5200).withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, roadGlow);

    // Road Base
    final roadPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, roadPaint);

    // Active Route Polyline (Glowing Orange / Green)
    final activePaint = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFFFF5200), Color(0xFF10B981)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, activePaint);

    // Restaurant Pin (Start)
    final restPaint = Paint()..color = const Color(0xFFFF5200);
    canvas.drawCircle(pStart, 8 + pulse * 2, Paint()..color = const Color(0xFFFF5200).withOpacity(0.35));
    canvas.drawCircle(pStart, 7, restPaint);
    canvas.drawCircle(pStart, 3, Paint()..color = Colors.white);

    // Customer Pin (End)
    final custPaint = Paint()..color = const Color(0xFF10B981);
    canvas.drawCircle(pEnd, 9 + pulse * 3, Paint()..color = const Color(0xFF10B981).withOpacity(0.35));
    canvas.drawCircle(pEnd, 8, custPaint);
    canvas.drawCircle(pEnd, 3.5, Paint()..color = Colors.white);

    // Driver Bike Location moving smoothly along progress
    final driverX = pStart.dx + (pEnd.dx - pStart.dx) * progress.clamp(0.0, 1.0);
    final driverY = pStart.dy + (pEnd.dy - pStart.dy) * progress.clamp(0.0, 1.0);
    final driverPos = Offset(driverX, driverY);

    canvas.drawCircle(driverPos, 12, Paint()..color = Colors.amber.withOpacity(0.3));
    canvas.drawCircle(driverPos, 7, Paint()..color = Colors.amber);
    canvas.drawCircle(driverPos, 3, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _InteractiveRoutePainter oldDelegate) => true;
}