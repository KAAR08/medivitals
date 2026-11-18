import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/network/api_client.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/session_storage.dart';

part 'auth_viewmodel.g.dart';

sealed class AuthState {
  const AuthState();

  /// The active session, or null when not signed in.
  AuthSession? get session => null;
}

/// App just started; the stored session hasn't been checked yet (splash).
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Signed out, with no error to report.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.byLogout = false});

  /// True when the user explicitly logged out (so the router doesn't offer
  /// to return them to where they were).
  final bool byLogout;
}

/// A login request is in flight.
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this._session);
  final AuthSession _session;

  @override
  AuthSession get session => _session;

  UserModel get user => _session.user;
}

/// Signed out because something went wrong (bad credentials, expired session).
class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
}

@Riverpod(keepAlive: true)
class AuthViewModel extends _$AuthViewModel {
  @override
  AuthState build() {
    Future.microtask(_restoreSession);
    return const AuthInitial();
  }

  /// Restores the session saved on a previous launch (no network needed).
  /// If its tokens have expired, the first API call's 401 triggers a refresh,
  /// and if that fails [expireSession] signs the user out.
  Future<void> _restoreSession() async {
    final session = await ref.read(sessionStorageProvider).load();
    if (state is! AuthInitial) return;
    state = session == null
        ? const AuthUnauthenticated()
        : AuthAuthenticated(session);
  }

  Future<void> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    state = const AuthLoading();
    try {
      final session = await ref.read(authRepositoryProvider).performLogin(
            email: email,
            password: password,
            role: role,
          );
      await ref.read(sessionStorageProvider).save(session);
      state = AuthAuthenticated(session);
    } on ApiException catch (e) {
      state = AuthError(e.message);
    } catch (_) {
      state =
          const AuthError('An unexpected error occurred. Please try again.');
    }
  }

  /// Signs out. Open screens dispose their streams as the router leaves them.
  Future<void> logout() async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    await ref
        .read(authRepositoryProvider)
        .performLogout(refreshToken: current.session.refreshToken);
    await ref.read(sessionStorageProvider).clear();
    state = const AuthUnauthenticated(byLogout: true);
  }

  /// Called by the API client after a successful token refresh.
  Future<void> updateTokens(
      {required String accessToken, required String refreshToken}) async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    final session = current.session
        .copyWith(accessToken: accessToken, refreshToken: refreshToken);
    state = AuthAuthenticated(session);
    await ref.read(sessionStorageProvider).save(session);
  }

  /// Called by the API client when the refresh token is rejected.
  Future<void> expireSession() async {
    if (state is! AuthAuthenticated) return;
    await ref.read(sessionStorageProvider).clear();
    state = const AuthError('Your session has expired. Please sign in again.');
  }

  /// Clear error state without affecting auth
  void clearError() {
    if (state is AuthError) state = const AuthUnauthenticated();
  }
}

/// The signed-in user, or null.
@riverpod
UserModel? currentUser(Ref ref) =>
    ref.watch(authViewModelProvider).session?.user;
