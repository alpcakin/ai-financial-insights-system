import 'package:financial_insights/data/models/alert_models.dart';
import 'package:financial_insights/data/models/asset_catalog.dart';
import 'package:financial_insights/data/models/news_models.dart';
import 'package:financial_insights/data/models/portfolio_models.dart';
import 'package:financial_insights/data/models/watchlist_models.dart';
import 'package:financial_insights/data/repositories/news_repository.dart';
import 'package:financial_insights/data/repositories/portfolio_repository.dart';
import 'package:financial_insights/data/repositories/watchlist_repository.dart';
import 'package:financial_insights/providers/alert_settings_provider.dart';
import 'package:financial_insights/providers/news_provider.dart';
import 'package:financial_insights/providers/portfolio_provider.dart';
import 'package:financial_insights/providers/watchlist_provider.dart';
import 'package:financial_insights/screens/home/today_card.dart';
import 'package:financial_insights/screens/news/article_widgets.dart';
import 'package:financial_insights/screens/news/asset_news_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _Portfolio extends PortfolioNotifier {
  _Portfolio(List<PortfolioAsset> assets) : super(PortfolioRepository()) {
    state = PortfolioState(assets: assets);
  }

  @override
  Future<void> load(String token) async {}
}

class _Watchlist extends WatchlistNotifier {
  _Watchlist(List<WatchlistItem> items) : super(WatchlistRepository()) {
    state = WatchlistState(items: items);
  }

  @override
  Future<void> load(String token) async {}
}

class _NoNews extends NewsRepository {
  @override
  Future<FeedResponse> getAssetNews(String token, String symbol, {int limit = 20, int offset = 0}) async =>
      FeedResponse(articles: const [], total: 0, offset: offset, limit: limit);
}

const _nvidia = AssetInfo(symbol: 'NVDA', name: 'NVIDIA Corporation', type: 'stock');

const _holding = PortfolioAsset(
  id: 'p1',
  assetSymbol: 'NVDA',
  assetType: 'stock',
  quantity: 10,
  purchasePrice: 100,
  currentPrice: 120,
  currentValue: 1200,
  dailyChange: 2,
  dailyChangePct: 1.69,
  addedAt: '2026-11-01T00:00:00Z',
);

const _watched = WatchlistItem(
  id: 'w1',
  assetSymbol: 'NVDA',
  assetType: 'stock',
  currentPrice: 120,
  priceChange: -2,
  priceChangePct: -1.64,
  addedAt: '2026-11-01T00:00:00Z',
);

AlertItem _alert(String id, String type, {Duration ago = Duration.zero, String? articleId, String? message}) => AlertItem(
      id: id,
      userId: 'u1',
      articleId: articleId,
      assetSymbol: 'NVDA',
      alertType: type,
      severity: 3,
      message: message,
      notificationSent: false,
      createdAt: DateTime.now().subtract(ago).toUtc().toIso8601String(),
    );

/// The test font is much wider than Inter, so this behaves like a narrow phone.
/// Overflow errors fail the test.
Future<void> _pump(WidgetTester tester, Widget child, List<Override> overrides) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: child)));
  await tester.pumpAndSettle();
}

