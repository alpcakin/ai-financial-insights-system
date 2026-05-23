import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/alert_models.dart';
import '../data/repositories/alert_repository.dart';

final alertRepositoryProvider =
    Provider<AlertRepository>((_) => AlertRepository());

class AlertState {
  final List<AlertItem> alerts;
  final bool isLoading;
  final String? error;
  final bool hasMore;

  const AlertState({
    this.alerts = const [],
    this.isLoading = false,
    this.error,
    this.hasMore = true,
  });

  int get unreadCount => alerts.where((a) => !a.isRead).length;

  AlertState copyWith({
    List<AlertItem>? alerts,
    bool? isLoading,
    String? error,
    bool? hasMore,
    bool clearError = false,
  }) =>
      AlertState(
        alerts: alerts ?? this.alerts,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        hasMore: hasMore ?? this.hasMore,
      );
}

class AlertNotifier extends StateNotifier<AlertState> {
  final AlertRepository _repository;
  static const _pageSize = 20;

  AlertNotifier(this._repository) : super(const AlertState());

  Future<void> load(String token) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _repository.getAlerts(
        token,
        limit: _pageSize,
        offset: 0,
      );
      state = state.copyWith(
        alerts: response.alerts,
        isLoading: false,
        hasMore: response.alerts.length >= _pageSize,
      );
    } on AlertException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Network error. Please try again.');
    }
  }

  Future<void> refresh(String token) => load(token);

  Future<void> markAllRead(String token) async {
    if (state.alerts.every((a) => a.isRead)) return;
    try {
      await _repository.markAllRead(token);
      state = state.copyWith(
        alerts: state.alerts.map((a) => AlertItem(
          id: a.id,
          userId: a.userId,
          articleId: a.articleId,
          assetSymbol: a.assetSymbol,
          alertType: a.alertType,
          severity: a.severity,
          message: a.message,
          notificationSent: a.notificationSent,
          isRead: true,
          createdAt: a.createdAt,
        )).toList(),
      );
    } catch (_) {
      // Non-fatal — UI still shows the alerts, badge stays until next load
    }
  }
}

final alertProvider = StateNotifierProvider<AlertNotifier, AlertState>((ref) {
  return AlertNotifier(ref.read(alertRepositoryProvider));
});
