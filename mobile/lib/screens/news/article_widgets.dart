import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/severity.dart';
import '../../data/models/news_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/news_provider.dart';
import '../../widgets/ai_provider_badge.dart';

class ArticleCard extends StatelessWidget {
  final FeedArticle article;
  final VoidCallback onTap;

  const ArticleCard({super.key, required this.article, required this.onTap});

  Color _sentimentColor() {
    switch (article.sentimentLabel?.toLowerCase()) {
      case 'positive': return const Color(0xFF10B981);
      case 'negative': return const Color(0xFFEF4444);
      default: return const Color(0xFF94A3B8);
    }
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
                        article.sources.length > 1
                            ? '${_cleanSource(article.source!)} +${article.sources.length - 1}'
                            : _cleanSource(article.source!),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _timeAgo(),
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                  ),
                  if (article.analyzedByName != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: AiProviderBadge(
                        name: article.analyzedByName,
                        isFallback: article.isFallback,
                      ),
                    ),
                  ],
                  if (article.isManual) ...[
                    const SizedBox(width: 6),
                    const _ManualBadge(),
                  ],
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
              if (article.analysisFailed) ...[
                const SizedBox(height: 6),
                const _AnalysisFailedNote(),
              ],
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
                        color: severityColor(article.severity).withAlpha(15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: severityColor(article.severity).withAlpha(80)),
                      ),
                      child: Text(
                        severityLabel(article.severity!),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: severityColor(article.severity),
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

class _ManualBadge extends StatelessWidget {
  const _ManualBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Manual',
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF1D4ED8)),
      ),
    );
  }
}

class _AnalysisFailedNote extends StatelessWidget {
  const _AnalysisFailedNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Analysis failed: none of your models could analyze this article.',
      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB45309), height: 1.4),
    );
  }
}

void showArticleDetail(BuildContext context, FeedArticle article) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ArticleDetailSheet(article: article),
  );
}

/// One story in full. When several models analyzed it, the sheet switches between
/// their analyses; the feed entry itself keeps the analysis it was delivered with.
class ArticleDetailSheet extends ConsumerStatefulWidget {
  final FeedArticle article;

  const ArticleDetailSheet({super.key, required this.article});

  @override
  ConsumerState<ArticleDetailSheet> createState() => _ArticleDetailSheetState();
}

class _ArticleDetailSheetState extends ConsumerState<ArticleDetailSheet> {
  List<ArticleAnalysis> _analyses = const [];
  late String? _selected = widget.article.analyzedBy;

  FeedArticle get article => widget.article;

  @override
  void initState() {
    super.initState();
    _loadAnalyses();
  }

  Future<void> _loadAnalyses() async {
    final token = ref.read(authProvider).token ?? '';
    try {
      final analyses = await ref.read(newsRepositoryProvider).getAnalyses(token, article.id);
      if (mounted) setState(() => _analyses = analyses);
    } catch (_) {
      // The sheet still shows the analysis the article came with.
    }
  }

  ArticleAnalysis? get _other {
    if (_selected == article.analyzedBy) return null;
    for (final a in _analyses) {
      if (a.provider == _selected) return a;
    }
    return null;
  }

  Color _sentimentColor(String? sentiment) {
    switch (sentiment?.toLowerCase()) {
      case 'positive': return const Color(0xFF10B981);
      case 'negative': return const Color(0xFFEF4444);
      default: return const Color(0xFF94A3B8);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = _other;
    final sentiment = other != null ? other.sentimentLabel : article.sentimentLabel;
    final severity = other != null ? other.severity : article.severity;
    final summary = other != null ? other.summary : article.summary;
    final impacts = other != null ? other.assetImpacts : article.assetImpacts;
    final sentimentColor = _sentimentColor(sentiment);

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
                if (!article.analysisFailed) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: sentimentColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    sentiment ?? 'neutral',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sentimentColor,
                    ),
                  ),
                ],
                if (severity != null) ...[
                  const SizedBox(width: 12),
                  Container(width: 1, height: 12, color: const Color(0xFFE2E8F0)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Severity: ${severityLabel(severity)}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                    ),
                  ),
                ],
                if (article.isManual) ...[
                  const SizedBox(width: 12),
                  const _ManualBadge(),
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
            if (article.analysisFailed) ...[
              const SizedBox(height: 12),
              const _AnalysisFailedNote(),
            ],
            if (_analyses.length > 1) ...[
              const SizedBox(height: 14),
              Text(
                'COMPARE MODELS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _analyses
                    .map(
                      (a) => ChoiceChip(
                        label: Text(a.providerName, style: GoogleFonts.inter(fontSize: 12)),
                        selected: a.provider == _selected,
                        onSelected: (_) => setState(() => _selected = a.provider),
                      ),
                    )
                    .toList(),
              ),
            ] else if (article.analyzedByName != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Analyzed by',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: AiProviderBadge(
                      name: article.analyzedByName,
                      isFallback: article.isFallback,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
            if (article.isFallback && other == null) ...[
              const SizedBox(height: 6),
              Text(
                'Your chosen model had no analysis for this article, so another model\'s view is shown.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFFB45309),
                  height: 1.4,
                ),
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: 18),
              Text(
                summary,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF334155),
                  height: 1.6,
                ),
              ),
            ],
            if (impacts.isNotEmpty) ...[
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
              ...impacts.map((impact) {
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
            if (article.sources.length > 1) ...[
              const SizedBox(height: 24),
              Text(
                'REPORTED BY ${article.sources.length} OUTLETS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              ...article.sources.map(
                (s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                  ),
                  subtitle: Text(
                    s.source ?? '',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF94A3B8)),
                  onTap: () => _openUrl(s.url),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _openUrl(article.url),
              child: Text('Read Full Article', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
