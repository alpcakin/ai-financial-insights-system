import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/severity.dart';
import '../../data/models/report_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/report_provider.dart';
import '../../widgets/advice_notice.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _expandedId;

  Future<void> _refresh() async {
    final token = ref.read(authProvider).token ?? '';
    await ref.read(reportProvider.notifier).load(token);
  }

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatPeriod(String start, String end) {
    final s = DateTime.tryParse(start);
    final e = DateTime.tryParse(end);
    if (s == null || e == null) return '$start – $end';
    return '${_months[s.month]} ${s.day} – ${_months[e.month]} ${e.day}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'Reports',
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      body: state.isLoading && state.reports.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: state.reports.isEmpty
                  ? ListView(
                      children: [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 64),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bar_chart_rounded,
                                    size: 48, color: Color(0xFFCBD5E1)),
                                const SizedBox(height: 12),
                                Text(
                                  'No reports yet',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Reports are generated automatically every Sunday',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      itemCount: state.reports.length,
                      itemBuilder: (context, index) {
                        final report = state.reports[index];
                        final isExpanded = _expandedId == report.id;
                        return _ReportCard(
                          report: report,
                          isLatest: index == 0,
                          isExpanded: isExpanded,
                          formatPeriod: _formatPeriod,
                          onTap: () => setState(() {
                            _expandedId = isExpanded ? null : report.id;
                          }),
                        );
                      },
                    ),
            ),
    );
  }
}

const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);

String _signedPct(double pct) => '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';

class _ReportCard extends StatelessWidget {
  final ReportItem report;
  final bool isLatest;
  final bool isExpanded;
  final String Function(String, String) formatPeriod;
  final VoidCallback onTap;

  const _ReportCard({
    required this.report,
    required this.isLatest,
    required this.isExpanded,
    required this.formatPeriod,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = report.content;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          hoverColor: const Color(0x050F172A),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'WEEKLY REPORT',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (isLatest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Latest',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ],
                    const Spacer(),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  formatPeriod(report.periodStart, report.periodEnd),
                  style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                ),
                const SizedBox(height: 14),
                if (content == null)
                  Text(
                    'This report could not be read.',
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                  )
                else ...[
                  _Headline(content: content),
                  if (content.portfolioPerformance.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _Movers(assets: content.portfolioPerformance),
                  ],
                ],
                if (isExpanded && content != null) ...[
                  const SizedBox(height: 18),
                  Container(height: 1, color: const Color(0xFFF1F5F9)),
                  const SizedBox(height: 16),
                  if (content.portfolioPerformance.isNotEmpty) ...[
                    _AssetPerformanceSection(assets: content.portfolioPerformance),
                    const SizedBox(height: 4),
                    Text(
                      '\$${content.totalValueNow.toStringAsFixed(2)} now, '
                      'vs \$${content.totalValue7dAgo.toStringAsFixed(2)} a week earlier',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                  if (content.topArticles.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _TopArticlesSection(articles: content.topArticles),
                    const SizedBox(height: 10),
                    const AdviceNotice(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The week's portfolio change, with how much the report covers next to it.
class _Headline extends StatelessWidget {
  final ReportContent content;

  const _Headline({required this.content});

  @override
  Widget build(BuildContext context) {
    final hasPortfolio = content.portfolioPerformance.isNotEmpty;
    final pct = content.totalChangePct;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasPortfolio ? _signedPct(pct) : '—',
                style: GoogleFonts.inter(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: !hasPortfolio ? const Color(0xFFCBD5E1) : pct >= 0 ? _green : _red,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasPortfolio ? 'Portfolio this week' : 'No portfolio to compare',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        _Stat(value: content.portfolioPerformance.length, label: 'assets'),
        const SizedBox(width: 18),
        _Stat(value: content.topArticles.length, label: 'top stories'),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A), height: 1),
        ),
        const SizedBox(height: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
      ],
    );
  }
}

/// The week's best and worst asset.
class _Movers extends StatelessWidget {
  final List<AssetPerformance> assets;

  const _Movers({required this.assets});

  @override
  Widget build(BuildContext context) {
    final sorted = [...assets]..sort((a, b) => b.changePct.compareTo(a.changePct));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MoverChip(label: 'Best', asset: sorted.first),
        if (sorted.length > 1) _MoverChip(label: 'Worst', asset: sorted.last),
      ],
    );
  }
}

class _MoverChip extends StatelessWidget {
  final String label;
  final AssetPerformance asset;

  const _MoverChip({required this.label, required this.asset});

  @override
  Widget build(BuildContext context) {
    final up = asset.changePct >= 0;
    final color = up ? _green : _red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
          Text(
            asset.symbol,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
          ),
          const SizedBox(width: 4),
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: color),
          Text(
            '${asset.changePct.abs().toStringAsFixed(2)}%',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _AssetPerformanceSection extends StatelessWidget {
  final List<AssetPerformance> assets;

  const _AssetPerformanceSection({required this.assets});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ASSET PERFORMANCE',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ...assets.map((a) {
          final isPositive = a.changePct >= 0;
          final color = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
          final sign = isPositive ? '+' : '';
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    a.symbol,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '$sign${a.changePct.toStringAsFixed(2)}%',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '\$${a.valueNow.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _TopArticlesSection extends StatelessWidget {
  final List<ArticleSummary> articles;

  const _TopArticlesSection({required this.articles});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOP ARTICLES',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ...articles.map((a) {
          final color = severityColor(a.severity);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (a.severity != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(80)),
                        ),
                        child: Text(
                          severityLabel(a.severity!),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    if (a.source != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        a.source!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ],
                ),
                if (a.title != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    a.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                      height: 1.35,
                    ),
                  ),
                ],
                if (a.summary != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    a.summary!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}
