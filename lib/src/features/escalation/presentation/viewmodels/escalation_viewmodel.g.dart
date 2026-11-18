// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'escalation_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$triageQueueHash() => r'32a213635fe9ded102ae3c4eb88e4208b96c2bbb';

/// The triage queue: ambulance cases and new requests first, then cases being
/// handled; most severe first, then oldest first; resolved ones last, newest
/// first.
///
/// Copied from [triageQueue].
@ProviderFor(triageQueue)
final triageQueueProvider = AutoDisposeProvider<List<Escalation>>.internal(
  triageQueue,
  name: r'triageQueueProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$triageQueueHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef TriageQueueRef = AutoDisposeProviderRef<List<Escalation>>;
String _$referralsHash() => r'84f704dde6748ba61ab1029d765afec7e431eb50';

/// Cases referred to a doctor, or with an ambulance on the way, not yet
/// resolved: what a doctor needs to look at.
///
/// Copied from [referrals].
@ProviderFor(referrals)
final referralsProvider = AutoDisposeProvider<List<Escalation>>.internal(
  referrals,
  name: r'referralsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$referralsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ReferralsRef = AutoDisposeProviderRef<List<Escalation>>;
String _$pendingEscalationCountHash() =>
    r'417f21932f693be9209fdf563cab927b888bb30c';

/// Number of requests still waiting for a nurse — for badges.
///
/// Copied from [pendingEscalationCount].
@ProviderFor(pendingEscalationCount)
final pendingEscalationCountProvider = AutoDisposeProvider<int>.internal(
  pendingEscalationCount,
  name: r'pendingEscalationCountProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$pendingEscalationCountHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef PendingEscalationCountRef = AutoDisposeProviderRef<int>;
String _$latestEscalationForHash() =>
    r'a2e817d95fcfd9ffc9d0082f53a239822fc90050';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// The patient's most recent request, or null if they have never asked.
///
/// Copied from [latestEscalationFor].
@ProviderFor(latestEscalationFor)
const latestEscalationForProvider = LatestEscalationForFamily();

/// The patient's most recent request, or null if they have never asked.
///
/// Copied from [latestEscalationFor].
class LatestEscalationForFamily extends Family<Escalation?> {
  /// The patient's most recent request, or null if they have never asked.
  ///
  /// Copied from [latestEscalationFor].
  const LatestEscalationForFamily();

  /// The patient's most recent request, or null if they have never asked.
  ///
  /// Copied from [latestEscalationFor].
  LatestEscalationForProvider call(
    String patientId,
  ) {
    return LatestEscalationForProvider(
      patientId,
    );
  }

  @override
  LatestEscalationForProvider getProviderOverride(
    covariant LatestEscalationForProvider provider,
  ) {
    return call(
      provider.patientId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'latestEscalationForProvider';
}

/// The patient's most recent request, or null if they have never asked.
///
/// Copied from [latestEscalationFor].
class LatestEscalationForProvider extends AutoDisposeProvider<Escalation?> {
  /// The patient's most recent request, or null if they have never asked.
  ///
  /// Copied from [latestEscalationFor].
  LatestEscalationForProvider(
    String patientId,
  ) : this._internal(
          (ref) => latestEscalationFor(
            ref as LatestEscalationForRef,
            patientId,
          ),
          from: latestEscalationForProvider,
          name: r'latestEscalationForProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$latestEscalationForHash,
          dependencies: LatestEscalationForFamily._dependencies,
          allTransitiveDependencies:
              LatestEscalationForFamily._allTransitiveDependencies,
          patientId: patientId,
        );

  LatestEscalationForProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.patientId,
  }) : super.internal();

  final String patientId;

  @override
  Override overrideWith(
    Escalation? Function(LatestEscalationForRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: LatestEscalationForProvider._internal(
        (ref) => create(ref as LatestEscalationForRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        patientId: patientId,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<Escalation?> createElement() {
    return _LatestEscalationForProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LatestEscalationForProvider && other.patientId == patientId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, patientId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin LatestEscalationForRef on AutoDisposeProviderRef<Escalation?> {
  /// The parameter `patientId` of this provider.
  String get patientId;
}

class _LatestEscalationForProviderElement
    extends AutoDisposeProviderElement<Escalation?>
    with LatestEscalationForRef {
  _LatestEscalationForProviderElement(super.provider);

  @override
  String get patientId => (origin as LatestEscalationForProvider).patientId;
}

String _$escalationsHash() => r'98ff3f3e1e9d8a8ce058a38a63747378669354af';

/// Every case the signed-in user may see, kept current by the server's
/// stream. Actions throw [ApiException] for the screen to show.
///
/// Copied from [Escalations].
@ProviderFor(Escalations)
final escalationsProvider =
    AutoDisposeAsyncNotifierProvider<Escalations, List<Escalation>>.internal(
  Escalations.new,
  name: r'escalationsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$escalationsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Escalations = AutoDisposeAsyncNotifier<List<Escalation>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
