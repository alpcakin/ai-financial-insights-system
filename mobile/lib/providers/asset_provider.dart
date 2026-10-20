import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/asset_catalog.dart';
import '../data/repositories/asset_repository.dart';
import 'auth_provider.dart';

final assetRepositoryProvider = Provider<AssetRepository>((_) => AssetRepository());

/// Loaded once per session; the asset browser invalidates it to retry after an error.
final assetCatalogProvider = FutureProvider<List<AssetInfo>>((ref) {
  final token = ref.watch(authProvider.select((s) => s.token)) ?? '';
  return ref.read(assetRepositoryProvider).getAssets(token);
});
