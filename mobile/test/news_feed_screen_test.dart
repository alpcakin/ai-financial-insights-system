import 'package:financial_insights/data/models/news_models.dart';
import 'package:financial_insights/data/models/watchlist_models.dart';
import 'package:financial_insights/data/repositories/news_repository.dart';
import 'package:financial_insights/data/repositories/watchlist_repository.dart';
import 'package:financial_insights/providers/news_provider.dart';
import 'package:financial_insights/providers/watchlist_provider.dart';
import 'package:financial_insights/screens/news/news_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

FeedArticle _story(String id, String title, List<String> categories) => FeedArticle(
      id: id,
      title: title,
      url: 'https://x.test/$id',
      source: 'WSJ',
      summary: null,
      sentimentLabel: 'neutral',
      severity: 2,
      relatedCategories: categories,
      relatedAssets: const [],
      assetImpacts: const [],
      publishedAt: '2026-11-20T10:00:00Z',
      read: false,
    );

/// The server's filter: a category gives only its own stories, and the first page
/// always lists every category in the feed, followed ones first, and counts the
/// unread stories of the whole view, more than one page holds.
class _FeedNews extends NewsRepository {
  final requested = <String?>[];

  @override
  Future<FeedResponse> getFeed(String token, {int limit = 20, int offset = 0, String? category}) async {
    requested.add(category);
    final all = [
      _story('b1', 'Bank story', ['Banking']),
      _story('e1', 'Oil story', ['Energy']),
      _story('c1', 'Coin story', ['Crypto']),
    ];
    final articles = category == null || category.isEmpty
        ? all
        : all.where((a) => a.relatedCategories.contains(category)).toList();
    return FeedResponse(
      articles: offset == 0 ? articles : const [],
      total: articles.length,
      offset: offset,
      limit: limit,
      categories: offset == 0
          ? const [
              FeedCategory(name: 'Energy', followed: true),
              FeedCategory(name: 'Banking', followed: false),
              FeedCategory(name: 'Crypto', followed: false),
            ]
          : null,
      unread: offset == 0 ? (category == null || category.isEmpty ? 42 : 7) : null,
    );
  }

  @override
  Future<void> markRead(String token, String articleId) async {}
}

/// Fails as often as told, then answers like [_FeedNews].
class _FlakyNews extends _FeedNews {
  int failures;
  _FlakyNews(this.failures);

  @override
  Future<FeedResponse> getFeed(String token, {int limit = 20, int offset = 0, String? category}) async {
    if (failures > 0) {
      failures--;
      throw NewsException('Failed to load feed');
    }
    return super.getFeed(token, limit: limit, offset: offset, category: category);
  }
}

Future<_FeedNews> _pump(WidgetTester tester) async {
  final news = _FeedNews();
  await tester.pumpWidget(ProviderScope(
    overrides: [newsRepositoryProvider.overrideWithValue(news)],
    child: const MaterialApp(home: NewsFeedScreen()),
  ));
  await tester.pump();
  await tester.pump();
  return news;
}

double _left(WidgetTester tester, String label) => tester.getTopLeft(find.text(label)).dx;

class _EmptyNews extends NewsRepository {
  @override
  Future<FeedResponse> getFeed(String token, {int limit = 20, int offset = 0, String? category}) async =>
      FeedResponse(articles: const [], total: 0, offset: offset, limit: limit, categories: const []);
}

class _Watching extends WatchlistNotifier {
  _Watching() : super(WatchlistRepository()) {
    state = const WatchlistState(items: [
      WatchlistItem(id: 'w1', assetSymbol: 'NVDA', assetType: 'stock', addedAt: '2026-11-01T00:00:00Z'),
    ]);
  }

  @override
  Future<void> load(String token) async {}
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('choosing a category keeps the other categories to choose from', (tester) async {
    final news = await _pump(tester);
    await tester.tap(find.text('Banking'));
    await tester.pump();
    await tester.pump();

    expect(news.requested.last, 'Banking');
    expect(find.text('Bank story'), findsOneWidget);
    expect(find.text('Oil story'), findsNothing);
    for (final label in ['All', 'Energy', 'Banking', 'Crypto']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('an empty feed offers the recent news of the user\'s assets', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        newsRepositoryProvider.overrideWithValue(_EmptyNews()),
        watchlistProvider.overrideWith((ref) => _Watching()),
      ],
      child: const MaterialApp(home: NewsFeedScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('No articles yet'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'NVDA'), findsOneWidget);
  });

  testWidgets('the badge counts the unread stories of the whole view, not the loaded page', (tester) async {
    await _pump(tester);
    expect(find.text('42 new'), findsOneWidget);

    await tester.tap(find.text('Banking'));
    await tester.pump();
    await tester.pump();
    expect(find.text('7 new'), findsOneWidget);
  });

  testWidgets('a feed that fails to load says so and can be tried again', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [newsRepositoryProvider.overrideWithValue(_FlakyNews(1))],
      child: const MaterialApp(home: NewsFeedScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't load your news"), findsOneWidget);
    expect(find.text('No articles yet'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Bank story'), findsOneWidget);
    expect(find.text("Couldn't load your news"), findsNothing);
  });

  testWidgets('a category that fails to load does not show the previous one\'s stories', (tester) async {
    final news = _FlakyNews(0);
    await tester.pumpWidget(ProviderScope(
      overrides: [newsRepositoryProvider.overrideWithValue(news)],
      child: const MaterialApp(home: NewsFeedScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Oil story'), findsOneWidget);

    news.failures = 1;
    await tester.tap(find.text('Banking'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Oil story'), findsNothing);
    expect(find.text("Couldn't load your news"), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the stories on screen and says so', (tester) async {
    final news = _FlakyNews(0);
    await tester.pumpWidget(ProviderScope(
      overrides: [newsRepositoryProvider.overrideWithValue(news)],
      child: const MaterialApp(home: NewsFeedScreen()),
    ));
    await tester.pump();
    await tester.pump();

    news.failures = 1;
    final container = ProviderScope.containerOf(tester.element(find.byType(NewsFeedScreen)));
    await container.read(newsProvider.notifier).refresh('');
    await tester.pump();
    expect(find.text('Oil story'), findsOneWidget);
    expect(find.text('Failed to load feed'), findsOneWidget);
  });

  test('reading a story lowers the badge once', () async {
    final notifier = NewsNotifier(_FeedNews());
    await notifier.load('');
    expect(notifier.state.unread, 42);

    await notifier.markRead('', 'b1');
    await notifier.markRead('', 'b1');
    expect(notifier.state.unread, 41);
  });

  testWidgets('followed categories come first and are marked', (tester) async {
    await _pump(tester);
    expect(_left(tester, 'Energy'), lessThan(_left(tester, 'Banking')));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
