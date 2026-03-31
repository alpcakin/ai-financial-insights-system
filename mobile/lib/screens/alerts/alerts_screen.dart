import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: state.isLoading && state.alerts.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.alerts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: Center(
                          child: Text(
                            'No alerts yet',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
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

  IconData _icon() =>
      alert.alertType == 'impact' ? Icons.newspaper : Icons.trending_up;

  Color _severityColor() {
    final s = alert.severity ?? 5;
    if (s >= 9) return Colors.red;
    if (s >= 7) return Colors.orange;
    return Colors.blue;
  }

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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(_icon(), color: color, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (alert.assetSymbol != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    alert.assetSymbol!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              if (alert.severity != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(30),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: color),
                                  ),
                                  child: Text(
                                    'Severity ${alert.severity}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              Text(
                                _timeAgo(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                          if (alert.message != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              alert.message!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
