import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/watchlist_models.dart';
import '../../core/constants.dart';

class WatchlistException implements Exception {
  final String message;
  const WatchlistException(this.message);
}

class WatchlistRepository {
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<List<WatchlistItem>> getWatchlist(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConstants.baseUrl}/watchlist'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((e) => WatchlistItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw WatchlistException(body['detail'] as String? ?? 'Failed to load watchlist');
  }

  Future<WatchlistItem> addItem(
    String token, {
    required String symbol,
    required String type,
    String? category,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/watchlist'),
          headers: _headers(token),
          body: jsonEncode({
            'asset_symbol': symbol,
            'asset_type': type,
            if (category != null) 'category': category,
          }),
        )
        .timeout(_timeout);

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 201) {
      return WatchlistItem.fromJson(body);
    }

    throw WatchlistException(body['detail'] as String? ?? 'Failed to add item');
  }

  Future<void> deleteItem(String token, {required String id}) async {
    final response = await http
        .delete(
          Uri.parse('${AppConstants.baseUrl}/watchlist/$id'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 204) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw WatchlistException(body['detail'] as String? ?? 'Failed to delete item');
  }
}
