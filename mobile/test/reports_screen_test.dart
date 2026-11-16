import 'package:financial_insights/data/models/report_models.dart';
import 'package:financial_insights/data/repositories/report_repository.dart';
import 'package:financial_insights/providers/report_provider.dart';
import 'package:financial_insights/screens/reports/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeReports extends ReportNotifier {
  _FakeReports(List<ReportItem> reports) : super(ReportRepository()) {
    state = ReportState(reports: reports);
  }

  @override
  Future<void> load(String token) async {}
}

AssetPerformance _asset(String symbol, double pct) => AssetPerformance(
      symbol: symbol,
      quantity: 1,
      priceNow: 100 + pct,
      price7dAgo: 100,
      changePct: pct,
      valueNow: 100 + pct,
    );

ReportItem _report(String id, String start, String end, {List<AssetPerformance> assets = const [], int stories = 0}) =>
    ReportItem(
      id: id,
      userId: 'u1',
      reportType: 'weekly',
      periodStart: start,
      periodEnd: end,
      generatedAt: '${end}T20:00:00Z',
      content: ReportContent(
        topArticles: List.generate(
          stories,
          (i) => ArticleSummary(id: 'a$i', title: 'Story $i', source: 'WSJ', severity: 3, summary: 'Summary $i'),
        ),
        portfolioPerformance: assets,
        totalValueNow: 300.64,
        totalValue7dAgo: 298.73,
        totalChangePct: 0.64,
      ),
    );

/// The test font is much wider than Inter, so this behaves like a narrow phone.
Future<void> _pump(WidgetTester tester, List<ReportItem> reports) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [reportProvider.overrideWith((ref) => _FakeReports(reports))],
    child: const MaterialApp(home: ReportsScreen()),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  final week = _report(
    'r2', '2026-11-08', '2026-11-15',
    assets: [_asset('ORCL', 7.97), _asset('MSFT', -1.27), _asset('MS', 5.08)],
    stories: 5,
  );
  final older = _report('r1', '2026-11-01', '2026-11-08');

  testWidgets('a closed report shows the week at a glance', (tester) async {
    await _pump(tester, [week, older]);
    expect(find.text('Nov 8 – Nov 15'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('+0.64%'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('ORCL'), findsOneWidget);
    expect(find.text('7.97%'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('1.27%'), findsOneWidget);
    expect(find.text('ASSET PERFORMANCE'), findsNothing);
    expect(find.text('No portfolio to compare'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a report shows its assets, stories and the notice', (tester) async {
    await _pump(tester, [week]);
    await tester.tap(find.text('Nov 8 – Nov 15'));
    await tester.pumpAndSettle();
    expect(find.text('ASSET PERFORMANCE'), findsOneWidget);
    expect(find.text('TOP ARTICLES'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Not investment advice.'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Not investment advice.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
