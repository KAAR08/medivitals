// Route paths and who may open them.

import '../../features/auth/data/models/user_model.dart';

abstract final class AppRoutes {
  // Public routes (no auth required)
  static const String splash = '/';
  static const String login = '/login';

  // Protected routes (auth required)
  static const String patientDashboard = '/patient-dashboard';
  static const String doctorMonitor = '/doctor-monitor';
  static const String patientDetail = '/patients/:patientId';
  static const String triage = '/triage';
  static const String chat = '/chat';
  static const String chatDetail = '/chat/:conversationId';
  static const String settings = '/settings';
  static const String profile = '/profile';

  /// Helper to build chat route with ID
  static String chatDetailPath(String conversationId) =>
      '/chat/$conversationId';

  /// Helper to build a doctor's per-patient vitals route
  static String patientDetailPath(String patientId) => '/patients/$patientId';

  /// Landing screen for a signed-in user.
  static String homeFor(UserRole role) => switch (role) {
        UserRole.doctor => doctorMonitor,
        UserRole.nurse => triage,
        UserRole.patient => patientDashboard,
      };

  /// Whether [role] may open [location] (a matched location, e.g. `/patients/x`).
  static bool isAllowed(String location, UserRole role) {
    final careTeamOnly =
        location == triage || location.startsWith('/patients/');
    return switch (role) {
      UserRole.doctor => location != patientDashboard,
      // Nurses see the ward too (their Patients tab).
      UserRole.nurse => location != patientDashboard,
      UserRole.patient => !careTeamOnly && location != doctorMonitor,
    };
  }
}
