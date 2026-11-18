import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../features/auth/presentation/views/login_view.dart';
import '../../features/vitals_monitor/presentation/views/patient_dashboard_view.dart';
import '../../features/vitals_monitor/presentation/views/doctor_monitor_view.dart';
import '../../features/medical_chat/presentation/views/chat_room_view.dart';
import '../../features/medical_chat/presentation/views/conversations_view.dart';
import '../../features/escalation/presentation/views/triage_queue_view.dart';
import '../../features/settings/presentation/views/settings_view.dart';
import '../../features/profile/presentation/views/profile_view.dart';
import '../../app/app_startup.dart';
import 'app_routes.dart';
import 'app_shell.dart';

part 'app_router.g.dart';

/// Routes and their auth guards. [_redirect] is the only place that decides
/// where the auth state sends the user; `refreshListenable` re-runs it on
/// login, logout and session expiry.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final authState = ValueNotifier<AuthState>(ref.read(authViewModelProvider));
  ref.listen(authViewModelProvider, (_, next) => authState.value = next);
  ref.onDispose(authState.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authState,
    redirect: (context, state) => _redirect(authState.value, state),

    /// Error builder: Show error page if route not found
    errorBuilder: (context, state) => _NotFoundView(uri: state.uri),

    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginView(),
      ),

      // The tabs. Branches load on first visit, so a patient never opens the
      // ward monitor. Branch order matches AppTab.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.patientDashboard,
                builder: (_, __) => const PatientDashboardView()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.doctorMonitor,
                builder: (_, __) => const DoctorMonitorView()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.triage,
                builder: (_, __) => const TriageQueueView()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.chat,
                builder: (_, __) => const ConversationsView()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.settings,
                builder: (_, __) => const SettingsView()),
          ]),
        ],
      ),

      // Opened on top of the tabs, full screen.

      /// One patient's vitals, opened from the monitor or the triage queue (care team)
      GoRoute(
        path: AppRoutes.patientDetail,
        builder: (context, state) =>
            PatientDashboardView(patientId: state.pathParameters['patientId']),
      ),

      /// Chat detail — e.g. /chat/conv-001 (deep-linkable)
      GoRoute(
        path: AppRoutes.chatDetail,
        builder: (context, state) => ChatRoomView(
            conversationId: state.pathParameters['conversationId']!),
      ),

      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileView(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

/// Decides where the user may be, given the current auth state.
///
/// When a signed-out user opens a protected link (cold-start deep link or an
/// expired session), the original location is kept in `?from=` and restored
/// after sign-in.
String? _redirect(AuthState auth, GoRouterState state) {
  final location = state.matchedLocation;
  final atSplash = location == AppRoutes.splash;
  final atLogin = location == AppRoutes.login;
  final pending = state.uri.queryParameters['from'];

  String gate(String target) {
    final from = (atSplash || atLogin) ? pending : state.uri.toString();
    return Uri(
            path: target, queryParameters: from == null ? null : {'from': from})
        .toString();
  }

  switch (auth) {
    // Still reading the stored session: wait on the splash screen.
    case AuthInitial():
      return atSplash ? null : gate(AppRoutes.splash);

    case AuthAuthenticated(:final user):
      final home = AppRoutes.homeFor(user.role);
      if (atSplash || atLogin) return pending ?? home;
      return AppRoutes.isAllowed(location, user.role) ? null : home;

    // Explicit logout: plain login screen, nothing to return to.
    case AuthUnauthenticated(byLogout: true):
      return atLogin ? null : AppRoutes.login;

    // Not signed in, login in progress or failed, or session expired.
    case AuthUnauthenticated() || AuthLoading() || AuthError():
      return atLogin ? null : gate(AppRoutes.login);
  }
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView({required this.uri});
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Page not found',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Path: $uri', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              // The redirect sends "/" to the right home for the user's role
              // (or to login when signed out).
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.splash),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
