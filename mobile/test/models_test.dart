import 'package:flutter_test/flutter_test.dart';

import 'package:financial_insights/data/models/alert_models.dart';
import 'package:financial_insights/data/models/manual_models.dart';
import 'package:financial_insights/data/models/news_models.dart';
import 'package:financial_insights/data/models/topic_models.dart';
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
      'severity': 3,
      'related_categories': ['Technology'],
      'related_assets': ['AAPL'],
      'asset_impacts': [
        {'symbol': 'AAPL', 'impact': 'positive', 'severity': 3, 'reason': 'earnings'},
      ],
      'published_at': '2026-05-01T00:00:00Z',
      'analyzed_by': 'gemini',
      'analyzed_by_name': 'Gemini',
      'is_fallback': true,
      'read': false,
    };

    test('parses analysis fields and provider badge data', () {
      final article = FeedArticle.fromJson(json);
      expect(article.id, 'a1');
      expect(article.severity, 3);
      expect(article.relatedAssets, ['AAPL']);
      expect(article.assetImpacts.single.symbol, 'AAPL');
      expect(article.assetImpacts.single.severity, 3);
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

    test('parses every outlet that reported the story and keeps them on copyWith', () {
      final article = FeedArticle.fromJson({
        ...json,
        'sources': [
          {'title': 'Apple beats estimates', 'url': 'https://reuters.com/a', 'source': 'Reuters', 'published_at': '2026-05-01T00:00:00Z'},
          {'title': 'Apple tops forecasts', 'url': 'https://cnbc.com/a', 'source': 'CNBC', 'published_at': null},
        ],
      }).copyWith(read: true);
      expect(article.sources.map((s) => s.source), ['Reuters', 'CNBC']);
      expect(article.sources.last.url, 'https://cnbc.com/a');
      expect(article.sources.last.publishedAt, isNull);
    });

    test('parses the followed topics that brought the story and keeps them on copyWith', () {
      final article = FeedArticle.fromJson({...json, 'matched_topics': ['New York', 'Gold']});
      expect(article.matchedTopics, ['New York', 'Gold']);
      expect(article.copyWith(read: true).matchedTopics, ['New York', 'Gold']);
      expect(FeedArticle.fromJson(json).matchedTopics, isEmpty);
    });

    test('sources default to empty for older payloads', () {
      expect(FeedArticle.fromJson(json).sources, isEmpty);
    });

    test('NewsSource parses outlet and section', () {
      final source = NewsSource.fromJson({'outlet': 'Bloomberg', 'section': 'Markets'});
      expect(source.outlet, 'Bloomberg');
      expect(source.section, 'Markets');
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
        'severity': 3,
        'message': 'AAPL: earnings',
        'notification_sent': true,
        'is_read': false,
        'ai_provider': 'openai',
        'created_at': '2026-05-01T00:00:00Z',
      });
      expect(alert.aiProvider, 'openai');
      expect(alert.aiProviderName, 'GPT');
      expect(alert.isRead, isFalse);
    });

    test('volatility alerts carry no provider', () {
      final alert = AlertItem.fromJson({
        'id': 'al2',
        'user_id': 'u1',
        'alert_type': 'volatility',
        'severity': 3,
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
        'notification_preferences': {'impact_alerts': false, 'impact_alert_level': 'very_high'},
        'ai_provider': 'gemini',
        'created_at': '2026-01-01T00:00:00',
      });
      expect(profile.preferences.impactAlerts, isFalse);
      expect(profile.preferences.impactAlertLevel, 'very_high');
      expect(profile.preferences.volatilityAlerts, isTrue);
      expect(profile.aiProvider, 'gemini');
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
        'model': 'gemini-3.8-flash',
        'is_default': false,
      });
      expect(info.name, 'gemini');
      expect(info.displayName, 'Gemini');
      expect(info.model, 'gemini-3.8-flash');
      expect(info.isDefault, isFalse);
    });
  });

  group('AlertSetting', () {
    test('parses a custom percentage and labels it without trailing zeros', () {
      final setting = AlertSetting.fromJson(
          {'asset_symbol': 'BTC-USD', 'mode': 'percent', 'threshold_pct': 2.5});
      expect(setting.isAutomatic, isFalse);
      expect(setting.thresholdText, '2.5');
      expect(setting.label, '±2.5%');
      expect(
          AlertSetting.fromJson({'asset_symbol': 'AAPL', 'mode': 'percent', 'threshold_pct': 10})
              .label,
          '±10%');
    });

    test('labels off and the automatic default', () {
      expect(
          AlertSetting.fromJson({'asset_symbol': 'AAPL', 'mode': 'off', 'threshold_pct': null}).label,
          'Off');
      const automatic = AlertSetting.automatic('AAPL');
      expect(automatic.isAutomatic, isTrue);
      expect(automatic.label, 'Automatic');
      expect(automatic.thresholdText, isNull);
    });
  });

  group('Topics', () {
    test('a topic users wrote has no level and is their own', () {
      final topic = TopicCategory.fromJson(
          {'id': 't1', 'name': 'New York', 'level': null, 'parent_id': null, 'kind': 'topic', 'followed': true});
      expect(topic.level, isNull);
      expect(topic.isOwnTopic, isTrue);
      expect(topic.copyWith(followed: false).isOwnTopic, isTrue);
    });

    test('an older payload without kind is a category', () {
      final category = TopicCategory.fromJson(
          {'id': 'c1', 'name': 'Software', 'level': 2, 'parent_id': 'c0', 'followed': false});
      expect(category.isOwnTopic, isFalse);
      expect(category.level, 2);
    });

    test('manual settings say which model matches topics, null for Snap', () {
      final base = {
        'package_enabled': true, 'manual_enabled': true, 'grouping_enabled': false,
        'selected_model_id': 'm1', 'can_store_keys': true,
      };
      expect(ManualSettings.fromJson({...base, 'topic_model_id': 'm2'}).topicModelId, 'm2');
      expect(ManualSettings.fromJson({...base, 'topic_model_id': null}).topicModelId, isNull);
    });
  });
}
