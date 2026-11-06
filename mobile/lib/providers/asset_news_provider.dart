import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/news_models.dart';
import '../data/repositories/news_repository.dart';
import 'news_provider.dart';

class AssetNewsState {
  final List<FeedArticle> articles;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  const AssetNewsState({
    this.articles = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
  });

  AssetNewsState copyWith({
    List<FeedArticle>? articles,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) =>
      AssetNewsState(
        articles: articles ?? this.articles,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : error ?? this.error,
      );
}

class AssetNewsNotifier extends StateNotifier<AssetNewsState> {
  final NewsRepository _repository;
  final String _symbol;
  static const _pageSize = 20;

  AssetNewsNotifier(this._repository, this._symbol) : super(const AssetNewsState());

  Future<void> load(String token) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _repository.getAssetNews(token, _symbol, limit: _pageSize);
      if (!mounted) return;
      state = state.copyWith(
        articles: response.articles,
        isLoading: false,
        hasMore: response.articles.length >= _pageSize,
      );
    } on NewsException catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
    }
  }

  Future<void> loadMore(String token) async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final response = await _repository.getAssetNews(
        token,
        _symbol,
        limit: _pageSize,
        offset: state.articles.length,
      );
      if (!mounted) return;
      state = state.copyWith(
        articles: appendNewArticles(state.articles, response.articles),
        isLoadingMore: false,
        hasMore: response.articles.length >= _pageSize,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoadingMore: false);
    }
  }

  void showAsRead(String articleId) {
    state = state.copyWith(
      articles: state.articles
          .map((a) => a.id == articleId ? a.copyWith(read: true) : a)
          .toList(),
    );
  }
}

final assetNewsProvider =
    StateNotifierProvider.autoDispose.family<AssetNewsNotifier, AssetNewsState, String>((ref, symbol) {
  return AssetNewsNotifier(ref.read(newsRepositoryProvider), symbol);
});
