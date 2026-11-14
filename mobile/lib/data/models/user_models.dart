class NotificationPreferences {
  final bool impactAlerts;

  /// Lowest asset level that sends a push: "high" or "very_high".
  final String impactAlertLevel;
  final bool volatilityAlerts;

  /// Lowest story level in the feed: "medium", or "low" to see low stories too.
  final String feedLevel;

  const NotificationPreferences({
    this.impactAlerts = true,
    this.impactAlertLevel = 'high',
    this.volatilityAlerts = true,
    this.feedLevel = 'medium',
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        impactAlerts: json['impact_alerts'] as bool? ?? true,
        impactAlertLevel: json['impact_alert_level'] as String? ?? 'high',
        volatilityAlerts: json['volatility_alerts'] as bool? ?? true,
        feedLevel: json['feed_level'] as String? ?? 'medium',
      );

  NotificationPreferences copyWith({
    bool? impactAlerts,
    String? impactAlertLevel,
    bool? volatilityAlerts,
    String? feedLevel,
  }) =>
      NotificationPreferences(
        impactAlerts: impactAlerts ?? this.impactAlerts,
        impactAlertLevel: impactAlertLevel ?? this.impactAlertLevel,
        volatilityAlerts: volatilityAlerts ?? this.volatilityAlerts,
        feedLevel: feedLevel ?? this.feedLevel,
      );
}

class UserProfile {
  final String id;
  final String email;
  final NotificationPreferences preferences;

  /// Key of the AI provider whose analyses this user is served, e.g. "openai".
  final String aiProvider;
  final String createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.preferences,
    required this.aiProvider,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        preferences: NotificationPreferences.fromJson(
          json['notification_preferences'] as Map<String, dynamic>? ?? {},
        ),
        aiProvider: json['ai_provider'] as String? ?? 'openai',
        createdAt: json['created_at'] as String,
      );
}

/// One AI provider the backend has enabled, as listed by GET /users/ai-providers.
class AIProviderInfo {
  final String name;
  final String displayName;
  final String model;
  final bool isDefault;

  const AIProviderInfo({
    required this.name,
    required this.displayName,
    required this.model,
    required this.isDefault,
  });

  factory AIProviderInfo.fromJson(Map<String, dynamic> json) => AIProviderInfo(
        name: json['name'] as String,
        displayName: json['display_name'] as String? ?? json['name'] as String,
        model: json['model'] as String? ?? '',
        isDefault: json['is_default'] as bool? ?? false,
      );
}

class UserException implements Exception {
  final String message;
  const UserException(this.message);
}
