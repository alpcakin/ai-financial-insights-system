import 'package:flutter_test/flutter_test.dart';

import 'package:financial_insights/data/models/alert_models.dart';
import 'package:financial_insights/data/models/news_models.dart';
import 'package:financial_insights/data/models/user_models.dart';

void main() {
  group('FeedArticle', () {
    final json = <String, dynamic>{
      'id': 'a1',
      'title': 'Apple beats estimates',
      'url': 'https://reuters.com/a',
      'source': 'Reuters',
      'summary': 'Strong quarter',
      'sentiment_label': 'positive',
      'severity': 7,
      'related_categories': ['Technology'],
      'related_assets': ['AAPL'],
      'asset_impacts': [
        {'symbol': 'AAPL', 'impact': 'positive', 'severity': 7, 'reason': 'earnings'},
      ],
      'published_at': '2026-05-01T00:00:00Z',
      'analyzed_by': 'gemini',
      'analyzed_by_name': 'Gemini',
      'is_fallback': true,
      'read': false,
      'bookmarked': false,
    };

    test('parses analysis fields and provider badge data', () {
      final article = FeedArticle.fromJson(json);
      expect(article.id, 'a1');
      expect(article.severity, 7);
      expect(article.relatedAssets, ['AAPL']);
      expect(article.assetImpacts.single.symbol, 'AAPL');
      expect(article.assetImpacts.single.severity, 7);
      expect(article.analyzedBy, 'gemini');
      expect(article.analyzedByName, 'Gemini');
      expect(article.isFallback, isTrue);
    });

    test('defaults when optional fields are missing', () {
      final minimal = <String, dynamic>{
        'id': 'a2',
        'title': 'T',
        'url': 'https://x.com',
      };
      final article = FeedArticle.fromJson(minimal);
      expect(article.relatedCategories, isEmpty);
      expect(article.assetImpacts, isEmpty);
      expect(article.analyzedBy, isNull);
      expect(article.isFallback, isFalse);
      expect(article.read, isFalse);
    });

    test('copyWith keeps provider fields when marking read', () {
      final article = FeedArticle.fromJson(json).copyWith(read: true);
      expect(article.read, isTrue);
      expect(article.analyzedByName, 'Gemini');
      expect(article.isFallback, isTrue);
      expect(article.summary, 'Strong quarter');
    });

    test('FeedResponse parses paging fields', () {
      final response = FeedResponse.fromJson({
        'articles': [json],
        'total': 1,
        'offset': 0,
        'limit': 20,
      });
      expect(response.total, 1);
      expect(response.articles.single.title, 'Apple beats estimates');
    });
  });

  group('AlertItem', () {
    test('parses provider and maps it to a display name', () {
      final alert = AlertItem.fromJson({
        'id': 'al1',
        'user_id': 'u1',
        'article_id': 'a1',
        'asset_symbol': 'AAPL',
        'alert_type': 'impact',
        'severity': 8,
        'message': 'AAPL: earnings',
        'notification_sent': true,
        'is_read': false,
        'ai_provider': 'openai',
        'created_at': '2026-05-01T00:00:00Z',
      });
      expect(alert.aiProvider, 'openai');
      expect(alert.aiProviderName, 'GPT-4o mini');
      expect(alert.isRead, isFalse);
    });

    test('volatility alerts carry no provider', () {
      final alert = AlertItem.fromJson({
        'id': 'al2',
        'user_id': 'u1',
        'alert_type': 'volatility',
        'severity': 8,
        'message': 'AAPL moved up 10.0% in 24 hours',
        'created_at': '2026-05-01T00:00:00Z',
      });
      expect(alert.aiProvider, isNull);
      expect(alert.aiProviderName, isNull);
      expect(alert.notificationSent, isFalse);
    });

    test('unknown provider falls back to its key', () {
      final alert = AlertItem.fromJson({
        'id': 'al3',
        'user_id': 'u1',
        'alert_type': 'impact',
        'ai_provider': 'mistral',
        'created_at': '2026-05-01T00:00:00Z',
      });
      expect(alert.aiProviderName, 'mistral');
    });
  });

  group('UserProfile and AIProviderInfo', () {
    test('parses preferences and provider choice', () {
      final profile = UserProfile.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'notification_preferences': {'impact_alerts': false},
        'ai_provider': 'grok',
        'created_at': '2026-01-01T00:00:00',
      });
      expect(profile.preferences.impactAlerts, isFalse);
      expect(profile.preferences.volatilityAlerts, isTrue);
      expect(profile.aiProvider, 'grok');
    });

    test('provider defaults to openai when absent', () {
      final profile = UserProfile.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'created_at': '2026-01-01T00:00:00',
      });
      expect(profile.aiProvider, 'openai');
    });

    test('AIProviderInfo parses listing entries', () {
      final info = AIProviderInfo.fromJson({
        'name': 'gemini',
        'display_name': 'Gemini',
        'model': 'gemini-2.5-flash',
        'is_default': false,
      });
      expect(info.name, 'gemini');
      expect(info.displayName, 'Gemini');
      expect(info.model, 'gemini-2.5-flash');
      expect(info.isDefault, isFalse);
    });
  });
}
