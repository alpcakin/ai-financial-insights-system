import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/report_models.dart';
import '../data/repositories/report_repository.dart';

final reportRepositoryProvider =
    Provider<ReportRepository>((_) => ReportRepository());

class ReportState {
  final List<ReportItem> reports;
  final bool isLoading;
  final String? error;

  const ReportState({
    this.reports = const [],
    this.isLoading = false,
    this.error,
  });

  ReportState copyWith({
    List<ReportItem>? reports,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      ReportState(
        reports: reports ?? this.reports,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );
}

class ReportNotifier extends StateNotifier<ReportState> {
  final ReportRepository _repository;

  ReportNotifier(this._repository) : super(const ReportState());

  Future<void> load(String token) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _repository.getReports(token);
      state = state.copyWith(reports: response.reports, isLoading: false);
    } on ReportException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Network error. Please try again.');
    }
  }
}

final reportProvider =
    StateNotifierProvider<ReportNotifier, ReportState>((ref) {
  return ReportNotifier(ref.read(reportRepositoryProvider));
});
