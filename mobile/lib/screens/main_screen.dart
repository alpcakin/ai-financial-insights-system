import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.newspaper),
            label: 'News',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: alertCount > 0 && _currentIndex != 2,
              label: Text('$alertCount'),
              child: const Icon(Icons.notifications),
            ),
            label: 'Alerts',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}
