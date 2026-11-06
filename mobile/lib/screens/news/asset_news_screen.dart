import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/asset_catalog.dart';
import '../../data/models/news_models.dart';
import '../../providers/asset_news_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/news_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../home/asset_browser_modal.dart';
import 'article_widgets.dart';

/// Recent stored news about one asset. The feed is not involved: nothing shown
/// here is written to it, and adding the asset only affects news that comes later.
class AssetNewsScreen extends ConsumerStatefulWidget {
  final AssetInfo asset;

  const AssetNewsScreen({super.key, required this.asset});

  @override
  ConsumerState<AssetNewsScreen> createState() => _AssetNewsScreenState();
}

class _AssetNewsScreenState extends ConsumerState<AssetNewsScreen> {
  final _scroll = ScrollController();
  bool _adding = false;

  String get _symbol => widget.asset.symbol;
  String get _token => ref.read(authProvider).token ?? '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(assetNewsProvider(_symbol).notifier).load(_token);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 400) {
      ref.read(assetNewsProvider(_symbol).notifier).loadMore(_token);
    }
  }

  Future<void> _pickAnother() async {
    final asset = await showDialog<AssetInfo>(
      context: context,
      builder: (_) => const AssetBrowserModal(),
    );
    if (asset == null || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AssetNewsScreen(asset: asset)),
    );
  }

  Future<void> _addToWatchlist() async {
    setState(() => _adding = true);
    try {
      await ref.read(watchlistProvider.notifier).add(_token, symbol: _symbol);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_symbol added to your watchlist. New news about it will reach your feed.')),
        );
      }
    } catch (_) {
      if (mounted) {
        final error = ref.read(watchlistProvider).error ?? 'Failed to add to watchlist';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _showDetail(FeedArticle article) {
    if (!article.read) {
      // Only marks anything when the story is also in the feed.
      ref.read(newsProvider.notifier).markRead(_token, article.id);
      ref.read(assetNewsProvider(_symbol).notifier).showAsRead(article.id);
    }
    showArticleDetail(context, article);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assetNewsProvider(_symbol));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _symbol,
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
            Text(
              widget.asset.name,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 22),
            tooltip: 'Search another asset',
            onPressed: _pickAnother,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(assetNewsProvider(_symbol).notifier).load(_token),
        color: const Color(0xFF3B82F6),
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _TrackingBar(symbol: _symbol, adding: _adding, onAdd: _addToWatchlist),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Last 30 days, as tagged by your model. Includes low importance news that the feed leaves out.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), height: 1.4),
              ),
            ),
            if (state.isLoading && state.articles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null && state.articles.isEmpty)
              _Message(title: 'Could not load the news', detail: state.error!)
            else if (state.articles.isEmpty)
              const _Message(
                title: 'No news yet',
                detail: 'Nothing about this asset has been analyzed in the last 30 days.',
              )
            else ...[
              ...state.articles.map((a) => ArticleCard(article: a, onTap: () => _showDetail(a))),
              if (state.isLoadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrackingBar extends ConsumerWidget {
  final String symbol;
  final bool adding;
  final VoidCallback onAdd;

  const _TrackingBar({required this.symbol, required this.adding, required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlist = ref.watch(watchlistProvider);
    final portfolio = ref.watch(portfolioProvider);
    final onWatchlist = watchlist.items.any((i) => i.assetSymbol == symbol);
    final inPortfolio = portfolio.assets.any((a) => a.assetSymbol == symbol);

    if (inPortfolio || onWatchlist) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Text(
              inPortfolio ? 'In your portfolio' : 'On your watchlist',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: adding || watchlist.isLoading || portfolio.isLoading ? null : onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text('Add to watchlist', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String title;
  final String detail;

  const _Message({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Column(
        children: [
          const Icon(Icons.article_outlined, size: 48, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8), height: 1.4),
          ),
        ],
      ),
    );
  }
}
