import 'package:flutter/material.dart';
import 'api.dart';
import 'security.dart';
import 'theme.dart';
import 'login_screen.dart';
import 'shell.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DriverSecurity.init();
  try {
    await Api.loadToken().timeout(const Duration(seconds: 3));
  } catch (_) {
    Api.token = null;
  }

  Api.onUnauthorized = () {
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  };

  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rameez Kitchen Driver',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      theme: buildTheme(),
      // No token -> login right away. Token -> open the app; a 401 sends them back to login.
      home: Api.token == null ? const LoginScreen() : const Shell(),
    );
  }
}