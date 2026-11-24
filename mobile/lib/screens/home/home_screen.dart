import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/money.dart';
import '../../core/severity.dart';
import '../../data/models/alert_models.dart';
import '../../data/models/asset_catalog.dart';
import '../../data/models/portfolio_models.dart';
import '../../data/models/watchlist_models.dart';
import '../../providers/alert_provider.dart';
import '../../providers/alert_settings_provider.dart';
import '../../providers/asset_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../widgets/sparkline.dart';
import '../alerts/alert_card.dart';
import '../alerts/alerts_screen.dart';
import '../news/asset_news_screen.dart';
import 'asset_browser_modal.dart';
import 'today_card.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);

/// The user's day at a glance: what their portfolio is worth, whether anything
/// important happened to their assets, and the assets themselves. Every row
/// shows two numbers; the rest is one tap away on the asset's page.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = ref.read(authProvider).token ?? '';
      ref.read(portfolioProvider.notifier).load(token);
      ref.read(watchlistProvider.notifier).load(token);
      ref.read(alertProvider.notifier).load(token);
      ref.read(alertSettingsProvider.notifier).load(token);
    });
  }

  Future<void> _refresh() async {
    final token = ref.read(authProvider).token ?? '';
    ref.invalidate(portfolioHistoryProvider);
    await Future.wait([
      ref.read(portfolioProvider.notifier).load(token),
      ref.read(watchlistProvider.notifier).load(token),
      ref.read(alertProvider.notifier).load(token),
      ref.read(alertSettingsProvider.notifier).load(token),
    ]);
  }

  /// One add button for both lists: the user first says what the asset is to them.
  Future<void> _openAddChoice() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Add an asset', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('To your portfolio'),
                subtitle: const Text('Something you own, with its quantity and price'),
                onTap: () => Navigator.pop(ctx, 'portfolio'),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('To your watchlist'),
                subtitle: const Text('Something you follow for its news and price'),
                onTap: () => Navigator.pop(ctx, 'watchlist'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'portfolio') await _addToPortfolio();
    if (choice == 'watchlist') await _addToWatchlist();
  }

  Future<AssetInfo?> _pickAsset() {
    return showDialog<AssetInfo>(
      context: context,
      builder: (_) => const AssetBrowserModal(),
    );
  }

  Future<void> _addToPortfolio() async {
    final asset = await _pickAsset();
    if (asset == null || !mounted) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PortfolioDetailsSheet(asset: asset),
    );
    if (!mounted) return;
    if (result == false) {
      final error = ref.read(portfolioProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  Future<void> _addToWatchlist() async {
    final asset = await _pickAsset();
    if (asset == null || !mounted) return;
    final token = ref.read(authProvider).token ?? '';
    try {
      await ref.read(watchlistProvider.notifier).add(token, symbol: asset.symbol);
    } catch (_) {
      if (!mounted) return;
      final error = ref.read(watchlistProvider).error ?? 'Failed to add to watchlist';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<bool> _confirmRemove(String title, String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _deletePortfolioAsset(PortfolioAsset asset) async {
    final confirmed = await _confirmRemove(
      'Remove ${asset.assetSymbol}?',
      '${asset.assetSymbol} will be removed from your portfolio.',
    );
    if (!confirmed || !mounted) return false;
    final token = ref.read(authProvider).token ?? '';
    try {
      await ref.read(portfolioProvider.notifier).remove(token, id: asset.id);
      return true;
    } catch (_) {
      if (mounted) {
        final error = ref.read(portfolioProvider).error ?? 'Failed to delete';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
      return false;
    }
  }

  Future<bool> _deleteWatchlistItem(WatchlistItem item) async {
    final confirmed = await _confirmRemove(
      'Stop watching ${item.assetSymbol}?',
      '${item.assetSymbol} will be removed from your watchlist.',
    );
    if (!confirmed || !mounted) return false;
    final token = ref.read(authProvider).token ?? '';
    try {
      await ref.read(watchlistProvider.notifier).remove(token, id: item.id);
      return true;
    } catch (_) {
      if (mounted) {
        final error = ref.read(watchlistProvider).error ?? 'Failed to delete';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    final watchlist = ref.watch(watchlistProvider);
    final today = todayImpactAlerts(ref.watch(alertProvider).alerts);
    final names = {
      for (final a in ref.watch(assetCatalogProvider).valueOrNull ?? const <AssetInfo>[]) a.symbol: a.name,
    };
    // The strongest of today's important stories per asset, shown on its row.
    final newsLevel = <String, int>{};
    for (final alert in today) {
      final symbol = alert.assetSymbol;
      if (symbol == null) continue;
      final level = alert.severity ?? 0;
      if (level > (newsLevel[symbol] ?? 0)) newsLevel[symbol] = level;
    }

    ref.listen(
      portfolioProvider.select((s) => s.isLoading ? null : s.error),
      (_, error) {
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        }
      },
    );

    ref.listen(
      watchlistProvider.select((s) => s.isLoading ? null : s.error),
      (_, error) {
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        }
      },
    );

    final hasHoldings = portfolio.assets.isNotEmpty;
    final hasWatched = watchlist.items.isNotEmpty;
    final loading = (portfolio.isLoading || watchlist.isLoading) && !hasHoldings && !hasWatched;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Financial Insights',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 24),
            tooltip: 'Add an asset',
            onPressed: _openAddChoice,
          ),
          _AlertsBellButton(onSeeAll: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertsScreen()),
            );
          }),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF3B82F6),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          children: [
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!hasHoldings && !hasWatched)
              _Welcome(onAdd: _openAddChoice)
            else ...[
              if (hasHoldings) _Summary(state: portfolio),
              TodayCard(alerts: today),
              if (hasHoldings) ...[
                _SectionTitle(title: 'Holdings', count: portfolio.assets.length),
                _Group(
                  children: [
                    for (final asset in portfolio.assets)
                      _Removable(
                        key: Key(asset.id),
                        onRemove: () => _deletePortfolioAsset(asset),
                        child: _AssetRow(
                          symbol: asset.assetSymbol,
                          subtitle: names[asset.assetSymbol] ?? _typeLabel(asset.assetType),
                          amount: asset.currentValue != null ? formatAmount(asset.currentValue!) : '—',
                          changePct: asset.dailyChangePct,
                          newsLevel: newsLevel[asset.assetSymbol],
                          onTap: () => openAssetPage(context, ref, asset.assetSymbol),
                        ),
                      ),
                  ],
                ),
              ],
              if (hasWatched) ...[
                _SectionTitle(title: 'Watching', count: watchlist.items.length),
                _Group(
                  children: [
                    for (final item in watchlist.items)
                      _Removable(
                        key: Key(item.id),
                        onRemove: () => _deleteWatchlistItem(item),
                        child: _AssetRow(
                          symbol: item.assetSymbol,
                          subtitle: names[item.assetSymbol] ?? _typeLabel(item.assetType),
                          amount: item.currentPrice != null ? formatPrice(item.currentPrice!) : '—',
                          changePct: item.priceChangePct,
                          newsLevel: newsLevel[item.assetSymbol],
                          onTap: () => openAssetPage(context, ref, item.assetSymbol),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _typeLabel(String type) {
  switch (type.toLowerCase()) {
    case 'stock': return 'Equity';
    case 'etf': return 'ETF';
    case 'crypto': return 'Crypto';
    case 'bond': return 'Bond';
    case 'commodity': return 'Commodity';
    default: return type;
  }
}

/// What the portfolio is worth, with today's move first and the all-time result
/// beneath it, quieter. Its last 30 days are a bare line beside it.
class _Summary extends ConsumerWidget {
  final PortfolioState state;

  const _Summary({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = state.totalDailyChange;
    final dailyColor = daily >= 0 ? _green : _red;
    final pnl = state.totalPnl;
    final pnlPct = state.totalPnlPct;
    final history = ref.watch(portfolioHistoryProvider).valueOrNull ?? const <double>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Portfolio value', style: GoogleFonts.inter(fontSize: 13, color: _muted)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatAmount(state.totalValue),
                    style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w700, color: _ink, letterSpacing: -1),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      daily >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 16,
                      color: dailyColor,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        '${formatAmount(daily.abs())} (${state.totalDailyChangePct.abs().toStringAsFixed(2)}%) today',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: dailyColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatAmount(pnl, signed: true)} (${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%) all time',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 13, color: _muted),
                ),
              ],
            ),
          ),
          if (history.length >= 2) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Sparkline(values: history, color: history.last >= history.first ? _green : _red),
                const SizedBox(height: 4),
                Text('30 days', style: GoogleFonts.inter(fontSize: 11, color: _faint)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  final VoidCallback onAdd;

  const _Welcome({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
      child: Column(
        children: [
          const Icon(Icons.insights_rounded, size: 48, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 16),
          Text(
            'Start with an asset',
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Add something you own or follow. Its news, analyzed for you, and its price alerts will show up here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: _muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add an asset'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(width: 6),
          Text('$count', style: GoogleFonts.inter(fontSize: 13, color: _faint)),
        ],
      ),
    );
  }
}

/// Rows in one card, divided by lines.
class _Group extends StatelessWidget {
  final List<Widget> children;

  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 64),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A row removed by swiping it to the left, after [onRemove] confirms.
class _Removable extends StatelessWidget {
  final Future<bool> Function() onRemove;
  final Widget child;

  const _Removable({required Key key, required this.onRemove, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: _red,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => onRemove(),
      child: child,
    );
  }
}

/// One asset: who it is on the left, what it is worth and how it moved today on
/// the right. A bolt marks important news about it today.
class _AssetRow extends StatelessWidget {
  final String symbol;
  final String subtitle;
  final String amount;
  final double? changePct;
  final int? newsLevel;
  final VoidCallback onTap;

  const _AssetRow({
    required this.symbol,
    required this.subtitle,
    required this.amount,
    required this.changePct,
    required this.newsLevel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final change = changePct;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _AssetLogo(symbol: symbol),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          symbol,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: _ink),
                        ),
                      ),
                      if (newsLevel != null) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: '${severityLabel(newsLevel!)} impact news today',
                          child: Icon(Icons.bolt_rounded, size: 16, color: severityColor(newsLevel)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: _faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(amount, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
                const SizedBox(height: 2),
                Text(
                  change == null ? '—' : '${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(2)}%',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: change == null ? _faint : (change >= 0 ? _green : _red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetLogo extends StatelessWidget {
  final String symbol;

  const _AssetLogo({required this.symbol});

  static const _size = 36.0;

  Widget _letterBox() {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          symbol.length > 3 ? symbol.substring(0, 3) : symbol,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: _muted),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        'https://assets.parqet.com/logos/symbol/$symbol?format=png',
        width: _size,
        height: _size,
        fit: BoxFit.contain,
        // The logo host sends no CORS header, so the web build can only show it
        // as an <img> element.
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, __, ___) => _letterBox(),
        loadingBuilder: (_, child, progress) => progress == null ? child : _letterBox(),
      ),
    );
  }
}

class _PortfolioDetailsSheet extends ConsumerStatefulWidget {
  final AssetInfo asset;
  const _PortfolioDetailsSheet({required this.asset});

  @override
  ConsumerState<_PortfolioDetailsSheet> createState() => _PortfolioDetailsSheetState();
}

class _PortfolioDetailsSheetState extends ConsumerState<_PortfolioDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final token = ref.read(authProvider).token ?? '';
    final quantity = double.parse(_quantityCtrl.text.trim());
    final price = double.parse(_priceCtrl.text.trim());
    try {
      await ref.read(portfolioProvider.notifier).add(
            token,
            symbol: widget.asset.symbol,
            quantity: quantity,
            purchasePrice: price,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  String? _positive(String? v, String name) {
    if (v == null || v.trim().isEmpty) return '$name is required';
    final n = double.tryParse(v.trim());
    if (n == null || n <= 0) return 'Must be greater than 0';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(portfolioProvider).isLoading;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add ${widget.asset.symbol}',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.asset.name,
              style: GoogleFonts.inter(fontSize: 13, color: _faint),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _quantityCtrl,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              validator: (v) => _positive(v, 'Quantity'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Purchase Price'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => _positive(v, 'Purchase price'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isLoading ? null : _save,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Add to Portfolio'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Alerts bell icon ─────────────────────────────────────────────────────────

class _AlertsBellButton extends ConsumerWidget {
  final VoidCallback onSeeAll;

  const _AlertsBellButton({required this.onSeeAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertCount = ref.watch(alertProvider).unreadCount;

    return IconButton(
      icon: Badge(
        isLabelVisible: alertCount > 0,
        label: Text(
          '$alertCount',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        child: const Icon(Icons.notifications_outlined, size: 22),
      ),
      onPressed: () => showDialog<void>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) => _AlertsPopup(
          onSeeAll: onSeeAll,
          targetOf: (alert) => alertTarget(context, ref, alert),
        ),
      ),
    );
  }
}

class _AlertsPopup extends ConsumerWidget {
  final VoidCallback onSeeAll;

  /// Opens from the screen behind the popup, which stays after the popup closes.
  final VoidCallback? Function(AlertItem alert) targetOf;

  const _AlertsPopup({required this.onSeeAll, required this.targetOf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertProvider).alerts;
    final preview = alerts.take(5).toList();

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(
          top: kToolbarHeight + MediaQuery.of(context).padding.top + 4,
          right: 8,
        ),
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text(
                    'Notifications',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                const Divider(height: 1),
                if (preview.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No alerts yet',
                        style: GoogleFonts.inter(fontSize: 13, color: _faint),
                      ),
                    ),
                  )
                else
                  ...preview.map((a) {
                    final target = targetOf(a);
                    return _CompactAlertRow(
                      alert: a,
                      onTap: target == null
                          ? null
                          : () {
                              Navigator.pop(context);
                              target();
                            },
                    );
                  }),
                if (alerts.isNotEmpty) ...[
                  const Divider(height: 1),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onSeeAll();
                    },
                    child: Text(
                      'See all alerts',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactAlertRow extends StatelessWidget {
  final AlertItem alert;
  final VoidCallback? onTap;

  const _CompactAlertRow({required this.alert, this.onTap});

  String _timeAgo() {
    final dt = DateTime.tryParse(alert.createdAt);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final color = severityColor(alert.severity);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withAlpha(60)),
              ),
              child: Icon(
                alert.alertType == 'model_stopped'
                    ? Icons.warning_amber_rounded
                    : alert.alertType == 'impact'
                        ? Icons.article_rounded
                        : Icons.trending_up_rounded,
                color: color,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (alert.message != null)
                    Text(
                      alert.message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF334155),
                        height: 1.35,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _timeAgo(),
                      if (alert.aiProviderName != null) alert.aiProviderName!,
                    ].join(' · '),
                    style: GoogleFonts.inter(fontSize: 11, color: _faint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
