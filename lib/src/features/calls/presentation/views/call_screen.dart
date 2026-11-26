import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/initials.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../../escalation/presentation/views/case_outcome_form.dart';
import '../../../vitals_monitor/presentation/viewmodels/vitals_viewmodel.dart';
import '../../data/models/call_models.dart';
import '../viewmodels/call_controller.dart';

/// Shows the call screen over the whole app whenever a call is ringing,
/// in progress, or waiting for its outcome to be recorded.
class CallOverlay extends ConsumerWidget {
  const CallOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callControllerProvider);
    return Stack(
      children: [
        child,
        if (call != null)
          // Its own Navigator gives the call screen an Overlay (text fields,
          // tooltips) independent of the app's routes underneath.
          Positioned.fill(
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, __, ___) => const CallScreen(),
                transitionDuration: Duration.zero,
              ),
            ),
          ),
      ],
    );
  }
}

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Redraw every second for the call timer.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callControllerProvider);
    if (call == null) return const SizedBox.shrink();
    final controller = ref.read(callControllerProvider.notifier);
    final media = controller.media;
    final me = ref.watch(currentUserProvider);
    final isCareTeam = me != null && me.role != UserRole.patient;
    final recordOutcome = call.phase == CallPhase.ended &&
        isCareTeam &&
        call.escalationId != null &&
        call.connectedAt != null;

    final showRemoteVideo = call.remoteVideo && media != null && call.isLive;
    final showLocalVideo = call.localVideo && media != null && call.isLive;

    return Scaffold(
      backgroundColor: _CallColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: showRemoteVideo
                ? ColoredBox(
                    color: Colors.black,
                    child: media.remoteView(
                        fill: MediaQuery.orientationOf(context) ==
                            Orientation.portrait),
                  )
                : const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _CallColors.gradientTop,
                          _CallColors.background
                        ],
                      ),
                    ),
                  ),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(call: call),
                if (isCareTeam && call.isLive)
                  _LiveVitalsStrip(patientId: call.patientId),
                Expanded(
                  child: recordOutcome
                      ? _OutcomePanel(call: call, onDone: controller.dismiss)
                      : showRemoteVideo
                          ? Align(
                              alignment: Alignment.topLeft,
                              child: _VideoCaption(call: call))
                          : _PeerInfo(call: call),
                ),
                if (call.errorMessage != null && !recordOutcome)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(
                      call.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _CallColors.warning,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                if (!recordOutcome)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    child: _Controls(call: call, controller: controller),
                  ),
              ],
            ),
          ),
          if (showLocalVideo)
            Positioned(
              // Below the top bar, and below the vitals strip for the care team.
              top: MediaQuery.paddingOf(context).top + (isCareTeam ? 136 : 48),
              right: 16,
              width: 112,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child:
                    ColoredBox(color: Colors.black, child: media.localView()),
              ),
            ),
        ],
      ),
    );
  }
}

/// The call screen is dark in both themes, like a phone's call screen.
abstract final class _CallColors {
  static const background = Color(0xFF0B1220);
  static const gradientTop = Color(0xFF16324F);
  static const text = Colors.white;
  static const textMuted = Color(0xB3FFFFFF);
  static const control = Color(0x33FFFFFF);
  static const hangUp = Color(0xFFE5484D);
  static const answer = Color(0xFF2EB67D);
  static const warning = Color(0xFFFFC53D);
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.call});
  final CallState call;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(call.simulated ? Icons.science_outlined : Icons.lock_rounded,
              size: 14, color: _CallColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              call.simulated
                  ? 'Simulated call (demo mode)'
                  : 'End-to-end encrypted',
              style:
                  const TextStyle(fontSize: 12, color: _CallColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerInfo extends StatelessWidget {
  const _PeerInfo({required this.call});
  final CallState call;

  @override
  Widget build(BuildContext context) {
    final status = switch (call.phase) {
      CallPhase.outgoing => 'Calling…',
      CallPhase.incoming =>
        call.localVideo ? 'Incoming video call' : 'Incoming call',
      CallPhase.connecting => 'Connecting…',
      CallPhase.active => _format(call.duration),
      CallPhase.ended => [
          call.endReason?.label ?? 'Call ended',
          if (call.connectedAt != null) _format(call.duration),
        ].join(' · '),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Avatar(
            role: call.peer.role,
            // The care team sees the patient's initials; patients see the
            // caller's role (clinicians aren't identified by name here).
            initials: call.peer.role == UserRole.patient
                ? initials(call.peer.name)
                : null,
            pulsing: call.phase == CallPhase.incoming,
          ),
          const SizedBox(height: 20),
          Text(
            call.peer.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: _CallColors.text),
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(status,
                style: const TextStyle(
                    fontSize: 16, color: _CallColors.textMuted)),
          ),
          if (call.remoteVideo == false &&
              call.phase == CallPhase.active &&
              call.localVideo)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Their camera is off',
                  style: TextStyle(fontSize: 13, color: _CallColors.textMuted)),
            ),
        ],
      ),
    );
  }

  static String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

