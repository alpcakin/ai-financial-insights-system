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

  const NewsState({
    this.articles = const [],
    this.isLoading = false,
    this.error,
    this.selectedCategory,
    this.hasMore = true,
  });

  NewsState copyWith({
    List<FeedArticle>? articles,
    bool? isLoading,
    String? error,
    String? selectedCategory,
    bool? hasMore,
    bool clearError = false,
  }) =>
      NewsState(
        articles: articles ?? this.articles,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        selectedCategory: selectedCategory ?? this.selectedCategory,
        hasMore: hasMore ?? this.hasMore,
      );
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
