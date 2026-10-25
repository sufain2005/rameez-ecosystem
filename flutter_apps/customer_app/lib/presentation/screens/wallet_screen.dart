import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../logic/wallet_provider.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  String _selectedFilter = 'ALL'; // ALL, CREDIT, DEBIT

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = _months[dt.month - 1];
    final year = dt.year;
    final hourInt = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hourInt:$min $ampm';
  }

  // ─────────────────────────────────────────────────────────────
  // DIRECT UPI APP LAUNCHER (GPay, PhonePe, Paytm, Default UPI)
  // ─────────────────────────────────────────────────────────────
  Future<void> _launchDirectUpiApp({
    required BuildContext context,
    required double amount,
    required String appName,
  }) async {
    final cleanAmt = amount.toStringAsFixed(2);
    final upiPayload =
        'pa=rameez@okaxis&pn=Rameez%20Kitchen&am=$cleanAmt&cu=INR&tn=Rameez%20Wallet%20Topup';

    String uriString;
    if (appName == 'Google Pay') {
      uriString = 'gpay://upi/pay?$upiPayload';
    } else if (appName == 'PhonePe') {
      uriString = 'phonepe://pay?$upiPayload';
    } else if (appName == 'Paytm') {
      uriString = 'paytmmp://pay?$upiPayload';
    } else {
      uriString = 'upi://pay?$upiPayload';
    }

    bool launched = false;
    try {
      final uri = Uri.parse(uriString);
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to standard generic upi scheme
        final fallbackUri = Uri.parse('upi://pay?$upiPayload');
        if (await canLaunchUrl(fallbackUri)) {
          launched = await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {
      launched = false;
    }

    if (!launched && context.mounted) {
      // If direct app link cannot be opened (e.g. on Desktop or browser with no handler), show the QR & Copy Modal
      _showQrCodeDialog(context, amount, appName);
    } else if (context.mounted) {
      _showPaymentConfirmationDialog(context, amount, appName);
    }
  }

  void _showPaymentConfirmationDialog(BuildContext context, double amount, String appName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 28),
            const SizedBox(width: 10),
            Text('Paying ₹$amount via $appName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Complete the payment in $appName and tap Confirm to credit your Rameez Wallet instantly.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security_rounded, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'UPI ID: rameez@okaxis\nMerchant: Rameez Kitchen Davanagere',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final wallet = context.read<WalletProvider>();
              await wallet.topUp(amount, note: 'Wallet Top-up ($appName)');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.shade700,
                    content: Text('🎉 ₹$amount added to Rameez Wallet via $appName!'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            child: const Text('I HAVE PAID • CONFIRM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  void _showQrCodeDialog(BuildContext context, double amount, String appName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.qr_code_2_rounded, color: AppColors.primaryOrange, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Direct UPI Payment',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textDark),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan using GPay, PhonePe, Paytm, or any UPI App to add ₹${amount.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_rounded, size: 100, color: Color(0xFF222222)),
                            const SizedBox(height: 6),
                            Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFFF5200))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(const ClipboardData(text: 'rameez@okaxis'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✓ UPI ID "rameez@okaxis" copied to clipboard!')),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'rameez@okaxis',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFFFF5200)),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.copy_rounded, size: 14, color: Color(0xFFFF5200)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final wallet = context.read<WalletProvider>();
              await wallet.topUp(amount, note: 'Wallet Top-up ($appName)');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.shade700,
                    content: Text('✓ Successfully credited ₹$amount to your Rameez Wallet!'),
                  ),
                );
              }
            },
            child: const Text('DONE • ADD TO WALLET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  void _showTopUpDialog(BuildContext context) {
    final amountCtrl = TextEditingController(text: '200');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final amtVal = double.tryParse(amountCtrl.text.trim()) ?? 0.0;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
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
                      Icon(Icons.account_balance_wallet_rounded, color: AppColors.primaryOrange, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Add Money to Rameez Wallet',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Direct checkout with GPay, PhonePe, Paytm or BHIM with instant refund guarantee.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: (_) => setSheetState(() {}),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primaryOrange),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primaryOrange),
                      labelText: 'Enter Top-Up Amount',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.primaryOrange, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Quick amount presets
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [100, 200, 500, 1000, 2000].map((amt) {
                      final isSelected = amtVal == amt.toDouble();
                      return ActionChip(
                        label: Text('+₹$amt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
                        backgroundColor: isSelected ? const Color(0xFFFF5200) : Colors.orange.shade50,
                        side: BorderSide(color: isSelected ? const Color(0xFFFF5200) : Colors.orange.shade200),
                        onPressed: () {
                          amountCtrl.text = amt.toString();
                          setSheetState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    'CHOOSE PAYMENT APP TO PAY DIRECTLY:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 10),

                  // Direct Payment App Buttons Grid
                  Row(
                    children: [
                      // Google Pay
                      Expanded(
                        child: _PaymentAppCard(
                          title: 'Google Pay',
                          icon: Icons.g_mobiledata_rounded,
                          color: const Color(0xFF4285F4),
                          onTap: () {
                            if (amtVal > 0) {
                              Navigator.pop(ctx);
                              _launchDirectUpiApp(context: context, amount: amtVal, appName: 'Google Pay');
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // PhonePe
                      Expanded(
                        child: _PaymentAppCard(
                          title: 'PhonePe',
                          icon: Icons.phone_android_rounded,
                          color: const Color(0xFF5F259F),
                          onTap: () {
                            if (amtVal > 0) {
                              Navigator.pop(ctx);
                              _launchDirectUpiApp(context: context, amount: amtVal, appName: 'PhonePe');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Paytm
                      Expanded(
                        child: _PaymentAppCard(
                          title: 'Paytm UPI',
                          icon: Icons.account_balance_rounded,
                          color: const Color(0xFF002E6E),
                          onTap: () {
                            if (amtVal > 0) {
                              Navigator.pop(ctx);
                              _launchDirectUpiApp(context: context, amount: amtVal, appName: 'Paytm');
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Any UPI
                      Expanded(
                        child: _PaymentAppCard(
                          title: 'Any UPI / QR',
                          icon: Icons.qr_code_scanner_rounded,
                          color: const Color(0xFFFF5200),
                          onTap: () {
                            if (amtVal > 0) {
                              Navigator.pop(ctx);
                              _launchDirectUpiApp(context: context, amount: amtVal, appName: 'UPI App');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Direct Instant Topup Fallback Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5200),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.flash_on_rounded, size: 20),
                    label: Text(
                      'INSTANT 1-CLICK TOP-UP (₹${amtVal > 0 ? amtVal.toStringAsFixed(0) : "0"})',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                    onPressed: amtVal <= 0
                        ? null
                        : () async {
                            final wallet = context.read<WalletProvider>();
                            await wallet.topUp(amtVal, note: 'Wallet Instant Top-up');
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.green.shade700,
                                  content: Text('✓ Successfully added ₹$amtVal to your Rameez Wallet!'),
                                ),
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final balance = wallet.balance;
    final isNegative = balance < 0;

    final filteredTxs = wallet.transactions.where((tx) {
      if (_selectedFilter == 'CREDIT') return tx.type == 'CREDIT';
      if (_selectedFilter == 'DEBIT') return tx.type == 'DEBIT';
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        centerTitle: true,
        title: const Text(
          'Rameez Wallet & UPI',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Balance',
            onPressed: () => wallet.fetchWallet(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Main Balance Card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isNegative
                    ? [Colors.red.shade700, Colors.red.shade900]
                    : [const Color(0xFFFF5200), const Color(0xFFFF7A00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: (isNegative ? Colors.red : const Color(0xFFFF5200)).withValues(alpha: 0.3),
                  blurRadius: 16,
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
                    const Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'TOTAL WALLET BALANCE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isNegative ? 'DUE CHARGES' : 'ACTIVE • READY TO USE',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  isNegative ? '-₹${balance.abs().toStringAsFixed(2)}' : '₹${balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                if (isNegative) ...[
                  const SizedBox(height: 4),
                  const Text(
                    '⚠️ Negative balance due to order cancellation charges. Please top-up to clear due.',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: isNegative ? Colors.red.shade800 : const Color(0xFFFF5200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.add_circle_rounded, size: 18),
                        label: const Text(
                          'ADD MONEY VIA UPI / GPAY',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        onPressed: () => _showTopUpDialog(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick Direct UPI App Launchers Strip
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.touch_app_rounded, color: AppColors.primaryOrange, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Direct 1-Tap App Access',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textDark),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _QuickAppChip(
                      name: 'GPay',
                      icon: Icons.g_mobiledata_rounded,
                      color: const Color(0xFF4285F4),
                      onTap: () => _launchDirectUpiApp(context: context, amount: 200, appName: 'Google Pay'),
                    ),
                    _QuickAppChip(
                      name: 'PhonePe',
                      icon: Icons.phone_android_rounded,
                      color: const Color(0xFF5F259F),
                      onTap: () => _launchDirectUpiApp(context: context, amount: 200, appName: 'PhonePe'),
                    ),
                    _QuickAppChip(
                      name: 'Paytm',
                      icon: Icons.account_balance_rounded,
                      color: const Color(0xFF002E6E),
                      onTap: () => _launchDirectUpiApp(context: context, amount: 200, appName: 'Paytm'),
                    ),
                    _QuickAppChip(
                      name: 'Scan QR',
                      icon: Icons.qr_code_scanner_rounded,
                      color: const Color(0xFFFF5200),
                      onTap: () => _showQrCodeDialog(context, 200, 'UPI Scanner'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Automatic Cancellation & Deductions Policy Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blueGrey.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.blueGrey, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Direct Wallet & Cancellation Policy',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '• Pay instantly during checkout with 1-click without repeated OTPs.\n• When cancelling an active order after food cooking begins or driver arrives at restaurant, cancellation fees (₹50 - ₹100) are securely deducted from your wallet balance.',
                        style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Transaction History Title & Filters
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transaction History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark),
              ),
              Row(
                children: ['ALL', 'CREDIT', 'DEBIT'].map((f) {
                  final isSel = _selectedFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () => setState(() => _selectedFilter = f),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFFFF5200) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          f == 'CREDIT' ? '+ Added' : f == 'DEBIT' ? '- Deducted' : 'All',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isSel ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (filteredTxs.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Center(
                child: Text('No transactions in this category.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...filteredTxs.map((tx) {
              final isCredit = tx.type == 'CREDIT';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isCredit ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: isCredit ? Colors.green.shade700 : Colors.red.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.title,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textDark),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(tx.date),
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isCredit ? "+" : "-"}₹${tx.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: isCredit ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                        Text(
                          'Bal: ₹${tx.balanceAfter.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PaymentAppCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PaymentAppCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAppChip extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAppChip({
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
          ],
        ),
      ),
    );
  }
}
