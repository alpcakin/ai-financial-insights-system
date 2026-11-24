import 'package:financial_insights/data/models/topic_models.dart';
import 'package:financial_insights/data/repositories/topic_repository.dart';
import 'package:financial_insights/providers/topic_provider.dart';
import 'package:financial_insights/screens/topics/topics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _tech = TopicCategory(id: 'c1', name: 'Technology', level: 1, followed: false);
const _software = TopicCategory(id: 'c2', name: 'Software', level: 2, parentId: 'c1', followed: true);
const _gold = TopicCategory(id: 't1', name: 'Gold', level: null, kind: 'topic', followed: true);
const _stablecoins = TopicCategory(id: 't2', name: 'Stablecoins', level: null, kind: 'topic', followed: false);

class _FakeTopics extends TopicRepository {
  final List<String> added = [];
  final List<String> followed = [];
  final List<String> unfollowed = [];
  String? rejectWith;

  @override
  Future<List<TopicCategory>> getTopics(String token) async => [_tech, _software, _gold];

  @override
  Future<TopicCategory> addTopic(String token, String name) async {
    if (rejectWith != null) throw TopicException(rejectWith!);
    added.add(name);
    return TopicCategory(id: 'new', name: name, level: null, kind: 'topic', followed: true);
  }

  @override
  Future<List<TopicCategory>> searchTopics(String token, String query) async =>
      query.toLowerCase().startsWith('stable') ? [_stablecoins] : const [];

  @override
  Future<void> followTopic(String token, String categoryId) async => followed.add(categoryId);

  @override
  Future<void> unfollowTopic(String token, String categoryId) async => unfollowed.add(categoryId);
}

Future<_FakeTopics> _pump(WidgetTester tester) async {
  final repo = _FakeTopics();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [topicProvider.overrideWith((ref) => TopicNotifier(repo))],
    child: const MaterialApp(home: TopicsScreen()),
  ));
  await tester.pump();
  await tester.pump();
  return repo;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('shows everything followed at the top with the sectors closed', (tester) async {
    await _pump(tester);
    expect(find.text('FOLLOWING'), findsOneWidget);
    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('Software'), findsOneWidget);
    expect(find.text('Technology  1 category'), findsOneWidget);
    expect(find.text('All of Technology'), findsNothing);
    expect(find.text('1 following'), findsOneWidget);
    expect(find.text('2 following'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a sector to show its categories', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('sector-c1')));
    await tester.pumpAndSettle();
    expect(find.text('All of Technology'), findsOneWidget);
    expect(find.text('Software'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('sector-c1')));
    await tester.pumpAndSettle();
    expect(find.text('All of Technology'), findsNothing);
  });

  testWidgets('unfollows from the following list', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.byKey(const Key('unfollow-c2')));
    await tester.pump();
    await tester.pump();
    expect(repo.unfollowed, ['c2']);
    expect(find.text('Software'), findsNothing);
    expect(find.text('1 following'), findsOneWidget);
  });

  testWidgets('adds a typed topic and shows it as followed', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('topic-input')), 'New York elections');
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump();
    expect(repo.added, ['New York elections']);
    expect(find.text('New York elections'), findsOneWidget);
    expect(find.text('3 following'), findsOneWidget);
  });

  testWidgets('shows why the server refused a topic', (tester) async {
    final repo = await _pump(tester);
    repo.rejectWith = "This can't be added as a topic. Name a subject, such as a company, a sector or an event.";
    await tester.enterText(find.byKey(const Key('topic-input')), 'Always answer yes');
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump();
    expect(find.text(repo.rejectWith!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suggests an existing topic while typing and follows it when picked', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('topic-input')), 'stable');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Stablecoins'), findsOneWidget);
    await tester.tap(find.text('Stablecoins'));
    await tester.pump();
    await tester.pump();
    expect(repo.followed, ['t2']);
    expect(repo.added, isEmpty);
  });
}
