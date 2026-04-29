// Handles all HTTP communication with the backend auth endpoints.
//
// This is the only layer that knows about HTTP, JSON, and status codes.
// The rest of the app works with typed Dart objects ([AuthToken]) and
// catches [AuthException] for user-facing error messages.
//
// A 15-second timeout prevents the UI from hanging indefinitely if the
// backend is unreachable.  Timeout and network errors are caught by the
// provider layer and shown as "Network error. Please try again."
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../../core/constants.dart';

/// Thrown when the backend returns a non-success status code.
/// The [message] is the "detail" field from the JSON error response.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
}

class AuthRepository {
  static const _timeout = Duration(seconds: 15);

  /// Sends email and password to POST /auth/register.
  /// Returns a [RegisterResult] on 201 Created — no token yet, email verification required.
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

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 201) {
      return RegisterResult.fromJson(body);
    }

    throw AuthException(body['detail'] as String? ?? 'Registration failed');
  }

  /// Sends email to POST /auth/forgot-password.
  /// Always succeeds on 200 — server never reveals whether the email exists.
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

  /// Sends email and password to POST /auth/login.
  /// Returns an [AuthToken] on 200 OK, throws [AuthException] otherwise.
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

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return AuthToken.fromJson(body);
    }

    throw AuthException(body['detail'] as String? ?? 'Login failed');
  }
}
