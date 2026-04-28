import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/report_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/report_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _expandedId;

  Future<void> _generate() async {
    final token = ref.read(authProvider).token ?? '';
    await ref.read(reportProvider.notifier).generate(token);
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: GestureDetector(
              onTap: state.isGenerating ? null : _generate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: state.isGenerating
                      ? const Color(0xFFF1F5F9)
                      : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (state.isGenerating)
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF94A3B8),
                        ),
                      )
                    else
                      const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      state.isGenerating ? 'Generating...' : 'Generate Weekly Report',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: state.isGenerating
                            ? const Color(0xFF94A3B8)
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                state.error!,
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEF4444)),
              ),
            ),
          Expanded(
            child: state.isLoading && state.reports.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.reports.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bar_chart_rounded, size: 48, color: Color(0xFFCBD5E1)),
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
                              'Generate your first weekly report above',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        itemCount: state.reports.length,
                        itemBuilder: (context, index) {
                          final report = state.reports[index];
                          final isExpanded = _expandedId == report.id;
                          return _ReportCard(
                            report: report,
                            isExpanded: isExpanded,
                            formatPeriod: _formatPeriod,
                            onTap: () => setState(() {
                              _expandedId = isExpanded ? null : report.id;
                            }),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ReportItem report;
  final bool isExpanded;
  final String Function(String, String) formatPeriod;
  final VoidCallback onTap;

  const _ReportCard({
    required this.report,
    required this.isExpanded,
    required this.formatPeriod,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = report.content;
    final changePct = content?.totalChangePct ?? 0.0;
    final isPositive = changePct >= 0;
    final changeColor = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final sign = isPositive ? '+' : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF475569)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekly Report',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          formatPeriod(report.periodStart, report.periodEnd),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (content != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: changeColor.withAlpha(15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: changeColor.withAlpha(80)),
                      ),
                      child: Text(
                        '$sign${changePct.toStringAsFixed(2)}%',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: changeColor,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF94A3B8),
                    size: 20,
                  ),
                ],
              ),
              if (isExpanded && content != null) ...[
                const SizedBox(height: 16),
                Container(height: 1, color: const Color(0xFFE2E8F0)),
                const SizedBox(height: 16),
                _PortfolioSummary(content: content),
                if (content.portfolioPerformance.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _AssetPerformanceSection(assets: content.portfolioPerformance),
                ],
                if (content.topArticles.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _TopArticlesSection(articles: content.topArticles),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PortfolioSummary extends StatelessWidget {
  final ReportContent content;

  const _PortfolioSummary({required this.content});

  @override
  Widget build(BuildContext context) {
    final pct = content.totalChangePct;
    final isPositive = pct >= 0;
    final color = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final sign = isPositive ? '+' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PORTFOLIO SUMMARY',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign${pct.toStringAsFixed(2)}%',
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '\$${content.totalValueNow.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'vs \$${content.totalValue7dAgo.toStringAsFixed(2)} seven days ago',
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
        ),
      ],
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

  Color _severityColor(int? s) {
    if (s == null) return const Color(0xFF3B82F6);
    if (s >= 9) return const Color(0xFFEF4444);
    if (s >= 7) return const Color(0xFFF97316);
    return const Color(0xFF3B82F6);
  }

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
          final color = _severityColor(a.severity);
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
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(80)),
                        ),
                        child: Text(
                          'S${a.severity}',
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
