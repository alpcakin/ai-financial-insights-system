import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/money.dart';
import '../../data/models/asset_catalog.dart';
import '../../data/models/news_models.dart';
import '../../data/models/portfolio_models.dart';
import '../../data/models/watchlist_models.dart';
import '../../providers/alert_settings_provider.dart';
import '../../providers/asset_news_provider.dart';
import '../../providers/asset_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/news_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../home/alert_setting_sheet.dart';
import '../home/asset_browser_modal.dart';
import '../home/edit_asset_sheet.dart';
import 'article_widgets.dart';

/// Opens the page of an asset known only by its symbol, such as one from the
/// portfolio, the watchlist or an alert. Its name comes from the catalog.
void openAssetPage(BuildContext context, WidgetRef ref, String symbol) {
  final catalog = ref.read(assetCatalogProvider).valueOrNull ?? const <AssetInfo>[];
  final known = catalog.where((a) => a.symbol == symbol);
  final asset = known.isEmpty ? AssetInfo(symbol: symbol, name: '', type: '') : known.first;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AssetNewsScreen(asset: asset)));
}

/// One asset: its price, the user's holding or watch and its price alert, then
/// its recent stored news. The feed is not involved: nothing shown here is
/// written to it, and adding the asset only affects news that comes later.
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

  /// The catalog is read only when the page was opened without the name.
  String _name() {
    if (widget.asset.name.isNotEmpty) return widget.asset.name;
    final catalog = ref.watch(assetCatalogProvider).valueOrNull ?? const <AssetInfo>[];
    final known = catalog.where((a) => a.symbol == _symbol);
    return known.isEmpty ? '' : known.first.name;
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
    final name = _name();

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
            if (name.isNotEmpty)
              Text(
                name,
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
            _AssetHeader(symbol: _symbol, adding: _adding, onAdd: _addToWatchlist),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'News',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: _ink),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
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

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);

/// The asset's price, the user's holding or watch, what can be done with it and,
/// quietly, its price alert. An asset the user does not track offers the watchlist.
class _AssetHeader extends ConsumerWidget {
  final String symbol;
  final bool adding;
  final VoidCallback onAdd;

  const _AssetHeader({required this.symbol, required this.adding, required this.onAdd});

  Future<void> _remove(BuildContext context, WidgetRef ref, {PortfolioAsset? holding, WatchlistItem? watched}) async {
    final fromPortfolio = holding != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fromPortfolio ? 'Remove $symbol?' : 'Stop watching $symbol?'),
        content: Text(fromPortfolio
            ? '$symbol will be removed from your portfolio.'
            : '$symbol will be removed from your watchlist.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final token = ref.read(authProvider).token ?? '';
    try {
      if (fromPortfolio) {
        await ref.read(portfolioProvider.notifier).remove(token, id: holding.id);
      } else {
        await ref.read(watchlistProvider.notifier).remove(token, id: watched!.id);
      }
    } catch (_) {
      if (!context.mounted) return;
      final error = fromPortfolio ? ref.read(portfolioProvider).error : ref.read(watchlistProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Failed to remove')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    final watchlist = ref.watch(watchlistProvider);
    final holdings = portfolio.assets.where((a) => a.assetSymbol == symbol);
    final watches = watchlist.items.where((i) => i.assetSymbol == symbol);
    final holding = holdings.isEmpty ? null : holdings.first;
    final watched = watches.isEmpty ? null : watches.first;

    if (holding == null && watched == null) {
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

    final price = holding?.currentPrice ?? watched?.currentPrice;
    final todayPct = holding?.dailyChangePct ?? watched?.priceChangePct;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                price == null ? '—' : formatPrice(price),
                style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w800, color: _ink),
              ),
              if (todayPct != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${todayPct >= 0 ? '+' : ''}${todayPct.toStringAsFixed(2)}% today',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: todayPct >= 0 ? _green : _red,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (holding != null)
            _Holding(holding: holding)
          else
            Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 16, color: _muted),
                const SizedBox(width: 6),
                Text('On your watchlist', style: GoogleFonts.inter(fontSize: 13, color: _muted)),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (holding != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showEditAssetSheet(context, ref, holding),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _remove(context, ref, holding: holding, watched: watched),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: BorderSide(color: _red.withAlpha(90)),
                    minimumSize: const Size(0, 44),
                  ),
                  icon: Icon(
                    holding != null ? Icons.delete_outline_rounded : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  label: Text(holding != null ? 'Remove' : 'Stop watching'),
                ),
              ),
            ],
          ),
          _PriceAlertRow(symbol: symbol),
        ],
      ),
    );
  }
}

class _Holding extends StatelessWidget {
  final PortfolioAsset holding;

  const _Holding({required this.holding});

  @override
  Widget build(BuildContext context) {
    final cost = holding.quantity * holding.purchasePrice;
    final value = holding.currentValue ?? cost;
    final pnl = value - cost;
    final pnlPct = cost > 0 ? pnl / cost * 100 : 0.0;
    final pnlColor = pnl >= 0 ? _green : _red;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _Line(label: 'Quantity', value: formatQuantity(holding.quantity)),
          _Line(label: 'Bought at', value: formatPrice(holding.purchasePrice)),
          _Line(label: 'Value', value: formatAmount(value)),
          _Line(
            label: 'Profit / loss',
            value: '${formatAmount(pnl, signed: true)} (${pnl >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%)',
            color: pnlColor,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Line({required this.label, required this.value, this.color = _ink});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: _muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The asset's price alert, kept quiet: one muted line that opens the choice.
/// The automatic one shows today's threshold.
class _PriceAlertRow extends ConsumerWidget {
  final String symbol;

  const _PriceAlertRow({required this.symbol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = ref.watch(alertSettingsProvider).forSymbol(symbol);
    final String text;
    if (setting.isAutomatic) {
      final threshold = ref.watch(usualMoveProvider(symbol)).valueOrNull?.thresholdPct;
      text = threshold == null
          ? 'Automatic price alert'
          : 'Automatic price alert, about ±${threshold.toStringAsFixed(1)}%';
    } else if (setting.mode == 'off') {
      text = 'Price alert off';
    } else {
      text = 'Price alert at ${setting.label}';
    }

    return InkWell(
      onTap: () => showAlertSettingSheet(context, symbol),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.notifications_none_rounded, size: 16, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, color: _muted),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Change',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF3B82F6)),
            ),
          ],
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
