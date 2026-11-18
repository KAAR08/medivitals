import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_router.dart';
import '../../core/navigation/app_routes.dart';
import 'alarm_controller.dart';

/// Puts the critical-patient alarm bar above every screen for the care team.
class AlarmFrame extends ConsumerWidget {
  const AlarmFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarm = ref.watch(alarmControllerProvider);
    if (!alarm.active) return child;
    return Column(
      children: [
        _AlarmStrip(alarm: alarm),
        Expanded(
          // The strip already covers the status bar.
          child: MediaQuery.removePadding(
              context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}

class _AlarmStrip extends ConsumerStatefulWidget {
  const _AlarmStrip({required this.alarm});
  final AlarmState alarm;

  @override
  ConsumerState<_AlarmStrip> createState() => _AlarmStripState();
}

class _AlarmStripState extends ConsumerState<_AlarmStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.alarm.silencedUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    final names = alarm.critical.values.toList()..sort();
    final title = names.length == 1
        ? '${names.single} is critical'
        : '${names.length} patients critical';
    final left = alarm.silencedUntil?.difference(DateTime.now());

    return Material(
      color: const Color(0xFFC8102E),
      child: SafeArea(
        bottom: false,
        child: Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.warning_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => ref.read(appRouterProvider).push(
                        AppRoutes.patientDetailPath(alarm.critical.keys.first)),
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                  ),
                ),
                if (left != null && !left.isNegative)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Silenced ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(alarmControllerProvider.notifier).silence(),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.volume_off_rounded, size: 18),
                    label: const Text('Silence 2 min'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
