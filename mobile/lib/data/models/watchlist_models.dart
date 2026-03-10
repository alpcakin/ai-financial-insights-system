class WatchlistItem {
  final String id;
  final String assetSymbol;
  final String assetType;
  final double? currentPrice;
  final double? priceChange;
  final double? priceChangePct;
  final String addedAt;

  const WatchlistItem({
    required this.id,
    required this.assetSymbol,
    required this.assetType,
    this.currentPrice,
    this.priceChange,
    this.priceChangePct,
    required this.addedAt,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> json) => WatchlistItem(
        id: json['id'] as String,
        assetSymbol: json['asset_symbol'] as String,
        assetType: json['asset_type'] as String,
        currentPrice: json['current_price'] != null
            ? (json['current_price'] as num).toDouble()
            : null,
        priceChange: json['price_change'] != null
            ? (json['price_change'] as num).toDouble()
            : null,
        priceChangePct: json['price_change_pct'] != null
            ? (json['price_change_pct'] as num).toDouble()
            : null,
        addedAt: json['added_at'] as String,
      );
}
