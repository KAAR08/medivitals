import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/storage/secure_storage.dart';

part 'settings_viewmodel.g.dart';

/// App appearance: follows the system by default; the user can force
/// light or dark from Settings. The choice is persisted across launches.
@Riverpod(keepAlive: true)
class ThemeModeSetting extends _$ThemeModeSetting {
  static const _key = 'medivitallink.theme_mode';

  @override
  ThemeMode build() {
    Future.microtask(_load);
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final stored = await ref.read(secureStorageProvider).read(key: _key);
      final mode = ThemeMode.values.where((m) => m.name == stored).firstOrNull;
      if (mode != null) state = mode;
    } catch (_) {
      // Keep the default if storage is unavailable.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await ref.read(secureStorageProvider).write(key: _key, value: mode.name);
    } catch (_) {
      // Still applied for this session.
    }
  }
}
