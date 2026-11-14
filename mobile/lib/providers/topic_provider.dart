import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/topic_models.dart';
import '../data/repositories/topic_repository.dart';

class TopicState {
  final List<TopicGroup> groups;

  /// Topics users wrote that this user follows, in the order the server lists them.
  final List<TopicCategory> ownTopics;
  final bool isLoading;
  final String? error;
  final Set<String> inFlight;

  const TopicState({
    this.groups = const [],
    this.ownTopics = const [],
    this.isLoading = false,
    this.error,
    this.inFlight = const {},
  });

  TopicState copyWith({
    List<TopicGroup>? groups,
    List<TopicCategory>? ownTopics,
    bool? isLoading,
    String? error,
    bool clearError = false,
    Set<String>? inFlight,
  }) =>
      TopicState(
        groups: groups ?? this.groups,
        ownTopics: ownTopics ?? this.ownTopics,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        inFlight: inFlight ?? this.inFlight,
      );

  int get followedCount =>
      ownTopics.length +
      groups.fold(0, (acc, g) {
        int n = g.parent.followed ? 1 : 0;
        for (final c in g.children) {
          if (c.followed) n++;
        }
        return acc + n;
      });
}

class TopicNotifier extends StateNotifier<TopicState> {
  final TopicRepository _repo;

  TopicNotifier(this._repo) : super(const TopicState());

  Future<void> load(String token) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cats = await _repo.getTopics(token);
      state = state.copyWith(
        groups: _group(cats),
        ownTopics: cats.where((c) => c.isOwnTopic).toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Follows or unfollows. An own topic leaves the list when it is unfollowed.
  Future<void> toggle(String token, TopicCategory category) async {
    if (state.inFlight.contains(category.id)) return;

    final wasFollowed = category.followed;
    state = _apply(category.copyWith(followed: !wasFollowed))
        .copyWith(inFlight: {...state.inFlight, category.id}, clearError: true);

    try {
      if (wasFollowed) {
        await _repo.unfollowTopic(token, category.id);
      } else {
        await _repo.followTopic(token, category.id);
      }
    } on TopicException catch (e) {
      state = _apply(category).copyWith(error: e.message);
    } catch (_) {
      state = _apply(category).copyWith(error: wasFollowed ? 'Failed to unfollow' : 'Failed to follow');
    } finally {
      final updated = {...state.inFlight}..remove(category.id);
      state = state.copyWith(inFlight: updated);
    }
  }

  /// Follows a topic by name. Returns the message to show when it was not added.
  Future<String?> addTopic(String token, String name) async {
    try {
      final topic = await _repo.addTopic(token, name);
      state = _apply(topic).copyWith(clearError: true);
      return null;
    } on TopicException catch (e) {
      return e.message;
    } catch (_) {
      return 'This topic could not be added. Please try again.';
    }
  }

  /// Existing categories and topics that contain the text, to pick from before adding.
  Future<List<TopicCategory>> search(String token, String query) async {
    try {
      return await _repo.searchTopics(token, query);
    } catch (_) {
      return const [];
    }
  }

  TopicState _apply(TopicCategory topic) {
    if (topic.isOwnTopic) {
      final others = state.ownTopics.where((t) => t.id != topic.id).toList();
      return state.copyWith(ownTopics: topic.followed ? [...others, topic] : others);
    }
    return state.copyWith(groups: _updateCategoryInGroups(state.groups, topic.id, topic.followed));
  }

  List<TopicGroup> _updateCategoryInGroups(
    List<TopicGroup> groups,
    String id,
    bool followed,
  ) {
    return groups.map((g) {
      if (g.parent.id == id) {
        return TopicGroup(parent: g.parent.copyWith(followed: followed), children: g.children);
      }
      final updatedChildren = g.children
          .map((c) => c.id == id ? c.copyWith(followed: followed) : c)
          .toList();
      return TopicGroup(parent: g.parent, children: updatedChildren);
    }).toList();
  }

  List<TopicGroup> _group(List<TopicCategory> cats) {
    final level1 = cats.where((c) => c.level == 1).toList();
    final level2 = cats.where((c) => c.level == 2).toList();
    return level1.map((parent) {
      final children = level2.where((c) => c.parentId == parent.id).toList();
      return TopicGroup(parent: parent, children: children);
    }).toList();
  }
}

final topicProvider = StateNotifierProvider<TopicNotifier, TopicState>(
  (_) => TopicNotifier(TopicRepository()),
);
