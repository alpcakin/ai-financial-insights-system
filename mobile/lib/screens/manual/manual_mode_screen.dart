import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../data/models/manual_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/manual_provider.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _line = Color(0xFFE2E8F0);
const _warning = Color(0xFFB45309);

const _kindNames = {
  'openai': 'OpenAI',
  'gemini': 'Google Gemini',
  'claude': 'Anthropic Claude',
  'compatible': 'OpenAI-compatible address',
};

const _intervals = {
  5: 'Every 5 minutes',
  15: 'Every 15 minutes',
  30: 'Every 30 minutes',
  60: 'Every hour',
  240: 'Every 4 hours',
  1440: 'Once a day',
};

/// Where a user chooses what fills their feed: the shared news package, their own
/// sources read with their own models, or both.
class ManualModeScreen extends ConsumerStatefulWidget {
  const ManualModeScreen({super.key});

  @override
  ConsumerState<ManualModeScreen> createState() => _ManualModeScreenState();
}

class _ManualModeScreenState extends ConsumerState<ManualModeScreen> {
  String get _token => ref.read(authProvider).token ?? '';
  ManualNotifier get _notifier => ref.read(manualProvider.notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _notifier.load(_token));
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
          'News Mode',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: _ink),
        ),
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
              onRefresh: () => _notifier.load(_token),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _heading('WHAT FILLS MY FEED'),
                  _card(Column(
                    children: [
                      _switch(
                        title: 'News package',
                        subtitle: 'Our sources, analyzed by our models.',
                        value: settings.packageEnabled,
                        onChanged: (v) => _run(() => _notifier.updateSettings(_token, packageEnabled: v)),
                      ),
                      const Divider(height: 1, color: _line),
                      _switch(
                        title: 'My sources',
                        subtitle: 'Your feeds, analyzed with your own API keys. Only you see them.',
                        value: settings.manualEnabled,
                        onChanged: (v) => _run(() => _notifier.updateSettings(_token, manualEnabled: v)),
                      ),
                    ],
                  )),
                  _note(
                    'Changes apply from now on: what is already in your feed stays. Both can be on. '
                    'News only reaches the feed when it matches your portfolio, watchlist or topics.',
                  ),
                  if (settings.manualEnabled && (state.sources.isEmpty || !state.hasWorkingModel))
                    _warningNote('My sources needs at least one source and one working model.'),
                  _heading('SAME-EVENT GROUPING'),
                  _card(_switch(
                    title: 'Group reports of the same event',
                    subtitle: settings.groupingEnabled
                        ? 'On: reports of one event become one card and are analyzed once.'
                        : 'Off: every article is its own card and is analyzed separately.',
                    value: settings.groupingEnabled,
                    onChanged: (v) => _run(() => _notifier.updateSettings(_token, groupingEnabled: v)),
                  )),
                  _note(
                    'Turning it on uses our measured system, on our keys, only among your own articles: '
                    'text-embedding-3-small finds candidates, SubQ Snap decides. Your articles\' titles and '
                    'descriptions then go to OpenAI and SubQ. It was measured on our 7 sources, not on yours, '
                    'and a wrong match keeps an article out of analysis. It applies to new articles only. While '
                    'it is on and the system is down, your articles wait instead of being analyzed one by one.',
                  ),
                  _sectionHeader(
                    'MY SOURCES',
                    '${state.sources.length}/20',
                    onAdd: state.sources.length >= 20 ? null : () => _openSheet(const _AddSourceSheet()),
                  ),
                  if (state.sources.isEmpty)
                    _note('Add an RSS or Atom address. What the feed already holds counts as seen; '
                        'only what arrives afterwards is analyzed.')
                  else
                    ...state.sources.map(_sourceTile),
                  _sectionHeader(
                    'MY MODELS',
                    null,
                    onAdd: settings.canStoreKeys ? () => _openSheet(const _AddModelSheet()) : null,
                  ),
                  if (!settings.canStoreKeys) _warningNote('This server cannot store API keys yet.'),
                  if (state.models.isEmpty && settings.canStoreKeys)
                    _note('Every model you add analyzes every new article from your sources, on your own '
                        'account. Your feed shows the one you pick; open an article to compare the others.')
                  else
                    ...state.models.map((m) => _modelTile(m, settings.selectedModelId)),
                ],
              ),
            ),
    );
  }

  Widget _sourceTile(UserSource source) {
    final error = switch (source.lastError) {
      'unreachable' => 'Could not reach this feed',
      'unreadable' => 'Could not read this feed',
      _ => null,
    };
    return _card(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                  const SizedBox(height: 2),
                  Text(
                    source.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _intervals[source.fetchIntervalMinutes] ?? 'Every ${source.fetchIntervalMinutes} minutes',
                    style: GoogleFonts.inter(fontSize: 11, color: _faint),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 2),
                    Text(error, style: GoogleFonts.inter(fontSize: 11, color: _warning)),
                  ],
                ],
              ),
            ),
            Switch(
              value: source.enabled,
              activeThumbColor: _ink,
              onChanged: (v) => _run(() => _notifier.updateSource(_token, source.id, enabled: v)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: _faint),
              onPressed: () async {
                if (await _confirm('Delete source', 'News already in your feed stays.')) {
                  await _run(() => _notifier.deleteSource(_token, source.id));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelTile(UserModel model, String? selectedId) {
    final stopped = switch (model.stoppedReason) {
      'auth' => 'Stopped: its key or model was rejected',
      'quota' => 'Stopped: its account has no quota left',
      _ => null,
    };
    final selected = model.id == selectedId;
    return _card(
      InkWell(
        onTap: selected ? null : () => _run(() => _notifier.updateSettings(_token, selectedModelId: model.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? _ink : _faint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                    const SizedBox(height: 2),
                    Text(
                      '${_kindNames[model.kind] ?? model.kind} · ${model.model} · key ends in ${model.keyLast4}',
                      style: GoogleFonts.inter(fontSize: 12, color: _muted),
                    ),
                    if (model.baseUrl != null)
                      Text(
                        model.baseUrl!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: _faint),
                      ),
                    if (stopped != null) ...[
                      const SizedBox(height: 2),
                      Text(stopped, style: GoogleFonts.inter(fontSize: 11, color: _warning)),
                    ],
                  ],
                ),
              ),
              if (stopped != null) _RetryButton(modelId: model.id),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: _faint),
                onPressed: () async {
                  if (await _confirm('Delete model', 'Its key is deleted. Analyses it already made stay.')) {
                    await _run(() => _notifier.deleteModel(_token, model.id));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
        title: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _muted)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: _ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      );

  Widget _card(Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _line),
          ),
          child: child,
        ),
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(
          text,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _faint, letterSpacing: 0.8),
        ),
      );

  Widget _sectionHeader(String text, String? count, {VoidCallback? onAdd}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Expanded(child: _heading(count == null ? text : '$text  $count')),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('Add', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text, style: GoogleFonts.inter(fontSize: 11, color: _faint, height: 1.45)),
      );

  Widget _warningNote(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: _warning, height: 1.45)),
      );
}

class _RetryButton extends ConsumerStatefulWidget {
  final String modelId;

  const _RetryButton({required this.modelId});

  @override
  ConsumerState<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends ConsumerState<_RetryButton> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    String message = 'Network error. Please try again.';
    try {
      await ref.read(manualProvider.notifier).retryModel(ref.read(authProvider).token ?? '', widget.modelId);
      message = 'The model is working again.';
    } on ManualException catch (e) {
      message = e.message;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return TextButton(onPressed: _retry, child: const Text('Retry'));
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
      if (mounted) Navigator.pop(context);
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
        if (!AppConstants.baseUrl.startsWith('https://'))
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
