import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../logic/cart_provider.dart';

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  static const List<_OfferData> _offers = [
    _OfferData(
      code: 'RAMEEZ50',
      title: '50% OFF up to ₹150',
      description: 'Valid on all orders above ₹200. Celebrate the grand launch.',
      accent: Color(0xFFFFF1E7),
      badge: 'Launch',
    ),
    _OfferData(
      code: 'WELCOME20',
      title: '20% Flat Discount',
      description: 'Use code WELCOME20 to get instant savings on any dish.',
      accent: Color(0xFFEAF7F1),
      badge: 'New',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        title: const Text(
          'Offers & Discounts',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF4EA), Color(0xFFFFFFFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.orange.withOpacity(0.18)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_offer_rounded,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exclusive deals for you',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Apply one promo code at a time for best savings.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ..._offers.map((offer) => _buildCouponCard(context, offer)),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponCard(BuildContext context, _OfferData offer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: offer.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        offer.badge,
                        style: const TextStyle(
                          color: AppColors.primaryOrange,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      offer.code,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryOrange,
                        fontSize: 18,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => _applyCoupon(context, offer.code),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange.withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'APPLY',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryOrange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            offer.title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            offer.description,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _applyCoupon(BuildContext context, String couponCode) {
    final normalizedCode = couponCode.trim().toUpperCase();

    if (normalizedCode.isEmpty) {
      _showStatus(context, 'Please enter a valid coupon code.', isError: true);
      return;
    }

    final couponExists = _offers.any((offer) => offer.code == normalizedCode);

    if (!couponExists) {
      _showStatus(context, 'This coupon is not valid for your account.', isError: true);
      return;
    }

    final cart = context.read<CartProvider>();
    final success = cart.applyCoupon(normalizedCode);

    if (success) {
      _showStatus(context, 'Coupon $normalizedCode applied successfully.');
    } else {
      _showStatus(context, 'Coupon $normalizedCode could not be applied.', isError: true);
    }
  }

  void _showStatus(BuildContext context, String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: isError ? Colors.red : AppColors.successGreen,
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }
}

class _OfferData {
  final String code;
  final String title;
  final String description;
  final Color accent;
  final String badge;

  const _OfferData({
    required this.code,
    required this.title,
    required this.description,
    required this.accent,
    required this.badge,
  });
}