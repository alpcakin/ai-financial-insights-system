class PortfolioAsset {
  final String id;
  final String assetSymbol;
  final String assetType;
  final double quantity;
  final double purchasePrice;
  final double? currentPrice;
  final double? currentValue;
  final double? dailyChange;
  final double? dailyChangePct;
  final String addedAt;

  const PortfolioAsset({
    required this.id,
    required this.assetSymbol,
    required this.assetType,
    required this.quantity,
    required this.purchasePrice,
    this.currentPrice,
    this.currentValue,
    this.dailyChange,
    this.dailyChangePct,
    required this.addedAt,
  });

  factory PortfolioAsset.fromJson(Map<String, dynamic> json) => PortfolioAsset(
        id: json['id'] as String,
        assetSymbol: json['asset_symbol'] as String,
        assetType: json['asset_type'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        purchasePrice: (json['purchase_price'] as num).toDouble(),
        currentPrice: json['current_price'] != null
            ? (json['current_price'] as num).toDouble()
            : null,
        currentValue: json['current_value'] != null
            ? (json['current_value'] as num).toDouble()
            : null,
        dailyChange: json['daily_change'] != null
            ? (json['daily_change'] as num).toDouble()
            : null,
        dailyChangePct: json['daily_change_pct'] != null
            ? (json['daily_change_pct'] as num).toDouble()
            : null,
        addedAt: json['added_at'] as String,
      );
}

class PortfolioResponse {
  final List<PortfolioAsset> assets;
  final double totalValue;
  final double totalPnl;
  final double totalPnlPct;
  final double totalDailyChange;
  final double totalDailyChangePct;

  const PortfolioResponse({
    required this.assets,
    required this.totalValue,
    required this.totalPnl,
    required this.totalPnlPct,
    required this.totalDailyChange,
    required this.totalDailyChangePct,
  });

  factory PortfolioResponse.fromJson(Map<String, dynamic> json) =>
      PortfolioResponse(
        assets: (json['assets'] as List<dynamic>)
            .map((e) => PortfolioAsset.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalValue: (json['total_value'] as num).toDouble(),
        totalPnl: (json['total_pnl'] as num).toDouble(),
        totalPnlPct: (json['total_pnl_pct'] as num).toDouble(),
        totalDailyChange: (json['total_daily_change'] as num).toDouble(),
        totalDailyChangePct: (json['total_daily_change_pct'] as num).toDouble(),
      );
}
