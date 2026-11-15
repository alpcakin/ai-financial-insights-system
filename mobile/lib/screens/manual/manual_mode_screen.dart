import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../data/models/manual_models.dart';
import '../../data/models/news_models.dart';
import '../../data/models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/manual_provider.dart';
import '../../providers/news_provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/info_tip.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _line = Color(0xFFE2E8F0);
const _accent = Color(0xFF3B82F6);
const _accentSoft = Color(0xFFEFF6FF);
const _neutralSoft = Color(0xFFF1F5F9);
const _warning = Color(0xFFB45309);
const _success = Color(0xFF10B981);

const _kindNames = {
  'openai': 'OpenAI',
  'gemini': 'Google Gemini',
  'claude': 'Anthropic Claude',
  'compatible': 'OpenAI-compatible address',
};

const _intervals = {
  1: 'Every minute',
  2: 'Every 2 minutes',
  5: 'Every 5 minutes',
  15: 'Every 15 minutes',
  30: 'Every 30 minutes',
  60: 'Every hour',
  240: 'Every 4 hours',
  1440: 'Once a day',
};

/// The server enforces the same limit.
const _maxSources = 20;

/// Whether a key typed here would cross a network in plain text. A server on this
/// machine is reached without one.
bool sendsKeysUnencrypted(String baseUrl) {
  final uri = Uri.parse(baseUrl);
  return uri.scheme != 'https' && !const {'localhost', '127.0.0.1'}.contains(uri.host);
}

/// Where a user chooses what fills their feed and which AI reads it: the shared news
/// package with the model they see, their own sources read with their own models,
/// or both.
class ManualModeScreen extends ConsumerStatefulWidget {
  const ManualModeScreen({super.key});

  @override
  ConsumerState<ManualModeScreen> createState() => _ManualModeScreenState();
}

class _ManualModeScreenState extends ConsumerState<ManualModeScreen> {
  String get _token => ref.read(authProvider).token ?? '';
  ManualNotifier get _notifier => ref.read(manualProvider.notifier);

