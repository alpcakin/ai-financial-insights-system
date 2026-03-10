import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
      await ref.read(watchlistProvider.notifier).add(token, symbol: asset.symbol, type: asset.type, category: asset.category);
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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

    final totalValue = portfolioState.assets.fold(0.0, (sum, a) => sum + (a.currentValue ?? 0.0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Insights'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Portfolio',
              onAdd: _openBrowserForPortfolio,
            ),
          ),
          SliverToBoxAdapter(
            child: _TotalValueBanner(totalValue: totalValue),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
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
                      color: Colors.red,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) => _deletePortfolioAsset(asset),
                    child: _AssetCard(
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
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
          ),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Watchlist',
              onAdd: _openBrowserForWatchlist,
            ),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
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
                      color: Colors.red,
                      child: const Icon(Icons.delete, color: Colors.white),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _TotalValueBanner extends StatelessWidget {
  final double totalValue;
  const _TotalValueBanner({required this.totalValue});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Value', style: Theme.of(context).textTheme.labelMedium),
          Text(
            '\$${totalValue.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  final PortfolioAsset asset;
  final VoidCallback onTap;

  const _AssetCard({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final costBasis = asset.quantity * asset.purchasePrice;
    final currentVal = asset.currentValue ?? costBasis;
    final pnl = currentVal - costBasis;
    final pnlPct = costBasis > 0 ? (pnl / costBasis) * 100 : 0.0;
    final isPositive = pnl >= 0;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.assetSymbol,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            asset.assetType,
                            style: Theme.of(context).textTheme.labelSmall,
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
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '\$${currentVal.toStringAsFixed(2)}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${asset.quantity} × \$${asset.purchasePrice.toStringAsFixed(2)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  Row(
                    children: [
                      Icon(
                        isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                        color: isPositive ? Colors.green : Colors.red,
                      ),
                      Text(
                        '${isPositive ? '+' : ''}\$${pnl.toStringAsFixed(2)} (${pnlPct.toStringAsFixed(2)}%)',
                        style: TextStyle(
                          color: isPositive ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
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

class _WatchlistTile extends StatelessWidget {
  final WatchlistItem item;
  const _WatchlistTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final change = item.priceChange;
    final changePct = item.priceChangePct;
    final isPositive = (change ?? 0) >= 0;
    final color = change == null
        ? Colors.grey
        : isPositive
            ? Colors.green
            : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.assetSymbol,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.assetType,
                      style: Theme.of(context).textTheme.labelSmall,
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
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (change != null)
                      Icon(
                        isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 13,
                        color: color,
                      ),
                    Text(
                      change != null && changePct != null
                          ? '${isPositive ? '+' : ''}\$${change.toStringAsFixed(2)} (${changePct.toStringAsFixed(2)}%)'
                          : '—',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
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
        left: 16,
        right: 16,
        top: 16,
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
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              widget.asset.name,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 16),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
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
        left: 16,
        right: 16,
        top: 16,
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
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
