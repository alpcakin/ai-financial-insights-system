import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdviceNotice extends StatelessWidget {
  const AdviceNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
        const SizedBox(width: 5),
        Text(
          'Not investment advice.',
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
        ),
      ],
    );
  }
}
