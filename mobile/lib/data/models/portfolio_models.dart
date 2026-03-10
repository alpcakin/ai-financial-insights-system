class PortfolioAsset {
  final String id;
  final String assetSymbol;
  final String assetType;
  final double quantity;
  final double purchasePrice;
  final double? currentPrice;
  final double? currentValue;
  final String addedAt;

  const PortfolioAsset({
    required this.id,
    required this.assetSymbol,
    required this.assetType,
    required this.quantity,
    required this.purchasePrice,
    this.currentPrice,
    this.currentValue,
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
        addedAt: json['added_at'] as String,
      );
}