List<Override> _assetOverrides({List<PortfolioAsset> holdings = const [], List<WatchlistItem> watched = const []}) => [
      portfolioProvider.overrideWith((ref) => _Portfolio(holdings)),
      watchlistProvider.overrideWith((ref) => _Watchlist(watched)),
      newsRepositoryProvider.overrideWithValue(_NoNews()),
      usualMoveProvider.overrideWith((ref, symbol) async => const UsualMove(usualMovePct: 1.6, thresholdPct: 4.13)),
    ];

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Asset page', () {
    testWidgets('a holding shows its price, value, profit and what can be done with it', (tester) async {
      await _pump(tester, const AssetNewsScreen(asset: _nvidia), _assetOverrides(holdings: [_holding]));
      expect(find.text('\$120.00'), findsOneWidget);
      expect(find.text('+1.69% today'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('\$100.00'), findsOneWidget);
      expect(find.text('\$1,200.00'), findsOneWidget);
      expect(find.text('+\$200.00 (+20.00%)'), findsOneWidget);
      expect(find.text('Automatic price alert, about ±4.1%'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Add to watchlist'), findsNothing);
      // Edit and Remove are the same size; the price alert sits quietly below them.
      expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Edit')),
          tester.getSize(find.widgetWithText(OutlinedButton, 'Remove')));
      expect(tester.getTopLeft(find.text('Change')).dy, greaterThan(tester.getTopLeft(find.text('Remove')).dy));
    });

    testWidgets('a watched asset can stop being watched', (tester) async {
      await _pump(tester, const AssetNewsScreen(asset: _nvidia), _assetOverrides(watched: [_watched]));
      expect(find.text('On your watchlist'), findsOneWidget);
      expect(find.text('-1.64% today'), findsOneWidget);
      expect(find.text('Stop watching'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('an asset the user does not track offers the watchlist', (tester) async {
      await _pump(tester, const AssetNewsScreen(asset: _nvidia), _assetOverrides());
      expect(find.text('Add to watchlist'), findsOneWidget);
      expect(find.textContaining('alert'), findsNothing);
    });
  });

  group('Today card', () {
    test('keeps only the impact alerts of the last 24 hours', () {
      final alerts = [
        _alert('a1', 'impact', articleId: 's1', message: 'NVDA: export limits widen'),
        _alert('a2', 'impact', ago: const Duration(hours: 30), articleId: 's2', message: 'NVDA: older news'),
        _alert('a3', 'volatility', message: 'NVDA moved down 6.0% since the previous close'),
      ];
      expect(todayImpactAlerts(alerts).map((a) => a.id), ['a1']);
    });

    testWidgets('counts today\'s stories and lists them in a sheet', (tester) async {
      final alerts = [
        _alert('a1', 'impact', articleId: 's1', message: 'NVDA: export limits widen'),
        _alert('a2', 'impact', articleId: 's2', message: 'NVDA: a second story'),
      ];
      await _pump(tester, Scaffold(body: TodayCard(alerts: alerts)), []);
      expect(find.text('2 stories may move your assets'), findsOneWidget);
      expect(find.text('NVDA'), findsOneWidget);
      expect(find.textContaining('export limits widen'), findsNothing);

      await tester.tap(find.text('2 stories may move your assets'));
      await tester.pumpAndSettle();
      expect(find.text('export limits widen'), findsOneWidget);
      expect(find.text('a second story'), findsOneWidget);
    });

    testWidgets('says so when nothing important happened', (tester) async {
      await _pump(tester, const Scaffold(body: TodayCard(alerts: [])), []);
      expect(find.text('No high-impact news about your assets today'), findsOneWidget);
    });
  });

  group('Story card', () {
    const article = FeedArticle(
      id: 'a1',
      title: 'Oil prices jump after the supply cut',
      url: 'https://x.test/a1',
      source: 'WSJ',
      summary: null,
      sentimentLabel: 'positive',
      severity: 2,
      relatedCategories: [],
      relatedAssets: ['DAL', 'XOM', 'CVX'],
      assetImpacts: [
        AssetImpact(symbol: 'DAL', impact: 'negative', severity: 3, reason: 'Fuel costs rise'),
        AssetImpact(symbol: 'XOM', impact: 'positive', severity: 2, reason: 'Higher prices'),
        AssetImpact(symbol: 'CVX', impact: 'positive', severity: 2, reason: 'Higher prices'),
      ],
      publishedAt: '2026-11-20T10:00:00Z',
      read: false,
    );
    const airline = PortfolioAsset(
      id: 'p1', assetSymbol: 'DAL', assetType: 'stock', quantity: 5, purchasePrice: 40, addedAt: '2026-11-01T00:00:00Z',
    );
    const oil = WatchlistItem(id: 'w1', assetSymbol: 'XOM', assetType: 'stock', addedAt: '2026-11-01T00:00:00Z');

    testWidgets('shows only the user\'s own assets, each with its direction, above the title', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        Scaffold(body: ArticleCard(article: article, onTap: () {})),
        [
          portfolioProvider.overrideWith((ref) => _Portfolio([airline])),
          watchlistProvider.overrideWith((ref) => _Watchlist(const [oil])),
        ],
      );
      // The tappable card merges its children into one semantics label.
      expect(find.bySemanticsLabel(RegExp('DAL: negative, High')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('XOM: positive, Medium')), findsOneWidget);
      semantics.dispose();
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.text('CVX'), findsNothing);
      expect(tester.getTopLeft(find.text('DAL')).dy, lessThan(tester.getTopLeft(find.text(article.title)).dy));
    });

    testWidgets('names no asset when the story touches none of the user\'s', (tester) async {
      await _pump(
        tester,
        Scaffold(body: ArticleCard(article: article, onTap: () {})),
        [
          portfolioProvider.overrideWith((ref) => _Portfolio(const [])),
          watchlistProvider.overrideWith((ref) => _Watchlist(const [])),
        ],
      );
      for (final symbol in ['DAL', 'XOM', 'CVX']) {
        expect(find.text(symbol), findsNothing);
      }
      expect(find.text('Medium'), findsOneWidget);
    });
  });
}
