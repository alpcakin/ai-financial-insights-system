class AssetImpact {
  final String symbol;
  final String impact;
  final int severity;
  final String reason;

  const AssetImpact({
    required this.symbol,
    required this.impact,
    required this.severity,
    required this.reason,
  });

  factory AssetImpact.fromJson(Map<String, dynamic> json) => AssetImpact(
        symbol: json['symbol'] as String,
        impact: json['impact'] as String,
        severity: json['severity'] as int,
        reason: json['reason'] as String,
      );
}

class FeedArticle {
  final String id;
  final String title;
  final String url;
  final String? source;
  final String? summary;
  final String? sentimentLabel;
  final int? severity;
  final List<String> relatedCategories;
  final List<String> relatedAssets;
  final List<AssetImpact> assetImpacts;
  final String? publishedAt;
  final bool read;
  final bool bookmarked;

  const FeedArticle({
    required this.id,
    required this.title,
    required this.url,
    this.source,
    this.summary,
    this.sentimentLabel,
    this.severity,
    required this.relatedCategories,
    required this.relatedAssets,
    required this.assetImpacts,
    this.publishedAt,
    required this.read,
    required this.bookmarked,
  });

  FeedArticle copyWith({bool? read}) => FeedArticle(
        id: id,
        title: title,
        url: url,
        source: source,
        summary: summary,
        sentimentLabel: sentimentLabel,
        severity: severity,
        relatedCategories: relatedCategories,
        relatedAssets: relatedAssets,
        assetImpacts: assetImpacts,
        publishedAt: publishedAt,
        read: read ?? this.read,
        bookmarked: bookmarked,
      );

  factory FeedArticle.fromJson(Map<String, dynamic> json) {
    List<String> toStringList(dynamic v) {
      if (v == null) return [];
      return (v as List<dynamic>).map((e) => e.toString()).toList();
    }

    List<AssetImpact> toImpacts(dynamic v) {
      if (v == null) return [];
      return (v as List<dynamic>)
          .map((e) => AssetImpact.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return FeedArticle(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      source: json['source'] as String?,
      summary: json['summary'] as String?,
      sentimentLabel: json['sentiment_label'] as String?,
      severity: json['severity'] as int?,
      relatedCategories: toStringList(json['related_categories']),
      relatedAssets: toStringList(json['related_assets']),
      assetImpacts: toImpacts(json['asset_impacts']),
      publishedAt: json['published_at'] as String?,
      read: json['read'] as bool? ?? false,
      bookmarked: json['bookmarked'] as bool? ?? false,
    );
  }
}

class FeedResponse {
  final List<FeedArticle> articles;
  final int total;
  final int offset;
  final int limit;

  const FeedResponse({
    required this.articles,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory FeedResponse.fromJson(Map<String, dynamic> json) => FeedResponse(
        articles: (json['articles'] as List<dynamic>)
            .map((e) => FeedArticle.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        offset: json['offset'] as int,
        limit: json['limit'] as int,
      );
}
