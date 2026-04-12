class ArticleSummary {
  final String? id;
  final String? title;
  final String? source;
  final int? severity;
  final String? sentimentLabel;
  final String? summary;
  final String? publishedAt;

  const ArticleSummary({
    this.id,
    this.title,
    this.source,
    this.severity,
    this.sentimentLabel,
    this.summary,
    this.publishedAt,
  });

  factory ArticleSummary.fromJson(Map<String, dynamic> json) => ArticleSummary(
        id: json['id'] as String?,
        title: json['title'] as String?,
        source: json['source'] as String?,
        severity: json['severity'] as int?,
        sentimentLabel: json['sentiment_label'] as String?,
        summary: json['summary'] as String?,
        publishedAt: json['published_at'] as String?,
      );
}

class AssetPerformance {
  final String symbol;
  final double quantity;
  final double priceNow;
  final double price7dAgo;
  final double changePct;
  final double valueNow;

  const AssetPerformance({
    required this.symbol,
    required this.quantity,
    required this.priceNow,
    required this.price7dAgo,
    required this.changePct,
    required this.valueNow,
  });

  factory AssetPerformance.fromJson(Map<String, dynamic> json) =>
      AssetPerformance(
        symbol: json['symbol'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        priceNow: (json['price_now'] as num).toDouble(),
        price7dAgo: (json['price_7d_ago'] as num).toDouble(),
        changePct: (json['change_pct'] as num).toDouble(),
        valueNow: (json['value_now'] as num).toDouble(),
      );
}

class ReportContent {
  final List<ArticleSummary> topArticles;
  final List<AssetPerformance> portfolioPerformance;
  final double totalValueNow;
  final double totalValue7dAgo;
  final double totalChangePct;

  const ReportContent({
    required this.topArticles,
    required this.portfolioPerformance,
    required this.totalValueNow,
    required this.totalValue7dAgo,
    required this.totalChangePct,
  });

  factory ReportContent.fromJson(Map<String, dynamic> json) => ReportContent(
        topArticles: (json['top_articles'] as List<dynamic>)
            .map((e) => ArticleSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        portfolioPerformance: (json['portfolio_performance'] as List<dynamic>)
            .map((e) => AssetPerformance.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalValueNow: (json['total_value_now'] as num).toDouble(),
        totalValue7dAgo: (json['total_value_7d_ago'] as num).toDouble(),
        totalChangePct: (json['total_change_pct'] as num).toDouble(),
      );
}

class ReportItem {
  final String id;
  final String userId;
  final String reportType;
  final String periodStart;
  final String periodEnd;
  final ReportContent? content;
  final String generatedAt;

  const ReportItem({
    required this.id,
    required this.userId,
    required this.reportType,
    required this.periodStart,
    required this.periodEnd,
    this.content,
    required this.generatedAt,
  });

  factory ReportItem.fromJson(Map<String, dynamic> json) => ReportItem(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        reportType: json['report_type'] as String,
        periodStart: json['period_start'] as String,
        periodEnd: json['period_end'] as String,
        content: json['content'] != null
            ? ReportContent.fromJson(json['content'] as Map<String, dynamic>)
            : null,
        generatedAt: json['generated_at'] as String,
      );
}

class ReportsResponse {
  final List<ReportItem> reports;
  final int total;
  final int offset;
  final int limit;

  const ReportsResponse({
    required this.reports,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory ReportsResponse.fromJson(Map<String, dynamic> json) =>
      ReportsResponse(
        reports: (json['reports'] as List<dynamic>)
            .map((e) => ReportItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        offset: json['offset'] as int,
        limit: json['limit'] as int,
      );
}
