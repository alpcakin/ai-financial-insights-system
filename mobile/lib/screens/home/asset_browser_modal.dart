import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/asset_catalog.dart';
import '../../providers/asset_provider.dart';

class AssetBrowserModal extends ConsumerStatefulWidget {
  const AssetBrowserModal({super.key});

  @override
  ConsumerState<AssetBrowserModal> createState() => _AssetBrowserModalState();
}

class _AssetBrowserModalState extends ConsumerState<AssetBrowserModal> {
  String _searchQuery = '';
  String? _selectedType;

  List<AssetInfo> _filter(List<AssetInfo> assets) => assets
      .where((a) => _selectedType == null || a.type == _selectedType)
      .where((a) =>
          _searchQuery.isEmpty ||
          a.symbol.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          a.name.toLowerCase().contains(_searchQuery.toLowerCase()))
      .toList();

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
                onChanged: (v) => setState(() => _searchQuery = v),
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
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final asset = filtered[index];
                      final color = _typeColor(asset.type);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.15),
                          child: Icon(_typeIcon(asset.type), color: color, size: 20),
                        ),
                        title: Text(
                          asset.symbol,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(asset.name),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            asset.type,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(asset),
                      );
                    },
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
