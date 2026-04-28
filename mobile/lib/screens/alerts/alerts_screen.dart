import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/alert_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/alert_provider.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = ref.read(authProvider).token ?? '';
      ref.read(alertProvider.notifier).load(token);
    });
  }

  Future<void> _refresh() async {
    final token = ref.read(authProvider).token ?? '';
    await ref.read(alertProvider.notifier).refresh(token);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(alertProvider);
    final count = state.alerts.length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Text(
              'Alerts',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF3B82F6),
        child: state.isLoading && state.alerts.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.alerts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Icons.notifications_outlined, size: 48, color: Color(0xFFCBD5E1)),
                              const SizedBox(height: 12),
                              Text(
                                'No alerts yet',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You\'ll be notified when something important happens',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: state.alerts.length,
                    itemBuilder: (context, index) =>
                        _AlertCard(alert: state.alerts[index]),
                  ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertItem alert;

  const _AlertCard({required this.alert});

  Color _severityColor() {
    final s = alert.severity ?? 5;
    if (s >= 9) return const Color(0xFFEF4444);
    if (s >= 7) return const Color(0xFFF97316);
    return const Color(0xFF3B82F6);
  }

  bool get _isImpact => alert.alertType == 'impact';

  String _timeAgo() {
    final dt = DateTime.tryParse(alert.createdAt);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Icon(
              _isImpact ? Icons.article_rounded : Icons.trending_up_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (alert.assetSymbol != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          alert.assetSymbol!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    if (alert.severity != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(80)),
                        ),
                        child: Text(
                          'S${alert.severity}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      _timeAgo(),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                if (alert.message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    alert.message!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF334155),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
