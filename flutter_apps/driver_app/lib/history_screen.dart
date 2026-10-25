import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _loading = true);
    try {
      final res = await Api.get('/history?range=$_selectedFilter');
      if (!mounted) return;
      if (res is List) {
        setState(() {
          _history = res.map((e) => Map<String, dynamic>.from(e)).toList();
          _error = null;
          _loading = false;
        });
      } else {
        setState(() { _error = null; _loading = false; });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Unable to load delivery history'; _loading = false; });
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final timeStr = '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
      if (isToday) return 'Today, $timeStr';
      return '${dt.day}/${dt.month}/${dt.year}, $timeStr';
    } catch (_) {
      return raw.toString().split('T').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalEarned = 0;
    for (var item in _history) {
      totalEarned += ((item['earning'] as num?) ?? 0).toDouble();
    }

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Completed Deliveries', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
      ),
      body: Column(
        children: [
          // Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip('all', 'All Deliveries'),
                const SizedBox(width: 8),
                _filterChip('today', 'Today'),
                const SizedBox(width: 8),
                _filterChip('week', 'This Week'),
                const Spacer(),
                if (_history.isNotEmpty)
                  Text(
                    'Total: ${rupees(totalEarned)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.orange, fontSize: 13),
                  ),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.muted),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                            const SizedBox(height: 16),
                            ElevatedButton(onPressed: _fetchHistory, child: const Text('RETRY')),
                          ]),
                        ),
                      )
                    : _history.isEmpty
                        ? RefreshIndicator(
                            color: AppColors.orange,
                            onRefresh: _fetchHistory,
                            child: ListView(
                              children: [
                                SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.5,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: AppColors.orange.withOpacity(0.08),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.history_rounded, size: 56, color: AppColors.muted),
                                        ),
                                        const SizedBox(height: 18),
                                        const Text('No deliveries in this period', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
                                        const SizedBox(height: 6),
                                        const Text('Completed delivery records will appear here', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.orange,
                            onRefresh: _fetchHistory,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _history.length,
                              itemBuilder: (context, index) {
                                final item = _history[index];
                                final orderId = item['order_code'] ?? 'ORD-${item['order_id']}';
                                final status = item['status']?.toString() ?? 'DELIVERED';
                                final earning = (item['earning'] as num?) ?? 0;
                                final tip = (item['tip'] as num?) ?? 0;
                                final dateStr = _formatDate(item['date'] ?? item['delivered_at']);
                                final custName = item['customer_name'] ?? 'Customer';
                                final address = item['delivery_address']?.toString() ?? 'Davangere';
                                final distance = item['distance_km'] != null ? '${(item['distance_km'] as num).toStringAsFixed(1)} km' : '3.5 km';
                                final rating = (item['rating'] as num?)?.toDouble() ?? 5.0;
                                final feedback = item['feedback']?.toString() ?? '';
                                final tags = (item['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
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
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                                              ),
                                              const SizedBox(width: 10),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(orderId, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                                  Row(
                                                    children: [
                                                      Text(status, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 11)),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.amber.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.amber.shade300, width: 0.8),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                                                            const SizedBox(width: 2),
                                                            Text(
                                                              rating.toStringAsFixed(1),
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.w900,
                                                                color: Colors.amber.shade900,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppColors.orange.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              rupees(earning),
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.orange),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      const Divider(height: 1),
                                      const SizedBox(height: 10),

                                      Row(
                                        children: [
                                          const Icon(Icons.person_pin_circle_outlined, size: 16, color: AppColors.muted),
                                          const SizedBox(width: 6),
                                          Text(custName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                          const Spacer(),
                                          const Icon(Icons.route, size: 16, color: AppColors.muted),
                                          const SizedBox(width: 4),
                                          Text(distance, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_outlined, size: 16, color: AppColors.muted),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              address,
                                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),

                                      if (tags.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: tags.map((t) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.orange.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppColors.orange.withOpacity(0.25)),
                                            ),
                                            child: Text(
                                              t,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.orange,
                                              ),
                                            ),
                                          )).toList(),
                                        ),
                                      ],

                                      if (feedback.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF9FAFB),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade200),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.format_quote_rounded, size: 14, color: AppColors.muted),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  feedback,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontStyle: FontStyle.italic,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],

                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w500)),
                                          if (tip > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.green.shade200),
                                              ),
                                              child: Text('Tip +${rupees(tip)}', style: TextStyle(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.w800)),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _selectedFilter = key);
        _fetchHistory();
      },
      selectedColor: AppColors.orange,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.text,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        fontSize: 12,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}