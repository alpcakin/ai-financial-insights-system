import 'package:financial_insights/data/models/manual_models.dart';
import 'package:financial_insights/data/models/news_models.dart';
import 'package:financial_insights/data/models/user_models.dart';
import 'package:financial_insights/data/repositories/manual_repository.dart';
import 'package:financial_insights/data/repositories/news_repository.dart';
import 'package:financial_insights/data/repositories/user_repository.dart';
import 'package:financial_insights/providers/manual_provider.dart';
import 'package:financial_insights/providers/news_provider.dart';
import 'package:financial_insights/providers/user_provider.dart';
import 'package:financial_insights/screens/profile/profile_screen.dart';
import 'package:financial_insights/widgets/info_tip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeManual extends ManualNotifier {
  final List<Map<String, bool?>> updates = [];

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
    updates.add({'package': packageEnabled, 'manual': manualEnabled});
  }
}

class _FakeNews extends NewsRepository {
  @override
  Future<List<NewsSource>> getSources(String token) async => const [NewsSource(outlet: 'Bloomberg', section: 'Markets')];
}

class _FakeUser extends UserNotifier {
  final List<String?> feedLevels = [];

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
    feedLevels.add(feedLevel);
  }
}

const _bothOn = ManualSettings(packageEnabled: true, manualEnabled: true, groupingEnabled: false, canStoreKeys: true);

const _source = UserSource(id: 's1', url: 'https://x.test/feed.xml', name: 'Feed', fetchIntervalMinutes: 5, enabled: true);
const _model = UserModel(id: 'm1', kind: 'claude', model: 'claude-haiku-5-5', label: 'Claude Haiku', keyLast4: '1234');

/// The test font is much wider than Inter, so this behaves like a narrow phone.
/// Overflow errors fail the test.
Future<(_FakeManual, _FakeUser)> _pump(WidgetTester tester, ManualState manual) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fakeManual = _FakeManual(manual);
  final fakeUser = _FakeUser();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      manualProvider.overrideWith((ref) => fakeManual),
      userProvider.overrideWith((ref) => fakeUser),
      newsRepositoryProvider.overrideWithValue(_FakeNews()),
    ],
    child: const MaterialApp(home: ProfileScreen()),
  ));
  await tester.pump();
  await tester.pump();
  return (fakeManual, fakeUser);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('puts both news modes and the analysis model in one place, on a narrow phone', (tester) async {
    await _pump(tester, const ManualState(settings: _bothOn, sources: [_source], models: [_model]));
    expect(find.text('News & AI'), findsOneWidget);
    expect(find.text('News package and my sources'), findsOneWidget);
    expect(find.text('News package'), findsOneWidget);
    expect(find.text('My sources'), findsOneWidget);
    expect(find.text('Feeds and AI models'), findsOneWidget);
    expect(find.text('News package: GPT · gpt-6-luna\nMy sources: 1 feed · Claude Haiku'), findsOneWidget);
    expect(find.text('News sources'), findsNothing);
    await tester.scrollUntilVisible(find.text('Delete account'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Export my data'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mode switches change the news modes', (tester) async {
    final (manual, _) = await _pump(tester, const ManualState(settings: _bothOn, sources: [_source], models: [_model]));
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    expect(manual.updates, [
      {'package': null, 'manual': false},
    ]);
  });

  testWidgets('my sources on without a model says what it needs', (tester) async {
    await _pump(tester, const ManualState(settings: _bothOn, sources: [_source]));
    expect(find.text('Needs a feed and a working model.'), findsOneWidget);
    expect(find.textContaining('My sources: 1 feed · no model yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without own feeds or models, invites the user to add them', (tester) async {
    await _pump(
      tester,
      const ManualState(
        settings: ManualSettings(packageEnabled: true, manualEnabled: false, groupingEnabled: false, canStoreKeys: true),
      ),
    );
    expect(find.text('News package'), findsWidgets);
    expect(find.textContaining('My sources: add your own RSS feeds and API keys'), findsOneWidget);
  });

  testWidgets('following the app\'s feeds shows in the summary', (tester) async {
    const following = ManualSettings(
      packageEnabled: false,
      manualEnabled: true,
      groupingEnabled: false,
      followPackageFeeds: true,
      canStoreKeys: true,
    );
    const appFeed = UserSource(
      id: 'p1', url: 'https://feeds.test/a', name: 'Bloomberg', fetchIntervalMinutes: 15, enabled: true, fromPackage: true,
    );
    await _pump(tester, const ManualState(settings: following, sources: [appFeed, _source], models: [_model]));
    expect(find.textContaining('My sources: the app\'s feeds + 1 feed · Claude Haiku'), findsOneWidget);
    expect(find.text('My sources only'), findsOneWidget);
  });

  testWidgets('feeds and AI models opens one screen with the package model and your models', (tester) async {
    await _pump(tester, const ManualState(settings: _bothOn, sources: [_source], models: [_model]));
    await tester.tap(find.text('Feeds and AI models'));
    await tester.pumpAndSettle();
    expect(find.text('Analysis model'), findsOneWidget);
    expect(find.text('gpt-6-luna'), findsOneWidget);
    expect(find.text('Bloomberg'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('AI models'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Claude Haiku'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explanations sit behind an info icon', (tester) async {
    await _pump(tester, const ManualState(settings: _bothOn));
    await tester.scrollUntilVisible(find.text('Show in feed'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('mostly opinion'), findsNothing);
    final tip = find.descendant(
      of: find.ancestor(of: find.text('Show in feed'), matching: find.byType(Row)).first,
      matching: find.byType(InfoTip),
    );
    await tester.tap(tip);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('mostly opinion'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets('show in feed is a two-way choice', (tester) async {
    final (_, user) = await _pump(tester, const ManualState(settings: _bothOn));
    await tester.scrollUntilVisible(find.text('Everything'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Everything'));
    await tester.pump();
    expect(user.feedLevels, ['low']);
    expect(tester.takeException(), isNull);
  });
}
