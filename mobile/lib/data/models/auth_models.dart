/// Represents the response returned by POST /auth/register and POST /auth/login.
///
/// The backend sends a JSON body like:
///   { "access_token": "eyJ...", "token_type": "bearer", "user_id": "...", "email": "..." }
///
/// [fromJson] converts that map into a typed Dart object so the rest
/// of the app never works with raw maps.
class AuthToken {
  final String accessToken;
  final String tokenType;
  final String userId;
  final String email;

  const AuthToken({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
    required this.email,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        accessToken: json['access_token'] as String,
        tokenType: json['token_type'] as String,
        userId: json['user_id'] as String,
        email: json['email'] as String,
      );
}
