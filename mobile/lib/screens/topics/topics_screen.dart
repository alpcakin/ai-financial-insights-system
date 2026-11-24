import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/topic_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/topic_provider.dart';

class TopicsScreen extends ConsumerStatefulWidget {
  const TopicsScreen({super.key});

  @override
  ConsumerState<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends ConsumerState<TopicsScreen> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = ref.read(authProvider).token ?? '';
      ref.read(topicProvider.notifier).load(token);
    });
  }

  void _toggle(TopicCategory category) {
    final token = ref.read(authProvider).token ?? '';
    ref.read(topicProvider.notifier).toggle(token, category);
  }

  void _toggleSector(String id) {
    setState(() => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(topicProvider);
    final count = state.followedCount;

    ref.listen(topicProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Flexible(
              child: Text(
                'Interests',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count following',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      body: state.isLoading && state.groups.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.interests_rounded, size: 48, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),
                      Text(
                        'No topics available',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _FollowingSection(
                      items: [
                        for (final g in state.groups) ...[
                          if (g.parent.followed) g.parent,
                          ...g.children.where((c) => c.followed),
                        ],
                        ...state.ownTopics,
                      ],
                      inFlight: state.inFlight,
                      onToggle: _toggle,
                    ),
                    const SizedBox(height: 24),
                    _OwnTopicsSection(onToggle: _toggle),
                    const SizedBox(height: 24),
                    const _SectionLabel('ALL CATEGORIES'),
                    const SizedBox(height: 10),
                    for (final group in state.groups)
                      _SectorTile(
                        group: group,
                        expanded: _expanded.contains(group.parent.id),
                        onExpand: () => _toggleSector(group.parent.id),
                        inFlight: state.inFlight,
                        onToggle: _toggle,
                      ),
                  ],
                ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF94A3B8),
        letterSpacing: 0.8,
      ),
    );
  }
}

/// Everything the user follows in one place, so it can be checked and
/// removed without scrolling through the catalog.
class _FollowingSection extends StatelessWidget {
  final List<TopicCategory> items;
  final Set<String> inFlight;
  final void Function(TopicCategory) onToggle;

  const _FollowingSection({
    required this.items,
    required this.inFlight,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('FOLLOWING'),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'Nothing yet. Open a sector below or add your own topic.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map((item) => _FollowedChip(
                        category: item,
                        isLoading: inFlight.contains(item.id),
                        onRemove: () => onToggle(item),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _FollowedChip extends StatelessWidget {
  final TopicCategory category;
  final bool isLoading;
  final VoidCallback onRemove;

  const _FollowedChip({
    required this.category,
    required this.isLoading,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Unfollow ${category.name}',
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('unfollow-${category.id}'),
        onTap: isLoading ? null : onRemove,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  category.name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: category.level == 1 ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              isLoading
                  ? const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                    )
                  : const Icon(Icons.close_rounded, size: 14, color: Color(0xFFCBD5E1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Topics the user writes: a company, a person, an event. Matching names are
/// suggested while typing, so the same topic is not added twice.
class _OwnTopicsSection extends ConsumerStatefulWidget {
  final void Function(TopicCategory) onToggle;

  const _OwnTopicsSection({required this.onToggle});

  @override
  ConsumerState<_OwnTopicsSection> createState() => _OwnTopicsSectionState();
}

class _OwnTopicsSectionState extends ConsumerState<_OwnTopicsSection> {
  static const _maxLength = 40;

  final _controller = TextEditingController();
  Timer? _debounce;
  List<TopicCategory> _suggestions = const [];
  String? _error;
  bool _adding = false;

  String get _token => ref.read(authProvider).token ?? '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    setState(() => _error = null);
    final query = text.trim();
    if (query.length < 2) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final found = await ref.read(topicProvider.notifier).search(_token, query);
      if (!mounted || _controller.text.trim() != query) return;
      setState(() => _suggestions = found.take(5).toList());
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _suggestions = const []);
  }

  Future<void> _add() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _adding) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    final error = await ref.read(topicProvider.notifier).addTopic(_token, name);
    if (!mounted) return;
    setState(() {
      _adding = false;
      _error = error;
    });
    if (error == null) _clear();
  }

  void _pick(TopicCategory topic) {
    if (!topic.followed) widget.onToggle(topic);
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('ADD YOUR OWN TOPIC'),
        const SizedBox(height: 6),
        Text(
          'Follow a company, a person or an event. Stories related to it reach your feed. '
          'Up to 10 topics. Matching categories also show up while you type.',
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('topic-input'),
                controller: _controller,
                onChanged: _onChanged,
                onSubmitted: (_) => _add(),
                textInputAction: TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(_maxLength)],
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. New York elections',
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _adding ? null : _add,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              child: _adding
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Add', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626)),
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: _suggestions
                  .map((topic) => _Suggestion(topic: topic, onTap: () => _pick(topic)))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  final TopicCategory topic;
  final VoidCallback onTap;

  const _Suggestion({required this.topic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                topic.name,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF0F172A)),
              ),
            ),
            if (topic.followed)
              const Icon(Icons.check_rounded, size: 16, color: Color(0xFF0F172A))
            else
              Text(
                topic.isOwnTopic ? 'Topic' : 'Category',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
              ),
          ],
        ),
      ),
    );
  }
}

/// A sector that opens to its categories. Closed by default, so the whole
/// catalog fits on about one screen; the badge tells what is followed inside.
class _SectorTile extends StatelessWidget {
  final TopicGroup group;
  final bool expanded;
  final VoidCallback onExpand;
  final Set<String> inFlight;
  final void Function(TopicCategory) onToggle;

  const _SectorTile({
    required this.group,
    required this.expanded,
    required this.onExpand,
    required this.inFlight,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final followedChildren = group.children.where((c) => c.followed).length;
    final badge = group.parent.followed
        ? 'Whole sector'
        : followedChildren > 0
            ? '$followedChildren following'
            : null;
    final count = group.children.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('sector-${group.parent.id}'),
            onTap: onExpand,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: group.parent.name,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                        children: [
                          TextSpan(
                            text: count == 1 ? '  1 category' : '  $count categories',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TopicChip(
                          category: group.parent,
                          label: 'All of ${group.parent.name}',
                          inFlight: inFlight,
                          onToggle: onToggle,
                          isSector: true,
                        ),
                        ...group.children.map((child) => _TopicChip(
                              category: child,
                              inFlight: inFlight,
                              onToggle: onToggle,
                            )),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  final TopicCategory category;
  final String? label;
  final Set<String> inFlight;
  final void Function(TopicCategory) onToggle;
  final bool isSector;

  const _TopicChip({
    required this.category,
    this.label,
    required this.inFlight,
    required this.onToggle,
    this.isSector = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = inFlight.contains(category.id);
    final followed = category.followed;

    return GestureDetector(
      onTap: isLoading ? null : () => onToggle(category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: isSector ? 14 : 12,
          vertical: isSector ? 8 : 6,
        ),
        decoration: BoxDecoration(
          color: followed ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(isSector ? 10 : 8),
          border: Border.all(
            color: followed ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                height: 10,
                width: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: followed ? Colors.white : const Color(0xFF64748B),
                ),
              )
            else if (followed)
              Icon(
                Icons.check_rounded,
                size: isSector ? 14 : 12,
                color: Colors.white,
              ),
            if (isLoading || followed) const SizedBox(width: 6),
            Text(
              label ?? category.name,
              style: GoogleFonts.inter(
                fontSize: isSector ? 13 : 12,
                fontWeight: isSector ? FontWeight.w700 : FontWeight.w500,
                color: followed ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
