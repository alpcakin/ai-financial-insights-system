/// Application-wide constants.
///
/// [baseUrl] defaults to 10.0.2.2 which is how the Android emulator
/// reaches the host machine's localhost.  It can be overridden at
/// build time with --dart-define=BASE_URL=http://192.168.x.x:8000
/// for physical device testing.
///
/// The storage keys are used by FlutterSecureStorage to persist
/// the JWT session so users stay logged in between app restarts.
abstract class AppConstants {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  static const String tokenKey = 'access_token';
  static const String userIdKey = 'user_id';
  static const String userEmailKey = 'user_email';
}
