import 'package:financial_insights/data/models/news_models.dart';
import 'package:financial_insights/data/repositories/news_repository.dart';
import 'package:financial_insights/providers/news_provider.dart';
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
/// always lists every category in the feed, followed ones first.
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
    );
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

  testWidgets('followed categories come first and are marked', (tester) async {
    await _pump(tester);
    expect(_left(tester, 'Energy'), lessThan(_left(tester, 'Banking')));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
