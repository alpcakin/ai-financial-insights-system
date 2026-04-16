import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: App()));
}

ThemeData _buildTheme() {
  const primary = Color(0xFF0F172A);
  const accent = Color(0xFF3B82F6);
  const bg = Color(0xFFF8FAFC);
  const surface = Color(0xFFFFFFFF);
  const border = Color(0xFFE2E8F0);
  const subtle = Color(0xFFF1F5F9);

  final base = GoogleFonts.interTextTheme();

  return ThemeData(
    useMaterial3: true,
    textTheme: base.copyWith(
      headlineMedium: base.headlineMedium?.copyWith(
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: primary,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: primary,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.bodyMedium?.copyWith(color: const Color(0xFF334155)),
      bodySmall: base.bodySmall?.copyWith(color: const Color(0xFF64748B)),
      labelSmall: base.labelSmall?.copyWith(color: const Color(0xFF94A3B8)),
      labelMedium: base.labelMedium?.copyWith(color: const Color(0xFF64748B)),
    ),
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: primary,
      surfaceContainerHighest: subtle,
      secondaryContainer: Color(0xFFDBEAFE),
      onSecondaryContainer: Color(0xFF1E3A5F),
      primaryContainer: Color(0xFFEFF6FF),
      onPrimaryContainer: primary,
      outline: border,
      outlineVariant: subtle,
    ),
    scaffoldBackgroundColor: bg,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: primary,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: border,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: accent,
      unselectedItemColor: Color(0xFF94A3B8),
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B)),
    ),
    dividerTheme: const DividerThemeData(color: border, space: 1),
  );
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Financial Insights',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const _AuthGate(),
    );
  }
}

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
