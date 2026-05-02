import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/news_models.dart';
import '../../core/constants.dart';

class NewsException implements Exception {
  final String message;
  const NewsException(this.message);
}

class NewsRepository {
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decode(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on FormatException {
      throw const NewsException('Server error. Please try again.');
    }
  }

  Future<FeedResponse> getFeed(
    String token, {
    int limit = 20,
    int offset = 0,
    String? category,
  }) async {
    final params = {
      'limit': '$limit',
      'offset': '$offset',
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final uri = Uri.parse('${AppConstants.baseUrl}/feed').replace(queryParameters: params);

    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(_timeout);

    final body = _decode(response);

    if (response.statusCode == 200) {
      return FeedResponse.fromJson(body);
    }

    throw NewsException(body['detail'] as String? ?? 'Failed to load feed');
  }

  Future<void> markRead(String token, String articleId) async {
    final response = await http
        .patch(
          Uri.parse('${AppConstants.baseUrl}/feed/$articleId/read'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) return;

    final body = _decode(response);
    throw NewsException(body['detail'] as String? ?? 'Failed to mark as read');
  }
}
