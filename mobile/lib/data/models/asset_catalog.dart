/// One entry of the asset catalog served by GET /assets.
class AssetInfo {
  final String symbol;
  final String name;
  final String type;
  final String category;

  const AssetInfo({
    required this.symbol,
    required this.name,
    required this.type,
    required this.category,
  });

  factory AssetInfo.fromJson(Map<String, dynamic> json) => AssetInfo(
        symbol: json['symbol'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        category: json['category'] as String,
      );
}
