import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/news_models.dart';
import '../data/repositories/news_repository.dart';

final newsRepositoryProvider = Provider<NewsRepository>((_) => NewsRepository());

class NewsState {
  final List<FeedArticle> articles;
  final bool isLoading;
  final String? error;
  final String? selectedCategory;
  final bool hasMore;
  final bool isLoadingMore;

  const NewsState({
    this.articles = const [],
    this.isLoading = false,
    this.error,
    this.selectedCategory,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  NewsState copyWith({
    List<FeedArticle>? articles,
    bool? isLoading,
    String? error,
    String? selectedCategory,
    bool? hasMore,
    bool? isLoadingMore,
    bool clearError = false,
  }) =>
      NewsState(
        articles: articles ?? this.articles,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        selectedCategory: selectedCategory ?? this.selectedCategory,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

/// New entries arriving between two page loads shift the offset, so the next
/// page can repeat articles already on screen.
List<FeedArticle> appendNewArticles(List<FeedArticle> current, List<FeedArticle> page) {
  final seen = current.map((a) => a.id).toSet();
  return [...current, ...page.where((a) => seen.add(a.id))];
}

class NewsNotifier extends StateNotifier<NewsState> {
  final NewsRepository _repository;
  static const _pageSize = 20;

  NewsNotifier(this._repository) : super(const NewsState());

  Future<void> load(String token) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _repository.getFeed(
        token,
        limit: _pageSize,
        offset: 0,
        category: state.selectedCategory,
      );
      state = state.copyWith(
        articles: response.articles,
        isLoading: false,
        hasMore: response.articles.length >= _pageSize,
      );
    } on NewsException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Network error. Please try again.');
    }
  }

  Future<void> loadMore(String token) async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final category = state.selectedCategory;
    state = state.copyWith(isLoadingMore: true);
    try {
      final response = await _repository.getFeed(
        token,
        limit: _pageSize,
        offset: state.articles.length,
        category: category,
      );
      if (state.selectedCategory != category) {
        state = state.copyWith(isLoadingMore: false);
        return;
      }
      state = state.copyWith(
        articles: appendNewArticles(state.articles, response.articles),
        isLoadingMore: false,
        hasMore: response.articles.length >= _pageSize,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh(String token) => load(token);

  Future<void> setCategory(String token, String? category) async {
    state = state.copyWith(selectedCategory: category ?? '');
    await load(token);
  }

  Future<void> markRead(String token, String articleId) async {
    try {
      await _repository.markRead(token, articleId);
      state = state.copyWith(
        articles: state.articles
            .map((a) => a.id == articleId ? a.copyWith(read: true) : a)
            .toList(),
      );
    } catch (_) {}
  }
}

final newsProvider = StateNotifierProvider<NewsNotifier, NewsState>((ref) {
  return NewsNotifier(ref.read(newsRepositoryProvider));
});
