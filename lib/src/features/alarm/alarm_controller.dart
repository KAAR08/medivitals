import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/data/models/user_model.dart';
import '../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../calls/presentation/viewmodels/call_controller.dart';
import '../vitals_monitor/domain/triage.dart';
import '../vitals_monitor/presentation/viewmodels/vitals_viewmodel.dart';

part 'alarm_controller.g.dart';

const alarmSilence = Duration(minutes: 2);

/// What the care team's alarm is doing.
class AlarmState {
  const AlarmState(
      {this.critical = const {}, this.silencedUntil, this.sounding = false});

  /// Critical patients: id -> name.
  final Map<String, String> critical;
  final DateTime? silencedUntil;
  final bool sounding;

  bool get active => critical.isNotEmpty;
}

/// Whether the alarm should sound. It sounds while any patient is critical,
/// unless silenced; a patient who becomes critical after the silence was
/// pressed ([acknowledged] is who was critical then) ends it straight away.
/// Calls stay quiet: the clinician is already talking to a patient.
bool shouldSound({
  required Set<String> critical,
  required Set<String> acknowledged,
  required DateTime? silencedUntil,
  required DateTime now,
  required bool onCall,
}) {
  if (critical.isEmpty || onCall) return false;
  final silenced = silencedUntil != null && now.isBefore(silencedUntil);
  return !silenced || !acknowledged.containsAll(critical);
}

/// Plays the alarm sound (tests use a silent one).
abstract interface class AlarmPlayer {
  Future<void> start();
  Future<void> stop();
}

class AudioAlarmPlayer implements AlarmPlayer {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ));
    // The IEC 60601-1-8 high-priority pattern: 10 pulses, then a pause.
    await _player.play(AssetSource('sounds/alarm_high.wav'), volume: 1);
  }

  @override
  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    await _player.stop();
  }

  /// For the on-device audio test.
  Stream<PlayerState> get states => _player.onPlayerStateChanged;
  Future<Duration?> position() => _player.getCurrentPosition();
}

@Riverpod(keepAlive: true)
AlarmPlayer alarmPlayer(Ref ref) {
  final player = AudioAlarmPlayer();
  ref.onDispose(player.stop);
  return player;
}

/// The care team's audible alarm for critical patients. Patients get no
/// siren (alarming a recovering cardiac patient does harm): their app plays
/// a short notification sound when their own status turns critical.
@Riverpod(keepAlive: true)
class AlarmController extends _$AlarmController {
  Set<String> _acknowledged = {};
  Timer? _unsilence;
  late AlarmPlayer _player;
  bool _disposed = false;

  @override
  AlarmState build() {
    final user = ref.watch(currentUserProvider);
    _disposed = false;
    final player = _player = ref.watch(alarmPlayerProvider);
    ref.onDispose(() {
      _disposed = true;
      _unsilence?.cancel();
      player.stop();
    });
    if (user == null) return const AlarmState();

    if (user.role == UserRole.patient) {
      ref.listen(vitalsViewModelProvider(user.id).select((v) => v.severity),
          (prev, next) {
        if (next == Severity.critical && prev != Severity.critical) {
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
        }
      });
      return const AlarmState();
    }

    ref.listen(doctorMonitorViewModelProvider, (_, __) => _evaluate());
    Future.microtask(_evaluate); // once the initial state is in place
    ref.listen(callControllerProvider.select((c) => c?.isLive ?? false),
        (_, __) => _evaluate());
    return const AlarmState();
  }

  /// "Silence 2 min": quiet until then, or until another patient turns critical.
  void silence() {
    _acknowledged = state.critical.keys.toSet();
    final until = DateTime.now().add(alarmSilence);
    state = AlarmState(critical: state.critical, silencedUntil: until);
    _unsilence?.cancel();
    _unsilence = Timer(alarmSilence, _evaluate);
    _evaluate();
  }

  void _evaluate() {
    if (_disposed) return; // signed out before a deferred check ran
    final patients = ref.read(doctorMonitorViewModelProvider).patients.values;
    final critical = {
      for (final p in patients)
        if (p.severity == Severity.critical) p.patientId: p.patientName,
    };
    var silencedUntil = state.silencedUntil;
    final now = DateTime.now();
    if (critical.isEmpty ||
        (silencedUntil != null && !now.isBefore(silencedUntil))) {
      silencedUntil = null; // the episode is over, or the silence ran out
    }
    final sound = shouldSound(
      critical: critical.keys.toSet(),
      acknowledged: _acknowledged,
      silencedUntil: silencedUntil,
      now: now,
      onCall: ref.read(callControllerProvider)?.isLive ?? false,
    );
    if (sound && silencedUntil != null) {
      silencedUntil = null; // a new patient broke the silence
    }
    unawaited(sound ? _player.start() : _player.stop());
    state = AlarmState(
        critical: critical, silencedUntil: silencedUntil, sounding: sound);
  }
}
