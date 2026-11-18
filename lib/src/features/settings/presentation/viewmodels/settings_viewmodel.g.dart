// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$themeModeSettingHash() => r'd96d774c7eb2315c1fa184dfa7536eef87d728bf';

/// App appearance: follows the system by default; the user can force
/// light or dark from Settings. The choice is persisted across launches.
///
/// Copied from [ThemeModeSetting].
@ProviderFor(ThemeModeSetting)
final themeModeSettingProvider =
    NotifierProvider<ThemeModeSetting, ThemeMode>.internal(
  ThemeModeSetting.new,
  name: r'themeModeSettingProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$themeModeSettingHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ThemeModeSetting = Notifier<ThemeMode>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
