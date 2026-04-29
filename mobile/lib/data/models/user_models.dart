class NotificationPreferences {
  final bool impactAlerts;
  final bool volatilityAlerts;

  const NotificationPreferences({
    this.impactAlerts = true,
    this.volatilityAlerts = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        impactAlerts: json['impact_alerts'] as bool? ?? true,
        volatilityAlerts: json['volatility_alerts'] as bool? ?? true,
      );

  NotificationPreferences copyWith({bool? impactAlerts, bool? volatilityAlerts}) =>
      NotificationPreferences(
        impactAlerts: impactAlerts ?? this.impactAlerts,
        volatilityAlerts: volatilityAlerts ?? this.volatilityAlerts,
      );
}

class UserProfile {
  final String id;
  final String email;
  final NotificationPreferences preferences;
  final String createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.preferences,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        preferences: NotificationPreferences.fromJson(
          json['notification_preferences'] as Map<String, dynamic>? ?? {},
        ),
        createdAt: json['created_at'] as String,
      );
}

class UserException implements Exception {
  final String message;
  const UserException(this.message);
}
