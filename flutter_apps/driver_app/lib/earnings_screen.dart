import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchEarnings();
  }

  Future<void> _fetchEarnings() async {
    setState(() => _loading = true);
    try {
      final d = Map<String, dynamic>.from(await Api.get('/home'));
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Failed to load earnings'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.orange));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetchEarnings, child: const Text('RETRY')),
        ]),
      );
    }

    final todayEarnings = (_data?['today_earnings'] as num?) ?? 0;
    final todayDeliveries = (_data?['today_deliveries'] as num?) ?? 0;
    final rating = (_data?['rating'] as num?)?.toDouble() ?? 0.0;

    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: _fetchEarnings,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header gradient card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.orange, AppColors.golden]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: AppColors.orange.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 42),
                const SizedBox(height: 12),
                const Text("TODAY'S EARNINGS", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Text(
                  rupees(todayEarnings),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 38),
                ),
                const SizedBox(height: 6),
                Text(
                  '$todayDeliveries deliveries completed',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stats row
          Row(children: [
            Expanded(child: _StatTile(icon: Icons.delivery_dining_rounded, label: 'Total Trips', value: '$todayDeliveries', color: AppColors.accepted)),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(icon: Icons.star_rounded, label: 'Rating', value: rating > 0 ? '⭐ ${rating.toStringAsFixed(1)}' : '—', color: AppColors.golden)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _StatTile(icon: Icons.payments_rounded, label: 'Avg / Trip', value: todayDeliveries > 0 ? rupees(todayEarnings / todayDeliveries) : '—', color: AppColors.online)),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(icon: Icons.trending_up_rounded, label: 'Tip Earned', value: rupees(0), color: AppColors.pending)),
          ]),
          const SizedBox(height: 24),

          // Weekly summary
          const Text('Weekly Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ...List.generate(7, (i) {
            final day = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i];
            final isToday = i == DateTime.now().weekday - 1;
            final amount = isToday ? todayEarnings : 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isToday ? AppColors.orange.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isToday ? AppColors.orange.withOpacity(0.3) : const Color(0xFFE6DCCB)),
              ),
              child: Row(children: [
                Text(day, style: TextStyle(fontWeight: FontWeight.w800, color: isToday ? AppColors.orange : AppColors.text)),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(6)),
                    child: const Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                  ),
                ],
                const Spacer(),
                Text(rupees(amount), style: TextStyle(fontWeight: FontWeight.w900, color: amount > 0 ? AppColors.orange : AppColors.muted)),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6DCCB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}