  /// Loaded the first time the news package is shown open.
  Future<List<NewsSource>>? _packageFeeds;
  Future<void>? _providersLoad;
  bool _updatingProvider = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(userProvider).providers.isEmpty) {
      _providersLoad = ref.read(userProvider.notifier).loadProviders(_token);
    }
    Future.microtask(() => _notifier.load(_token));
  }

  Future<void> _refresh() async {
    final providers = ref.read(userProvider.notifier).loadProviders(_token);
    setState(() => _providersLoad = providers);
    await Future.wait([_notifier.load(_token), providers]);
  }

  void _show(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on ManualException catch (e) {
      _show(e.message);
    } catch (_) {
      _show('Network error. Please try again.');
    }
  }

  Future<void> _selectProvider(String name) async {
    if (name == ref.read(userProvider).profile?.aiProvider) return;
    setState(() => _updatingProvider = true);
    try {
      await ref.read(userProvider.notifier).updatePreferences(_token, aiProvider: name);
    } on UserException catch (e) {
      _show(e.message);
    } catch (_) {
      _show('Failed to update AI model');
    }
    if (mounted) setState(() => _updatingProvider = false);
  }

  Future<bool> _confirm(String title, String body) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return answer ?? false;
  }

  void _openSheet(Widget sheet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => sheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualProvider);
    final settings = state.settings;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'News & AI',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: _ink),
        ),
        actions: const [
          InfoTip(
            'Both can be on. Changes apply from now on: what is already in your feed stays. News only '
            'reaches the feed when it matches your portfolio, watchlist or topics.',
          ),
          SizedBox(width: 10),
        ],
      ),
      body: settings == null
          ? Center(
              child: state.error != null
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(state.error!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: _muted)),
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _ModeSection(
                    icon: Icons.newspaper_rounded,
                    title: 'News package',
                    subtitle: 'Our sources, read by our AI models.',
                    value: settings.packageEnabled,
                    onChanged: (v) => _run(() => _notifier.updateSettings(_token, packageEnabled: v)),
                    children: settings.packageEnabled ? _packageOptions() : const [],
                  ),
                  const SizedBox(height: 12),
                  _ModeSection(
                    icon: Icons.vpn_key_outlined,
                    title: 'My sources',
                    subtitle: 'Your feeds, read with your own API keys. Only you see them.',
                    note: !settings.manualEnabled && (state.sources.isNotEmpty || state.models.isNotEmpty)
                        ? 'Your sources and models are kept while My sources is off.'
                        : null,
                    value: settings.manualEnabled,
                    onChanged: (v) => _run(() => _notifier.updateSettings(_token, manualEnabled: v)),
                    children: settings.manualEnabled ? _manualOptions(state, settings) : const [],
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _packageOptions() {
    final userState = ref.watch(userProvider);
    final selected = userState.profile?.aiProvider;
    return [
      const _BlockHeader(
        icon: Icons.auto_awesome_rounded,
        title: 'Analysis model',
        info: 'Every article of the news package is analyzed by all available models. Your feed and alerts '
            'show the one you pick; if it has no result for an article, another model\'s analysis is shown '
            'and marked.',
      ),
      if (userState.providers.isEmpty)
        FutureBuilder<void>(
          future: _providersLoad,
          builder: (context, snapshot) => _hint(
            snapshot.connectionState == ConnectionState.waiting
                ? 'Loading the models…'
                : 'The models could not be loaded. Pull down to try again.',
          ),
        )
      else
        for (final p in userState.providers)
          _ChoiceRow(
            title: p.displayName,
            badge: p.isDefault ? 'Default' : null,
            subtitle: p.model,
            selected: p.name == selected,
            onTap: _updatingProvider ? null : () => _selectProvider(p.name),
          ),
      const _BlockDivider(),
      const _BlockHeader(
        icon: Icons.public_rounded,
        title: 'Our sources',
        info: 'Chosen for credibility (Media Bias/Fact Check ratings, where one exists), real summaries rather '
            'than bare headlines, a fit with markets, business, technology and crypto, broad coverage and speed. '
            'When several outlets report the same event, it is analyzed once and shown as one story with all of '
            'its sources.',
      ),
      FutureBuilder<List<NewsSource>>(
        future: _packageFeeds ??= ref.read(newsRepositoryProvider).getSources(_token),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _hint('The source list could not be loaded.');
          if (!snapshot.hasData) return _hint('Loading the sources…');
          final sections = <String, List<String>>{};
          for (final s in snapshot.data!) {
            sections.putIfAbsent(s.outlet, () => []).add(s.section);
          }
          return Column(
            children: [
              for (final e in sections.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 104,
                        child: Text(e.key, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                      ),
                      Expanded(child: Text(e.value.join(', '), style: GoogleFonts.inter(fontSize: 13, color: _muted))),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _manualOptions(ManualState state, ManualSettings settings) {
    final own = state.sources.where((s) => !s.fromPackage).toList();
    final followed = state.sources.where((s) => s.fromPackage).toList();
    final topicModel = state.models.where((m) => m.id == settings.topicModelId).firstOrNull;
    return [
      if (state.sources.isEmpty || !state.hasWorkingModel)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _warningText('My sources needs at least one source and one working model.'),
        ),
      const _BlockHeader(
        icon: Icons.rss_feed_rounded,
        title: 'Feeds',
        info: 'Add an RSS or Atom address. What a feed already holds counts as seen; only what arrives '
            'afterwards is analyzed. Your own feeds can be read as often as every minute; the app\'s own feeds '
            'at most every 5 minutes.',
      ),
      _followTile(settings, followed),
      for (final source in own) _sourceRow(source),
      _addButton(
        'Add a feed',
        own.length >= _maxSources
            ? () => _show('You can have at most $_maxSources sources.')
            : () => _openSheet(const _AddSourceSheet()),
      ),
      const _BlockDivider(),
      const _BlockHeader(
        icon: Icons.vpn_key_outlined,
        title: 'AI models',
        info: 'Every model you add analyzes every new article from your feeds, on your own account. Your feed '
            'shows the one marked "In your feed"; open an article to compare the others.',
      ),
      if (!settings.canStoreKeys) _warningText('This server cannot store API keys yet.'),
      for (final model in state.models) _modelRow(model, settings.selectedModelId),
      _addButton('Add a model', settings.canStoreKeys ? () => _openSheet(const _AddModelSheet()) : null),
      const _BlockDivider(),
      const _BlockHeader(icon: Icons.tune_rounded, title: 'Options'),
      _switchRow(
        title: 'Group reports of the same event',
        info: 'Turning it on uses our measured system, on our keys, only among your own articles: '
            'text-embedding-3-small finds candidates, SubQ Snap decides. Your articles\' titles and descriptions '
            'then go to OpenAI and SubQ. It was measured on our 7 sources, not on yours, and a wrong match keeps '
            'an article out of analysis. It applies to new articles only. While it is on and the system is down, '
            'your articles wait instead of being analyzed one by one.',
        subtitle: settings.groupingEnabled
            ? 'On: reports of one event become one card and are analyzed once.'
            : 'Off: every article is its own card and is analyzed separately.',
        value: settings.groupingEnabled,
        onChanged: (v) => _run(() => _notifier.updateSettings(_token, groupingEnabled: v)),
      ),
      InkWell(
        onTap: state.models.isEmpty ? null : () => _chooseTopicMatcher(state.models, settings.topicModelId),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Topic matching',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
                          ),
                        ),
                        const InfoTip(
                          'Decides which categories and topics of yours a new article relates to. SubQ Snap does '
                          'it on our key, only on your own articles; it was measured on our sources. Once you add '
                          'a model, you can pick it instead: it answers in the same call as its analysis, so it '
                          'costs no extra call, but this way was not measured. If it gives no answer, Snap answers '
                          'for that article.',
                        ),
                      ],
                    ),
                    Text(
                      topicModel == null ? 'SubQ Snap' : '${topicModel.label}, inside its analysis',
                      style: GoogleFonts.inter(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              if (state.models.isNotEmpty) const Icon(Icons.chevron_right_rounded, color: _faint),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> _chooseTopicMatcher(List<UserModel> models, String? selected) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TopicMatcherSheet(models: models, selected: selected),
    );
    if (picked != null) await _run(() => _notifier.setTopicModel(_token, picked.isEmpty ? null : picked));
  }

  Future<void> _retryModel(String id) async {
    var message = 'Network error. Please try again.';
    try {
      await _notifier.retryModel(_token, id);
      message = 'The model is working again.';
    } on ManualException catch (e) {
      message = e.message;
    } catch (_) {}
    _show(message);
  }

  Widget _followTile(ManualSettings settings, List<UserSource> followed) {
    final on = settings.followPackageFeeds;
    final failing = followed.where((s) => s.lastError != null).length;
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: on ? _accentSoft : _neutralSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.newspaper_rounded, size: 20, color: on ? _accent : _faint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Follow the app\'s feeds',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
                      ),
                    ),
                    const InfoTip(
                      'Reads the news package\'s feeds with your own models, as if you had added them. When the '
                      'app adds or drops a feed, yours change with it. They bring a few hundred articles a day and '
                      'every model you add analyzes each one on your account; same-event grouping analyzes reports '
                      'of one event once.',
                    ),
                  ],
                ),
                Text(
                  on && followed.isNotEmpty
                      ? {for (final s in followed) s.name}.join(', ')
                      : 'Our feeds, read by your models.',
                  style: GoogleFonts.inter(fontSize: 12, color: _muted),
                ),
                if (failing > 0)
                  Text(
                    '$failing of them could not be read last time.',
                    style: GoogleFonts.inter(fontSize: 11, color: _warning),
                  ),
              ],
            ),
          ),
          Switch(
            key: const ValueKey('follow-app-feeds'),
            value: on,
            activeThumbColor: _ink,
            onChanged: (v) => _run(() => _notifier.updateSettings(_token, followPackageFeeds: v)),
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(UserSource source) {
    final error = switch (source.lastError) {
      'unreachable' => 'Could not reach this feed',
      'unreadable' => 'Could not read this feed',
      _ => null,
    };
    final host = Uri.tryParse(source.url)?.host ?? '';
    // The address goes last: it is the part that may be cut short.
    final details = [
      if (!source.enabled) 'Paused',
      _intervals[source.fetchIntervalMinutes] ?? 'Every ${source.fetchIntervalMinutes} minutes',
      host.isEmpty ? source.url : host,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _RowIcon(Icons.rss_feed_rounded, active: source.enabled),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: source.enabled ? _ink : _faint,
                  ),
                ),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: _muted),
                ),
                if (error != null) Text(error, style: GoogleFonts.inter(fontSize: 11, color: _warning)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options for ${source.name}',
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: _faint),
            onSelected: (action) async {
              if (action == 'toggle') {
                await _run(() => _notifier.updateSource(_token, source.id, enabled: !source.enabled));
              } else if (await _confirm('Delete source', 'News already in your feed stays.')) {
                await _run(() => _notifier.deleteSource(_token, source.id));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'toggle', child: Text(source.enabled ? 'Pause' : 'Resume')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modelRow(UserModel model, String? selectedId) {
    final stopped = switch (model.stoppedReason) {
      'auth' => 'Stopped: its key or model was rejected',
      'quota' => 'Stopped: its account has no quota left',
      _ => null,
    };
    final selected = model.id == selectedId;
    final details = [
      _kindNames[model.kind] ?? model.kind,
      if (model.label != model.model) model.model,
      'key ends in ${model.keyLast4}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _RowIcon(Icons.smart_toy_outlined, active: stopped == null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(model.label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                    if (selected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: _accentSoft, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          'In your feed',
                          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: _accent),
                        ),
                      ),
                  ],
                ),
                Text(details, style: GoogleFonts.inter(fontSize: 12, color: _muted)),
                if (model.baseUrl != null)
                  Text(
                    model.baseUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: _faint),
                  ),
                if (stopped != null) Text(stopped, style: GoogleFonts.inter(fontSize: 11, color: _warning)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options for ${model.label}',
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: _faint),
            onSelected: (action) async {
              switch (action) {
                case 'select':
                  await _run(() => _notifier.updateSettings(_token, selectedModelId: model.id));
                case 'retry':
                  await _retryModel(model.id);
                case 'delete':
                  if (await _confirm('Delete model', 'Its key is deleted. Analyses it already made stay.')) {
                    await _run(() => _notifier.deleteModel(_token, model.id));
                  }
              }
            },
            itemBuilder: (_) => [
              if (!selected) const PopupMenuItem(value: 'select', child: Text('Show in my feed')),
              if (stopped != null) const PopupMenuItem(value: 'retry', child: Text('Try again')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? info,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                    ),
                    if (info != null) InfoTip(info),
                  ],
                ),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _muted)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: _ink),
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback? onPressed) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(foregroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 6)),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: _faint, height: 1.45)),
      );

  Widget _warningText(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: _warning, height: 1.45)),
      );
}

