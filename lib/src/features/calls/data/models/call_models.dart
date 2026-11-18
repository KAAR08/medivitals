import '../../../auth/data/models/user_model.dart';

/// Where a call is in its life.
enum CallPhase {
  /// We rang someone and are waiting for them to answer.
  outgoing,

  /// Someone is ringing us.
  incoming,

  /// Answered; the audio/video connection is being set up.
  connecting,

  /// Talking.
  active,

  /// Over (see [CallState.endReason]).
  ended,
}

/// Why a call ended, in words for the call screen.
enum CallEndReason {
  hungUp('Call ended'),
  declined('Call declined'),
  missed('No answer'),
  cancelled('Call cancelled'),
  busy('Line busy, try again shortly'),
  failed('Call failed');

  const CallEndReason(this.label);
  final String label;

  static CallEndReason fromServer(String? reason) => switch (reason) {
        'ended' => hungUp,
        'declined' => declined,
        'missed' => missed,
        'cancelled' => cancelled,
        _ => hungUp,
      };
}

/// The other person on the call.
class CallPeer {
  const CallPeer({this.id, required this.role, required this.name});

  final String? id;
  final UserRole role;
  final String name;

  CallPeer copyWith({String? id, String? name}) =>
      CallPeer(id: id ?? this.id, role: role, name: name ?? this.name);
}

/// Everything the call screen shows.
class CallState {
  const CallState({
    required this.callId,
    required this.phase,
    required this.peer,
    required this.patientId,
    this.escalationId,
    this.localVideo = false,
    this.remoteVideo = false,
    this.muted = false,
    this.speakerOn = false,
    this.connectedAt,
    this.endedAt,
    this.endReason,
    this.simulated = false,
    this.errorMessage,
  });

  final String callId;
  final CallPhase phase;
  final CallPeer peer;

  /// The patient this call is about (the caller, when a patient calls).
  final String patientId;

  /// The case the call belongs to; the care team records an outcome on it.
  final String? escalationId;

  final bool localVideo;
  final bool remoteVideo;
  final bool muted;
  final bool speakerOn;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final CallEndReason? endReason;

  /// Mock backend: no real connection, the other side is simulated.
  final bool simulated;
  final String? errorMessage;

  bool get isLive => phase != CallPhase.ended;

  Duration get duration {
    final start = connectedAt;
    if (start == null) return Duration.zero;
    return (endedAt ?? DateTime.now()).difference(start);
  }

  CallState copyWith({
    CallPhase? phase,
    CallPeer? peer,
    String? escalationId,
    bool? localVideo,
    bool? remoteVideo,
    bool? muted,
    bool? speakerOn,
    DateTime? connectedAt,
    DateTime? endedAt,
    CallEndReason? endReason,
    String? errorMessage,
  }) {
    return CallState(
      callId: callId,
      phase: phase ?? this.phase,
      peer: peer ?? this.peer,
      patientId: patientId,
      escalationId: escalationId ?? this.escalationId,
      localVideo: localVideo ?? this.localVideo,
      remoteVideo: remoteVideo ?? this.remoteVideo,
      muted: muted ?? this.muted,
      speakerOn: speakerOn ?? this.speakerOn,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      simulated: simulated,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// How a role is shown on the call screen. The telemetry side carries IDs
/// only, so the care team is shown by role, never by a name it didn't verify.
String roleLabel(UserRole role) => switch (role) {
      UserRole.nurse => 'Triage nurse',
      UserRole.doctor => 'Doctor',
      UserRole.patient => 'Patient',
    };
