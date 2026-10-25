import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';

class WalletTransaction {
  final String id;
  final double amount;
  final String type; // 'CREDIT' or 'DEBIT'
  final String title;
  final DateTime date;
  final double balanceAfter;

  WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.title,
    required this.date,
    required this.balanceAfter,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id']?.toString() ?? 'tx_${DateTime.now().millisecondsSinceEpoch}',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      type: json['type']?.toString().toUpperCase() ?? 'CREDIT',
      title: json['title']?.toString() ?? 'Transaction',
      date: json['date'] != null ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now() : DateTime.now(),
      balanceAfter: (json['balanceAfter'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class WalletProvider extends ChangeNotifier {
  double _balance = 500.0;
  List<WalletTransaction> _transactions = [
    WalletTransaction(
      id: 'tx_welcome',
      amount: 500.0,
      type: 'CREDIT',
      title: 'Welcome Promotional Bonus',
      date: DateTime.now().subtract(const Duration(days: 2)),
      balanceAfter: 500.0,
    ),
  ];
  bool _loading = false;

  double get balance => _balance;
  List<WalletTransaction> get transactions => _transactions;
  bool get isLoading => _loading;

  WalletProvider() {
    fetchWallet();
  }

  Future<void> fetchWallet() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/customer/wallet'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['wallet'] != null) {
          _balance = (data['wallet']['balance'] as num?)?.toDouble() ?? _balance;
          if (data['wallet']['transactions'] is List) {
            _transactions = (data['wallet']['transactions'] as List)
                .map((t) => WalletTransaction.fromJson(t))
                .toList();
          }
        }
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<bool> topUp(double amount, {String note = 'Wallet Top-up via UPI'}) async {
    if (amount <= 0) return false;
    try {
      final res = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/customer/wallet/topup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': amount, 'note': note}),
      );
      if (res.statusCode == 200) {
        await fetchWallet();
        return true;
      }
    } catch (_) {}

    // Local fallback
    _balance += amount;
    _transactions.insert(
      0,
      WalletTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        amount: amount,
        type: 'CREDIT',
        title: note,
        date: DateTime.now(),
        balanceAfter: _balance,
      ),
    );
    notifyListeners();
    return true;
  }

  Future<bool> deduct(double amount, {String reason = 'Order Cancellation Charge'}) async {
    if (amount <= 0) return false;
    try {
      final res = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/customer/wallet/deduct'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': amount, 'reason': reason}),
      );
      if (res.statusCode == 200) {
        await fetchWallet();
        return true;
      }
    } catch (_) {}

    // Local fallback
    _balance -= amount;
    _transactions.insert(
      0,
      WalletTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        amount: amount,
        type: 'DEBIT',
        title: reason,
        date: DateTime.now(),
        balanceAfter: _balance,
      ),
    );
    notifyListeners();
    return true;
  }

  Future<bool> debit(double amount, [String reason = 'Payment']) =>
      deduct(amount, reason: reason);
}
