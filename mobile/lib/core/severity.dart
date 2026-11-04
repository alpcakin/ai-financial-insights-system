import 'package:flutter/material.dart';

/// Importance levels as the backend stores them.
const _severityLabels = {1: 'Low', 2: 'Medium', 3: 'High', 4: 'Very high'};

String severityLabel(int severity) => _severityLabels[severity] ?? 'Unknown';

Color severityColor(int? severity) {
  if (severity == null) return const Color(0xFF3B82F6);
  if (severity >= 4) return const Color(0xFFEF4444);
  if (severity == 3) return const Color(0xFFF97316);
  return const Color(0xFF3B82F6);
}
