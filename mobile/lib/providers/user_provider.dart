import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/user_models.dart';
import '../data/repositories/user_repository.dart';

final userRepositoryProvider = Provider<UserRepository>((_) => UserRepository());

class UserState {
  final UserProfile? profile;
  final bool isLoading;
  final bool isUpdating;
  final String? error;

  const UserState({
    this.profile,
    this.isLoading = false,
    this.isUpdating = false,
    this.error,
  });

  UserState copyWith({
    UserProfile? profile,
    bool? isLoading,
    bool? isUpdating,
    String? error,
    bool clearError = false,
  }) =>
      UserState(
        profile: profile ?? this.profile,
        isLoading: isLoading ?? this.isLoading,
        isUpdating: isUpdating ?? this.isUpdating,
        error: clearError ? null : error ?? this.error,
      );
}

class UserNotifier extends StateNotifier<UserState> {
  final UserRepository _repository;

  UserNotifier(this._repository) : super(const UserState());

  Future<void> loadProfile(String token) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profile = await _repository.getMe(token);
      state = state.copyWith(profile: profile, isLoading: false);
    } on UserException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
    }
  }

  Future<void> updatePreferences(
    String token, {
    bool? impactAlerts,
    bool? volatilityAlerts,
  }) async {
    state = state.copyWith(isUpdating: true, clearError: true);
    try {
      final updated = await _repository.updatePreferences(
        token,
        impactAlerts: impactAlerts,
        volatilityAlerts: volatilityAlerts,
      );
      state = state.copyWith(profile: updated, isUpdating: false);
    } on UserException catch (e) {
      state = state.copyWith(isUpdating: false, error: e.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(isUpdating: false, error: 'Network error. Please try again.');
      rethrow;
    }
  }

  Future<void> changePassword(
    String token, {
    required String currentPassword,
    required String newPassword,
  }) async {
    await _repository.changePassword(
      token,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<void> deleteAccount(String token) async {
    await _repository.deleteAccount(token);
  }

  Future<Map<String, dynamic>> exportData(String token) async {
    return _repository.exportData(token);
  }
}

final userProvider = StateNotifierProvider<UserNotifier, UserState>((ref) {
  return UserNotifier(ref.read(userRepositoryProvider));
});
