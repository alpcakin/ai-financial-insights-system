import 'package:financial_insights/data/models/alert_models.dart';
import 'package:financial_insights/screens/alerts/alert_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

AlertItem _alert({String? articleId, String type = 'impact'}) => AlertItem(
      id: 'al1',
      userId: 'u1',
      articleId: articleId,
      assetSymbol: 'NVDA',
      alertType: type,
      severity: 3,
      message: 'NVDA: export limits widen',
      notificationSent: true,
      createdAt: DateTime.now().toIso8601String(),
    );

Future<void> _pump(WidgetTester tester, Widget card) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('an alert about a story opens it', (tester) async {
    var opened = 0;
    await _pump(tester, AlertCard(alert: _alert(articleId: 'a1'), onTap: () => opened++));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    await tester.tap(find.text('NVDA: export limits widen'));
    expect(opened, 1);
  });

  testWidgets('an alert with nothing to open shows no arrow', (tester) async {
    await _pump(tester, AlertCard(alert: _alert(type: 'volatility')));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });
}
