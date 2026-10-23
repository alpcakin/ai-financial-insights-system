import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/alert_models.dart';
import '../data/repositories/alert_repository.dart';
import 'alert_provider.dart';

class AlertSettingsState {
  /// Only assets with a non-default choice, keyed by symbol.
  final Map<String, AlertSetting> settings;
  final bool isSaving;
  final String? error;

  const AlertSettingsState({
    this.settings = const {},
    this.isSaving = false,
    this.error,
  });

  AlertSetting forSymbol(String symbol) =>
      settings[symbol] ?? AlertSetting.automatic(symbol);

  AlertSettingsState copyWith({
    Map<String, AlertSetting>? settings,
    bool? isSaving,
    String? error,
    bool clearError = false,
  }) =>
      AlertSettingsState(
        settings: settings ?? this.settings,
        isSaving: isSaving ?? this.isSaving,
        error: clearError ? null : error ?? this.error,
      );
}

class AlertSettingsNotifier extends StateNotifier<AlertSettingsState> {
  final AlertRepository _repository;

  AlertSettingsNotifier(this._repository) : super(const AlertSettingsState());

  Future<void> load(String token) async {
    try {
      final settings = await _repository.getSettings(token);
      state = state.copyWith(
        settings: {for (final s in settings) s.assetSymbol: s},
        clearError: true,
      );
    } on AlertException catch (e) {
      state = state.copyWith(error: e.message);
    } catch (_) {
      state = state.copyWith(error: 'Network error. Please try again.');
    }
  }

  /// Returns whether the choice was saved; on failure [AlertSettingsState.error] says why.
  Future<bool> save(
    String token,
    String symbol, {
    required String mode,
    double? thresholdPct,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final saved = await _repository.updateSetting(
        token,
        symbol,
        mode: mode,
        thresholdPct: thresholdPct,
      );
      final settings = Map<String, AlertSetting>.from(state.settings);
      if (saved.isAutomatic) {
        settings.remove(symbol);
      } else {
        settings[symbol] = saved;
      }
      state = state.copyWith(settings: settings, isSaving: false);
      return true;
    } on AlertException catch (e) {
      state = state.copyWith(isSaving: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
          isSaving: false, error: 'Network error. Please try again.');
    }
    return false;
  }
}

final alertSettingsProvider =
    StateNotifierProvider<AlertSettingsNotifier, AlertSettingsState>((ref) {
  return AlertSettingsNotifier(ref.read(alertRepositoryProvider));
});