/// The title of one group of options inside a mode.
class _BlockHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? info;

  const _BlockHeader({required this.icon, required this.title, this.info});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(title, style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
          ),
          if (info != null) InfoTip(info!),
        ],
      ),
    );
  }
}

class _BlockDivider extends StatelessWidget {
  const _BlockDivider();

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.only(top: 10), child: Divider(height: 1, color: _line));
}

class _RowIcon extends StatelessWidget {
  final IconData icon;
  final bool active;

  const _RowIcon(this.icon, {required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: _neutralSoft, borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, size: 17, color: active ? const Color(0xFF475569) : _faint),
    );
  }
}

/// A radio-style choice: the package's analysis model or the topic matcher.
class _ChoiceRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final String? badge;

  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selected ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? _ink : _faint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: _neutralSoft, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            badge!,
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _muted),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicMatcherSheet extends StatelessWidget {
  final List<UserModel> models;
  final String? selected;

  const _TopicMatcherSheet({required this.models, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Topic matching', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 6),
            Text(
              'Decides which categories and topics of yours a new article relates to.',
              style: GoogleFonts.inter(fontSize: 13, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 8),
            _ChoiceRow(
              title: 'SubQ Snap',
              subtitle: 'Our measured system, on our key, only on your own articles.',
              selected: selected == null,
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final m in models)
              _ChoiceRow(
                title: m.label,
                subtitle: 'In the same call as its analysis, no extra call.',
                selected: selected == m.id,
                onTap: () => Navigator.pop(context, m.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// One of the two ways news reaches the feed. Its options open beneath it while it is on.
class _ModeSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? note;
  final bool value;
  final ValueChanged<bool> onChanged;
  final List<Widget> children;

  const _ModeSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.children,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: value ? _accent : _line, width: value ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: value ? _accentSoft : _neutralSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: value ? _accent : _faint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _muted, height: 1.35)),
                      if (note != null) ...[
                        const SizedBox(height: 4),
                        Text(note!, style: GoogleFonts.inter(fontSize: 11.5, color: _faint, height: 1.35)),
                      ],
                    ],
                  ),
                ),
                Switch(value: value, onChanged: onChanged, activeThumbColor: _ink),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: children.isEmpty
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1, color: _line),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddSourceSheet extends ConsumerStatefulWidget {
  const _AddSourceSheet();

  @override
  ConsumerState<_AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends ConsumerState<_AddSourceSheet> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  int _interval = 15;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_url.text.trim().isEmpty) {
      setState(() => _error = 'Enter the address of the feed.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(manualProvider.notifier).addSource(
            ref.read(authProvider).token ?? '',
            url: _url.text.trim(),
            name: _name.text.trim(),
            intervalMinutes: _interval,
          );
      if (mounted) Navigator.pop(context);
    } on ManualException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: 'Add a source',
      error: _error,
      busy: _busy,
      actionLabel: 'Check and add',
      onAction: _save,
      children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'RSS or Atom address', hintText: 'https://...'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'The feed\'s own title'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: _interval,
          decoration: const InputDecoration(labelText: 'Check it'),
          items: _intervals.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setState(() => _interval = v ?? 15),
        ),
      ],
    );
  }
}

