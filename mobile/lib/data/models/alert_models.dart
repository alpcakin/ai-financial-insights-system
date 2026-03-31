class AlertItem {
  final String id;
  final String userId;
  final String? articleId;
  final String? assetSymbol;
  final String alertType;
  final int? severity;
  final String? message;
  final bool notificationSent;
  final String createdAt;

  const AlertItem({
    required this.id,
    required this.userId,
    this.articleId,
    this.assetSymbol,
    required this.alertType,
    this.severity,
    this.message,
    required this.notificationSent,
    required this.createdAt,
  });

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        articleId: json['article_id'] as String?,
        assetSymbol: json['asset_symbol'] as String?,
        alertType: json['alert_type'] as String,
        severity: json['severity'] as int?,
        message: json['message'] as String?,
        notificationSent: json['notification_sent'] as bool? ?? false,
        createdAt: json['created_at'] as String,
      );
}

class AlertsResponse {
  final List<AlertItem> alerts;
  final int total;
  final int offset;
  final int limit;

  const AlertsResponse({
    required this.alerts,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory AlertsResponse.fromJson(Map<String, dynamic> json) => AlertsResponse(
        alerts: (json['alerts'] as List<dynamic>)
            .map((e) => AlertItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        offset: json['offset'] as int,
        limit: json['limit'] as int,
      );
}
