import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../models/user_models.dart';

class UserRepository {
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decode(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on FormatException {
      throw const UserException('Server error. Please try again.');
    }
  }

  Future<UserProfile> getMe(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConstants.baseUrl}/users/me'),
          headers: _authHeaders(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return UserProfile.fromJson(_decode(response));
    }
    throw const UserException('Failed to load profile');
  }

  Future<UserProfile> updatePreferences(
    String token, {
    bool? impactAlerts,
    bool? volatilityAlerts,
  }) async {
    final body = <String, dynamic>{};
    if (impactAlerts != null) body['impact_alerts'] = impactAlerts;
    if (volatilityAlerts != null) body['volatility_alerts'] = volatilityAlerts;

    final response = await http
        .patch(
          Uri.parse('${AppConstants.baseUrl}/users/me'),
          headers: _authHeaders(token),
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return UserProfile.fromJson(_decode(response));
    }
    throw const UserException('Failed to update preferences');
  }

  Future<void> changePassword(
    String token, {
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http
        .patch(
          Uri.parse('${AppConstants.baseUrl}/users/me/password'),
          headers: _authHeaders(token),
          body: jsonEncode({
            'current_password': currentPassword,
            'new_password': newPassword,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) return;

    final decoded = _decode(response);
    throw UserException(decoded['detail'] as String? ?? 'Failed to change password');
  }

  Future<void> deleteAccount(String token) async {
    final response = await http
        .delete(
          Uri.parse('${AppConstants.baseUrl}/users/me'),
          headers: _authHeaders(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 204) return;
    throw const UserException('Failed to delete account');
  }

  Future<Map<String, dynamic>> exportData(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConstants.baseUrl}/users/me/export'),
          headers: _authHeaders(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return _decode(response);
    }
    throw const UserException('Failed to export data');
  }
}