class _AddModelSheet extends ConsumerStatefulWidget {
  const _AddModelSheet();

  @override
  ConsumerState<_AddModelSheet> createState() => _AddModelSheetState();
}

class _AddModelSheetState extends ConsumerState<_AddModelSheet> {
  final _model = TextEditingController();
  final _key = TextEditingController();
  final _label = TextEditingController();
  final _address = TextEditingController();
  String _kind = 'openai';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _model.dispose();
    _key.dispose();
    _label.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_model.text.trim().isEmpty || _key.text.trim().isEmpty) {
      setState(() => _error = 'Enter the model name and the API key.');
      return;
    }
    if (_kind == 'compatible' && _address.text.trim().isEmpty) {
      setState(() => _error = 'Enter the address of the model.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(manualProvider.notifier).addModel(
            ref.read(authProvider).token ?? '',
            kind: _kind,
            model: _model.text.trim(),
            apiKey: _key.text.trim(),
            label: _label.text.trim(),
            baseUrl: _kind == 'compatible' ? _address.text.trim() : null,
          );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          backgroundColor: _success,
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Successful', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ));
      }
    } on ManualException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The check took too long or the network failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: 'Add a model',
      error: _error,
      busy: _busy,
      actionLabel: 'Test and save',
      onAction: _save,
      children: [
        if (sendsKeysUnencrypted(AppConstants.baseUrl))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'This connection to the server is not encrypted. Do not enter a real key.',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFEF4444)),
            ),
          ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Provider'),
          items: _kindNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setState(() => _kind = v ?? 'openai'),
        ),
        const SizedBox(height: 12),
        if (_kind == 'compatible') ...[
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Address', hintText: 'https://.../v1'),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _model,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Model name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'API key'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _label,
          decoration: const InputDecoration(labelText: 'Name in the app (optional)'),
        ),
        const SizedBox(height: 8),
        Text(
          'Saving makes one test call on your account. The key is stored encrypted, is never shown again and '
          'is deleted with the model or your account. From then on this model analyzes every new article from '
          'your sources at your cost, with no daily limit.',
          style: GoogleFonts.inter(fontSize: 11, color: _faint, height: 1.45),
        ),
      ],
    );
  }
}

class _SheetBody extends StatelessWidget {
  final String title;
  final String? error;
  final bool busy;
  final String actionLabel;
  final VoidCallback onAction;
  final List<Widget> children;

  const _SheetBody({
    required this.title,
    required this.error,
    required this.busy,
    required this.actionLabel,
    required this.onAction,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 16),
            ...children,
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFEF4444))),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : onAction,
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(actionLabel, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
