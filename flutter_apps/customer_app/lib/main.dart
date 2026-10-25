import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/security/app_security.dart';
import 'core/theme/app_theme.dart';
import 'logic/auth_provider.dart';
import 'logic/cart_provider.dart';
import 'logic/wallet_provider.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/main_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppSecurity.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..restoreSession()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
      ],
      child: const RameezKitchenCustomerApp(),
    ),
  );
}

class RameezKitchenCustomerApp extends StatelessWidget {
  const RameezKitchenCustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return MaterialApp(
      title: 'Rameez Kitchen',
      debugShowCheckedModeBanner: false,
      // Dynamic Theme: Light & Dark theme support
      theme: AppTheme.themeData,
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFFFF5200),
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF5200),
          secondary: Color(0xFFD4AF37),
        ),
      ),
      themeMode: auth.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      // If user is authenticated, route to Main Navigation; otherwise show OTP Auth Screen
      home: auth.isAuthenticated ? const MainNavigationScreen() : const AuthScreen(),
    );
  }
}