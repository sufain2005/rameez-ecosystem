import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'theme.dart';
import 'deliveries_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _home;
  Map<String, dynamic>? _offer;
  List<Map<String, dynamic>> _reviews = [];
  String? _error;
  bool _toggling = false;
  bool _acting = false;
  Timer? _poll;
  Timer? _alarmTimer;
  Timer? _countdownTimer;
  int _secondsRemaining = 30;
  bool _isAlarmPlaying = false;
  bool _isMuted = false;
  String? _lastAlertOfferId;
  String? _readyPickupNotice;
  IO.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _initSocket();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  void _initSocket() {
    try {
      _socket = IO.io('http://localhost:5000', IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .disableAutoConnect()
        .build());
      _socket?.connect();
      _socket?.on('driver:pickup_ready', (data) {
        final msg = data is Map ? (data['message'] ?? 'Food is packed and ready for pickup from restaurant!') : 'Food is packed and ready for pickup from restaurant!';
        if (mounted) {
          setState(() => _readyPickupNotice = msg.toString());
          _snack('📦 $msg');
          HapticFeedback.heavyImpact();
        }
      });
      _socket?.on('offers:updated', (_) {
        if (mounted) _refresh();
      });
      _socket?.on('order:status_update', (data) {
        if (data is Map && (data['status'] == 'READY_FOR_PICKUP' || data['status'] == 'READY')) {
          final orderId = data['orderId'] ?? '';
          final msg = 'Order #$orderId is PACKED & READY for pickup at Restaurant!';
          if (mounted) {
            setState(() => _readyPickupNotice = msg);
            _snack('📦 $msg');
            HapticFeedback.heavyImpact();
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    _alarmTimer?.cancel();
    _countdownTimer?.cancel();
    try {
      _socket?.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1E1E22),
    ));
  }

  // ──── Authentic Vintage Old Telephone Double-Bell Ring Synthesizer ────
  void _playOldTelephoneRing() {
    try {
      js.context.callMethod('eval', [
        '''
        (function() {
          try {
            var AudioContext = window.AudioContext || window.webkitAudioContext;
            if (!AudioContext) return;
            var ctx = window._drvAudioCtx || new AudioContext();
            window._drvAudioCtx = ctx;
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

              // 20Hz rapid mechanical hammer oscillation
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

  void _startAlarm() {
    if (_isMuted || _isAlarmPlaying) return;
    _isAlarmPlaying = true;
    _playOldTelephoneRing();
    HapticFeedback.heavyImpact();

    _alarmTimer?.cancel();
    _alarmTimer = Timer.periodic(const Duration(milliseconds: 2400), (t) {
      if (!_isAlarmPlaying || _isMuted || _offer == null) {
        t.cancel();
        _isAlarmPlaying = false;
      } else {
        _playOldTelephoneRing();
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _stopAlarm() {
    _alarmTimer?.cancel();
    _isAlarmPlaying = false;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _offer == null || _offer!['offer_status'] != 'PENDING') {
        t.cancel();
        return;
      }
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        }
      });
      if (_secondsRemaining <= 0) {
        t.cancel();
        _autoCascadeOffer();
      }
    });
  }

  Future<void> _autoCascadeOffer() async {
    final o = _offer;
    if (o == null || o['offer_status'] != 'PENDING') return;
    _stopAlarm();
    try {
      await Api.post('/offers/${o['offer_id']}/decline');
      _snack('⏳ 30s Window expired. Offer transferred to the next available live driver.');
    } catch (_) {}
    if (mounted) {
      setState(() => _offer = null);
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final h = Map<String, dynamic>.from(await Api.get('/home'));
      Map<String, dynamic>? offer;
      if (h['status'] == 'ONLINE') {
        final o = await Api.get('/offers/current');
        if (o != null) offer = Map<String, dynamic>.from(o);
      }
      if (!mounted) return;

      final offerId = offer?['offer_id']?.toString();
      final isNewOffer = offer != null && (offer['offer_status'] == 'PENDING') && (offerId != _lastAlertOfferId || _offer == null);

      setState(() {
        _home = h;
        _error = null;
        _offer = offer;
      });

      if (isNewOffer) {
        _lastAlertOfferId = offerId;
        _secondsRemaining = (offer['seconds_remaining'] as num?)?.toInt() ?? 30;
        _startAlarm();
        _startCountdown();
      } else if (offer == null || offer['offer_status'] == 'ON_HOLD') {
        _stopAlarm();
        _countdownTimer?.cancel();
      }

      // Fetch driver customer reviews and tips
      try {
        final res = await http.get(Uri.parse('http://localhost:5000/api/driver/ratings'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map && data['ratings'] is List) {
            final list = List<Map<String, dynamic>>.from(data['ratings']);
            if (mounted) setState(() => _reviews = list);
          }
        }
      } catch (_) {}
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    final goOnline = _home?['status'] != 'ONLINE';
    setState(() => _toggling = true);
    try {
      await Api.post('/status', {'status': goOnline ? 'ONLINE' : 'OFFLINE'});
      await _refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _accept() async {
    final o = _offer;
    if (o == null) return;
    _stopAlarm();
    _countdownTimer?.cancel();
    setState(() => _acting = true);
    try {
      await Api.post('/offers/${o['offer_id']}/accept');
      setState(() => _offer = null);
      await _refresh();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DeliveriesScreen()),
        ).then((_) => _refresh());
      }
    } on ApiException catch (e) {
      _snack(e.message);
      await _refresh();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _holdOffer() async {
    final o = _offer;
    if (o == null) return;
    _stopAlarm();
    _countdownTimer?.cancel();
    setState(() => _acting = true);
    try {
      await Api.post('/offers/${o['offer_id']}/hold');
      _snack('⏳ Offer kept on hold. You can accept it after finishing your ongoing delivery.');
      await _refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _decline() async {
    final o = _offer;
    if (o == null) return;
    _stopAlarm();
    _countdownTimer?.cancel();
    setState(() => _acting = true);
    try {
      await Api.post('/offers/${o['offer_id']}/decline');
      setState(() => _offer = null);
      _snack('Offer declined. Automatically transferring to next driver.');
      await _refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _openGoogleMapsRoute(String destAddress) async {
    final o = _offer;
    String destination = Uri.encodeComponent(destAddress.isNotEmpty ? destAddress : 'Rameez Kitchen, 60 Feet Ring Road');
    
    if (o != null) {
      final lat = o['pickup_lat'];
      final lng = o['pickup_lng'];
      if (lat != null && lng != null && lat != 0 && lng != 0) {
        destination = '$lat,$lng';
      }
    }
    
    // Don't set origin so it uses the driver's current location
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _home;
    if (h == null) {
      return Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off, size: 48, color: AppColors.muted),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _refresh, child: const Text('RETRY')),
                ]),
              )
            : const CircularProgressIndicator(color: AppColors.orange),
      );
    }

    final online = h['status'] == 'ONLINE';
    final active = h['active_delivery'];

    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_readyPickupNotice != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade400, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.green.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
                    child: const Icon(Icons.takeout_dining_rounded, color: Colors.green, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('KITCHEN READY FOR PICKUP!', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(_readyPickupNotice!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.green),
                    onPressed: () => setState(() => _readyPickupNotice = null),
                  ),
                ],
              ),
            ),
          ],

          // ---------- header ----------
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.orange, AppColors.golden]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(color: AppColors.orange.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text(
                      'RAMEEZ KITCHEN',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      h['name'] ?? 'Driver',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'ID: ${h['driver_code'] ?? ''}',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
                Column(children: [
                  Switch(
                    value: online,
                    onChanged: _toggling ? null : (_) => _toggle(),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.online,
                  ),
                  Text(
                    online ? 'ONLINE' : 'OFFLINE',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---------- online status card ----------
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  Icon(Icons.circle, size: 16, color: online ? AppColors.online : AppColors.offline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        online ? "You're Online & Ready" : "You're Offline",
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        online ? 'Ready to receive kitchen delivery requests with telephone alarm.' : "Go online to start receiving delivery requests.",
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                online
                    ? OutlinedButton(
                        onPressed: _toggling ? null : _toggle,
                        child: const Text('GO OFFLINE'),
                      )
                    : ElevatedButton(
                        onPressed: _toggling ? null : _toggle,
                        child: const Text('GO ONLINE'),
                      ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ---------- stats ----------
          Row(children: [
            Expanded(
              child: _StatCard(
                icon: Icons.account_balance_wallet,
                label: "Today's Earnings",
                value: rupees((h['today_earnings'] as num?) ?? 0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.check_circle,
                label: 'Deliveries',
                value: '${h['today_deliveries'] ?? 0}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.star_rounded,
                label: 'Rating',
                value: '⭐ ${(h['rating'] as num?)?.toStringAsFixed(1) ?? '5.0'}',
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ---------- new / held request card ----------
          if (online && _offer != null) _offerCard(_offer!),

          // ---------- active delivery ----------
          const Text('Current Active Delivery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: active == null
                  ? const Row(children: [
                      Icon(Icons.inbox_outlined, color: AppColors.muted, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('No active delivery right now.', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                      ),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('ORD-${active['order_id']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        StatusChip(active['status']),
                      ]),
                      if (active['customer_name'] != null) ...[
                        const SizedBox(height: 6),
                        Text('Customer: ${active['customer_name']}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      ],
                      if (active['delivery_address'] != null) ...[
                        const SizedBox(height: 4),
                        Text('📍 ${active['delivery_address']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const DeliveriesScreen()),
                                ).then((_) => _refresh());
                              },
                              icon: const Icon(Icons.navigation),
                              label: const Text('OPEN LIVE NAVIGATION'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _openGoogleMapsRoute(active['delivery_address']?.toString() ?? ''),
                            tooltip: 'Open Easiest Route in Google Maps',
                            icon: const Icon(Icons.map, color: AppColors.orange),
                          ),
                        ],
                      ),
                    ]),
            ),
          ),
          const SizedBox(height: 20),

          // ---------- Customer Reviews, Ratings & Tips Feed ----------
          _buildCustomerReviewsSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCustomerReviewsSection() {
    double totalTips = 0.0;
    for (var r in _reviews) {
      final t = (r['tip'] as num?)?.toDouble() ?? 0.0;
      totalTips += t;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Row(
                children: [
                  Icon(Icons.rate_review_rounded, color: AppColors.orange, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Customer Reviews & Tips',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (totalTips > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volunteer_activism_rounded, color: Colors.green, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Tips: ₹${totalTips.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (_reviews.isEmpty)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.star_border_rounded, size: 36, color: AppColors.muted),
                    SizedBox(height: 8),
                    Text(
                      'No Customer Reviews Yet',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Ratings and tips received upon delivering orders will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ..._reviews.map((r) => _buildReviewCard(r)),
      ],
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> r) {
    final custName = r['customerName'] ?? 'Customer';
    final orderId = r['orderId'] ?? '';
    final rating = (r['rating'] as num?)?.toDouble() ?? 5.0;
    final tip = (r['tip'] as num?)?.toDouble() ?? 0.0;
    final feedback = r['feedback']?.toString() ?? '';
    final dateStr = r['date']?.toString();
    final tags = (r['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];

    String timeAgo = 'Recent';
    if (dateStr != null) {
      try {
        final dt = DateTime.parse(dateStr).toLocal();
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeAgo = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeAgo = '${diff.inHours}h ago';
        } else {
          timeAgo = DateFormat('dd MMM, hh:mm a').format(dt);
        }
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.orange.withValues(alpha: 0.12),
                      child: Text(
                        custName.isNotEmpty ? custName[0].toUpperCase() : 'C',
                        style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            custName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (orderId.isNotEmpty)
                            Text(
                              orderId,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (idx) {
                      return Icon(
                        idx < rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: idx < rating.round() ? const Color(0xFFFFB800) : Colors.grey.shade300,
                        size: 16,
                      );
                    }),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeAgo,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
          if (tip > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.volunteer_activism_rounded, color: Colors.green, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '💰 Tip Received: +₹${tip.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (feedback.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"$feedback"',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade800,
                height: 1.3,
              ),
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tags.map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    t,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.orange),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _offerCard(Map<String, dynamic> o) {
    final isOnHold = o['offer_status'] == 'ON_HOLD';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isOnHold ? AppColors.golden : AppColors.orange, width: 2),
        boxShadow: [
          BoxShadow(
            color: (isOnHold ? AppColors.golden : AppColors.orange).withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            isOnHold ? Icons.pause_circle_outline : Icons.notifications_active,
            color: isOnHold ? Colors.amber.shade800 : AppColors.orange,
            size: 26,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOnHold ? 'DELIVERY REQUEST ON HOLD' : '🔔 NEW DELIVERY REQUEST',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: isOnHold ? Colors.amber.shade900 : AppColors.orange,
              ),
            ),
          ),
          // Mute / Sound indicator button
          IconButton(
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: AppColors.muted, size: 22),
            tooltip: _isMuted ? 'Unmute telephone ring' : 'Mute ring',
            onPressed: () {
              setState(() => _isMuted = !_isMuted);
              if (_isMuted) _stopAlarm();
            },
          ),
        ]),
        const SizedBox(height: 10),

        if (!isOnHold) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _secondsRemaining <= 10 ? Colors.red.shade50 : AppColors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _secondsRemaining <= 10 ? Colors.red.shade400 : AppColors.orange.withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, color: _secondsRemaining <= 10 ? Colors.red : AppColors.orange, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Auto-transfer in: $_secondsRemaining s',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: _secondsRemaining <= 10 ? Colors.red.shade900 : AppColors.orange,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _secondsRemaining <= 10 ? '🚨 EXPIRING SOON' : '⚡ 30s WINDOW',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        color: _secondsRemaining <= 10 ? Colors.red : AppColors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_secondsRemaining / 30.0).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(_secondsRemaining <= 10 ? Colors.red : AppColors.orange),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (isOnHold)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You put this order on hold. Tap Accept when ready to deliver.',
                    style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

        _kv(Icons.receipt_long, 'Order ID', o['order_code'] ?? 'ORD-${o['order_id']}'),
        _kv(Icons.store, 'Pickup Point', o['pickup_address'] ?? '60 Feet Ring Road'),
        _kv(Icons.location_on, 'Drop Address', o['delivery_address'] ?? 'Customer Address'),
        if (o['distance_km'] != null)
          _kv(Icons.alt_route, 'Easiest Route', '${(o['distance_km'] as num).toStringAsFixed(1)} km (~${o['est_minutes'] ?? 15} mins)'),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.golden.withOpacity(.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.payments, color: AppColors.orange, size: 24),
            const SizedBox(width: 8),
            const Text('Driver Earning', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const Spacer(),
            Text(
              rupees((o['base_earning'] as num?) ?? 25),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.orange),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ──── 3 Actions: Accept, Hold / Wait, Decline ────
        ElevatedButton(
          onPressed: _acting ? null : _accept,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _acting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isOnHold ? 'RESUME & ACCEPT ORDER' : 'ACCEPT', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        ),
        const SizedBox(height: 10),

        if (!isOnHold) ...[
          OutlinedButton.icon(
            onPressed: _acting ? null : _holdOffer,
            icon: const Icon(Icons.hourglass_top, color: Colors.amber, size: 18),
            label: const Text('WAIT TO COMPLETE ANOTHER ORDER', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w800, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.amber.shade700, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
        ],

        OutlinedButton(
          onPressed: _acting ? null : _decline,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.danger),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('DECLINE', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _kv(IconData i, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ]),
      );
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(children: [
          Icon(icon, color: AppColors.orange, size: 24),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}