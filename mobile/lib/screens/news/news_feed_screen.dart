import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/news_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/news_provider.dart';

class NewsFeedScreen extends ConsumerStatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  ConsumerState<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = ref.read(authProvider).token ?? '';
      ref.read(newsProvider.notifier).load(token);
    });
  }

  Future<void> _refresh() async {
    final token = ref.read(authProvider).token ?? '';
    await ref.read(newsProvider.notifier).refresh(token);
  }

  void _setCategory(String? category) {
    final token = ref.read(authProvider).token ?? '';
    ref.read(newsProvider.notifier).setCategory(token, category);
  }

  List<String> _allCategories(List<FeedArticle> articles) {
    final seen = <String>{};
    for (final a in articles) {
      seen.addAll(a.relatedCategories);
    }
    return seen.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newsProvider);
    final categories = _allCategories(state.articles);
    final selected = state.selectedCategory;
    final unread = state.articles.where((a) => !a.read).length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Text(
              'News',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$unread new',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF3B82F6),
        child: Column(
          children: [
            if (categories.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  children: [
                    _CategoryPill(
                      label: 'All',
                      selected: selected == null || selected.isEmpty,
                      onTap: () => _setCategory(null),
                    ),
                    ...categories.map(
                      (cat) => _CategoryPill(
                        label: cat,
                        selected: selected == cat,
                        onTap: () => _setCategory(cat),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: state.isLoading && state.articles.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : state.articles.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 80),
                              child: Center(
                                child: Column(
                                  children: [
                                    const Icon(Icons.article_outlined, size: 48, color: Color(0xFFCBD5E1)),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No articles yet',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF475569),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Pull down to refresh',
                                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4, bottom: 24),
                          itemCount: state.articles.length,
                          itemBuilder: (context, index) {
                            final article = state.articles[index];
                            return _ArticleCard(article: article, onTap: () => _showDetail(article));
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(FeedArticle article) {
    final token = ref.read(authProvider).token ?? '';
    if (!article.read) {
      ref.read(newsProvider.notifier).markRead(token, article.id);
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ArticleDetailSheet(article: article),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final FeedArticle article;
  final VoidCallback onTap;

  const _ArticleCard({required this.article, required this.onTap});

  Color _sentimentColor() {
    switch (article.sentimentLabel?.toLowerCase()) {
      case 'positive': return const Color(0xFF10B981);
      case 'negative': return const Color(0xFFEF4444);
      default: return const Color(0xFF94A3B8);
    }
  }

  Color _severityColor() {
    final s = article.severity ?? 5;
    if (s >= 9) return const Color(0xFFEF4444);
    if (s >= 7) return const Color(0xFFF97316);
    return const Color(0xFF3B82F6);
  }

  String _timeAgo() {
    if (article.publishedAt == null) return '';
    final published = DateTime.tryParse(article.publishedAt!);
    if (published == null) return '';
    final diff = DateTime.now().difference(published);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  String _cleanSource(String source) {
    var s = source.split('|').first.trim();
    s = s.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: article.read ? 0.72 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (article.sentimentLabel != null) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _sentimentColor(),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      article.sentimentLabel!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _sentimentColor(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(width: 1, height: 10, color: const Color(0xFFE2E8F0)),
                    const SizedBox(width: 8),
                  ],
                  if (article.source != null)
                    Flexible(
                      child: Text(
                        _cleanSource(article.source!),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _timeAgo(),
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                article.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                  height: 1.35,
                ),
              ),
              if (article.summary != null) ...[
                const SizedBox(height: 6),
                Text(
                  article.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (article.severity != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _severityColor().withAlpha(15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _severityColor().withAlpha(80)),
                      ),
                      child: Text(
                        'S${article.severity}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _severityColor(),
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  ...article.relatedAssets.take(3).map(
                    (sym) => Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sym,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleDetailSheet extends StatelessWidget {
  final FeedArticle article;

  const _ArticleDetailSheet({required this.article});

  Color _sentimentColor() {
    switch (article.sentimentLabel?.toLowerCase()) {
      case 'positive': return const Color(0xFF10B981);
      case 'negative': return const Color(0xFFEF4444);
      default: return const Color(0xFF94A3B8);
    }
  }

  Future<void> _openUrl() async {
    final uri = Uri.parse(article.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ListView(
          controller: controller,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: _sentimentColor(), shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  article.sentimentLabel ?? 'neutral',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _sentimentColor(),
                  ),
                ),
                if (article.severity != null) ...[
                  const SizedBox(width: 12),
                  Container(width: 1, height: 12, color: const Color(0xFFE2E8F0)),
                  const SizedBox(width: 12),
                  Text(
                    'Severity ${article.severity}',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              article.title,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (article.source != null)
                  article.source!.split('|').first.trim().replaceAll('&amp;', '&'),
                if (article.publishedAt != null) article.publishedAt!.substring(0, 10),
              ].join(' · '),
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
            ),
            if (article.summary != null) ...[
              const SizedBox(height: 18),
              Text(
                article.summary!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF334155),
                  height: 1.6,
                ),
              ),
            ],
            if (article.assetImpacts.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'ASSET IMPACTS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              ...article.assetImpacts.map((impact) {
                final isPositive = impact.impact.toLowerCase() == 'positive';
                final isNegative = impact.impact.toLowerCase() == 'negative';
                final impactColor = isPositive
                    ? const Color(0xFF10B981)
                    : isNegative
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF94A3B8);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          impact.symbol,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              impact.impact,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: impactColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              impact.reason,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF64748B),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _openUrl,
              child: Text('Read Full Article', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
