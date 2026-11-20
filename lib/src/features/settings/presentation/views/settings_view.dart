import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../../../../core/layout/responsive.dart';

/// Profile, appearance, about, privacy notice and sign-out.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final themeMode = ref.watch(themeModeSettingProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Account'),
        elevation: 0,
      ),
      body: ReadableWidth(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(label: 'Account'),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: 'View and edit your profile',
            onTap: () => context.push(AppRoutes.profile),
          ),
          const SizedBox(height: 24),

          const _SectionHeader(label: 'App Settings'),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.dark_mode_outlined, size: 24, color: c.brand),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Appearance',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  ref.read(themeModeSettingProvider.notifier).set(s.first),
            ),
          ),
          const SizedBox(height: 24),

          const _SectionHeader(label: 'About'),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'About MedVitals Link',
            subtitle: 'Version $_appVersion · open-source licences',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'MedVitals Link',
              applicationVersion: _appVersion,
              applicationLegalese: 'Simulated data only. Not a medical device; '
                  'does not diagnose or prescribe.',
            ),
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & data',
            subtitle: 'How your health data is protected',
            onTap: () => _showPrivacyNotice(context),
          ),
          const SizedBox(height: 24),

          // The router redirects to login as soon as the auth state changes.
          _LogoutButton(
              onPressed: () =>
                  ref.read(authViewModelProvider.notifier).logout()),
        ],
      )),
    );
  }
}

const _appVersion = '1.0.0';

/// What the system does with health data.
void _showPrivacyNotice(BuildContext context) {
  const points = [
    (
      'Simulated data only',
      'Vitals come from a biometric simulator. No real patient data or medical devices are used.'
    ),
    (
      'Pseudonymized',
      'The telemetry system stores readings against a random ID, never your name '
          '(Kenya Data Protection Act, 2019). Names are kept separately by the identity service.'
    ),
    ('Encrypted in transit', 'All traffic uses TLS 1.3.'),
    ('Encrypted at rest', 'Readings are stored encrypted with AES-256.'),
    (
      'Need to know',
      'You see only your own record. Clinicians and triage nurses see their ward.'
    ),
    (
      'On this device',
      'Sign-in tokens are kept in the platform keystore and removed when you log out.'
    ),
  ];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final c = context.colors;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy & data',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary)),
              const SizedBox(height: 16),
              for (final (title, body) in points) ...[
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 14, height: 1.4, color: c.textSecondary)),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.colors.textTertiary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 24, color: c.brand),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.critical),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'Logout',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.critical,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
