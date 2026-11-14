import 'dart:async';
import 'dart:convert';

import 'package:financial_insights/core/constants.dart';
import 'package:financial_insights/data/models/auth_models.dart';
import 'package:financial_insights/data/repositories/auth_repository.dart';
import 'package:financial_insights/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(Duration expiresIn) {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'exp': exp})}.sig';
}

final _renewed = _jwt(const Duration(hours: 24));

AuthToken _token() => AuthToken(
      accessToken: _renewed,
      refreshToken: 'r2',
      tokenType: 'bearer',
      userId: 'u1',
      email: 'a@b.com',
    );

class _FakeAuth extends AuthRepository {
  final List<Future<AuthToken?> Function()> answers;
  int calls = 0;

  _FakeAuth(this.answers);

  @override
  Future<AuthToken?> refresh(String refreshToken) => answers[calls++]();

  @override
  Future<void> serverLogout(String refreshToken) async {}
}

const _storage = FlutterSecureStorage();

ProviderContainer _start(_FakeAuth repo, String accessToken) {
  FlutterSecureStorage.setMockInitialValues({
    AppConstants.tokenKey: accessToken,
    AppConstants.refreshTokenKey: 'r1',
    AppConstants.userIdKey: 'u1',
    AppConstants.userEmailKey: 'a@b.com',
  });
  final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(repo)]);
  container.read(authProvider);
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(Duration.zero);
  }
}

void main() {
  testWidgets('renews the token five minutes before it expires', (tester) async {
    final repo = _FakeAuth([() async => _token()]);
    final container = _start(repo, _jwt(const Duration(minutes: 10)));
    await _settle(tester);
    expect(container.read(authProvider).isAuthenticated, isTrue);

    await tester.pump(const Duration(minutes: 4));
    expect(repo.calls, 0);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await _settle(tester);
    expect(repo.calls, 1);
    expect(container.read(authProvider).token, _renewed);
    expect(await _storage.read(key: AppConstants.tokenKey), _renewed);
    expect(await _storage.read(key: AppConstants.refreshTokenKey), 'r2');
    container.dispose();
  });

  testWidgets('logs out when the server rejects the refresh token', (tester) async {
    final repo = _FakeAuth([() async => null]);
    final container = _start(repo, _jwt(const Duration(minutes: 2)));
    await _settle(tester);

    expect(repo.calls, 1);
    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(await _storage.read(key: AppConstants.refreshTokenKey), isNull);
    container.dispose();
  });

  testWidgets('keeps an expired session while offline and tries again a minute later',
      (tester) async {
    final expired = _jwt(const Duration(minutes: -1));
    final repo = _FakeAuth([
      () async => throw TimeoutException('offline'),
      () async => _token(),
    ]);
    final container = _start(repo, expired);
    await _settle(tester);

    expect(repo.calls, 1);
    expect(container.read(authProvider).isAuthenticated, isTrue);
    expect(container.read(authProvider).token, expired);

    await tester.pump(AuthNotifier.retryDelay);
    await _settle(tester);
    expect(repo.calls, 2);
    expect(container.read(authProvider).token, _renewed);
    container.dispose();
  });

  testWidgets('does not send a second refresh while one is in flight', (tester) async {
    final pending = Completer<AuthToken?>();
    final repo = _FakeAuth([() => pending.future]);
    final container = _start(repo, _jwt(const Duration(minutes: 2)));
    await _settle(tester);
    expect(repo.calls, 1);

    container.read(authProvider.notifier).onAppResumed();
    await _settle(tester);
    expect(repo.calls, 1);

    pending.complete(_token());
    await _settle(tester);
    expect(container.read(authProvider).token, _renewed);
    container.dispose();
  });

  testWidgets('a refresh that ends after logout does not bring the session back',
      (tester) async {
    final pending = Completer<AuthToken?>();
    final repo = _FakeAuth([() => pending.future]);
    final container = _start(repo, _jwt(const Duration(minutes: 2)));
    await _settle(tester);

    await container.read(authProvider.notifier).logout();
    pending.complete(_token());
    await _settle(tester);

    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(await _storage.read(key: AppConstants.tokenKey), isNull);
    container.dispose();
  });

  testWidgets('coming back to the app leaves a fresh token alone', (tester) async {
    final repo = _FakeAuth([() async => _token()]);
    final container = _start(repo, _jwt(const Duration(hours: 1)));
    await _settle(tester);
    expect(repo.calls, 0);

    container.read(authProvider.notifier).onAppResumed();
    await _settle(tester);
    expect(repo.calls, 0);
    container.dispose();
  });
}
