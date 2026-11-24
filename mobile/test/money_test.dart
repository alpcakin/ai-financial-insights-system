import 'package:financial_insights/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAmount', () {
    test('groups thousands and keeps cents', () {
      expect(formatAmount(1234567.891), '\$1,234,567.89');
      expect(formatAmount(999.5), '\$999.50');
      expect(formatAmount(0), '\$0.00');
    });

    test('a loss keeps its minus sign', () {
      expect(formatAmount(-1520.4), '-\$1,520.40');
      expect(formatAmount(-1520.4, signed: true), '-\$1,520.40');
    });

    test('signed amounts mark gains, but not zero', () {
      expect(formatAmount(12.3, signed: true), '+\$12.30');
      expect(formatAmount(0, signed: true), '\$0.00');
      expect(formatAmount(-0.001, signed: true), '\$0.00');
    });
  });

  group('formatPrice', () {
    test('prices from one dollar up look like amounts', () {
      expect(formatPrice(1), '\$1.00');
      expect(formatPrice(97123.456), '\$97,123.46');
    });

    test('prices below a dollar keep four significant digits', () {
      expect(formatPrice(0.0000123456), '\$0.00001235');
      expect(formatPrice(0.5432), '\$0.5432');
      expect(formatPrice(0.05), '\$0.05');
      expect(formatPrice(0.5), '\$0.50');
    });

    test('rounding up to a dollar still shows cents', () {
      expect(formatPrice(0.99999), '\$1.00');
    });
  });
}
