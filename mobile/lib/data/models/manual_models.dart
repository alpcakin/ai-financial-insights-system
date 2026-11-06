class ManualSettings {
  final bool packageEnabled;
  final bool manualEnabled;
  final bool groupingEnabled;
  final String? selectedModelId;

  /// False when the server has no encryption key, so no API key can be stored.
  final bool canStoreKeys;

  const ManualSettings({
    required this.packageEnabled,
    required this.manualEnabled,
    required this.groupingEnabled,
    this.selectedModelId,
    required this.canStoreKeys,
  });

  factory ManualSettings.fromJson(Map<String, dynamic> json) => ManualSettings(
        packageEnabled: json['package_enabled'] as bool,
        manualEnabled: json['manual_enabled'] as bool,
        groupingEnabled: json['grouping_enabled'] as bool,
        selectedModelId: json['selected_model_id'] as String?,
        canStoreKeys: json['can_store_keys'] as bool,
      );
}

/// A feed the user added.
class UserSource {
  final String id;
  final String url;
  final String name;
  final int fetchIntervalMinutes;
  final bool enabled;
  final String? lastFetchedAt;

  /// "unreachable" or "unreadable" when the last fetch failed.
  final String? lastError;

  const UserSource({
    required this.id,
    required this.url,
    required this.name,
    required this.fetchIntervalMinutes,
    required this.enabled,
    this.lastFetchedAt,
    this.lastError,
  });

  factory UserSource.fromJson(Map<String, dynamic> json) => UserSource(
        id: json['id'] as String,
        url: json['url'] as String,
        name: json['name'] as String,
        fetchIntervalMinutes: json['fetch_interval_minutes'] as int,
        enabled: json['enabled'] as bool,
        lastFetchedAt: json['last_fetched_at'] as String?,
        lastError: json['last_error'] as String?,
      );
}

/// A model the user added. The key itself never comes back from the server.
class UserModel {
  final String id;
  final String kind;
  final String model;
  final String label;
  final String? baseUrl;
  final String keyLast4;

  /// "auth" or "quota" when the model was left out of the analysis.
  final String? stoppedReason;

  const UserModel({
    required this.id,
    required this.kind,
    required this.model,
    required this.label,
    this.baseUrl,
    required this.keyLast4,
    this.stoppedReason,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        kind: json['kind'] as String,
        model: json['model'] as String,
        label: json['label'] as String,
        baseUrl: json['base_url'] as String?,
        keyLast4: json['key_last4'] as String,
        stoppedReason: json['stopped_reason'] as String?,
      );
}

class ManualException implements Exception {
  final String message;
  const ManualException(this.message);
}
