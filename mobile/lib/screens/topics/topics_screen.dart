import 'package:flutter/material.dart';
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
            Text(
              'Interests',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count following',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: state.groups.length,
                  itemBuilder: (context, index) {
                    final group = state.groups[index];
                    return _TopicGroupSection(
                      group: group,
                      inFlight: state.inFlight,
                      onToggle: _toggle,
                    );
                  },
                ),
    );
  }
}

class _TopicGroupSection extends StatelessWidget {
  final TopicGroup group;
  final Set<String> inFlight;
  final void Function(TopicCategory) onToggle;

  const _TopicGroupSection({
    required this.group,
    required this.inFlight,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.parent.name.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TopicChip(
                category: group.parent,
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
          const SizedBox(height: 4),
          const Divider(color: Color(0xFFE2E8F0), height: 24),
        ],
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  final TopicCategory category;
  final Set<String> inFlight;
  final void Function(TopicCategory) onToggle;
  final bool isSector;

  const _TopicChip({
    required this.category,
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
              category.name,
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
