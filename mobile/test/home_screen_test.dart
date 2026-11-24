import 'package:financial_insights/data/models/alert_models.dart';
import 'package:financial_insights/data/models/asset_catalog.dart';
import 'package:financial_insights/data/models/portfolio_models.dart';
import 'package:financial_insights/data/models/watchlist_models.dart';
import 'package:financial_insights/data/repositories/alert_repository.dart';
import 'package:financial_insights/data/repositories/portfolio_repository.dart';
import 'package:financial_insights/data/repositories/watchlist_repository.dart';
import 'package:financial_insights/providers/alert_provider.dart';
import 'package:financial_insights/providers/alert_settings_provider.dart';
import 'package:financial_insights/providers/asset_provider.dart';
import 'package:financial_insights/providers/portfolio_provider.dart';
import 'package:financial_insights/providers/watchlist_provider.dart';
import 'package:financial_insights/screens/home/home_screen.dart';
import 'package:financial_insights/widgets/sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

PortfolioAsset _holding(String id, String symbol, String type, double quantity, double price, double value) =>
    PortfolioAsset(
      id: id,
      assetSymbol: symbol,
      assetType: type,
      quantity: quantity,
      purchasePrice: price,
      currentPrice: value / quantity,
      currentValue: value,
      dailyChangePct: 1.2,
      addedAt: '2026-11-01T00:00:00Z',
    );

class _Portfolio extends PortfolioNotifier {
  _Portfolio() : super(PortfolioRepository()) {
    state = PortfolioState(
      assets: [
        _holding('p1', 'NVDA', 'stock', 10, 100, 1200),
        _holding('p2', 'DAL', 'stock', 20, 45, 824),
        _holding('p3', 'SHIB-USD', 'crypto', 5000000, 0.000012, 61.5),
      ],
      totalValue: 2085.5,
      totalPnl: 125.5,
      totalPnlPct: 6.4,
      totalDailyChange: 2.2,
      totalDailyChangePct: 0.11,
    );
  }

  @override
  Future<void> load(String token) async {}
}

class _Watchlist extends WatchlistNotifier {
  _Watchlist() : super(WatchlistRepository()) {
    state = const WatchlistState(items: [
      WatchlistItem(id: 'w1', assetSymbol: 'XOM', assetType: 'stock', currentPrice: 118.4, priceChange: -0.9,
          priceChangePct: -0.8, addedAt: '2026-11-01T00:00:00Z'),
      WatchlistItem(id: 'w2', assetSymbol: 'AAPL', assetType: 'stock', currentPrice: 229.1, priceChange: 0.9,
          priceChangePct: 0.4, addedAt: '2026-11-01T00:00:00Z'),
    ]);
  }

  @override
  Future<void> load(String token) async {}
}

class _Alerts extends AlertNotifier {
  _Alerts() : super(AlertRepository()) {
    state = AlertState(alerts: [
      for (final (i, symbol) in ['NVDA', 'DAL', 'XOM'].indexed)
        AlertItem(
          id: 'a$i',
          userId: 'u1',
          articleId: 's$i',
          assetSymbol: symbol,
          alertType: 'impact',
          severity: 3,
          message: '$symbol: a reason long enough to need more than one line on a narrow phone screen',
          notificationSent: false,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
    ]);
  }

  @override
  Future<void> load(String token) async {}
}

class _AlertSettings extends AlertSettingsNotifier {
  _AlertSettings() : super(AlertRepository());

  @override
  Future<void> load(String token) async {}
}

class _NoHoldings extends PortfolioNotifier {
  _NoHoldings() : super(PortfolioRepository());

  @override
  Future<void> load(String token) async {}
}

class _NoWatched extends WatchlistNotifier {
  _NoWatched() : super(WatchlistRepository());

  @override
  Future<void> load(String token) async {}
}

Future<void> _pump(WidgetTester tester, List<Override> overrides, {List<double> history = const [2000, 2050, 2085.5]}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioHistoryProvider.overrideWith((ref) async => history),
      alertSettingsProvider.overrideWith((ref) => _AlertSettings()),
      assetCatalogProvider.overrideWith((ref) async => const [
            AssetInfo(symbol: 'NVDA', name: 'NVIDIA Corporation', type: 'stock'),
            AssetInfo(symbol: 'XOM', name: 'Exxon Mobil Corporation', type: 'stock'),
          ]),
      ...overrides,
    ],
    child: const MaterialApp(home: HomeScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Home leads with the portfolio value and today\'s important news', (tester) async {
    await _pump(tester, [
      portfolioProvider.overrideWith((ref) => _Portfolio()),
      watchlistProvider.overrideWith((ref) => _Watchlist()),
      alertProvider.overrideWith((ref) => _Alerts()),
    ]);

    expect(find.text('\$2,085.50'), findsOneWidget);
    expect(find.text('\$2.20 (0.11%) today'), findsOneWidget);
    expect(find.text('+\$125.50 (+6.40%) all time'), findsOneWidget);
    expect(find.text('3 stories may move your assets'), findsOneWidget);
    expect(find.text('NVDA · DAL · XOM'), findsOneWidget);
    expect(find.byType(Sparkline), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
  });

  testWidgets('no line is drawn before there are two closes', (tester) async {
    await _pump(tester, [
      portfolioProvider.overrideWith((ref) => _Portfolio()),
      watchlistProvider.overrideWith((ref) => _Watchlist()),
      alertProvider.overrideWith((ref) => _Alerts()),
    ], history: const [2085.5]);

    expect(find.text('\$2,085.50'), findsOneWidget);
    expect(find.byType(Sparkline), findsNothing);
  });

  testWidgets('each asset row shows its name, two numbers and a bolt for news', (tester) async {
    await _pump(tester, [
      portfolioProvider.overrideWith((ref) => _Portfolio()),
      watchlistProvider.overrideWith((ref) => _Watchlist()),
      alertProvider.overrideWith((ref) => _Alerts()),
    ]);

    expect(find.text('NVIDIA Corporation'), findsOneWidget);
    expect(find.text('Crypto'), findsOneWidget);
    expect(find.text('\$1,200.00'), findsOneWidget);
    expect(find.text('\$118.40'), findsOneWidget);
    expect(find.text('▼ 0.80%'), findsOneWidget);
    // NVDA, DAL and XOM have news today; the Today card has a bolt of its own.
    expect(find.byIcon(Icons.bolt_rounded), findsNWidgets(4));
  });

  testWidgets('a new user is asked to add an asset', (tester) async {
    await _pump(tester, [
      portfolioProvider.overrideWith((ref) => _NoHoldings()),
      watchlistProvider.overrideWith((ref) => _NoWatched()),
      alertProvider.overrideWith((ref) => _Alerts()),
    ]);

    expect(find.text('Start with an asset'), findsOneWidget);
    expect(find.text('Add an asset'), findsOneWidget);
    expect(find.text('Holdings'), findsNothing);
  });
}
