// Application entry point.
//
// [ProviderScope] at the root enables Riverpod state management for
// the entire widget tree.  [_AuthGate] listens to [authProvider] and
// shows either the login screen or the home screen based on whether
// the user has a valid session.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  bool _fcmInitialized = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (authState.isAuthenticated && !_fcmInitialized && authState.token != null) {
      _fcmInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FcmService.init(authState.token!);
      });
    }

    if (!authState.isAuthenticated) {
      _fcmInitialized = false;
    }

    return authState.isAuthenticated ? const MainScreen() : const LoginScreen();
  }
}
