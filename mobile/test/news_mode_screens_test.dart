import 'package:financial_insights/data/models/asset_catalog.dart';
import 'package:financial_insights/data/models/manual_models.dart';
import 'package:financial_insights/data/models/news_models.dart';
import 'package:financial_insights/data/repositories/manual_repository.dart';
import 'package:financial_insights/data/repositories/news_repository.dart';
import 'package:financial_insights/providers/asset_news_provider.dart';
import 'package:financial_insights/providers/manual_provider.dart';
import 'package:financial_insights/providers/news_provider.dart';
import 'package:financial_insights/screens/manual/manual_mode_screen.dart';
import 'package:financial_insights/screens/news/article_widgets.dart';
import 'package:financial_insights/screens/news/asset_news_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeManual extends ManualNotifier {
  _FakeManual(ManualState initial) : super(ManualRepository()) {
    state = initial;
  }

  @override
  Future<void> load(String token) async {}
}

class _FakeNews extends NewsRepository {
  final List<ArticleAnalysis> analyses;
  final List<FeedArticle> articles;

  _FakeNews({this.analyses = const [], this.articles = const []});

  @override
  Future<List<ArticleAnalysis>> getAnalyses(String token, String articleId) async => analyses;

  @override
  Future<FeedResponse> getAssetNews(String token, String symbol, {int limit = 20, int offset = 0}) async =>
      FeedResponse(articles: offset == 0 ? articles : const [], total: articles.length, offset: offset, limit: limit);
}

FeedArticle _article({
  String id = 'a1',
  String? analyzedBy = 'm1',
  String? analyzedByName = 'A very long name for my own model',
  String? summary = 'The first model says this.',
  String mode = 'manual',
  bool failed = false,
  int? severity = 3,
}) =>
    FeedArticle(
      id: id,
      title: 'Exxon Mobil reports a long headline that has to wrap over more than one line on a small phone',
      url: 'https://x.test/a',
      source: 'A source with a really long name that goes on and on',
      summary: summary,
      sentimentLabel: failed ? null : 'positive',
      severity: severity,
      relatedCategories: const [],
      relatedAssets: const ['XOM', 'CVX', 'BP', 'SHEL'],
      assetImpacts: const [],
      publishedAt: '2026-11-05T10:00:00Z',
      analyzedBy: analyzedBy,
      analyzedByName: analyzedByName,
      read: false,
      mode: mode,
      analysisFailed: failed,
    );

const _settings = ManualSettings(
  packageEnabled: true,
  manualEnabled: true,
  groupingEnabled: false,
  selectedModelId: 'm1',
  canStoreKeys: true,
);

const _sources = [
  UserSource(id: 's1', url: 'https://a-very-long-domain-name.example.com/path/to/the/feed.xml', name: 'Feed with a long name', fetchIntervalMinutes: 15, enabled: true),
  UserSource(id: 's2', url: 'https://x.test/b', name: 'Broken', fetchIntervalMinutes: 7, enabled: false, lastError: 'unreachable'),
];

const _models = [
  UserModel(id: 'm1', kind: 'openai', model: 'gpt-x', label: 'Mine', keyLast4: '1234'),
  UserModel(id: 'm2', kind: 'compatible', model: 'local-model-with-long-name', label: 'Stopped one', baseUrl: 'https://x.test/v1', keyLast4: '9876', stoppedReason: 'quota'),
];

