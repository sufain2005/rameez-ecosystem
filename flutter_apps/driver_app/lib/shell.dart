import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'earnings_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  /// Lets a screen (e.g. Home) jump to another tab.
  static _ShellState? of(BuildContext c) => c.findAncestorStateOfType<_ShellState>();
  void goTo(int i) => setState(() => _i = i);

  @override
  Widget build(BuildContext context) {
    // Screens are rebuilt when their tab is selected, so data is always fresh.
    final pages = <Widget>[
      const HomeScreen(),
      const EarningsScreen(),
      const HistoryScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_i]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        height: 70,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Call from any screen: goToTab(context, 0)
void goToTab(BuildContext c, int i) => _ShellState.of(c)?.goTo(i);