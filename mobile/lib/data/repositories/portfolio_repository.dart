import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/portfolio_models.dart';
import '../../core/constants.dart';

class PortfolioException implements Exception {
  final String message;
  const PortfolioException(this.message);
}

class PortfolioRepository {
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<PortfolioResponse> getPortfolio(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConstants.baseUrl}/portfolio'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return PortfolioResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw PortfolioException(body['detail'] as String? ?? 'Failed to load portfolio');
  }

  Future<PortfolioAsset> addAsset(
    String token, {
    required String symbol,
    required String type,
    required double quantity,
    required double purchasePrice,
    String? category,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/portfolio'),
          headers: _headers(token),
          body: jsonEncode({
            'asset_symbol': symbol,
            'asset_type': type,
            'quantity': quantity,
            'purchase_price': purchasePrice,
            if (category != null) 'category': category,
          }),
        )
        .timeout(_timeout);

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 201) {
      return PortfolioAsset.fromJson(body);
    }

    throw PortfolioException(body['detail'] as String? ?? 'Failed to add asset');
  }

  Future<PortfolioAsset> updateAsset(
    String token, {
    required String id,
    required double quantity,
    required double purchasePrice,
  }) async {
    final response = await http
        .put(
          Uri.parse('${AppConstants.baseUrl}/portfolio/$id'),
          headers: _headers(token),
          body: jsonEncode({
            'quantity': quantity,
            'purchase_price': purchasePrice,
          }),
        )
        .timeout(_timeout);

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return PortfolioAsset.fromJson(body);
    }

    throw PortfolioException(body['detail'] as String? ?? 'Failed to update asset');
  }

  Future<void> deleteAsset(String token, {required String id}) async {
    final response = await http
        .delete(
          Uri.parse('${AppConstants.baseUrl}/portfolio/$id'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 204) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw PortfolioException(body['detail'] as String? ?? 'Failed to delete asset');
  }
}
