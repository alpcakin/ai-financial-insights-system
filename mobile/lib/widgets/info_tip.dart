import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A small "i" that explains something on tap, or on hover with a mouse, so the
/// screens can keep their explanations out of the way.
class InfoTip extends StatelessWidget {
  final String message;

  const InfoTip(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 10),
      waitDuration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: GoogleFonts.inter(fontSize: 12.5, color: Colors.white, height: 1.45),
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
      ),
    );
  }
}
