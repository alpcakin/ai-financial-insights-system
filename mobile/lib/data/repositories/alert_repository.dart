import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/alert_models.dart';
import '../../core/constants.dart';

class AlertException implements Exception {
  final String message;
  const AlertException(this.message);
}

class AlertRepository {
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<AlertsResponse> getAlerts(
    String token, {
    int limit = 20,
    int offset = 0,
  }) async {
    final params = {'limit': '$limit', 'offset': '$offset'};
    final uri = Uri.parse('${AppConstants.baseUrl}/alerts')
        .replace(queryParameters: params);

    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return AlertsResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw AlertException(body['detail'] as String? ?? 'Failed to load alerts');
  }

  Future<void> registerToken(String token, String fcmToken) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/alerts/register-token'),
          headers: _headers(token),
          body: jsonEncode({'fcm_token': fcmToken}),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw AlertException(
        body['detail'] as String? ?? 'Failed to register token');
  }
}
