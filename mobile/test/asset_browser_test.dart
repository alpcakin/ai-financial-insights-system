import 'package:financial_insights/data/models/asset_catalog.dart';
import 'package:financial_insights/data/repositories/asset_repository.dart';
import 'package:financial_insights/providers/asset_provider.dart';
import 'package:financial_insights/screens/home/asset_browser_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _apple = AssetInfo(symbol: 'AAPL', name: 'Apple Inc.', type: 'stock', category: 'Consumer Electronics');

class _FakeAssets extends AssetRepository {
  final List<AssetCandidate> results;
  final AssetException? addError;
  final List<String> searched = [];
  final List<String> added = [];

  _FakeAssets({this.results = const [], this.addError});

  @override
  Future<List<AssetInfo>> getAssets(String token) async => const [_apple];

  @override
  Future<List<AssetCandidate>> search(String token, String query) async {
    searched.add(query);
    return results;
  }

  @override
  Future<AssetInfo> add(String token, String symbol) async {
    if (addError != null) throw addError!;
    added.add(symbol);
    final candidate = results.firstWhere((c) => c.symbol == symbol);
    return AssetInfo(symbol: symbol, name: candidate.name, type: candidate.type);
  }
}

/// Opens the browser and returns a getter for what it closed with.
Future<AssetInfo? Function()> _open(WidgetTester tester, _FakeAssets repo) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AssetInfo? picked;
  await tester.pumpWidget(ProviderScope(
    overrides: [assetRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await showDialog<AssetInfo>(context: context, builder: (_) => const AssetBrowserModal());
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => picked;
}

Future<void> _searchYahoo(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump();
  await tester.tap(find.text('Search Yahoo for "$query"'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Asset models', () {
    test('an added asset has no category', () {
      final asset = AssetInfo.fromJson({'symbol': 'THYAO.IS', 'name': 'THY', 'type': 'stock', 'category': null});
      expect(asset.category, isNull);
    });

    test('a candidate carries its catalog asset and why it is blocked', () {
      final candidate = AssetCandidate.fromJson({
        'symbol': 'APC.DE',
        'name': 'Apple Inc.',
        'type': 'stock',
        'exchange': 'XETRA',
        'catalog_asset': {'symbol': 'AAPL', 'name': 'Apple Inc.', 'type': 'stock', 'category': 'Consumer Electronics'},
        'blocked': null,
      });
      expect(candidate.catalogAsset!.symbol, 'AAPL');
      expect(candidate.blocked, isNull);
      expect(AssetCandidate.fromJson({'symbol': 'ARB-USD', 'name': 'ARbit', 'type': 'crypto', 'blocked': 'taken'}).blocked,
          'taken');
    });
  });

  group('Asset browser', () {
    testWidgets('adds an asset found on Yahoo and returns it', (tester) async {
      final repo = _FakeAssets(results: const [
        AssetCandidate(symbol: 'THYAO.IS', name: 'Türk Hava Yollari Anonim Ortakligi', type: 'stock', exchange: 'IST'),
      ]);
      final picked = await _open(tester, repo);
      await _searchYahoo(tester, 'thy');
      expect(repo.searched, ['thy']);
      expect(find.textContaining('Tap to add'), findsOneWidget);

      await tester.tap(find.text('THYAO.IS'));
      await tester.pumpAndSettle();
      expect(repo.added, ['THYAO.IS']);
      expect(find.byType(AssetBrowserModal), findsNothing);
      expect(picked()!.symbol, 'THYAO.IS');
      expect(picked()!.category, isNull);
    });

    testWidgets('another listing leads to the catalog asset and a blocked one cannot be picked', (tester) async {
      final repo = _FakeAssets(results: const [
        AssetCandidate(symbol: 'APC.DE', name: 'Apple Inc.', type: 'stock', catalogAsset: _apple),
        AssetCandidate(symbol: 'ARB-USD', name: 'ARbit', type: 'crypto', blocked: 'ARB-USD was the symbol of Arbitrum.'),
      ]);
      final picked = await _open(tester, repo);
      await _searchYahoo(tester, 'ap');
      expect(find.textContaining('In the catalog as AAPL'), findsOneWidget);
      expect(find.textContaining('ARB-USD was the symbol of Arbitrum.'), findsOneWidget);

      await tester.tap(find.text('ARB-USD'));
      await tester.pumpAndSettle();
      expect(find.byType(AssetBrowserModal), findsOneWidget);

      await tester.tap(find.text('APC.DE'));
      await tester.pumpAndSettle();
      expect(repo.added, isEmpty);
      expect(picked()!.symbol, 'AAPL');
    });

    testWidgets('shows why adding failed and stays open', (tester) async {
      final repo = _FakeAssets(
        results: const [AssetCandidate(symbol: 'NOPRICE', name: 'No Price Inc.', type: 'stock')],
        addError: const AssetException('Yahoo has no price for NOPRICE'),
      );
      await _open(tester, repo);
      await _searchYahoo(tester, 'no');
      await tester.tap(find.text('NOPRICE'));
      await tester.pumpAndSettle();
      expect(find.text('Yahoo has no price for NOPRICE'), findsOneWidget);
      expect(find.byType(AssetBrowserModal), findsOneWidget);
    });

    testWidgets('a new query clears the Yahoo results', (tester) async {
      final repo = _FakeAssets(results: const [AssetCandidate(symbol: 'THYAO.IS', name: 'THY', type: 'stock')]);
      await _open(tester, repo);
      await _searchYahoo(tester, 'thy');
      expect(find.text('THYAO.IS'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'thya');
      await tester.pump();
      expect(find.text('THYAO.IS'), findsNothing);
      expect(find.text('Search Yahoo for "thya"'), findsOneWidget);
    });
  });
}
