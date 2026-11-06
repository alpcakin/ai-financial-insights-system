import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../models/manual_models.dart';

class ManualRepository {
  static const _timeout = Duration(seconds: 15);

  /// Adding a source fetches it.
  static const _sourceTimeout = Duration(seconds: 40);

  /// Adding a model makes a real call to it, which can retry.
  static const _modelTimeout = Duration(seconds: 150);

  Uri _uri(String path) => Uri.parse('${AppConstants.baseUrl}/manual$path');

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  dynamic _decode(http.Response r) {
    try {
      return jsonDecode(r.body);
    } on FormatException {
      throw const ManualException('Server error. Please try again.');
    }
  }

  dynamic _check(http.Response r, String fallback) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.statusCode == 204 ? null : _decode(r);
    }
    final body = _decode(r);
    final detail = body is Map<String, dynamic> ? body['detail'] : null;
    throw ManualException(detail is String ? detail : fallback);
  }

  Future<ManualSettings> getSettings(String token) async {
    final r = await http.get(_uri('/settings'), headers: _headers(token)).timeout(_timeout);
    return ManualSettings.fromJson(_check(r, 'Failed to load settings') as Map<String, dynamic>);
  }

  Future<ManualSettings> updateSettings(
    String token, {
    bool? packageEnabled,
    bool? manualEnabled,
    bool? groupingEnabled,
    String? selectedModelId,
  }) async {
    final r = await http
        .patch(
          _uri('/settings'),
          headers: _headers(token),
          body: jsonEncode({
            if (packageEnabled != null) 'package_enabled': packageEnabled,
            if (manualEnabled != null) 'manual_enabled': manualEnabled,
            if (groupingEnabled != null) 'grouping_enabled': groupingEnabled,
            if (selectedModelId != null) 'selected_model_id': selectedModelId,
          }),
        )
        .timeout(_timeout);
    return ManualSettings.fromJson(_check(r, 'Failed to update settings') as Map<String, dynamic>);
  }

  Future<List<UserSource>> getSources(String token) async {
    final r = await http.get(_uri('/sources'), headers: _headers(token)).timeout(_timeout);
    return (_check(r, 'Failed to load sources') as List<dynamic>)
        .map((e) => UserSource.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserSource> addSource(String token, {required String url, String? name, required int intervalMinutes}) async {
    final r = await http
        .post(
          _uri('/sources'),
          headers: _headers(token),
          body: jsonEncode({
            'url': url,
            if (name != null && name.isNotEmpty) 'name': name,
            'fetch_interval_minutes': intervalMinutes,
          }),
        )
        .timeout(_sourceTimeout);
    return UserSource.fromJson(_check(r, 'Failed to add source') as Map<String, dynamic>);
  }

  Future<UserSource> updateSource(String token, String id, {bool? enabled, int? intervalMinutes}) async {
    final r = await http
        .patch(
          _uri('/sources/$id'),
          headers: _headers(token),
          body: jsonEncode({
            if (enabled != null) 'enabled': enabled,
            if (intervalMinutes != null) 'fetch_interval_minutes': intervalMinutes,
          }),
        )
        .timeout(_timeout);
    return UserSource.fromJson(_check(r, 'Failed to update source') as Map<String, dynamic>);
  }

  Future<void> deleteSource(String token, String id) async {
    final r = await http.delete(_uri('/sources/$id'), headers: _headers(token)).timeout(_timeout);
    _check(r, 'Failed to delete source');
  }

  Future<List<UserModel>> getModels(String token) async {
    final r = await http.get(_uri('/models'), headers: _headers(token)).timeout(_timeout);
    return (_check(r, 'Failed to load models') as List<dynamic>)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserModel> addModel(
    String token, {
    required String kind,
    required String model,
    required String apiKey,
    String? label,
    String? baseUrl,
  }) async {
    final r = await http
        .post(
          _uri('/models'),
          headers: _headers(token),
          body: jsonEncode({
            'kind': kind,
            'model': model,
            'api_key': apiKey,
            if (label != null && label.isNotEmpty) 'label': label,
            if (baseUrl != null && baseUrl.isNotEmpty) 'base_url': baseUrl,
          }),
        )
        .timeout(_modelTimeout);
    return UserModel.fromJson(_check(r, 'Failed to add model') as Map<String, dynamic>);
  }

  Future<UserModel> retryModel(String token, String id) async {
    final r = await http.post(_uri('/models/$id/retry'), headers: _headers(token)).timeout(_modelTimeout);
    return UserModel.fromJson(_check(r, 'The model could not be tested') as Map<String, dynamic>);
  }

  Future<void> deleteModel(String token, String id) async {
    final r = await http.delete(_uri('/models/$id'), headers: _headers(token)).timeout(_timeout);
    _check(r, 'Failed to delete model');
  }
}
