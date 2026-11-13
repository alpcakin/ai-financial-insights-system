/// One entry of the asset catalog served by GET /assets.
class AssetInfo {
  final String symbol;
  final String name;
  final String type;

  /// Null for an asset a user added until a category is set by hand.
  final String? category;

  const AssetInfo({
    required this.symbol,
    required this.name,
    required this.type,
    this.category,
  });

  factory AssetInfo.fromJson(Map<String, dynamic> json) => AssetInfo(
        symbol: json['symbol'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        category: json['category'] as String?,
      );
}

/// A Yahoo listing found by GET /assets/search.
class AssetCandidate {
  final String symbol;
  final String name;
  final String type;
  final String? exchange;

  /// The catalog asset this listing already is, possibly under another symbol.
  final AssetInfo? catalogAsset;

  /// Why the listing cannot be added, when it cannot.
  final String? blocked;

  const AssetCandidate({
    required this.symbol,
    required this.name,
    required this.type,
    this.exchange,
    this.catalogAsset,
    this.blocked,
  });

  factory AssetCandidate.fromJson(Map<String, dynamic> json) {
    final catalogAsset = json['catalog_asset'] as Map<String, dynamic>?;
    return AssetCandidate(
      symbol: json['symbol'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      exchange: json['exchange'] as String?,
      catalogAsset: catalogAsset == null ? null : AssetInfo.fromJson(catalogAsset),
      blocked: json['blocked'] as String?,
    );
  }
}