/// The test font is much wider than Inter, so this behaves like a narrow phone.
/// Overflow errors fail the test.
Future<void> _pump(WidgetTester tester, Widget child, List<Override> overrides) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: child)));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('News Mode screen', () {
    List<Override> overrides(ManualState state) => [manualProvider.overrideWith((ref) => _FakeManual(state))];

    testWidgets('shows both modes, grouping off and the sources and models', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings, sources: _sources, models: _models)));
      expect(find.text('News package'), findsOneWidget);
      expect(find.text('My sources'), findsOneWidget);
      expect(find.text('Off: every article is its own card and is analyzed separately.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Stopped one'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Could not reach this feed'), findsOneWidget);
      expect(find.text('Stopped: its account has no quota left'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('warns when my sources is on without a source or a working model', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings)));
      expect(find.text('My sources needs at least one source and one working model.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says so when the server cannot store keys', (tester) async {
      const settings = ManualSettings(packageEnabled: true, manualEnabled: false, groupingEnabled: false, canStoreKeys: false);
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: settings)));
      await tester.scrollUntilVisible(find.text('This server cannot store API keys yet.'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('This server cannot store API keys yet.'), findsOneWidget);
    });

    testWidgets('the add model sheet warns about an unencrypted connection and needs fields', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings, sources: _sources, models: _models)));
      await tester.scrollUntilVisible(find.text('MY MODELS'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      expect(find.text('This connection to the server is not encrypted. Do not enter a real key.'), findsOneWidget);
      await tester.tap(find.text('Test and save'));
      await tester.pump();
      expect(find.text('Enter the model name and the API key.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Article card', () {
    testWidgets('fits long names on a narrow phone and marks manual news', (tester) async {
      await _pump(tester, Scaffold(body: ArticleCard(article: _article(), onTap: () {})), []);
      expect(find.text('Manual'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('marks a story no model could analyze', (tester) async {
      final article = _article(failed: true, analyzedBy: null, analyzedByName: null, summary: null, severity: null);
      await _pump(tester, Scaffold(body: ArticleCard(article: article, onTap: () {})), []);
      expect(find.text('Analysis failed: none of your models could analyze this article.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('package news has no manual mark', (tester) async {
      await _pump(tester, Scaffold(body: ArticleCard(article: _article(mode: 'package'), onTap: () {})), []);
      expect(find.text('Manual'), findsNothing);
    });
  });

  group('Article detail', () {
    const analyses = [
      ArticleAnalysis(provider: 'm1', providerName: 'First', summary: 'The first model says this.', severity: 3),
      ArticleAnalysis(provider: 'm2', providerName: 'Second', summary: 'The second model disagrees.', severity: 1, sentimentLabel: 'negative'),
    ];

    testWidgets('switches between models on the same article', (tester) async {
      await _pump(
        tester,
        Scaffold(body: ArticleDetailSheet(article: _article())),
        [newsRepositoryProvider.overrideWithValue(_FakeNews(analyses: analyses))],
      );
      await tester.pumpAndSettle();
      expect(find.text('COMPARE MODELS'), findsOneWidget);
      expect(find.text('The first model says this.'), findsOneWidget);
      expect(find.text('Severity: High'), findsOneWidget);

      await tester.tap(find.text('Second'));
      await tester.pump();
      expect(find.text('The second model disagrees.'), findsOneWidget);
      expect(find.text('The first model says this.'), findsNothing);
      expect(find.text('Severity: Low'), findsOneWidget);
      expect(find.text('negative'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has no tabs when one model analyzed it', (tester) async {
      await _pump(
        tester,
        Scaffold(body: ArticleDetailSheet(article: _article())),
        [newsRepositoryProvider.overrideWithValue(_FakeNews(analyses: analyses.sublist(0, 1)))],
      );
      await tester.pumpAndSettle();
      expect(find.text('COMPARE MODELS'), findsNothing);
      expect(find.text('Analyzed by'), findsOneWidget);
    });
  });

  group('Asset news screen', () {
    const asset = AssetInfo(symbol: 'XOM', name: 'Exxon Mobil Corporation', type: 'stock', category: 'Oil & Gas');

    testWidgets('lists the stored news and offers the watchlist', (tester) async {
      await _pump(
        tester,
        const AssetNewsScreen(asset: asset),
        [newsRepositoryProvider.overrideWithValue(_FakeNews(articles: [_article(mode: 'package', severity: 1)]))],
      );
      await tester.pumpAndSettle();
      expect(find.text('Add to watchlist'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('explains an empty result', (tester) async {
      await _pump(tester, const AssetNewsScreen(asset: asset), [newsRepositoryProvider.overrideWithValue(_FakeNews())]);
      await tester.pumpAndSettle();
      expect(find.text('No news yet'), findsOneWidget);
    });

    test('a provider is kept per asset', () async {
      final container = ProviderContainer(overrides: [newsRepositoryProvider.overrideWithValue(_FakeNews(articles: [_article()]))]);
      addTearDown(container.dispose);
      final subscription = container.listen(assetNewsProvider('XOM'), (_, _) {});
      await container.read(assetNewsProvider('XOM').notifier).load('t');
      expect(container.read(assetNewsProvider('XOM')).articles, hasLength(1));
      expect(container.read(assetNewsProvider('CVX')).articles, isEmpty);
      subscription.close();
    });
  });

  group('Feed paging', () {
    test('a repeated article is not shown twice', () {
      final merged = appendNewArticles([_article(id: 'a'), _article(id: 'b')], [_article(id: 'b'), _article(id: 'c')]);
      expect(merged.map((a) => a.id), ['a', 'b', 'c']);
    });
  });
}
