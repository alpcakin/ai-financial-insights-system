import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../models/asset_catalog.dart';

class AssetRepository {
  static const _timeout = Duration(seconds: 15);

  Future<List<AssetInfo>> getAssets(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConstants.baseUrl}/assets'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to load assets');
    }
    final list = (jsonDecode(response.body) as Map<String, dynamic>)['assets'] as List<dynamic>;
    return list.map((e) => AssetInfo.fromJson(e as Map<String, dynamic>)).toList();
  }
}
