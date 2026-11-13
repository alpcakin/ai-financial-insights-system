import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/asset_catalog.dart';
import '../../data/repositories/asset_repository.dart';
import '../../providers/asset_provider.dart';
import '../../providers/auth_provider.dart';

class AssetBrowserModal extends ConsumerStatefulWidget {
  const AssetBrowserModal({super.key});

  @override
  ConsumerState<AssetBrowserModal> createState() => _AssetBrowserModalState();
}

class _AssetBrowserModalState extends ConsumerState<AssetBrowserModal> {
  String _searchQuery = '';
  String? _selectedType;

  List<AssetCandidate>? _yahooResults;
  bool _yahooLoading = false;
  String? _yahooError;
  String? _adding;

  bool _matchesType(String type) => _selectedType == null || type == _selectedType;

  List<AssetInfo> _filter(List<AssetInfo> assets) => assets
      .where((a) => _matchesType(a.type))
      .where((a) =>
          _searchQuery.isEmpty ||
          a.symbol.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          a.name.toLowerCase().contains(_searchQuery.toLowerCase()))
      .toList();

  void _onQueryChanged(String value) => setState(() {
        _searchQuery = value;
        _yahooResults = null;
        _yahooLoading = false;
        _yahooError = null;
      });

  Future<void> _searchYahoo() async {
    final query = _searchQuery.trim();
    setState(() {
      _yahooLoading = true;
      _yahooError = null;
    });
    try {
      final token = ref.read(authProvider).token ?? '';
      final results = await ref.read(assetRepositoryProvider).search(token, query);
      if (!mounted || query != _searchQuery.trim()) return;
      setState(() {
        _yahooResults = results;
        _yahooLoading = false;
      });
    } catch (e) {
      if (!mounted || query != _searchQuery.trim()) return;
      setState(() {
        _yahooLoading = false;
        _yahooError = e is AssetException ? e.message : 'Search failed. Please try again.';
      });
    }
  }

  Future<void> _add(AssetCandidate candidate) async {
    setState(() {
      _adding = candidate.symbol;
      _yahooError = null;
    });
    try {
      final token = ref.read(authProvider).token ?? '';
      final asset = await ref.read(assetRepositoryProvider).add(token, candidate.symbol);
      ref.invalidate(assetCatalogProvider);
      if (mounted) Navigator.of(context).pop(asset);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _adding = null;
        _yahooError = e is AssetException ? e.message : 'Could not add ${candidate.symbol}.';
      });
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'stock':
        return Icons.show_chart;
      case 'etf':
        return Icons.pie_chart;
      case 'crypto':
        return Icons.currency_bitcoin;
      case 'commodity':
        return Icons.inventory_2_outlined;
      default:
        return Icons.attach_money;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'stock':
        return Colors.blue;
      case 'etf':
        return Colors.purple;
      case 'crypto':
        return Colors.orange;
      case 'commodity':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  Widget _typeAvatar(String type) {
    final color = _typeColor(type);
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(_typeIcon(type), color: color, size: 20),
    );
  }

  Widget _typeChip(String type) {
    final color = _typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        type,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _assetTile(AssetInfo asset) => ListTile(
        leading: _typeAvatar(asset.type),
        title: Text(asset.symbol, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(asset.name),
        trailing: _typeChip(asset.type),
        onTap: () => Navigator.of(context).pop(asset),
      );

  Widget _candidateTile(AssetCandidate candidate) {
    final catalogAsset = candidate.catalogAsset;
    final String note;
    if (candidate.blocked != null) {
      note = candidate.blocked!;
    } else if (catalogAsset == null) {
      note = 'Tap to add';
    } else if (catalogAsset.symbol == candidate.symbol) {
      note = 'Already in the catalog';
    } else {
      note = 'In the catalog as ${catalogAsset.symbol}';
    }
    final exchange = candidate.exchange == null ? '' : ' · ${candidate.exchange}';

    Widget trailing = _typeChip(candidate.type);
    if (_adding == candidate.symbol) {
      trailing = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (candidate.blocked == null && catalogAsset == null) {
      trailing = const Icon(Icons.add_circle_outline);
    }

    return ListTile(
      enabled: candidate.blocked == null && _adding == null,
      leading: _typeAvatar(candidate.type),
      title: Text(candidate.symbol, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('${candidate.name}$exchange\n$note'),
      isThreeLine: true,
      trailing: trailing,
      onTap: () => catalogAsset != null ? Navigator.of(context).pop(catalogAsset) : _add(candidate),
    );
  }

  List<Widget> _yahooSection() {
    final query = _searchQuery.trim();
    if (query.isEmpty) return [];
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12);
    final results = _yahooResults?.where((c) => _matchesType(c.type)).toList();

    return [
      const Divider(),
      if (results == null && !_yahooLoading)
        ListTile(
          leading: const Icon(Icons.travel_explore),
          title: Text('Search Yahoo for "$query"'),
          subtitle: const Text('For assets that are not listed yet'),
          onTap: _searchYahoo,
        ),
      if (_yahooLoading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (results != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'From Yahoo. An asset you add is shared with everyone and analyzed from now on.',
            style: muted,
          ),
        ),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No stocks, ETFs or crypto found on Yahoo.', style: muted),
          ),
        ...results.map(_candidateTile),
      ],
      if (_yahooError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(_yahooError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(assetCatalogProvider);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Browse Assets',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search symbol or name...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(50)],
                onChanged: _onQueryChanged,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _selectedType == null,
                    onSelected: (_) => setState(() => _selectedType = null),
                  ),
                  const SizedBox(width: 8),
                  for (final type in ['stock', 'etf', 'crypto', 'commodity'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(type[0].toUpperCase() + type.substring(1)),
                        selected: _selectedType == type,
                        onSelected: (_) => setState(
                          () => _selectedType = _selectedType == type ? null : type,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: catalog.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load assets'),
                      TextButton(
                        onPressed: () => ref.invalidate(assetCatalogProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (assets) {
                  final filtered = _filter(assets);
                  final yahoo = _yahooSection();
                  return ListView.builder(
                    itemCount: filtered.length + yahoo.length,
                    itemBuilder: (context, index) => index < filtered.length
                        ? _assetTile(filtered[index])
                        : yahoo[index - filtered.length],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
