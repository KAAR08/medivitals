import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/storage/secure_storage.dart';
import '../models/auth_session.dart';
import '../models/user_model.dart';

part 'session_storage.g.dart';

/// Persists the signed-in session (token pair + user profile) in the device
/// keychain/keystore, so the app can restore it on the next launch without a
/// network round-trip.
class SessionStorage {
  const SessionStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'medivitallink.access_token';
  static const _refreshTokenKey = 'medivitallink.refresh_token';
  static const _userKey = 'medivitallink.user';

  /// Returns the stored session, or null if there is none (or it is corrupt).
  Future<AuthSession?> load() async {
    try {
      final values = await Future.wait([
        _storage.read(key: _accessTokenKey),
        _storage.read(key: _refreshTokenKey),
        _storage.read(key: _userKey),
      ]);
      final [accessToken, refreshToken, userJson] = values;
      if (accessToken == null || refreshToken == null || userJson == null) {
        return null;
      }

      return AuthSession(
        user: UserModel.fromJson(jsonDecode(userJson) as Map<String, dynamic>),
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } catch (e, stackTrace) {
      developer.log('Failed to restore session',
          name: 'medivitallink.session_storage',
          error: e,
          stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> save(AuthSession session) async {
    try {
      await Future.wait([
        _storage.write(key: _accessTokenKey, value: session.accessToken),
        _storage.write(key: _refreshTokenKey, value: session.refreshToken),
        _storage.write(key: _userKey, value: jsonEncode(session.user.toJson())),
      ]);
    } catch (e, stackTrace) {
      developer.log('Failed to save session',
          name: 'medivitallink.session_storage',
          error: e,
          stackTrace: stackTrace);
    }
  }

  Future<void> clear() async {
    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
        _storage.delete(key: _userKey),
      ]);
    } catch (e, stackTrace) {
      developer.log('Failed to clear session',
          name: 'medivitallink.session_storage',
          error: e,
          stackTrace: stackTrace);
    }
  }
}

@Riverpod(keepAlive: true)
SessionStorage sessionStorage(Ref ref) =>
    SessionStorage(ref.watch(secureStorageProvider));