/// Name and call time over the other person's video.
class _VideoCaption extends StatelessWidget {
  const _VideoCaption({required this.call});
  final CallState call;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 6, color: Colors.black54)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(call.peer.name,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _CallColors.text,
                  shadows: shadow)),
          Text(
            call.phase == CallPhase.active
                ? _PeerInfo._format(call.duration)
                : 'Connecting…',
            style: const TextStyle(
                fontSize: 14, color: _CallColors.text, shadows: shadow),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatefulWidget {
  const _Avatar({required this.role, required this.pulsing, this.initials});
  final UserRole role;
  final String? initials;
  final bool pulsing;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Avatar old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!widget.pulsing && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (widget.role) {
      UserRole.nurse => Icons.support_agent_rounded,
      UserRole.doctor => Icons.medical_services_rounded,
      UserRole.patient => Icons.person_rounded,
    };
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _CallColors.control,
          boxShadow: [
            BoxShadow(
              color: _CallColors.answer
                  .fade(widget.pulsing ? 0.45 * _pulse.value : 0),
              blurRadius: 40,
              spreadRadius: 12 * _pulse.value,
            ),
          ],
        ),
        child: child,
      ),
      child: Center(
        child: widget.initials != null
            ? Text(
                widget.initials!,
                style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w600,
                    color: _CallColors.text),
              )
            : Icon(icon, size: 64, color: _CallColors.text),
      ),
    );
  }
}

/// The nurse or doctor keeps an eye on the patient's vitals while talking.
class _LiveVitalsStrip extends ConsumerWidget {
  const _LiveVitalsStrip({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(vitalsViewModelProvider(patientId)).latest;
    if (latest == null) return const SizedBox.shrink();
    final c = context.colors;
    final color = switch (latest.severity.name) {
      'critical' => c.critical,
      'warning' => c.warning,
      _ => _CallColors.answer,
    };
    Widget item(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _CallColors.text)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: _CallColors.textMuted)),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.fade(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Triage level at a glance: green, amber or red.
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
          ),
          item('Heart rate', '${latest.heartRate.round()}'),
          item('SpO₂ %', '${latest.spo2.round()}'),
          item('Blood pressure',
              '${latest.systolicBP.round()}/${latest.diastolicBP.round()}'),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.call, required this.controller});
  final CallState call;
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    if (call.phase == CallPhase.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            color: _CallColors.hangUp,
            onPressed: controller.decline,
          ),
          _RoundButton(
            icon: Icons.call_rounded,
            label: 'Answer',
            color: _CallColors.answer,
            onPressed: controller.accept,
          ),
        ],
      );
    }
    if (call.phase == CallPhase.ended) {
      return Center(
        child: TextButton(
          onPressed: controller.dismiss,
          child: const Text('Close',
              style: TextStyle(color: _CallColors.text, fontSize: 16)),
        ),
      );
    }
    final media = controller.media;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.end, // labels on one line
      spacing: 18,
      runSpacing: 16,
      children: [
        _RoundButton(
          icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: call.muted ? 'Unmute' : 'Mute',
          active: call.muted,
          onPressed: controller.toggleMute,
        ),
        _RoundButton(
          icon: call.localVideo
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          label: call.localVideo ? 'Video off' : 'Video',
          active: call.localVideo,
          onPressed: controller.toggleVideo,
        ),
        if (media?.hasSpeakerToggle ?? false)
          _RoundButton(
            icon: call.speakerOn
                ? Icons.volume_up_rounded
                : Icons.hearing_rounded,
            label: 'Speaker',
            active: call.speakerOn,
            onPressed: controller.toggleSpeaker,
          ),
        if (call.localVideo && (media?.canSwitchCamera ?? false))
          _RoundButton(
            icon: Icons.cameraswitch_rounded,
            label: 'Flip',
            onPressed: controller.switchCamera,
          ),
        _RoundButton(
          icon: Icons.call_end_rounded,
          label: 'End',
          color: _CallColors.hangUp,
          onPressed: controller.hangUp,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final background =
        color ?? (active ? _CallColors.text : _CallColors.control);
    final foreground = color != null
        ? _CallColors.text
        : (active ? _CallColors.background : _CallColors.text);
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: background,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: color != null ? 72 : 60,
                height: color != null ? 72 : 60,
                child: Icon(icon, color: foreground, size: 28),
              ),
            ),
          ),
          // The label is part of the button: tapping the word works too.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ExcludeSemantics(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: _CallColors.textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutcomePanel extends StatelessWidget {
  const _OutcomePanel({required this.call, required this.onDone});
  final CallState call;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final summary = [
      call.endReason?.label ?? 'Call ended',
      _PeerInfo._format(call.duration),
    ].join(' · ');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          extensions:
              Theme.of(context).extensions.values, // keep the app's palette
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(call.peer.name,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _CallColors.text)),
            Text(summary, style: const TextStyle(color: _CallColors.textMuted)),
            const SizedBox(height: 20),
            CaseOutcomeForm(
              escalationId: call.escalationId!,
              onDone: onDone,
              onLater: onDone,
              foreground: _CallColors.text,
            ),
          ],
        ),
      ),
    );
  }
}
