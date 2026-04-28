import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/topic_models.dart';
import '../../core/constants.dart';

class TopicException implements Exception {
  final String message;
  const TopicException(this.message);
}

class TopicRepository {
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<List<TopicCategory>> getTopics(String token) async {
    final response = await http
        .get(Uri.parse('${AppConstants.baseUrl}/topics'), headers: _headers(token))
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.map((e) => TopicCategory.fromJson(e as Map<String, dynamic>)).toList();
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw TopicException(body['detail'] as String? ?? 'Failed to load topics');
  }

  Future<void> followTopic(String token, String categoryId) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/topics/$categoryId/follow'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw TopicException(body['detail'] as String? ?? 'Failed to follow topic');
  }

  Future<void> unfollowTopic(String token, String categoryId) async {
    final response = await http
        .delete(
          Uri.parse('${AppConstants.baseUrl}/topics/$categoryId/follow'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 204) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw TopicException(body['detail'] as String? ?? 'Failed to unfollow topic');
  }
}
