// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vitals_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vitalsRepositoryHash() => r'a29e0961a503920f24417a3da7cef4f17b99bac8';

/// See also [vitalsRepository].
@ProviderFor(vitalsRepository)
final vitalsRepositoryProvider = Provider<VitalsRepository>.internal(
  vitalsRepository,
  name: r'vitalsRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$vitalsRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef VitalsRepositoryRef = ProviderRef<VitalsRepository>;
String _$monitoredPatientsHash() => r'1709e6bdb6ddf4b309b06ea69f79915e611571bb';

/// The doctor's patient list (also used to name patients on detail screens).
///
/// Copied from [monitoredPatients].
@ProviderFor(monitoredPatients)
final monitoredPatientsProvider =
    AutoDisposeFutureProvider<List<PatientSummary>>.internal(
  monitoredPatients,
  name: r'monitoredPatientsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$monitoredPatientsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef MonitoredPatientsRef
    = AutoDisposeFutureProviderRef<List<PatientSummary>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
