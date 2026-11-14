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
              'Not Investment Advice',
              'The analyses in this app are written automatically by AI models from news headlines and short descriptions. They can be wrong or incomplete and are for information only. Nothing in the app is investment, financial or tax advice, or a recommendation to buy or sell any asset. Make your own decisions, or ask a licensed adviser.',
            ),
            _section(
              'Data We Collect',
              'We collect your email address, portfolio holdings (asset symbols, quantities, purchase prices), watchlist items, news and price alert preferences, followed topics, and the topics and assets you add. This data is necessary to provide personalized financial insights.',
            ),
            _section(
              'How We Use Your Data',
              'Your portfolio and watchlist are used to match relevant financial news and generate alerts when these assets experience significant market events. We do not sell your data to third parties.\n\nNews articles are analyzed by third-party AI services (OpenAI, Google Gemini and Anthropic Claude); the model you select decides whose analysis you see. Only the article text and the shared asset catalog (symbols and names) are sent to these services. SubQ decides which categories and topics each article relates to, so it receives the article text and the category and topic names. To find reports of the same event, article text also goes to OpenAI and SubQ. Your email address, holdings, quantities and prices are never shared with them.',
            ),
            _section(
              'Topics and Assets You Add',
              'A topic you add is sent once to SubQ, which checks that it names a subject and is not an instruction or offensive text. Topics and assets you add join shared lists that every user can find and follow; who added them is not shown to anyone. When you search for an asset, the search text is sent to Yahoo Finance.',
            ),
            _section(
              'Your Own Sources and Keys',
              'If you use your own sources, we store their addresses, the articles fetched from them and your API keys. Keys are stored encrypted, are used only to analyze your own articles with the model you added, are never shown again (only their last 4 characters) and never written to logs. They are deleted when you delete the model or your account. Your articles and their analyses are visible only to you.\n\nThe text of your articles goes to the vendor of each model you add, on your account and under that vendor\'s terms. To match your articles to categories and your topics, it also goes to SubQ, unless you pick one of your own models for that. If you turn on same-event grouping, it also goes to OpenAI and SubQ.',
            ),
            _section(
              'Data Storage',
              'All data is stored in a secure database hosted by Supabase. Passwords are hashed using bcrypt and are never stored in plaintext. Authentication tokens are stored securely on your device.',
            ),
            _section(
              'Push Notifications',
              'With your permission, we may send push notifications for high-impact news events or significant price movements affecting your portfolio or watchlist. You can disable these at any time from the Profile screen.',
            ),
            _section(
              'Your Rights',
              'You have the right to access all data we hold about you (use "Export My Data" in Profile), and the right to delete your account and all associated data at any time.',
            ),
            _section(
              'Data Retention',
              'Your account, portfolio, watchlist, alert settings and reports are retained for as long as your account is active. News feed entries and alerts are deleted after 30 days. When you delete your account, all associated data is permanently removed from our systems. Topics and assets you added stay in the shared lists, with no link to you.',
            ),
            _section(
              'Contact',
              'For any privacy-related questions, contact us at the email address associated with this application.',
            ),
            const SizedBox(height: 8),
            Text(
              'Last updated: November 2026',
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
