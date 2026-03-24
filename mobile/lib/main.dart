// Application entry point.
//
// [ProviderScope] at the root enables Riverpod state management for
// the entire widget tree.  [_AuthGate] listens to [authProvider] and
// shows either the login screen or the home screen based on whether
// the user has a valid session.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Financial Insights',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Switches between LoginScreen and HomeScreen reactively.
/// When authProvider.isAuthenticated changes, this widget rebuilds
/// and the user is automatically redirected.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    return authState.isAuthenticated ? const MainScreen() : const LoginScreen();
  }
}
