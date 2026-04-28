import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/topic_models.dart';
import '../data/repositories/topic_repository.dart';

class TopicState {
  final List<TopicGroup> groups;
  final bool isLoading;
  final String? error;
  final Set<String> inFlight;

  const TopicState({
    this.groups = const [],
    this.isLoading = false,
    this.error,
    this.inFlight = const {},
  });

  TopicState copyWith({
    List<TopicGroup>? groups,
    bool? isLoading,
    String? error,
    bool clearError = false,
    Set<String>? inFlight,
  }) =>
      TopicState(
        groups: groups ?? this.groups,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        inFlight: inFlight ?? this.inFlight,
      );

  int get followedCount => groups.fold(0, (acc, g) {
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
      state = state.copyWith(groups: _group(cats), isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> toggle(String token, TopicCategory category) async {
    if (state.inFlight.contains(category.id)) return;

    final wasFollowed = category.followed;
    final newInFlight = {...state.inFlight, category.id};

    // Optimistic update
    category.followed = !wasFollowed;
    state = state.copyWith(groups: List.of(state.groups), inFlight: newInFlight);

    try {
      if (wasFollowed) {
        await _repo.unfollowTopic(token, category.id);
      } else {
        await _repo.followTopic(token, category.id);
      }
    } catch (_) {
      // Revert
      category.followed = wasFollowed;
      state = state.copyWith(
        groups: List.of(state.groups),
        error: wasFollowed ? 'Failed to unfollow' : 'Failed to follow',
      );
    } finally {
      final updated = {...state.inFlight}..remove(category.id);
      state = state.copyWith(inFlight: updated);
    }
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
