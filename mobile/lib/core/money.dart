import 'dart:math';

final _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

String _grouped(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  return '${parts[0].replaceAll(_thousands, ',')}.${parts[1]}';
}

/// A dollar amount in cents with thousands separators: "$12,345.67", "-$8.20".
/// With [signed], gains get a "+" too.
String formatAmount(double value, {bool signed = false}) {
  final cents = (value * 100).round();
  final sign = cents < 0 ? '-' : signed && cents > 0 ? '+' : '';
  return '$sign\$${_grouped(value.abs())}';
}

/// A unit price. Below one dollar it keeps four significant digits, so a coin
/// worth a fraction of a cent does not read "$0.00".
String formatPrice(double value) {
  if (value >= 1 || value <= 0) return '\$${_grouped(value)}';
  final decimals = min((-log(value) / ln10).floor() + 4, 20);
  final trimmed = value.toStringAsFixed(decimals).replaceFirst(RegExp(r'0+$'), '');
  final kept = trimmed.length - trimmed.indexOf('.') - 1;
  return '\$${kept < 2 ? value.toStringAsFixed(2) : trimmed}';
}
