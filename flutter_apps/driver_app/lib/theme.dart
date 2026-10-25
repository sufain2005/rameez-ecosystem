import 'package:flutter/material.dart';

class AppColors {
  static const orange = Color(0xFFF57C00);
  static const golden = Color(0xFFFFB300);
  static const cream = Color(0xFFFFFBF2);
  static const text = Color(0xFF2B2118);
  static const muted = Color(0xFF8A7F74);

  // status colors
  static const online = Color(0xFF2E9E5B);
  static const offline = Color(0xFF9E9E9E);
  static const pending = Color(0xFFFFB300);
  static const accepted = Color(0xFF1E88E5);
  static const pickedUp = Color(0xFF8E24AA);
  static const onTheWay = Color(0xFFEF6C00);
  static const delivered = Color(0xFF2E9E5B);
  static const danger = Color(0xFFD32F2F);
}

/// Color + label for any driver / delivery status code from the backend.
Color statusColor(String code) {
  switch (code) {
    case 'ONLINE':
      return AppColors.online;
    case 'OFFLINE':
      return AppColors.offline;
    case 'PENDING':
      return AppColors.pending;
    case 'ACCEPTED':
    case 'GOING_TO_RESTAURANT':
    case 'ARRIVED_RESTAURANT':
      return AppColors.accepted;
    case 'PICKED_UP':
      return AppColors.pickedUp;
    case 'ON_THE_WAY':
    case 'ARRIVED_CUSTOMER':
    case 'OTP_VERIFIED':
      return AppColors.onTheWay;
    case 'DELIVERED':
      return AppColors.delivered;
    default:
      return AppColors.muted;
  }
}

String statusLabel(String code) {
  const m = {
    'ONLINE': 'Online',
    'OFFLINE': 'Offline',
    'PENDING': 'Pending',
    'ACCEPTED': 'Accepted',
    'GOING_TO_RESTAURANT': 'Going to Restaurant',
    'ARRIVED_RESTAURANT': 'At Restaurant',
    'PICKED_UP': 'Picked Up',
    'ON_THE_WAY': 'On the Way',
    'ARRIVED_CUSTOMER': 'Arrived at Customer',
    'OTP_VERIFIED': 'OTP Verified',
    'DELIVERED': 'Delivered',
  };
  return m[code] ?? code;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.orange,
    primary: AppColors.orange,
    secondary: AppColors.golden,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black12,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56), // large driver-friendly button
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: .5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orange,
        side: const BorderSide(color: AppColors.orange, width: 1.6),
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6DCCB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6DCCB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.orange, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.orange.withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// Small colored status chip used everywhere.
class StatusChip extends StatelessWidget {
  final String code;
  const StatusChip(this.code, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(statusLabel(code),
          style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

String rupees(num v) => '₹${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(2)}';