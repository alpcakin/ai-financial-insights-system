import 'package:flutter/material.dart';

/// A trend at a glance: the values as one line, with no axes or labels.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double width;
  final double height;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.width = 110,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(width, height), painter: _SparklinePainter(values, color));
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final range = high - low;
    // The stroke would be cut at the edges otherwise.
    const inset = 2.0;
    final drawable = size.height - inset * 2;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = range == 0 ? size.height / 2 : inset + drawable * (1 - (values[i] - low) / range);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values || old.color != color;
}
