import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../data/models/cart_item.dart';
import '../data/models/menu_item.dart';

class _Coupon {
  final double percent;
  final double? maxDiscount; // e.g. 150.0 to cap the saving; null = no cap
  final double minSubtotal;
  const _Coupon(this.percent, {this.maxDiscount, this.minSubtotal = 0});
}

class CartProvider extends ChangeNotifier {
  // ---------- rules (display only, the SERVER recalculates at order time) ----------
  static const double freeDeliveryAbove = 500.0;
  static const double deliveryFeeFlat = 40.0;
  static const int maxTip = 500;
  static const int maxDistinctItems = 40;

  // Same discounts as before. Add maxDiscount / minSubtotal if you want limits.
  static const Map<String, _Coupon> _coupons = {
    'RAMEEZ50': _Coupon(0.50),
    'WELCOME20': _Coupon(0.20),
  };

  final Map<int, CartItem> _items = {};
  String? _appliedCoupon;
  int _tip = 0;
  String? _couponError;

  /// Read-only view: screens must use addItem / removeItem so the rules always apply.
  Map<int, CartItem> get items => UnmodifiableMapView(_items);
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  String? get appliedCoupon => _activeCoupon == null ? null : _appliedCoupon;
  String? get couponError => _couponError;
  double get discountPercent => _activeCoupon?.percent ?? 0.0;
  int get tip => _tip;

  int get totalQuantity => _items.values.fold(0, (sum, i) => sum + i.quantity);

  double get subtotal => _r2(_items.values.fold(0.0, (sum, i) => sum + i.totalPrice));

  double get discountAmount {
    final c = _activeCoupon;
    if (c == null) return 0.0;
    var d = _r2(subtotal * c.percent);
    final cap = c.maxDiscount;
    if (cap != null && d > cap) d = cap;
    return d > subtotal ? subtotal : d;
  }

  double get deliveryFee =>
      subtotal > 0 ? (subtotal > freeDeliveryAbove ? 0.0 : deliveryFeeFlat) : 0.0;

  double get grandTotal => _r2(subtotal - discountAmount + deliveryFee + _tip);
  double get totalAmount => grandTotal;

  // ---------- cart actions ----------
  /// Returns false if the item is unavailable or a limit was reached.
  bool addItem(MenuItem item) {
    if (!item.isAvailable) return false;
    final existing = _items[item.id];
    if (existing != null) {
      if (!existing.canIncrease) return false;
      existing.quantity += 1;
    } else {
      if (_items.length >= maxDistinctItems) return false;
      _items[item.id] = CartItem(item: item);
    }
    notifyListeners();
    return true;
  }

  void removeItem(int itemId) {
    final existing = _items[itemId];
    if (existing == null) return;
    if (existing.quantity > 1) {
      existing.quantity -= 1;
    } else {
      _items.remove(itemId);
    }
    if (_items.isEmpty) _resetExtras();
    notifyListeners();
  }

  /// Removes the whole line regardless of quantity.
  void deleteItem(int itemId) {
    if (_items.remove(itemId) == null) return;
    if (_items.isEmpty) _resetExtras();
    notifyListeners();
  }

  // ---------- coupon ----------
  bool applyCoupon(String code) {
    final c = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{3,20}$').hasMatch(c)) {
      _couponError = 'Enter a valid coupon code.';
      notifyListeners();
      return false;
    }
    final coupon = _coupons[c];
    if (coupon == null) {
      _couponError = 'This coupon is not valid.';
      notifyListeners();
      return false;
    }
    if (subtotal <= 0) {
      _couponError = 'Add items to your cart first.';
      notifyListeners();
      return false;
    }
    if (subtotal < coupon.minSubtotal) {
      _couponError = 'Add items worth ₹${coupon.minSubtotal.toStringAsFixed(0)} to use this coupon.';
      notifyListeners();
      return false;
    }
    _appliedCoupon = c;
    _couponError = null;
    notifyListeners();
    return true;
  }

  void removeCoupon() {
    _appliedCoupon = null;
    _couponError = null;
    notifyListeners();
  }

  // ---------- tip for the driver ----------
  void setTip(int amount) {
    _tip = amount < 0 ? 0 : (amount > maxTip ? maxTip : amount);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _resetExtras();
    notifyListeners();
  }

  // ---------- order payload ----------
  /// The app sends only IDs, quantities, the coupon code and the tip.
  /// `expected_total` lets the server warn "prices changed", but the server
  /// must never trust it: it recalculates everything itself.
  Map<String, dynamic> toOrderJson() => {
        'items': _items.values.map((c) => c.toOrderJson()).toList(),
        if (_activeCoupon != null) 'coupon': _appliedCoupon,
        'tip': _tip,
        'expected_total': grandTotal,
      };

  // ---------- internals ----------
  _Coupon? get _activeCoupon {
    final code = _appliedCoupon;
    if (code == null) return null;
    final c = _coupons[code];
    if (c == null || subtotal < c.minSubtotal) return null;
    return c;
  }

  void _resetExtras() {
    _appliedCoupon = null;
    _couponError = null;
    _tip = 0;
  }

  static double _r2(double v) => double.parse(v.toStringAsFixed(2));
}