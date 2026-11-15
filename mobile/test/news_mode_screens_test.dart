import 'package:financial_insights/data/models/asset_catalog.dart';
import 'package:financial_insights/data/models/manual_models.dart';
import 'package:financial_insights/data/models/news_models.dart';
import 'package:financial_insights/data/repositories/manual_repository.dart';
import 'package:financial_insights/data/models/user_models.dart';
import 'package:financial_insights/data/repositories/news_repository.dart';
import 'package:financial_insights/data/repositories/user_repository.dart';
import 'package:financial_insights/providers/asset_news_provider.dart';
import 'package:financial_insights/providers/manual_provider.dart';
import 'package:financial_insights/providers/news_provider.dart';
import 'package:financial_insights/providers/user_provider.dart';
import 'package:financial_insights/screens/manual/manual_mode_screen.dart';
import 'package:financial_insights/screens/news/article_widgets.dart';
import 'package:financial_insights/screens/news/asset_news_screen.dart';
import 'package:financial_insights/widgets/info_tip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeManual extends ManualNotifier {
  final List<bool?> follows = [];

  _FakeManual(ManualState initial) : super(ManualRepository()) {
    state = initial;
  }

  @override
  Future<void> load(String token) async {}

  @override
  Future<void> updateSettings(
    String token, {
    bool? packageEnabled,
    bool? manualEnabled,
    bool? groupingEnabled,
    String? selectedModelId,
    bool? followPackageFeeds,
  }) async {
    follows.add(followPackageFeeds);
  }
  final List<(String, bool?)> pausedOrResumed = [];

  @override
  Future<void> updateSource(String token, String id, {bool? enabled, int? intervalMinutes}) async {
    pausedOrResumed.add((id, enabled));
  }
}

class _FakeUser extends UserNotifier {
  final List<String?> picked = [];

  _FakeUser() : super(UserRepository()) {
    state = const UserState(
      profile: UserProfile(
        id: 'u1',
        email: 'someone@example.com',
        preferences: NotificationPreferences(),
        aiProvider: 'openai',
        createdAt: '2026-11-01T00:00:00Z',
      ),
      providers: [
        AIProviderInfo(name: 'openai', displayName: 'GPT', model: 'gpt-6-luna', isDefault: true),
        AIProviderInfo(name: 'claude', displayName: 'Claude', model: 'claude-haiku-5-5', isDefault: false),
      ],
    );
  }

  @override
  Future<void> loadProviders(String token) async {}

  @override
  Future<void> updatePreferences(
    String token, {
    bool? impactAlerts,
    String? impactAlertLevel,
    bool? volatilityAlerts,
    String? feedLevel,
    String? aiProvider,
  }) async {
    picked.add(aiProvider);
  }
}

class _AddsModel extends _FakeManual {
  _AddsModel(super.initial);

  @override
  Future<void> addModel(
    String token, {
    required String kind,
    required String model,
    required String apiKey,
    String? label,
    String? baseUrl,
  }) async {}
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

  @override
  Future<List<NewsSource>> getSources(String token) async => const [
        NewsSource(outlet: 'Bloomberg', section: 'Markets'),
        NewsSource(outlet: 'Bloomberg', section: 'Economics'),
        NewsSource(outlet: 'CNBC', section: 'Top News'),
      ];
}

