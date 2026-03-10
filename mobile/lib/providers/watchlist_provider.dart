import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/watchlist_models.dart';
import '../data/repositories/watchlist_repository.dart';

final watchlistRepositoryProvider = Provider<WatchlistRepository>(
  (_) => WatchlistRepository(),
);

class WatchlistState {
  final List<WatchlistItem> items;
  final bool isLoading;
  final String? error;

  const WatchlistState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  WatchlistState copyWith({
    List<WatchlistItem>? items,
    bool? isLoading,
    String? error,
  }) =>
      WatchlistState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class WatchlistNotifier extends StateNotifier<WatchlistState> {
  final WatchlistRepository _repository;

  WatchlistNotifier(this._repository) : super(const WatchlistState());

  Future<void> load(String token) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _repository.getWatchlist(token);
      state = state.copyWith(items: items, isLoading: false);
    } on WatchlistException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
    }
  }

  Future<void> add(String token, {required String symbol, required String type, String? category}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final item = await _repository.addItem(token, symbol: symbol, type: type, category: category);
      state = state.copyWith(items: [...state.items, item], isLoading: false);
    } on WatchlistException catch (e) {
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
      await _repository.deleteItem(token, id: id);
      state = state.copyWith(
        items: state.items.where((i) => i.id != id).toList(),
        isLoading: false,
      );
    } on WatchlistException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
      rethrow;
    }
  }
}

final watchlistProvider = StateNotifierProvider<WatchlistNotifier, WatchlistState>((ref) {
  return WatchlistNotifier(ref.read(watchlistRepositoryProvider));
});
