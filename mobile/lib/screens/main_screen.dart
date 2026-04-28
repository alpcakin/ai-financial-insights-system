import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/alert_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/report_provider.dart';
import 'alerts/alerts_screen.dart';
import 'home/home_screen.dart';
import 'news/news_feed_screen.dart';
import 'reports/reports_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = ref.read(authProvider).token ?? '';
      ref.read(alertProvider.notifier).load(token);
      ref.read(reportProvider.notifier).load(token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final alertCount = ref.watch(alertProvider).alerts.length;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeScreen(),
          NewsFeedScreen(),
          AlertsScreen(),
          ReportsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          indicatorColor: const Color(0xFF0F172A),
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: Colors.white),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article_rounded, color: Colors.white),
              label: 'News',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: alertCount > 0 && _currentIndex != 2,
                label: Text(
                  '$alertCount',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
                ),
                child: const Icon(Icons.notifications_outlined),
              ),
              selectedIcon: const Icon(Icons.notifications_rounded, color: Colors.white),
              label: 'Alerts',
            ),
            const NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart_rounded, color: Colors.white),
              label: 'Reports',
            ),
          ],
        ),
      ),
    );
  }
}
