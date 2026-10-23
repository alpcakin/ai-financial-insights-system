import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/alert_settings_provider.dart';
import '../../providers/auth_provider.dart';

/// Volatility alert choice for one portfolio or watchlist asset. Pops `true`
/// when the choice was saved.
class AlertSettingSheet extends ConsumerStatefulWidget {
  final String symbol;
  const AlertSettingSheet({super.key, required this.symbol});

  @override
  ConsumerState<AlertSettingSheet> createState() => _AlertSettingSheetState();
}

class _AlertSettingSheetState extends ConsumerState<AlertSettingSheet> {
  static const _descriptions = {
    'auto': 'Alerts when the price moves 2.58 times its usual daily move. '
        'The usual move is learned from the asset\'s own recent volatility.',
    'percent': 'Alerts when the price moves at least this much: '
        'since the previous close, or in 24 hours for crypto.',
    'off': 'No price alerts for this asset. News alerts are not affected.',
  };

  final _formKey = GlobalKey<FormState>();
  final _pctCtrl = TextEditingController();
  late String _mode;

  @override
  void initState() {
    super.initState();
    final current = ref.read(alertSettingsProvider).forSymbol(widget.symbol);
    _mode = current.mode;
    _pctCtrl.text = current.thresholdText ?? '';
  }

  @override
  void dispose() {
    _pctCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final token = ref.read(authProvider).token ?? '';
    final saved = await ref.read(alertSettingsProvider.notifier).save(
          token,
          widget.symbol,
          mode: _mode,
          thresholdPct: _mode == 'percent' ? double.parse(_pctCtrl.text.trim()) : null,
        );
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(alertSettingsProvider).error ?? 'Failed to save';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(alertSettingsProvider).isSaving;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Price alert · ${widget.symbol}',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text('Automatic')),
                ButtonSegment(value: 'percent', label: Text('Custom %')),
                ButtonSegment(value: 'off', label: Text('Off')),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() => _mode = selection.first),
            ),
            const SizedBox(height: 12),
            Text(
              _descriptions[_mode]!,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            if (_mode == 'percent') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _pctCtrl,
                decoration: const InputDecoration(labelText: 'Move (%)', suffixText: '%'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a percentage';
                  if (n < 1 || n > 50) return 'Between 1 and 50';
                  return null;
                },
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isSaving ? null : _save,
              child: isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> showAlertSettingSheet(BuildContext context, String symbol) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => AlertSettingSheet(symbol: symbol),
  );
}
