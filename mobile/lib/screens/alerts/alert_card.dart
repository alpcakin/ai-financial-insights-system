import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/alert_models.dart';
import '../../widgets/ai_provider_badge.dart';

class AlertCard extends StatelessWidget {
  final AlertItem alert;

  const AlertCard({super.key, required this.alert});

  Color _severityColor() {
    final s = alert.severity ?? 5;
    if (s >= 9) return const Color(0xFFEF4444);
    if (s >= 7) return const Color(0xFFF97316);
    return const Color(0xFF3B82F6);
  }

  bool get _isImpact => alert.alertType == 'impact';

  String _timeAgo() {
    final dt = DateTime.tryParse(alert.createdAt);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Icon(
              _isImpact ? Icons.article_rounded : Icons.trending_up_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (alert.assetSymbol != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          alert.assetSymbol!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    if (alert.severity != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(80)),
                        ),
                        child: Text(
                          'S${alert.severity}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    if (alert.aiProviderName != null) ...[
                      const SizedBox(width: 6),
                      AiProviderBadge(name: alert.aiProviderName),
                    ],
                    const Spacer(),
                    Text(
                      _timeAgo(),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                if (alert.message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    alert.message!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF334155),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
