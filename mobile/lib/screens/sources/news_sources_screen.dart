import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/news_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/news_provider.dart';

class NewsSourcesScreen extends ConsumerStatefulWidget {
  const NewsSourcesScreen({super.key});

  @override
  ConsumerState<NewsSourcesScreen> createState() => _NewsSourcesScreenState();
}

class _NewsSourcesScreenState extends ConsumerState<NewsSourcesScreen> {
  late final Future<List<NewsSource>> _sources;

  static const _criteria = [
    ('Credibility', 'Outlets rated high credibility by Media Bias/Fact Check, where a rating exists.'),
    ('Data quality', 'Every item carries a real summary, not just a headline.'),
    ('Topic fit', 'Feeds cover markets, business, technology and crypto.'),
    ('Coverage', 'Together they cover stocks and ETFs, crypto, commodities and the economy.'),
    ('Speed', 'New stories usually appear in the feeds within minutes.'),
  ];

  @override
  void initState() {
    super.initState();
    final token = ref.read(authProvider).token ?? '';
    _sources = ref.read(newsRepositoryProvider).getSources(token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'News Sources',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            'News comes from a fixed list of RSS feeds. When several outlets report the same event, '
            'it is analyzed once and shown as one story with all of its sources.',
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569), height: 1.6),
          ),
          const SizedBox(height: 24),
          _heading('FEEDS'),
          FutureBuilder<List<NewsSource>>(
            future: _sources,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _body('Could not load the source list. Please try again later.');
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final sections = <String, List<String>>{};
              for (final s in snapshot.data!) {
                sections.putIfAbsent(s.outlet, () => []).add(s.section);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections.entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(
                                  e.key,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              Expanded(child: _body(e.value.join(', '))),
                            ],
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          _heading('HOW THEY WERE CHOSEN'),
          ..._criteria.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.$1,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    _body(c.$2),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _body(String text) => Text(
        text,
        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569), height: 1.5),
      );
}
