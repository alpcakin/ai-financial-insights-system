import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('News Feed')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Column(
          children: [
            if (categories.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: selected == null || selected.isEmpty,
                        onSelected: (_) => _setCategory(null),
                      ),
                    ),
                    ...categories.map(
                      (cat) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(cat),
                          selected: selected == cat,
                          onSelected: (_) => _setCategory(cat),
                        ),
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
                                child: Text(
                                  'No articles yet. Pull to refresh.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: state.articles.length,
                          itemBuilder: (context, index) {
                            final article = state.articles[index];
                            return _ArticleCard(
                              article: article,
                              onTap: () => _showDetail(article),
                            );
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ArticleDetailSheet(article: article),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final FeedArticle article;
  final VoidCallback onTap;

  const _ArticleCard({required this.article, required this.onTap});

  Color _sentimentColor() {
    switch (article.sentimentLabel?.toLowerCase()) {
      case 'positive':
        return Colors.green;
      case 'negative':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _severityColor() {
    final s = article.severity ?? 5;
    if (s >= 8) return Colors.red;
    if (s >= 6) return Colors.orange;
    return Colors.blue;
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

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: article.read ? 0.75 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: _sentimentColor(),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (article.source != null) article.source!,
                            _timeAgo(),
                          ].where((s) => s.isNotEmpty).join(' • '),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        if (article.summary != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            article.summary!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (article.severity != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _severityColor().withAlpha(30),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _severityColor()),
                                ),
                                child: Text(
                                  'Severity ${article.severity}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _severityColor(),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            ...article.relatedAssets.take(3).map(
                                  (sym) => Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        sym,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
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
              ],
            ),
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
      case 'positive':
        return Colors.green;
      case 'negative':
        return Colors.red;
      default:
        return Colors.grey;
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ListView(
          controller: controller,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _sentimentColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  article.sentimentLabel ?? 'neutral',
                  style: TextStyle(
                    color: _sentimentColor(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (article.severity != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Severity ${article.severity}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              article.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (article.source != null) article.source!,
                if (article.publishedAt != null) article.publishedAt!.substring(0, 10),
              ].join(' • '),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            if (article.summary != null) ...[
              const SizedBox(height: 16),
              Text(
                article.summary!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (article.assetImpacts.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Asset Impacts',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...article.assetImpacts.map(
                (impact) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              impact.symbol,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: impact.impact.toLowerCase() == 'positive'
                                    ? Colors.green.withAlpha(30)
                                    : impact.impact.toLowerCase() == 'negative'
                                        ? Colors.red.withAlpha(30)
                                        : Colors.grey.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                impact.impact,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: impact.impact.toLowerCase() == 'positive'
                                      ? Colors.green
                                      : impact.impact.toLowerCase() == 'negative'
                                          ? Colors.red
                                          : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          impact.reason,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _openUrl,
              child: const Text('Read Full Article →'),
            ),
          ],
        ),
      ),
    );
  }
}
