// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vitals_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vitalsViewModelHash() => r'7982c165410ac063f8793dcc34b1377542d83886';

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

abstract class _$VitalsViewModel
    extends BuildlessAutoDisposeNotifier<PatientVitalsState> {
  late final String patientId;

  PatientVitalsState build(
    String patientId,
  );
}

/// See also [VitalsViewModel].
@ProviderFor(VitalsViewModel)
const vitalsViewModelProvider = VitalsViewModelFamily();

/// See also [VitalsViewModel].
class VitalsViewModelFamily extends Family<PatientVitalsState> {
  /// See also [VitalsViewModel].
  const VitalsViewModelFamily();

  /// See also [VitalsViewModel].
  VitalsViewModelProvider call(
    String patientId,
  ) {
    return VitalsViewModelProvider(
      patientId,
    );
  }

  @override
  VitalsViewModelProvider getProviderOverride(
    covariant VitalsViewModelProvider provider,
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
  String? get name => r'vitalsViewModelProvider';
}

/// See also [VitalsViewModel].
class VitalsViewModelProvider extends AutoDisposeNotifierProviderImpl<
    VitalsViewModel, PatientVitalsState> {
  /// See also [VitalsViewModel].
  VitalsViewModelProvider(
    String patientId,
  ) : this._internal(
          () => VitalsViewModel()..patientId = patientId,
          from: vitalsViewModelProvider,
          name: r'vitalsViewModelProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$vitalsViewModelHash,
          dependencies: VitalsViewModelFamily._dependencies,
          allTransitiveDependencies:
              VitalsViewModelFamily._allTransitiveDependencies,
          patientId: patientId,
        );

  VitalsViewModelProvider._internal(
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
  PatientVitalsState runNotifierBuild(
    covariant VitalsViewModel notifier,
  ) {
    return notifier.build(
      patientId,
    );
  }

  @override
  Override overrideWith(VitalsViewModel Function() create) {
    return ProviderOverride(
      origin: this,
      override: VitalsViewModelProvider._internal(
        () => create()..patientId = patientId,
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
  AutoDisposeNotifierProviderElement<VitalsViewModel, PatientVitalsState>
      createElement() {
    return _VitalsViewModelProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is VitalsViewModelProvider && other.patientId == patientId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, patientId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin VitalsViewModelRef on AutoDisposeNotifierProviderRef<PatientVitalsState> {
  /// The parameter `patientId` of this provider.
  String get patientId;
}

class _VitalsViewModelProviderElement
    extends AutoDisposeNotifierProviderElement<VitalsViewModel,
        PatientVitalsState> with VitalsViewModelRef {
  _VitalsViewModelProviderElement(super.provider);

  @override
  String get patientId => (origin as VitalsViewModelProvider).patientId;
}

String _$doctorMonitorViewModelHash() =>
    r'fd0d74db7cda0ea9e29054cb91ea578b3a07a473';

/// See also [DoctorMonitorViewModel].
@ProviderFor(DoctorMonitorViewModel)
final doctorMonitorViewModelProvider = AutoDisposeNotifierProvider<
    DoctorMonitorViewModel, DoctorMonitorState>.internal(
  DoctorMonitorViewModel.new,
  name: r'doctorMonitorViewModelProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$doctorMonitorViewModelHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DoctorMonitorViewModel = AutoDisposeNotifier<DoctorMonitorState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
