import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/portfolio_models.dart';
import '../data/repositories/portfolio_repository.dart';

final portfolioRepositoryProvider = Provider<PortfolioRepository>(
  (_) => PortfolioRepository(),
);

class PortfolioState {
  final List<PortfolioAsset> assets;
  final bool isLoading;
  final String? error;

  const PortfolioState({
    this.assets = const [],
    this.isLoading = false,
    this.error,
  });

  PortfolioState copyWith({
    List<PortfolioAsset>? assets,
    bool? isLoading,
    String? error,
  }) =>
      PortfolioState(
        assets: assets ?? this.assets,
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
      final assets = await _repository.getPortfolio(token);
      state = state.copyWith(assets: assets, isLoading: false);
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
