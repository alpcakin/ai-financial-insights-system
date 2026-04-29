// Central authentication state management using Riverpod.
//
// [AuthState] holds the current session: whether the user is logged in,
// whether a request is in progress, and any error message to display.
//
// [AuthNotifier] is a StateNotifier that exposes [register], [login],
// and [logout] methods.  On app startup it automatically checks
// FlutterSecureStorage for a saved token and restores the session
// so users do not have to log in again every time they open the app.
//
// The two top-level providers ([authRepositoryProvider] and
// [secureStorageProvider]) are defined separately so they can be
// overridden in tests with mock implementations.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants.dart';
import '../data/models/auth_models.dart';
import '../data/repositories/auth_repository.dart';
import 'alert_provider.dart';
import 'news_provider.dart';
import 'portfolio_provider.dart';
import 'report_provider.dart';
import 'topic_provider.dart';
import 'user_provider.dart';
import 'watchlist_provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((_) => AuthRepository());

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;
  final String? userId;
  final String? email;
  final String? token;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
    this.userId,
    this.email,
    this.token,
  });

  /// Creates a copy with only the specified fields changed.
  /// Passing null for [error] clears any previous error message.
  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
    String? userId,
    String? email,
    String? token,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        userId: userId ?? this.userId,
        email: email ?? this.email,
        token: token ?? this.token,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final FlutterSecureStorage _storage;
  final Ref _ref;

  AuthNotifier(this._repository, this._storage, this._ref) : super(const AuthState()) {
    _restoreSession();
  }

  void _invalidateDataProviders() {
    _ref.invalidate(portfolioProvider);
    _ref.invalidate(watchlistProvider);
    _ref.invalidate(newsProvider);
    _ref.invalidate(alertProvider);
    _ref.invalidate(reportProvider);
    _ref.invalidate(topicProvider);
    _ref.invalidate(userProvider);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Check secure storage for a previously saved token.
  /// If all three values exist the user is considered logged in.
  Future<void> _restoreSession() async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    final userId = await _storage.read(key: AppConstants.userIdKey);
    final email = await _storage.read(key: AppConstants.userEmailKey);

    if (token != null && userId != null && email != null) {
      state = state.copyWith(
        isAuthenticated: true,
        userId: userId,
        email: email,
        token: token,
      );
    }
  }

  /// Create a new account.  Returns true when the server accepted the request
  /// and a verification email was sent.  Does not authenticate — the user must
  /// verify their email first and then log in.
  Future<bool> register(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.register(email: email, password: password);
      state = state.copyWith(isLoading: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
      return false;
    }
  }

  /// Authenticate with existing credentials.  Same error handling as register.
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final token = await _repository.login(email: email, password: password);
      _invalidateDataProviders();
      await _persistSession(token);
      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        userId: token.userId,
        email: token.email,
        token: token.accessToken,
      );
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
      return false;
    }
  }

  /// Clear all stored credentials and reset to the initial state.
  Future<void> logout() async {
    await _storage.deleteAll();
    _invalidateDataProviders();
    state = const AuthState();
  }

  /// Write session data to the Android Keystore via FlutterSecureStorage.
  Future<void> _persistSession(AuthToken token) async {
    await _storage.write(key: AppConstants.tokenKey, value: token.accessToken);
    await _storage.write(key: AppConstants.userIdKey, value: token.userId);
    await _storage.write(key: AppConstants.userEmailKey, value: token.email);
  }
}

/// The single source of truth for authentication state.
/// UI widgets call ref.watch(authProvider) to rebuild when the state changes.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(authRepositoryProvider),
    ref.read(secureStorageProvider),
    ref,
  );
});
