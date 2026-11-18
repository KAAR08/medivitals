// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$callControllerHash() => r'2bcfc9a578b2297186ecf53175c6101520876a98';

/// The call this device is on or ringing with, if any.
///
/// outgoing/incoming -> connecting -> active -> ended. The caller sends the
/// WebRTC offer once answered. An ended care-team call stays on screen until
/// the clinician records the case outcome; other ended calls close themselves.
///
/// Copied from [CallController].
@ProviderFor(CallController)
final callControllerProvider =
    NotifierProvider<CallController, CallState?>.internal(
  CallController.new,
  name: r'callControllerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$callControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CallController = Notifier<CallState?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
