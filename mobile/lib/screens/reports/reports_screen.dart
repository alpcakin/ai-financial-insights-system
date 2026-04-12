import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      appBar: AppBar(title: const Text('Weekly Reports')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: state.isGenerating ? null : _generate,
                child: state.isGenerating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Generate Weekly Report'),
              ),
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                state.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: state.isLoading && state.reports.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.reports.isEmpty
                    ? Center(
                        child: Text(
                          'No reports yet',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
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

  Color _changeColor(double pct) =>
      pct >= 0 ? Colors.green : Colors.red;

  @override
  Widget build(BuildContext context) {
    final content = report.content;
    final changePct = content?.totalChangePct ?? 0.0;
    final changeColor = _changeColor(changePct);
    final sign = changePct >= 0 ? '+' : '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatPeriod(report.periodStart, report.periodEnd),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (content != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: changeColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: changeColor),
                      ),
                      child: Text(
                        '$sign${changePct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: changeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
              if (isExpanded && content != null) ...[
                const Divider(height: 24),
                _PortfolioSummary(content: content),
                if (content.portfolioPerformance.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _AssetPerformanceSection(assets: content.portfolioPerformance),
                ],
                if (content.topArticles.isNotEmpty) ...[
                  const SizedBox(height: 16),
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
    final color = pct >= 0 ? Colors.green : Colors.red;
    final sign = pct >= 0 ? '+' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Portfolio Summary',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '$sign${pct.toStringAsFixed(2)}%',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '\$${content.totalValueNow.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
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
        Text('Asset Performance',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...assets.map((a) {
          final color = a.changePct >= 0 ? Colors.green : Colors.red;
          final sign = a.changePct >= 0 ? '+' : '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    a.symbol,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    '$sign${a.changePct.toStringAsFixed(2)}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '\$${a.valueNow.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
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
    if (s == null) return Colors.blue;
    if (s >= 9) return Colors.red;
    if (s >= 7) return Colors.orange;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Top Articles', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...articles.map((a) {
          final color = _severityColor(a.severity);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (a.severity != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: color),
                          ),
                          child: Text(
                            'S${a.severity}',
                            style: TextStyle(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (a.source != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          a.source!,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                  if (a.title != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      a.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                  if (a.summary != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      a.summary!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
