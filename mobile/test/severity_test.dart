import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:financial_insights/core/severity.dart';

void main() {
  test('labels the four levels', () {
    expect(severityLabel(1), 'Low');
    expect(severityLabel(2), 'Medium');
    expect(severityLabel(3), 'High');
    expect(severityLabel(4), 'Very high');
  });

  test('an unexpected value is not shown as a level', () {
    expect(severityLabel(7), 'Unknown');
  });

  test('high and very high stand out from the rest', () {
    expect(severityColor(4), const Color(0xFFEF4444));
    expect(severityColor(3), const Color(0xFFF97316));
    expect(severityColor(2), const Color(0xFF3B82F6));
    expect(severityColor(null), const Color(0xFF3B82F6));
  });
}
