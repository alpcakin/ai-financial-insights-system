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

  Map<String, dynamic> _decodeMap(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on FormatException {
      throw const TopicException('Server error. Please try again.');
    }
  }

  List<dynamic> _decodeList(http.Response r) {
    try {
      return jsonDecode(r.body) as List<dynamic>;
    } on FormatException {
      throw const TopicException('Server error. Please try again.');
    }
  }

  /// The server's message when it sent a readable one; validation errors come as a list.
  String _detail(http.Response r, String fallback) {
    final detail = _decodeMap(r)['detail'];
    return detail is String ? detail : fallback;
  }

  List<TopicCategory> _topics(http.Response r) =>
      _decodeList(r).map((e) => TopicCategory.fromJson(e as Map<String, dynamic>)).toList();

  Future<List<TopicCategory>> getTopics(String token) async {
    final response = await http
        .get(Uri.parse('${AppConstants.baseUrl}/topics'), headers: _headers(token))
        .timeout(_timeout);

    if (response.statusCode == 200) return _topics(response);
    throw TopicException(_detail(response, 'Failed to load topics'));
  }

  /// Follows a topic by name. A new name is checked first and joins the shared list.
  Future<TopicCategory> addTopic(String token, String name) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/topics'),
          headers: _headers(token),
          body: jsonEncode({'name': name}),
        )
        .timeout(_timeout);

    if (response.statusCode == 201) {
      return TopicCategory.fromJson(_decodeMap(response));
    }
    throw TopicException(_detail(response, 'This topic could not be added.'));
  }

  Future<List<TopicCategory>> searchTopics(String token, String query) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/topics/search').replace(queryParameters: {'q': query});
    final response = await http.get(uri, headers: _headers(token)).timeout(_timeout);

    if (response.statusCode == 200) return _topics(response);
    throw TopicException(_detail(response, 'Search failed'));
  }

  Future<void> followTopic(String token, String categoryId) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/topics/$categoryId/follow'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) return;
    throw TopicException(_detail(response, 'Failed to follow topic'));
  }

  Future<void> unfollowTopic(String token, String categoryId) async {
    final response = await http
        .delete(
          Uri.parse('${AppConstants.baseUrl}/topics/$categoryId/follow'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 204) return;
    throw TopicException(_detail(response, 'Failed to unfollow topic'));
  }
}
