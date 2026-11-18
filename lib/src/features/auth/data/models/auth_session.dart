import 'user_model.dart';

/// Everything that identifies a signed-in user: who they are and the token
/// pair used to call the API. Persisted by [SessionStorage].
class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final UserModel user;
  final String accessToken;
  final String refreshToken;

  /// Parses a login response:
  /// `{ "user": {...}, "access_token": "...", "refresh_token": "..." }`
  factory AuthSession.fromLoginJson(Map<String, dynamic> json) {
    return AuthSession(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
    );
  }

  AuthSession copyWith(
      {UserModel? user, String? accessToken, String? refreshToken}) {
    return AuthSession(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }
}