FeedArticle _article({
  String id = 'a1',
  String? analyzedBy = 'm1',
  String? analyzedByName = 'A very long name for my own model',
  String? summary = 'The first model says this.',
  String mode = 'manual',
  bool failed = false,
  int? severity = 3,
  List<String> topics = const [],
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
      matchedTopics: topics,
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

/// The News & AI screen builds each mode as one card, so a row is built before it is on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('News & AI screen', () {
    List<Override> overrides(ManualState state, {_FakeManual? manual, _FakeUser? user}) => [
          manualProvider.overrideWith((ref) => manual ?? _FakeManual(state)),
          userProvider.overrideWith((ref) => user ?? _FakeUser()),
          newsRepositoryProvider.overrideWithValue(_FakeNews()),
        ];

    testWidgets('shows both modes, grouping off and the sources and models', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings, sources: _sources, models: _models)));
      expect(find.text('News package'), findsOneWidget);
      expect(find.text('My sources'), findsOneWidget);
      for (final block in ['Feeds', 'AI models', 'Options']) {
        expect(find.text(block), findsOneWidget);
      }
      expect(find.text('Off: every article is its own card and is analyzed separately.'), findsOneWidget);
      await _reveal(tester, find.text('Stopped one'));
      expect(find.text('Could not reach this feed'), findsOneWidget);
      expect(find.text('Paused · Every 7 minutes · x.test'), findsOneWidget);
      expect(find.text('Stopped: its account has no quota left'), findsOneWidget);
      expect(find.text('In your feed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a feed is paused or deleted from its menu', (tester) async {
      final manual = _FakeManual(const ManualState(settings: _settings, sources: _sources, models: _models));
      await _pump(tester, const ManualModeScreen(), overrides(manual.state, manual: manual));
      await _reveal(tester, find.byTooltip('Options for Feed with a long name'));
      await tester.tap(find.byTooltip('Options for Feed with a long name'));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(manual.pausedOrResumed, [('s1', false)]);
    });

    testWidgets('a stopped model is tried again or shown in the feed from its menu', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings, sources: _sources, models: _models)));
      await _reveal(tester, find.byTooltip('Options for Stopped one'));
      await tester.tap(find.byTooltip('Options for Stopped one'));
      await tester.pumpAndSettle();
      expect(find.text('Show in my feed'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Options for Mine'));
      await tester.pumpAndSettle();
      expect(find.text('Show in my feed'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('topic matching shows its choice and offers Snap and every model', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings, sources: _sources, models: _models)));
      await _reveal(tester, find.text('Topic matching'));
      expect(find.text('SubQ Snap'), findsOneWidget);
      await tester.tap(find.text('Topic matching'));
      await tester.pumpAndSettle();
      final snapTile = find.ancestor(of: find.text('SubQ Snap').last, matching: find.byType(Row)).first;
      expect(find.descendant(of: snapTile, matching: find.byIcon(Icons.radio_button_checked_rounded)), findsOneWidget);
      expect(find.text('One more call per article, on your account.'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    test('a key is only called unencrypted when it would cross a network', () {
      expect(sendsKeysUnencrypted('http://localhost:8000'), isFalse);
      expect(sendsKeysUnencrypted('http://127.0.0.1:8000'), isFalse);
      expect(sendsKeysUnencrypted('https://example.com/api'), isFalse);
      expect(sendsKeysUnencrypted('http://192.168.1.20:8000'), isTrue);
      expect(sendsKeysUnencrypted('http://10.0.2.2:8000'), isTrue);
      expect(sendsKeysUnencrypted('http://localhost.example.com'), isTrue);
    });

    testWidgets('the source count is not shown, and adding a 21st says why it cannot', (tester) async {
      final full = [
        for (var i = 0; i < 20; i++)
          UserSource(id: 's$i', url: 'https://x.test/$i', name: 'Feed $i', fetchIntervalMinutes: 15, enabled: true),
      ];
      await _pump(tester, const ManualModeScreen(), overrides(ManualState(settings: _settings, sources: full, models: _models)));
      expect(find.textContaining('/20'), findsNothing);
      await _reveal(tester, find.text('Add a feed'));
      await tester.tap(find.text('Add a feed'));
      await tester.pump();
      expect(find.text('You can have at most 20 sources.'), findsOneWidget);
      expect(find.text('Add a source'), findsNothing);
    });

    testWidgets('without a model, topic matching is Snap with nothing to choose', (tester) async {
      const manualOnly = ManualSettings(packageEnabled: false, manualEnabled: true, groupingEnabled: false, canStoreKeys: true);
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: manualOnly, sources: _sources)));
      await _reveal(tester, find.text('Topic matching'));
      expect(find.text('SubQ Snap'), findsOneWidget);
      await tester.tap(find.text('Topic matching'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsNothing);
    });

    testWidgets('warns when my sources is on without a source or a working model', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings)));
      expect(find.text('My sources needs at least one source and one working model.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with my sources off, its options stay closed', (tester) async {
      const settings = ManualSettings(packageEnabled: true, manualEnabled: false, groupingEnabled: false, canStoreKeys: true);
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: settings)));
      expect(find.text('News package'), findsOneWidget);
      expect(find.text('My sources'), findsOneWidget);
      for (final hidden in ['Feeds', 'AI models', 'Options', 'Add a feed', 'Add a model', 'Follow the app\'s feeds']) {
        expect(find.text(hidden), findsNothing);
      }
      expect(find.text('Your sources and models are kept while My sources is off.'), findsNothing);
      expect(find.text('My sources needs at least one source and one working model.'), findsNothing);
    });

    testWidgets('with my sources off, says what was added is kept', (tester) async {
      const settings = ManualSettings(packageEnabled: true, manualEnabled: false, groupingEnabled: false, canStoreKeys: true);
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: settings, sources: _sources, models: _models)));
      expect(find.text('Your sources and models are kept while My sources is off.'), findsOneWidget);
      expect(find.text('Feed with a long name'), findsNothing);
      expect(find.text('Mine'), findsNothing);
    });

    testWidgets('says so when the server cannot store keys', (tester) async {
      const settings = ManualSettings(packageEnabled: true, manualEnabled: true, groupingEnabled: false, canStoreKeys: false);
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: settings)));
      await _reveal(tester, find.text('This server cannot store API keys yet.'));
      expect(find.text('This server cannot store API keys yet.'), findsOneWidget);
    });

    testWidgets('the add model sheet warns about an unencrypted connection and needs fields', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings, sources: _sources, models: _models)));
      await _reveal(tester, find.text('Add a model'));
      await tester.tap(find.text('Add a model'));
      await tester.pumpAndSettle();
      expect(find.text('This connection to the server is not encrypted. Do not enter a real key.'), findsOneWidget);
      await tester.tap(find.text('Test and save'));
      await tester.pump();
      expect(find.text('Enter the model name and the API key.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a model that passes its test closes the sheet with a short success mark', (tester) async {
      final manual = _AddsModel(const ManualState(settings: _settings, sources: _sources, models: _models));
      await _pump(tester, const ManualModeScreen(), overrides(manual.state, manual: manual));
      await _reveal(tester, find.text('Add a model'));
      await tester.tap(find.text('Add a model'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Model name'), 'claude-haiku-5-5');
      await tester.enterText(find.widgetWithText(TextField, 'API key'), 'test-key');
      await tester.tap(find.text('Test and save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Test and save'), findsNothing);
      expect(find.text('Successful'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Successful'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the news package opens its model choice and our sources beneath it', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings)));
      expect(find.text('Analysis model'), findsOneWidget);
      expect(find.text('gpt-6-luna'), findsOneWidget);
      expect(find.text('Our sources'), findsOneWidget);
      expect(find.text('Markets, Economics'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with the news package off, its options stay closed', (tester) async {
      const packageOff = ManualSettings(packageEnabled: false, manualEnabled: true, groupingEnabled: false, canStoreKeys: true);
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: packageOff)));
      expect(find.text('Analysis model'), findsNothing);
      expect(find.text('Our sources'), findsNothing);
    });

    testWidgets('picking a package model saves it for the feed', (tester) async {
      final user = _FakeUser();
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings), user: user));
      await tester.tap(find.text('claude-haiku-5-5'));
      await tester.pump();
      expect(user.picked, ['claude']);
    });

    testWidgets('following the app\'s feeds is one switch, and those feeds are not listed one by one', (tester) async {
      const following = ManualSettings(
        packageEnabled: false,
        manualEnabled: true,
        groupingEnabled: false,
        followPackageFeeds: true,
        canStoreKeys: true,
      );
      const appFeeds = [
        UserSource(id: 'p1', url: 'https://feeds.test/a', name: 'Bloomberg', fetchIntervalMinutes: 15, enabled: true, fromPackage: true),
        UserSource(id: 'p2', url: 'https://feeds.test/b', name: 'CNBC', fetchIntervalMinutes: 15, enabled: true, fromPackage: true, lastError: 'unreachable'),
      ];
      final manual = _FakeManual(const ManualState(settings: following, sources: appFeeds, models: _models));
      await _pump(tester, const ManualModeScreen(), overrides(manual.state, manual: manual));
      expect(find.text('Bloomberg, CNBC'), findsOneWidget);
      expect(find.text('1 of them could not be read last time.'), findsOneWidget);
      expect(find.textContaining('feeds.test'), findsNothing);
      expect(find.byTooltip('Options for Bloomberg'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('follow-app-feeds')));
      await tester.pump();
      expect(manual.follows, [false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long explanations sit behind info icons', (tester) async {
      await _pump(tester, const ManualModeScreen(), overrides(const ManualState(settings: _settings, sources: _sources, models: _models)));
      expect(find.byType(InfoTip), findsWidgets);
      expect(find.textContaining('text-embedding-3-small'), findsNothing);
      expect(find.textContaining('Changes apply from now on'), findsNothing);
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byType(InfoTip)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Changes apply from now on'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
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

    testWidgets('names the followed topics that brought the story, on a narrow phone', (tester) async {
      final article = _article(topics: const ['A topic with a very long name that keeps going', 'Gold', 'Third']);
      await _pump(tester, Scaffold(body: ArticleCard(article: article, onTap: () {})), []);
      expect(find.text('Gold'), findsOneWidget);
      expect(find.text('Third'), findsNothing);
      expect(find.byIcon(Icons.sell_outlined), findsNWidgets(2));
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
