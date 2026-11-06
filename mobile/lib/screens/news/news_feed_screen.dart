import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/asset_catalog.dart';
import '../../data/models/news_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/news_provider.dart';
import '../home/asset_browser_modal.dart';
import '../topics/topics_screen.dart';
import 'article_widgets.dart';
import 'asset_news_screen.dart';

class NewsFeedScreen extends ConsumerStatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  ConsumerState<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = ref.read(authProvider).token ?? '';
      ref.read(newsProvider.notifier).load(token);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 400) {
      ref.read(newsProvider.notifier).loadMore(ref.read(authProvider).token ?? '');
    }
  }

  Future<void> _searchAsset() async {
    final asset = await showDialog<AssetInfo>(
      context: context,
      builder: (_) => const AssetBrowserModal(),
    );
    if (asset == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AssetNewsScreen(asset: asset)),
    );
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
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 22),
            tooltip: 'Search news by asset',
            onPressed: _searchAsset,
          ),
          IconButton(
            icon: const Icon(Icons.interests_rounded, size: 20),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TopicsScreen()),
            ),
          ),
        ],
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
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: Text(
                                        'News reaches your feed when it matches your portfolio, watchlist or topics. '
                                        'Add an asset, or use search to read about one.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8), height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4, bottom: 24),
                          itemCount: state.articles.length + (state.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == state.articles.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final article = state.articles[index];
                            return ArticleCard(article: article, onTap: () => _showDetail(article));
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
    showArticleDetail(context, article);
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
