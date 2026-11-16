import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/manual_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/manual_provider.dart';
import '../../providers/topic_provider.dart';
import '../../providers/user_provider.dart';
import '../manual/manual_mode_screen.dart';
import '../privacy/privacy_policy_screen.dart';
import '../topics/topics_screen.dart';
import '../../widgets/info_tip.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _line = Color(0xFFE2E8F0);
const _accent = Color(0xFF3B82F6);
const _accentSoft = Color(0xFFEFF6FF);
const _neutralSoft = Color(0xFFF1F5F9);
const _warning = Color(0xFFB45309);
const _danger = Color(0xFFEF4444);

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool? _impactOverride;
  String? _impactLevelOverride;
  bool? _volatilityOverride;
  String? _feedLevelOverride;
  bool _updatingFeedLevel = false;
  bool _updatingImpact = false;
  bool _updatingImpactLevel = false;
  bool _updatingVolatility = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final token = ref.read(authProvider).token ?? '';
      if (ref.read(userProvider).providers.isEmpty) {
        ref.read(userProvider.notifier).loadProviders(token);
      }
      if (ref.read(manualProvider).settings == null) {
        ref.read(manualProvider.notifier).load(token);
      }
      if (ref.read(topicProvider).groups.isEmpty) {
        ref.read(topicProvider.notifier).load(token);
      }
    });
  }

  void _show(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setModes({bool? package, bool? manual}) async {
    try {
      await ref.read(manualProvider.notifier).updateSettings(
            ref.read(authProvider).token ?? '',
            packageEnabled: package,
            manualEnabled: manual,
          );
    } on ManualException catch (e) {
      _show(e.message);
    } catch (_) {
      _show('Failed to update preferences');
    }
  }

  void _openManual() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ManualModeScreen()));
  }

  void _openInterests() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TopicsScreen()));
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

  Future<void> _setImpactLevel(String value) async {
    setState(() { _impactLevelOverride = value; _updatingImpactLevel = true; });
    try {
      final token = ref.read(authProvider).token ?? '';
      await ref.read(userProvider.notifier).updatePreferences(token, impactAlertLevel: value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preferences')),
        );
      }
    }
    if (mounted) setState(() { _impactLevelOverride = null; _updatingImpactLevel = false; });
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

  Future<void> _setFeedLevel(String value) async {
    setState(() { _feedLevelOverride = value; _updatingFeedLevel = true; });
    try {
      final token = ref.read(authProvider).token ?? '';
      await ref.read(userProvider.notifier).updatePreferences(token, feedLevel: value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preferences')),
        );
      }
    }
    if (mounted) setState(() { _feedLevelOverride = null; _updatingFeedLevel = false; });
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
    final manual = ref.watch(manualProvider);
    final settings = manual.settings;
    final topics = ref.watch(topicProvider);
    final followed = topics.followedCount;
    final prefs = userState.profile?.preferences;

    final impactValue = _impactOverride ?? prefs?.impactAlerts ?? true;
    final impactLevel = _impactLevelOverride ?? prefs?.impactAlertLevel ?? 'high';
    final volatilityValue = _volatilityOverride ?? prefs?.volatilityAlerts ?? true;
    final feedLevel = _feedLevelOverride ?? prefs?.feedLevel ?? 'medium';
    final currentProvider = userState.currentProvider;
    final providerLabel = currentProvider?.displayName ??
        userState.profile?.aiProvider ??
        'Default';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'Profile',
          style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _ink),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _header(authState.email, settings),
          const SizedBox(height: 20),
          _newsAndAi(
            manual,
            currentProvider != null ? '$providerLabel · ${currentProvider.model}' : providerLabel,
          ),
          const _Label('FEED & ALERTS'),
          _Group(children: [
            _SettingRow(
              icon: Icons.interests_rounded,
              title: 'Interests',
              subtitle: topics.groups.isEmpty
                  ? 'Categories and your own topics'
                  : followed == 0
                      ? 'Follow categories or add your own topics'
                      : '$followed followed: categories and your own topics',
              trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: _faint),
              onTap: _openInterests,
            ),
            _SettingRow(
              icon: Icons.filter_list_rounded,
              title: 'Show in feed',
              info: 'Low news is mostly opinion, previews and ordinary moves. With Medium and above it stays out '
                  'of the feed; an asset\'s news page still lists it. A change applies to news arriving from now on.',
              below: _Choice(
                options: const {'medium': 'Medium and above', 'low': 'Everything'},
                value: feedLevel,
                onChanged: _updatingFeedLevel ? null : _setFeedLevel,
              ),
            ),
            _SettingRow(
              icon: Icons.notifications_none_rounded,
              title: 'Impact alerts',
              subtitle: 'News with high market impact',
              trailing: Switch(
                value: impactValue,
                onChanged: _updatingImpact ? null : _toggleImpact,
                activeThumbColor: _ink,
              ),
              below: impactValue
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text('Notify me for', style: GoogleFonts.inter(fontSize: 12, color: _muted)),
                            const InfoTip(
                              'Very high news is rare, so Very high only sends few notifications. High news '
                              'still appears in your alerts either way.',
                            ),
                          ],
                        ),
                        _Choice(
                          options: const {'high': 'High and above', 'very_high': 'Very high only'},
                          value: impactLevel,
                          onChanged: _updatingImpactLevel ? null : _setImpactLevel,
                        ),
                      ],
                    )
                  : null,
            ),
            _SettingRow(
              icon: Icons.show_chart_rounded,
              title: 'Volatility alerts',
              subtitle: 'Assets with significant price changes',
              trailing: Switch(
                value: volatilityValue,
                onChanged: _updatingVolatility ? null : _toggleVolatility,
                activeThumbColor: _ink,
              ),
            ),
          ]),
          const _Label('MORE'),
          _Group(children: [
            _SettingRow(
              icon: Icons.lock_outline_rounded,
              title: 'Change password',
              dense: true,
              trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: _faint),
              onTap: _showChangePasswordSheet,
            ),
            _SettingRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              dense: true,
              trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: _faint),
              onTap: _openPrivacyPolicy,
            ),
            _SettingRow(
              icon: Icons.download_rounded,
              title: 'Export my data',
              dense: true,
              onTap: _exportData,
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: Text('Sign out', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(foregroundColor: _muted),
              ),
              TextButton(
                onPressed: _confirmDeleteAccount,
                style: TextButton.styleFrom(foregroundColor: _danger),
                child: Text('Delete account', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(String? email, ManualSettings? settings) {
    final modes = switch (settings) {
      null => null,
      ManualSettings(packageEnabled: true, manualEnabled: true) => 'News package and my sources',
      ManualSettings(packageEnabled: true) => 'News package',
      ManualSettings(manualEnabled: true) => 'My sources only',
      _ => 'No news source is on',
    };
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: _ink,
          child: Text(
            _initials(email),
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: _ink),
              ),
              if (modes != null) ...[
                const SizedBox(height: 2),
                Text(
                  modes,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: settings!.packageEnabled || settings.manualEnabled ? _muted : _warning,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// One place for everything about where news comes from and which AI reads it.
  Widget _newsAndAi(ManualState manual, String packageModel) {
    final settings = manual.settings;
    final packageOn = settings?.packageEnabled ?? false;
    final manualOn = settings?.manualEnabled ?? false;
    final needsSetup = manualOn && (manual.sources.isEmpty || !manual.hasWorkingModel);

    final own = manual.sources.where((s) => !s.fromPackage).length;
    final feeds = [
      if (settings?.followPackageFeeds ?? false) 'the app\'s feeds',
      if (own > 0) own == 1 ? '1 feed' : '$own feeds',
    ];
    final models = manual.models;
    final String mine;
    if (feeds.isEmpty && models.isEmpty) {
      mine = 'add your own RSS feeds and API keys';
    } else {
      final modelText = switch (models.length) {
        0 => 'no model yet',
        1 => models.first.label,
        _ => '${models.length} models',
      };
      mine = '${feeds.isEmpty ? 'no feed yet' : feeds.join(' + ')} · $modelText';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6FF), Color(0xFFE0EFFE)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('News & AI', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 2),
                Text(
                  'Where your news comes from and which AI reads it. Both can be on.',
                  style: GoogleFonts.inter(fontSize: 12, color: _muted, height: 1.4),
                ),
              ],
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ModeTile(
                    icon: Icons.newspaper_rounded,
                    title: 'News package',
                    detail: 'Our sources, read by our AI models.',
                    value: packageOn,
                    onChanged: settings == null ? null : (v) => _setModes(package: v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeTile(
                    icon: Icons.vpn_key_outlined,
                    title: 'My sources',
                    detail: needsSetup ? 'Needs a feed and a working model.' : 'Your feeds, read with your API keys.',
                    warn: needsSetup,
                    value: manualOn,
                    onChanged: settings == null ? null : (v) => _setModes(manual: v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Group(children: [
            _SettingRow(
              icon: Icons.auto_awesome_rounded,
              accent: true,
              title: 'Feeds and AI models',
              subtitle: 'News package: $packageModel\nMy sources: $mine',
              trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: _faint),
              onTap: _openManual,
            ),
          ]),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _faint, letterSpacing: 0.8),
      ),
    );
  }
}

/// Rows in one white card, split by hairlines.
class _Group extends StatelessWidget {
  final List<Widget> children;

  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56, color: _line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? info;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;
  final bool dense;
  final bool accent;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.info,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
    this.dense = false,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final box = dense ? 28.0 : 32.0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, dense ? 9 : 12, 10, dense ? 9 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: box,
                  height: box,
                  margin: EdgeInsets.only(right: dense ? 16 : 12),
                  decoration: BoxDecoration(
                    color: accent ? _accentSoft : _neutralSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: dense ? 16 : 18, color: accent ? _accent : const Color(0xFF475569)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: dense ? 13.5 : 14,
                                fontWeight: dense ? FontWeight.w500 : FontWeight.w600,
                                color: _ink,
                              ),
                            ),
                          ),
                          if (info != null) InfoTip(info!),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, color: _muted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (below != null)
              Padding(
                padding: EdgeInsets.only(left: box + 12, top: 10, right: 4),
                child: below,
              ),
          ],
        ),
      ),
    );
  }
}

/// One of the two ways news reaches the feed, with its own switch.
class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool value;
  final bool warn;
  final ValueChanged<bool>? onChanged;

  const _ModeTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: value ? _accent : _line, width: value ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: value ? _accentSoft : _neutralSoft,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: value ? _accent : _faint),
                ),
                const Spacer(),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: _ink,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 2),
            Text(
              detail,
              style: GoogleFonts.inter(fontSize: 11.5, color: warn ? _warning : _muted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two options side by side; the chosen one is lifted.
class _Choice extends StatelessWidget {
  final Map<String, String> options;
  final String value;
  final ValueChanged<String>? onChanged;

  const _Choice({required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: _neutralSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          for (final option in options.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onChanged == null || option.key == value ? null : () => onChanged!(option.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: BoxDecoration(
                    color: option.key == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: option.key == value
                        ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: Text(
                    option.value,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: option.key == value ? FontWeight.w600 : FontWeight.w500,
                      color: option.key == value ? _ink : _muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
      final messenger = ScaffoldMessenger.of(context);
      final auth = ref.read(authProvider.notifier);
      Navigator.pop(context);
      // The backend ends every session when the password changes.
      await auth.logout();
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated. Please sign in again.')),
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
