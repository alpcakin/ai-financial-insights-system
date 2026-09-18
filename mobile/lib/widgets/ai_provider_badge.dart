import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Small chip naming the AI model that produced an analysis.
///
/// When [isFallback] is true the user's chosen model had no analysis for
/// this item and another model's result is shown instead; the chip switches
/// to an amber style so that is visible at a glance.
class AiProviderBadge extends StatelessWidget {
  final String? name;
  final bool isFallback;
  final double fontSize;

  const AiProviderBadge({
    super.key,
    required this.name,
    this.isFallback = false,
    this.fontSize = 10,
  });

  static const _neutralFg = Color(0xFF475569);
  static const _neutralBg = Color(0xFFF1F5F9);
  static const _fallbackFg = Color(0xFFB45309);
  static const _fallbackBg = Color(0xFFFEF3C7);

  @override
  Widget build(BuildContext context) {
    if (name == null || name!.isEmpty) return const SizedBox.shrink();

    final fg = isFallback ? _fallbackFg : _neutralFg;
    final bg = isFallback ? _fallbackBg : _neutralBg;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFallback ? Icons.swap_horiz_rounded : Icons.auto_awesome_rounded,
            size: fontSize + 1,
            color: fg,
          ),
          const SizedBox(width: 3),
          Text(
            name!,
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: isFallback
          ? 'Your chosen model had no analysis for this item, so $name is shown instead.'
          : 'Analyzed by $name',
      child: chip,
    );
  }
}
