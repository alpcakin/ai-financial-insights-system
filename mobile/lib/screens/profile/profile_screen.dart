import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../privacy/privacy_policy_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool? _impactOverride;
  bool? _volatilityOverride;
  bool _updatingImpact = false;
  bool _updatingVolatility = false;
  bool _updatingProvider = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(userProvider).providers.isEmpty) {
        final token = ref.read(authProvider).token ?? '';
        ref.read(userProvider.notifier).loadProviders(token);
      }
    });
  }

  String _initials(String? email) {
    if (email == null || email.isEmpty) return '?';
    final name = email.split('@').first;
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
  }

  Future<void> _toggleImpact(bool value) async {
    setState(() { _impactOverride = value; _updatingImpact = true; });
    try {
      final token = ref.read(authProvider).token ?? '';
      await ref.read(userProvider.notifier).updatePreferences(token, impactAlerts: value);
    } catch (_) {
      if (mounted) {
        setState(() => _impactOverride = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preferences')),
        );
      }
    }
    if (mounted) setState(() { _impactOverride = null; _updatingImpact = false; });
  }

  Future<void> _toggleVolatility(bool value) async {
    setState(() { _volatilityOverride = value; _updatingVolatility = true; });
    try {
      final token = ref.read(authProvider).token ?? '';
      await ref.read(userProvider.notifier).updatePreferences(token, volatilityAlerts: value);
    } catch (_) {
      if (mounted) {
        setState(() => _volatilityOverride = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preferences')),
        );
      }
    }
    if (mounted) setState(() { _volatilityOverride = null; _updatingVolatility = false; });
  }

  Future<void> _selectProvider(String name) async {
    if (name == ref.read(userProvider).profile?.aiProvider) return;
    setState(() => _updatingProvider = true);
    try {
      final token = ref.read(authProvider).token ?? '';
      await ref.read(userProvider.notifier).updatePreferences(token, aiProvider: name);
    } on UserException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update AI model')),
        );
      }
    }
    if (mounted) setState(() => _updatingProvider = false);
  }

  Future<void> _showProviderSheet() async {
    var providers = ref.read(userProvider).providers;
    if (providers.isEmpty) {
      final token = ref.read(authProvider).token ?? '';
      await ref.read(userProvider.notifier).loadProviders(token);
      providers = ref.read(userProvider).providers;
    }
    if (!mounted) return;
    if (providers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load available AI models')),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProviderSheet(
        providers: providers,
        selected: ref.read(userProvider).profile?.aiProvider,
      ),
    );
    if (selected != null) await _selectProvider(selected);
  }

  void _openPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }

  Future<void> _exportData() async {
    final token = ref.read(authProvider).token ?? '';
    try {
      await ref.read(userProvider.notifier).exportData(token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your data has been exported successfully.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export data. Please try again.')),
      );
    }
  }

  void _showChangePasswordSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete your account?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This permanently removes all your data and cannot be undone.',
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final token = ref.read(authProvider).token ?? '';
      await ref.read(userProvider.notifier).deleteAccount(token);
      if (mounted) await ref.read(authProvider.notifier).logout();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete account. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final userState = ref.watch(userProvider);
    final prefs = userState.profile?.preferences;

    final impactValue = _impactOverride ?? prefs?.impactAlerts ?? true;
    final volatilityValue = _volatilityOverride ?? prefs?.volatilityAlerts ?? true;
    final currentProvider = userState.currentProvider;
    final providerLabel = currentProvider?.displayName ??
        userState.profile?.aiProvider ??
        'Default';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'Profile',
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar + email
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF0F172A),
                    child: Text(
                      _initials(authState.email),
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authState.email ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            _SectionHeader(title: 'Notifications'),

            _SettingsTile(
              child: SwitchListTile(
                title: Text('Impact alerts',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('News with high market impact',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                value: impactValue,
                onChanged: _updatingImpact ? null : _toggleImpact,
                activeThumbColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            _SettingsTile(
              child: SwitchListTile(
                title: Text('Volatility alerts',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('Assets with significant price changes',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                value: volatilityValue,
                onChanged: _updatingVolatility ? null : _toggleVolatility,
                activeThumbColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),

            const SizedBox(height: 8),
            _SectionHeader(title: 'AI Analysis'),

            _SettingsTile(
              child: ListTile(
                title: Text('Analysis model',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(
                  currentProvider != null
                      ? '$providerLabel · ${currentProvider.model}'
                      : providerLabel,
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                trailing: _updatingProvider
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: _updatingProvider ? null : _showProviderSheet,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                'Every article is analyzed by all available models. Your feed and alerts '
                'show the view of the model you pick here; if it has no result for an '
                'article, another model\'s analysis is shown and marked.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 8),
            _SectionHeader(title: 'Security'),

            _SettingsTile(
              child: ListTile(
                title: Text('Change password',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: _showChangePasswordSheet,
              ),
            ),

            const SizedBox(height: 8),
            _SectionHeader(title: 'Privacy'),

            _SettingsTile(
              child: ListTile(
                title: Text('Privacy Policy',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: _openPrivacyPolicy,
              ),
            ),
            _SettingsTile(
              child: ListTile(
                title: Text('Export My Data',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('Download a copy of your data',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                trailing: const Icon(Icons.download_outlined, size: 18, color: Color(0xFF94A3B8)),
                onTap: _exportData,
              ),
            ),

            const SizedBox(height: 8),
            _SectionHeader(title: 'Account'),

            _SettingsTile(
              child: ListTile(
                title: Text(
                  'Delete account',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFEF4444),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: _confirmDeleteAccount,
              ),
            ),
            _SettingsTile(
              child: ListTile(
                title: Text('Sign out',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF94A3B8)),
                onTap: () => ref.read(authProvider.notifier).logout(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF94A3B8),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final Widget child;

  const _SettingsTile({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}

// ── AI Provider Sheet ────────────────────────────────────────────────────────

class _ProviderSheet extends StatelessWidget {
  final List<AIProviderInfo> providers;
  final String? selected;

  const _ProviderSheet({required this.providers, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Analysis model',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose which AI model\'s analysis you want to see.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            ...providers.map(
              (p) => ListTile(
                onTap: () => Navigator.pop(context, p.name),
                contentPadding: EdgeInsets.zero,
                trailing: Icon(
                  p.name == selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: p.name == selected
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFCBD5E1),
                ),
                title: Row(
                  children: [
                    Text(
                      p.displayName,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (p.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Default',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  p.model,
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Change Password Sheet ────────────────────────────────────────────────────

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  static final _passwordPattern =
      RegExp(r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$');

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = ref.read(authProvider).token ?? '';
      await ref.read(userProvider.notifier).changePassword(
            token,
            currentPassword: _currentCtrl.text,
            newPassword: _newCtrl.text,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully')),
      );
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to change password. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Change Password',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _currentCtrl,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureCurrent
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText:
                      'Min. 8 chars, uppercase, lowercase, number, special char',
                  helperMaxLines: 2,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!_passwordPattern.hasMatch(v)) {
                    return 'Must be 8+ chars with uppercase, lowercase, number, special char';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v != _newCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: const Color(0xFFEF4444)),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
