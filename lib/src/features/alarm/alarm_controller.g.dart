// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alarm_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$alarmPlayerHash() => r'bc1c760acebcc762de6b24772dccb2c1a54c2ce1';

/// See also [alarmPlayer].
@ProviderFor(alarmPlayer)
final alarmPlayerProvider = Provider<AlarmPlayer>.internal(
  alarmPlayer,
  name: r'alarmPlayerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$alarmPlayerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AlarmPlayerRef = ProviderRef<AlarmPlayer>;
String _$alarmControllerHash() => r'832ad6743c8cc4a04cc52f69e39667dcebbb1d5a';

/// The care team's audible alarm for critical patients. Patients get no
/// siren (alarming a recovering cardiac patient does harm): their app plays
/// a short notification sound when their own status turns critical.
///
/// Copied from [AlarmController].
@ProviderFor(AlarmController)
final alarmControllerProvider =
    NotifierProvider<AlarmController, AlarmState>.internal(
  AlarmController.new,
  name: r'alarmControllerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$alarmControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$AlarmController = Notifier<AlarmState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
