import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/report_models.dart';
import '../../core/constants.dart';

class ReportException implements Exception {
  final String message;
  const ReportException(this.message);
}

class ReportRepository {
  static const _timeout = Duration(seconds: 30);

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<ReportItem> generateReport(String token) async {
    final response = await http
        .post(
          Uri.parse('${AppConstants.baseUrl}/reports/generate'),
          headers: _headers(token),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return ReportItem.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw ReportException(
        body['detail'] as String? ?? 'Failed to generate report');
  }

  Future<ReportsResponse> getReports(
    String token, {
    int limit = 10,
    int offset = 0,
  }) async {
    final params = {'limit': '$limit', 'offset': '$offset'};
    final uri = Uri.parse('${AppConstants.baseUrl}/reports')
        .replace(queryParameters: params);

    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return ReportsResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw ReportException(
        body['detail'] as String? ?? 'Failed to load reports');
  }
}
