import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/models/user_model.dart';
import '../../features/auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../features/escalation/presentation/viewmodels/escalation_viewmodel.dart';
import '../config/app_config.dart';
import '../layout/responsive.dart';
import '../theme/app_colors.dart';

/// The shell's branches, in the order they're declared in the router.
enum AppTab { home, patients, queue, messages, account }

class _Destination {
  const _Destination(this.tab, this.label, this.icon, this.selectedIcon,
      {this.badge = 0});
  final AppTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badge;
}

/// Bottom navigation on phones, a side rail on wide windows; tabs per role:
///   patient  Home · Messages · Account
///   nurse    Queue · Patients · Messages · Account
///   doctor   Patients · Cases · Messages · Account
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider)?.role ?? UserRole.patient;
    final destinations = <_Destination>[
      ...switch (role) {
        UserRole.patient => const [
            _Destination(AppTab.home, 'Home', Icons.monitor_heart_outlined,
                Icons.monitor_heart),
          ],
        UserRole.nurse => [
            _Destination(
                AppTab.queue, 'Queue', Icons.inbox_outlined, Icons.inbox,
                badge: ref.watch(pendingEscalationCountProvider)),
            const _Destination(AppTab.patients, 'Patients',
                Icons.grid_view_outlined, Icons.grid_view_rounded),
          ],
        UserRole.doctor => [
            const _Destination(AppTab.patients, 'Patients',
                Icons.grid_view_outlined, Icons.grid_view_rounded),
            _Destination(AppTab.queue, 'Cases', Icons.assignment_outlined,
                Icons.assignment,
                badge: ref.watch(referralsProvider).length),
          ],
      },
      if (AppConfig.chatEnabled)
        const _Destination(AppTab.messages, 'Messages',
            Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
      const _Destination(AppTab.account, 'Account',
          Icons.person_outline_rounded, Icons.person_rounded),
    ];

    final selected = destinations
        .indexWhere((d) => d.tab.index == navigationShell.currentIndex);
    final selectedIndex = selected < 0 ? 0 : selected;
    void onSelected(int i) {
      final branch = destinations[i].tab.index;
      // Tapping the current tab again returns to its first screen.
      navigationShell.goBranch(branch,
          initialLocation: branch == navigationShell.currentIndex);
    }

    Widget icon(_Destination d, IconData data) => Badge(
        isLabelVisible: d.badge > 0,
        label: Text('${d.badge}'),
        child: Icon(data));

    if (context.isWide) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.9,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      label: Text(d.label),
                      icon: icon(d, d.icon),
                      selectedIcon: icon(d, d.selectedIcon),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: context.colors.divider),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colors.divider))),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                label: d.label,
                icon: icon(d, d.icon),
                selectedIcon: icon(d, d.selectedIcon),
              ),
          ],
        ),
      ),
    );
  }
}
