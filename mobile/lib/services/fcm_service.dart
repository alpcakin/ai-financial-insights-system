import 'package:firebase_messaging/firebase_messaging.dart';

import '../data/repositories/alert_repository.dart';

class FcmService {
  static final _messaging = FirebaseMessaging.instance;
  static final _repository = AlertRepository();

  static Future<void> init(String authToken) async {
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    final fcmToken = await _messaging.getToken();
    if (fcmToken == null) return;

    try {
      await _repository.registerToken(authToken, fcmToken);
    } catch (_) {}

    _messaging.onTokenRefresh.listen((newToken) async {
      try {
        await _repository.registerToken(authToken, newToken);
      } catch (_) {}
    });

    FirebaseMessaging.onMessage.listen((_) {});
  }
}
