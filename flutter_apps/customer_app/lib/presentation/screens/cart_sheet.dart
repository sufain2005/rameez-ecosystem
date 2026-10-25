import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../logic/cart_provider.dart';

class CartSheet extends StatefulWidget {
  const CartSheet({super.key});

  @override
  State<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<CartSheet> {
  final TextEditingController _couponController = TextEditingController();
  final FocusNode _couponFocusNode = FocusNode();

  bool _isOrdering = false;
  bool _isCouponApplying = false;
  String? _couponError;

  String _sanitizePhone(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red : AppColors.successGreen,
        content: Text(message),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _placeOrder(CartProvider cart) async {
    if (_isOrdering) return;

    if (cart.items.isEmpty) {
      _showMessage('Your cart is empty.', isError: true);
      return;
    }

    if (cart.grandTotal <= 0) {
      _showMessage('Invalid cart total. Please retry.', isError: true);
      return;
    }

    final customerPhone = _sanitizePhone('9876543210');
    if (customerPhone.length != 10) {
      _showMessage('Customer phone is invalid.', isError: true);
      return;
    }

    setState(() => _isOrdering = true);

    try {
      final payload = {
        'customerPhone': customerPhone,
        'deliveryAddress': '124 Park Street, Flat 4B',
        'totalAmount': cart.grandTotal,
        'items': cart.items.values.map((e) => {
              'id': e.item.id,
              'name': e.item.name,
              'quantity': e.quantity,
              'price': e.item.price,
            }).toList(),
      };

      final res = await http.post(
        Uri.parse(ApiConstants.ordersEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      final isSuccess = res.statusCode >= 200 && res.statusCode < 300;

      if (!mounted) return;

      if (isSuccess) {
        cart.clearCart();
        _couponController.clear();
        _couponError = null;
        Navigator.pop(context);

        _showMessage(
          'Order placed successfully! Sent to kitchen.',
          isError: false,
        );
      } else {
        _showMessage(
          'Order failed. Please try again. (${res.statusCode})',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to place order. Please check your connection.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isOrdering = false);
      }
    }
  }

  Future<void> _applyCoupon(CartProvider cart) async {
    final enteredCode = _couponController.text.trim();

    if (enteredCode.isEmpty) {
      setState(() => _couponError = 'Please enter a promo code.');
      return;
    }

    setState(() {
      _isCouponApplying = true;
      _couponError = null;
    });

    await Future.delayed(const Duration(milliseconds: 300));

    final isValid = cart.applyCoupon(enteredCode);

    if (!mounted) return;

    setState(() {
      _isCouponApplying = false;
    });

    if (isValid) {
      _couponController.clear();
      _couponFocusNode.unfocus();
      _showMessage('Promo code applied successfully.');
    } else {
      setState(() => _couponError = 'Invalid promo code.');
      _showMessage('Invalid promo code.', isError: true);
    }
  }

  Widget _buildBillRow(String title, String value, {bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: isGreen ? AppColors.successGreen : AppColors.textDark,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isGreen ? AppColors.successGreen : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemRow(cartItem) {
    final item = cartItem.item;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${item.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryOrange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Row(
                children: [
                  _quantityButton(
                    icon: Icons.remove,
                    onPressed: () => context.read<CartProvider>().removeItem(item.id),
                    isMinus: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '${cartItem.quantity}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  _quantityButton(
                    icon: Icons.add,
                    onPressed: () => context.read<CartProvider>().addItem(item),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '₹${cartItem.totalPrice.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quantityButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool isMinus = false,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isMinus ? Colors.grey.shade100 : AppColors.primaryOrange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMinus ? Colors.grey.shade300 : AppColors.primaryOrange.withOpacity(0.2),
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isMinus ? AppColors.textDark : AppColors.primaryOrange,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFFFFFDFB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My Cart',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.textDark,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F3EF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primaryOrange, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Delivery to: 124 Park Street, Flat 4B',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  if (cart.items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Center(
                        child: Text(
                          'Your cart is empty',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    ...cart.items.values.map((cartItem) => _buildCartItemRow(cartItem)),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _couponController,
                                  focusNode: _couponFocusNode,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    hintText: 'Enter promo code',
                                    hintStyle: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF7F7F7),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 14,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppColors.primaryOrange,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isCouponApplying || _isOrdering
                                      ? null
                                      : () => _applyCoupon(cart),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryOrange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isCouponApplying
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Apply',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                          if (_couponError != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  _couponError!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          if (cart.appliedCoupon != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: AppColors.successGreen, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Applied: ${cart.appliedCoupon}',
                                        style: const TextStyle(
                                          color: AppColors.successGreen,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: cart.removeCoupon,
                                    child: const Text(
                                      'Remove',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bill Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildBillRow('Item Total', '₹${cart.subtotal.toStringAsFixed(0)}'),
                          if (cart.discountAmount > 0)
                            _buildBillRow('Discount', '- ₹${cart.discountAmount.toStringAsFixed(0)}', isGreen: true),
                          _buildBillRow(
                            'Delivery Fee',
                            cart.deliveryFee == 0 ? 'FREE' : '₹${cart.deliveryFee.toStringAsFixed(0)}',
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Grand Total',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                ),
                              ),
                              Text(
                                '₹${cart.grandTotal.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryOrange,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (cart.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isOrdering ? null : () => _placeOrder(cart),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isOrdering
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.shopping_bag_outlined, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'PLACE ORDER • ₹${cart.grandTotal.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _couponController.dispose();
    _couponFocusNode.dispose();
    super.dispose();
  }
}