import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'Privacy Policy',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(
              'Data We Collect',
              'We collect your email address, portfolio holdings (asset symbols, quantities, purchase prices), watchlist items, news alert preferences, and followed topics. This data is necessary to provide personalized financial insights.',
            ),
            _section(
              'How We Use Your Data',
              'Your portfolio data is used to match relevant financial news and generate alerts when assets in your portfolio experience significant market events. We do not sell your data to third parties.\n\nNews articles are analyzed by third-party AI services (OpenAI, Google Gemini and xAI Grok, depending on the model you select). Only the article text and the combined list of asset symbols held across all users are sent to these services. Your email address, holdings, quantities and prices are never shared with them.',
            ),
            _section(
              'Data Storage',
              'All data is stored in a secure database hosted by Supabase. Passwords are hashed using bcrypt and are never stored in plaintext. Authentication tokens are stored securely on your device.',
            ),
            _section(
              'Push Notifications',
              'With your permission, we may send push notifications for high-impact news events or significant price movements affecting your portfolio. You can disable these at any time from the Profile screen.',
            ),
            _section(
              'Your Rights',
              'You have the right to access all data we hold about you (use "Export My Data" in Profile), and the right to delete your account and all associated data at any time.',
            ),
            _section(
              'Data Retention',
              'Your data is retained for as long as your account is active. When you delete your account, all associated data is permanently removed from our systems.',
            ),
            _section(
              'Contact',
              'For any privacy-related questions, contact us at the email address associated with this application.',
            ),
            const SizedBox(height: 8),
            Text(
              'Last updated: May 2026',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF475569),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
