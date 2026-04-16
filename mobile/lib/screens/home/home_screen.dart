import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/asset_catalog.dart';
import '../../data/models/portfolio_models.dart';
import '../../data/models/watchlist_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/watchlist_provider.dart';
import 'asset_browser_modal.dart';

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
    });
  }

  Future<void> _refresh() async {
    final token = ref.read(authProvider).token ?? '';
    await Future.wait([
      ref.read(portfolioProvider.notifier).load(token),
      ref.read(watchlistProvider.notifier).load(token),
    ]);
  }

  Future<AssetInfo?> _openBrowser() {
    return showDialog<AssetInfo>(
      context: context,
      builder: (_) => const AssetBrowserModal(),
    );
  }

  Future<void> _openBrowserForPortfolio() async {
    final asset = await _openBrowser();
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

  Future<void> _openBrowserForWatchlist() async {
    final asset = await _openBrowser();
    if (asset == null || !mounted) return;
    final token = ref.read(authProvider).token ?? '';
    try {
      await ref.read(watchlistProvider.notifier).add(
            token,
            symbol: asset.symbol,
            type: asset.type,
            category: asset.category,
          );
    } catch (_) {
      if (!mounted) return;
      final error = ref.read(watchlistProvider).error ?? 'Failed to add to watchlist';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<bool> _deletePortfolioAsset(PortfolioAsset asset) async {
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

  void _showEditAssetSheet(PortfolioAsset asset) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditAssetSheet(asset: asset),
    );
    if (!mounted) return;
    if (result == false) {
      final error = ref.read(portfolioProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolioState = ref.watch(portfolioProvider);
    final watchlistState = ref.watch(watchlistProvider);

    ref.listen(portfolioProvider, (_, next) {
      if (next.error != null && !next.isLoading) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    ref.listen(watchlistProvider, (_, next) {
      if (next.error != null && !next.isLoading) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Financial Insights',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF3B82F6),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _SectionHeader(title: 'Portfolio', onAdd: _openBrowserForPortfolio),
            ),
            SliverToBoxAdapter(
              child: _PortfolioHeader(state: portfolioState),
            ),
            if (portfolioState.isLoading && portfolioState.assets.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (portfolioState.assets.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No assets yet. Tap + to add one.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final asset = portfolioState.assets[index];
                    return Dismissible(
                      key: Key(asset.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: const Color(0xFFEF4444),
                        child: const Icon(Icons.delete_rounded, color: Colors.white),
                      ),
                      confirmDismiss: (_) => _deletePortfolioAsset(asset),
                      child: _AssetTile(
                        asset: asset,
                        onTap: () => _showEditAssetSheet(asset),
                      ),
                    );
                  },
                  childCount: portfolioState.assets.length,
                ),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Divider(),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionHeader(title: 'Watchlist', onAdd: _openBrowserForWatchlist),
            ),
            if (watchlistState.isLoading && watchlistState.items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (watchlistState.items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No items yet. Tap + to add one.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = watchlistState.items[index];
                    return Dismissible(
                      key: Key(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: const Color(0xFFEF4444),
                        child: const Icon(Icons.delete_rounded, color: Colors.white),
                      ),
                      confirmDismiss: (_) => _deleteWatchlistItem(item),
                      child: _WatchlistTile(item: item),
                    );
                  },
                  childCount: watchlistState.items.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;

  const _SectionHeader({required this.title, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
                letterSpacing: 0.8,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(
              'Add',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3B82F6),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioHeader extends StatelessWidget {
  final PortfolioState state;

  const _PortfolioHeader({required this.state});

  static const _chartColors = [
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF84CC16),
  ];

  @override
  Widget build(BuildContext context) {
    final pnl = state.totalPnl;
    final pnlPct = state.totalPnlPct;
    final daily = state.totalDailyChange;
    final dailyPct = state.totalDailyChangePct;
    final pnlPositive = pnl >= 0;
    final dailyPositive = daily >= 0;

    final assetsWithValue = state.assets
        .where((a) => (a.currentValue ?? 0) > 0)
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6FF), Color(0xFFE0EFFE)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Value',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '\$${state.totalValue.toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatBlock(
                        label: 'All-time P&L',
                        value:
                            '${pnlPositive ? '+' : ''}\$${pnl.abs().toStringAsFixed(2)}',
                        sub:
                            '${pnlPositive ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                        positive: pnlPositive,
                      ),
                      const SizedBox(height: 14),
                      _StatBlock(
                        label: 'Today',
                        value:
                            '${dailyPositive ? '+' : ''}\$${daily.abs().toStringAsFixed(2)}',
                        sub:
                            '${dailyPositive ? '+' : ''}${dailyPct.toStringAsFixed(2)}%',
                        positive: dailyPositive,
                      ),
                    ],
                  ),
                ),
                if (assetsWithValue.length >= 2)
                  _DonutChart(
                    assets: assetsWithValue,
                    totalValue: state.totalValue,
                    colors: _chartColors,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final bool positive;

  const _StatBlock({
    required this.label,
    required this.value,
    required this.sub,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    final color = positive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF94A3B8),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          sub,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color.withAlpha(180),
          ),
        ),
      ],
    );
  }
}

class _DonutChart extends StatelessWidget {
  final List<PortfolioAsset> assets;
  final double totalValue;
  final List<Color> colors;

  const _DonutChart({
    required this.assets,
    required this.totalValue,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withAlpha(40),
                blurRadius: 20,
                spreadRadius: 4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: PieChart(
            PieChartData(
              sections: assets.asMap().entries.map((entry) {
                final i = entry.key;
                final a = entry.value;
                final pct = (a.currentValue ?? 0) / totalValue * 100;
                return PieChartSectionData(
                  value: pct,
                  color: colors[i % colors.length],
                  radius: 42,
                  title: '',
                  borderSide: const BorderSide(
                    color: Color(0xFFEFF6FF),
                    width: 2,
                  ),
                );
              }).toList(),
              centerSpaceRadius: 28,
              sectionsSpace: 0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...assets.asMap().entries.take(4).map((entry) {
          final i = entry.key;
          final a = entry.value;
          final pct = (a.currentValue ?? 0) / totalValue * 100;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors[i % colors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${a.assetSymbol} ${pct.toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF475569),
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

class _AssetTile extends StatelessWidget {
  final PortfolioAsset asset;
  final VoidCallback onTap;

  const _AssetTile({required this.asset, required this.onTap});

  String _formatType(String type) {
    switch (type.toLowerCase()) {
      case 'stock': return 'Equity';
      case 'etf': return 'ETF';
      case 'crypto': return 'Crypto';
      case 'bond': return 'Bond';
      case 'commodity': return 'Commodity';
      default: return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final costBasis = asset.quantity * asset.purchasePrice;
    final currentVal = asset.currentValue ?? costBasis;
    final pnl = currentVal - costBasis;
    final pnlPct = costBasis > 0 ? (pnl / costBasis) * 100 : 0.0;
    final pnlPositive = pnl >= 0;
    final pnlColor = pnlPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  asset.assetSymbol.length > 3
                      ? asset.assetSymbol.substring(0, 3)
                      : asset.assetSymbol,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.assetSymbol,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatType(asset.assetType)} · ${asset.quantity % 1 == 0 ? asset.quantity.toInt() : asset.quantity} shares',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  asset.currentPrice != null
                      ? '\$${asset.currentPrice!.toStringAsFixed(2)}'
                      : '—',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$${currentVal.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: pnlColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${pnlPositive ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: pnlColor,
                    ),
                  ),
                ),
                if (asset.dailyChangePct != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${asset.dailyChangePct! >= 0 ? '+' : ''}${asset.dailyChangePct!.toStringAsFixed(2)}% today',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: asset.dailyChangePct! >= 0
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchlistTile extends StatelessWidget {
  final WatchlistItem item;
  const _WatchlistTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final change = item.priceChange;
    final changePct = item.priceChangePct;
    final isPositive = (change ?? 0) >= 0;
    final color = change == null
        ? const Color(0xFF94A3B8)
        : isPositive
            ? const Color(0xFF10B981)
            : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Text(
                item.assetSymbol.length > 3
                    ? item.assetSymbol.substring(0, 3)
                    : item.assetSymbol,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.assetSymbol,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.assetType,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.currentPrice != null
                    ? '\$${item.currentPrice!.toStringAsFixed(2)}'
                    : '—',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              if (change != null && changePct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${isPositive ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                )
              else
                Text('—', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
            ],
          ),
        ],
      ),
    );
  }
}

class _PortfolioDetailsSheet extends ConsumerStatefulWidget {
  final AssetInfo asset;
  const _PortfolioDetailsSheet({required this.asset});

  @override
  ConsumerState<_PortfolioDetailsSheet> createState() =>
      _PortfolioDetailsSheetState();
}

class _PortfolioDetailsSheetState
    extends ConsumerState<_PortfolioDetailsSheet> {
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
            type: widget.asset.type,
            quantity: quantity,
            purchasePrice: price,
            category: widget.asset.category,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(false);
    }
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
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _quantityCtrl,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Quantity is required';
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return 'Must be greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Purchase Price'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Purchase price is required';
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return 'Must be greater than 0';
                return null;
              },
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

class _EditAssetSheet extends ConsumerStatefulWidget {
  final PortfolioAsset asset;
  const _EditAssetSheet({required this.asset});

  @override
  ConsumerState<_EditAssetSheet> createState() => _EditAssetSheetState();
}

class _EditAssetSheetState extends ConsumerState<_EditAssetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _quantityCtrl.text = widget.asset.quantity.toString();
    _priceCtrl.text = widget.asset.purchasePrice.toString();
  }

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
      await ref.read(portfolioProvider.notifier).update(
            token,
            id: widget.asset.id,
            quantity: quantity,
            purchasePrice: price,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(false);
    }
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
              'Edit ${widget.asset.assetSymbol}',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _quantityCtrl,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Quantity is required';
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return 'Must be greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Purchase Price'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Purchase price is required';
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return 'Must be greater than 0';
                return null;
              },
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
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
