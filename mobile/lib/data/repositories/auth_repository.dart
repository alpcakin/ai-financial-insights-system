import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../../core/constants.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
}

class AuthRepository {
  static const _timeout = Duration(seconds: 15);

  Map<String, dynamic> _decode(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on FormatException {
      throw const AuthException('Server error. Please try again.');
    }
  }

  Future<RegisterResult> register({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    final body = _decode(response);

    if (response.statusCode == 201) {
      return RegisterResult.fromJson(body);
    }

    throw AuthException(body['detail'] as String? ?? 'Registration failed');
  }

  Future<void> forgotPassword(String email) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw const AuthException('Failed to send reset email. Please try again.');
    }
  }

  Future<AuthToken> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    final body = _decode(response);

    if (response.statusCode == 200) {
      return AuthToken.fromJson(body);
    }

    throw AuthException(body['detail'] as String? ?? 'Login failed');
  }
}
