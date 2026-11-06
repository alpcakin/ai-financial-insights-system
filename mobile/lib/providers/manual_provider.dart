import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/manual_models.dart';
import '../data/repositories/manual_repository.dart';

final manualRepositoryProvider = Provider<ManualRepository>((_) => ManualRepository());

class ManualState {
  final ManualSettings? settings;
  final List<UserSource> sources;
  final List<UserModel> models;
  final bool isLoading;
  final String? error;

  const ManualState({
    this.settings,
    this.sources = const [],
    this.models = const [],
    this.isLoading = false,
    this.error,
  });

  ManualState copyWith({
    ManualSettings? settings,
    List<UserSource>? sources,
    List<UserModel>? models,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      ManualState(
        settings: settings ?? this.settings,
        sources: sources ?? this.sources,
        models: models ?? this.models,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );

  bool get hasWorkingModel => models.any((m) => m.stoppedReason == null);
}

/// Actions rethrow [ManualException], whose message the screens show as it is.
class ManualNotifier extends StateNotifier<ManualState> {
  final ManualRepository _repository;

  ManualNotifier(this._repository) : super(const ManualState());

  Future<void> load(String token) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repository.getSettings(token),
        _repository.getSources(token),
        _repository.getModels(token),
      ]);
      state = state.copyWith(
        settings: results[0] as ManualSettings,
        sources: results[1] as List<UserSource>,
        models: results[2] as List<UserModel>,
        isLoading: false,
      );
    } on ManualException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
    }
  }

  Future<void> updateSettings(
    String token, {
    bool? packageEnabled,
    bool? manualEnabled,
    bool? groupingEnabled,
    String? selectedModelId,
  }) async {
    final settings = await _repository.updateSettings(
      token,
      packageEnabled: packageEnabled,
      manualEnabled: manualEnabled,
      groupingEnabled: groupingEnabled,
      selectedModelId: selectedModelId,
    );
    state = state.copyWith(settings: settings);
  }

  Future<void> addSource(String token, {required String url, String? name, required int intervalMinutes}) async {
    final source = await _repository.addSource(token, url: url, name: name, intervalMinutes: intervalMinutes);
    state = state.copyWith(sources: [...state.sources, source]);
  }

  Future<void> updateSource(String token, String id, {bool? enabled, int? intervalMinutes}) async {
    final updated = await _repository.updateSource(token, id, enabled: enabled, intervalMinutes: intervalMinutes);
    state = state.copyWith(sources: state.sources.map((s) => s.id == id ? updated : s).toList());
  }

  Future<void> deleteSource(String token, String id) async {
    await _repository.deleteSource(token, id);
    state = state.copyWith(sources: state.sources.where((s) => s.id != id).toList());
  }

  Future<void> addModel(
    String token, {
    required String kind,
    required String model,
    required String apiKey,
    String? label,
    String? baseUrl,
  }) async {
    await _repository.addModel(token, kind: kind, model: model, apiKey: apiKey, label: label, baseUrl: baseUrl);
    await load(token);
  }

  Future<void> retryModel(String token, String id) async {
    final updated = await _repository.retryModel(token, id);
    state = state.copyWith(models: state.models.map((m) => m.id == id ? updated : m).toList());
  }

  Future<void> deleteModel(String token, String id) async {
    await _repository.deleteModel(token, id);
    await load(token);
  }
}

final manualProvider = StateNotifierProvider<ManualNotifier, ManualState>((ref) {
  return ManualNotifier(ref.read(manualRepositoryProvider));
});
