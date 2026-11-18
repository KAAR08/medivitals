import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../data/services/mock_api_service.dart';
import '../models/auth_session.dart';
import '../models/user_model.dart';
import '../../presentation/viewmodels/auth_viewmodel.dart';

part 'auth_repository.g.dart';

/// Sign-in, token refresh and sign-out. Methods throw [ApiException].
abstract interface class AuthRepository {
  Future<AuthSession> performLogin({
    required String email,
    required String password,
    required UserRole role,
  });

  /// Invalidates the session on the server (revoking [refreshToken]'s whole
  /// token family). Best-effort: never throws.
  Future<void> performLogout({String? refreshToken});

  /// Returns the user the current access token belongs to.
  Future<UserModel> fetchCurrentUser();

  // Token refresh is not here: it is transport plumbing handled inside
  // ApiClient's 401 interceptor (see api_client.dart).
}

class RemoteAuthRepository implements AuthRepository {
  const RemoteAuthRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<AuthSession> performLogin({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password, 'role': role.name},
    );
    return AuthSession.fromLoginJson(response.data!);
  }

  @override
  Future<void> performLogout({String? refreshToken}) async {
    try {
      await _apiClient.post<void>(
        '/auth/logout',
        data: {if (refreshToken != null) 'refresh_token': refreshToken},
      );
    } on ApiException catch (_) {
      // Logout is best-effort; local cleanup happens regardless.
    }
  }

  @override
  Future<UserModel> fetchCurrentUser() async {
    final response = await _apiClient.get<Map<String, dynamic>>('/auth/me');
    return UserModel.fromJson(response.data!);
  }
}

class MockAuthRepository implements AuthRepository {
  const MockAuthRepository(this._api, this._accessToken);

  final MockApiService _api;
  final String? Function() _accessToken;

  @override
  Future<AuthSession> performLogin({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final json = await _api.login(email: email, password: password, role: role);
    return AuthSession.fromLoginJson(json);
  }

  @override
  Future<void> performLogout({String? refreshToken}) => _api.logout();

  @override
  Future<UserModel> fetchCurrentUser() async {
    final token = _accessToken();
    if (token == null) throw ApiException.server(401, 'Not signed in');
    return UserModel.fromJson(await _api.getCurrentUser(token));
  }
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  if (AppConfig.useMockBackend) {
    return MockAuthRepository(
      ref.watch(mockApiServiceProvider),
      () => ref.read(authViewModelProvider).session?.accessToken,
    );
  }
  return RemoteAuthRepository(ref.watch(apiClientProvider));
}
