import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../models/asset_catalog.dart';

class AssetException implements Exception {
  final String message;
  const AssetException(this.message);

  @override
  String toString() => message;
}

class AssetRepository {
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decode(http.Response r, String fallback) {
    try {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200) return body;
      final detail = body['detail'];
      throw AssetException(detail is String ? detail : fallback);
    } on FormatException {
      throw AssetException(fallback);
    }
  }

  Future<List<AssetInfo>> getAssets(String token) async {
    final response = await http
        .get(Uri.parse('${AppConstants.baseUrl}/assets'), headers: _headers(token))
        .timeout(_timeout);
    final list = _decode(response, 'Failed to load assets')['assets'] as List<dynamic>;
    return list.map((e) => AssetInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AssetCandidate>> search(String token, String query) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/assets/search').replace(queryParameters: {'q': query});
    final response = await http.get(uri, headers: _headers(token)).timeout(_timeout);
    final list = _decode(response, 'Search failed')['results'] as List<dynamic>;
    return list.map((e) => AssetCandidate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AssetInfo> add(String token, String symbol) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/assets'),
          headers: _headers(token),
          body: jsonEncode({'symbol': symbol}),
        )
        .timeout(_timeout);
    return AssetInfo.fromJson(_decode(response, 'Could not add $symbol'));
  }
}
