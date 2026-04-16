import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/portfolio_models.dart';
import '../data/repositories/portfolio_repository.dart';

final portfolioRepositoryProvider = Provider<PortfolioRepository>(
  (_) => PortfolioRepository(),
);

class PortfolioState {
  final List<PortfolioAsset> assets;
  final double totalValue;
  final double totalPnl;
  final double totalPnlPct;
  final double totalDailyChange;
  final double totalDailyChangePct;
  final bool isLoading;
  final String? error;

  const PortfolioState({
    this.assets = const [],
    this.totalValue = 0.0,
    this.totalPnl = 0.0,
    this.totalPnlPct = 0.0,
    this.totalDailyChange = 0.0,
    this.totalDailyChangePct = 0.0,
    this.isLoading = false,
    this.error,
  });

  PortfolioState copyWith({
    List<PortfolioAsset>? assets,
    double? totalValue,
    double? totalPnl,
    double? totalPnlPct,
    double? totalDailyChange,
    double? totalDailyChangePct,
    bool? isLoading,
    String? error,
  }) =>
      PortfolioState(
        assets: assets ?? this.assets,
        totalValue: totalValue ?? this.totalValue,
        totalPnl: totalPnl ?? this.totalPnl,
        totalPnlPct: totalPnlPct ?? this.totalPnlPct,
        totalDailyChange: totalDailyChange ?? this.totalDailyChange,
        totalDailyChangePct: totalDailyChangePct ?? this.totalDailyChangePct,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class PortfolioNotifier extends StateNotifier<PortfolioState> {
  final PortfolioRepository _repository;

  PortfolioNotifier(this._repository) : super(const PortfolioState());

  Future<void> load(String token) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _repository.getPortfolio(token);
      state = state.copyWith(
        assets: response.assets,
        totalValue: response.totalValue,
        totalPnl: response.totalPnl,
        totalPnlPct: response.totalPnlPct,
        totalDailyChange: response.totalDailyChange,
        totalDailyChangePct: response.totalDailyChangePct,
        isLoading: false,
      );
    } on PortfolioException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
    }
  }

  Future<void> add(
    String token, {
    required String symbol,
    required String type,
    required double quantity,
    required double purchasePrice,
    String? category,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final asset = await _repository.addAsset(
        token,
        symbol: symbol,
        type: type,
        quantity: quantity,
        purchasePrice: purchasePrice,
        category: category,
      );
      state = state.copyWith(
        assets: [...state.assets, asset],
        isLoading: false,
      );
    } on PortfolioException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
      rethrow;
    }
  }

  Future<void> update(
    String token, {
    required String id,
    required double quantity,
    required double purchasePrice,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final updated = await _repository.updateAsset(
        token,
        id: id,
        quantity: quantity,
        purchasePrice: purchasePrice,
      );
      state = state.copyWith(
        assets: state.assets.map((a) => a.id == id ? updated : a).toList(),
        isLoading: false,
      );
    } on PortfolioException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
      rethrow;
    }
  }

  Future<void> remove(String token, {required String id}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.deleteAsset(token, id: id);
      state = state.copyWith(
        assets: state.assets.where((a) => a.id != id).toList(),
        isLoading: false,
      );
    } on PortfolioException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
      rethrow;
    }
  }
}

final portfolioProvider = StateNotifierProvider<PortfolioNotifier, PortfolioState>((ref) {
  return PortfolioNotifier(ref.read(portfolioRepositoryProvider));
});
