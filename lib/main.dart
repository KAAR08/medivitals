import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/core/theme/theme.dart';
import 'src/core/navigation/app_router.dart';
import 'src/core/network/dev_ca_trust.dart';
import 'src/features/alarm/alarm_strip.dart';
import 'src/features/calls/presentation/views/call_screen.dart';
import 'src/features/settings/presentation/viewmodels/settings_viewmodel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installDevCaTrust();
  runApp(const ProviderScope(child: MedVitalsLinkApp()));
}

class MedVitalsLinkApp extends ConsumerWidget {
  const MedVitalsLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'MedVitals Link',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeSettingProvider),
      routerConfig: router,
      // Calls ring and run above every screen.
      builder: (context, child) => AlarmFrame(
        child: CallOverlay(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
