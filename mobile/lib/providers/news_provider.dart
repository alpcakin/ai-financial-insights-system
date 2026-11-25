import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/news_models.dart';
import '../data/repositories/news_repository.dart';

final newsRepositoryProvider = Provider<NewsRepository>((_) => NewsRepository());

class NewsState {
  final List<FeedArticle> articles;

  /// Every category in the feed, followed ones first; the filter's choices.
  final List<FeedCategory> categories;

  /// Unread stories in the whole view, counted by the server, not just the loaded ones.
  final int unread;
  final bool isLoading;
  final String? error;
  final String? selectedCategory;
  final bool hasMore;
  final bool isLoadingMore;

  const NewsState({
    this.articles = const [],
    this.categories = const [],
    this.unread = 0,
    this.isLoading = false,
    this.error,
    this.selectedCategory,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  NewsState copyWith({
    List<FeedArticle>? articles,
    List<FeedCategory>? categories,
    int? unread,
    bool? isLoading,
    String? error,
    String? selectedCategory,
    bool? hasMore,
    bool? isLoadingMore,
    bool clearError = false,
  }) =>
      NewsState(
        articles: articles ?? this.articles,
        categories: categories ?? this.categories,
        unread: unread ?? this.unread,
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
    final category = state.selectedCategory;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _repository.getFeed(
        token,
        limit: _pageSize,
        offset: 0,
        category: category,
      );
      // Another category was chosen while this one loaded; its own load shows it.
      if (state.selectedCategory != category) return;
      state = state.copyWith(
        articles: response.articles,
        categories: response.categories,
        unread: response.unread ?? 0,
        isLoading: false,
        hasMore: response.articles.length >= _pageSize,
      );
    } on NewsException catch (e) {
      if (state.selectedCategory != category) return;
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      if (state.selectedCategory != category) return;
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

  /// The previous view's stories are dropped at once, so a category that fails
  /// to load shows the error instead of another category's stories.
  Future<void> setCategory(String token, String? category) async {
    state = state.copyWith(
      selectedCategory: category ?? '',
      articles: const [],
      unread: 0,
      hasMore: true,
      clearError: true,
    );
    await load(token);
  }

  Future<void> markRead(String token, String articleId) async {
    try {
      await _repository.markRead(token, articleId);
      final wasUnread = state.articles.any((a) => a.id == articleId && !a.read);
      state = state.copyWith(
        articles: state.articles
            .map((a) => a.id == articleId ? a.copyWith(read: true) : a)
            .toList(),
        unread: wasUnread && state.unread > 0 ? state.unread - 1 : state.unread,
      );
    } catch (_) {}
  }
}

final newsProvider = StateNotifierProvider<NewsNotifier, NewsState>((ref) {
  return NewsNotifier(ref.read(newsRepositoryProvider));
});
