import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/viewmodels/auth_viewmodel.dart';
import '../config/app_config.dart';

part 'api_client.g.dart';

sealed class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  factory ApiException.timeout([String? msg]) = RequestTimeoutException;
  factory ApiException.network([String? msg]) = NetworkException;
  factory ApiException.server(int statusCode, String msg) = ServerException;
  factory ApiException.unknown([String? msg]) = UnknownApiException;

  /// Converts any DioException into an [ApiException].
  factory ApiException.fromDio(DioException err) {
    final wrapped = err.error;
    if (wrapped is ApiException) return wrapped;
    return switch (err.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        ApiException.timeout(),
      DioExceptionType.connectionError => ApiException.network(),
      DioExceptionType.badResponse => ApiException.server(
          err.response?.statusCode ?? 0,
          _extractMessage(err.response?.data),
        ),
      _ => ApiException.unknown(),
    };
  }

  static String _extractMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['message'] as String? ??
          data['error'] as String? ??
          'Server error';
    }
    return 'Server error';
  }

  @override
  String toString() => '$runtimeType: $message';
}

class RequestTimeoutException extends ApiException {
  const RequestTimeoutException([String? msg])
      : super(msg ?? 'The server took too long to respond. Please try again.');
}

class NetworkException extends ApiException {
  const NetworkException([String? msg])
      : super(msg ?? 'Unable to reach the server. Check your connection.');
}

class ServerException extends ApiException {
  const ServerException(this.statusCode, super.message);
  final int statusCode;
}

class UnknownApiException extends ApiException {
  const UnknownApiException([String? msg])
      : super(msg ?? 'An unexpected error occurred. Please try again.');
}

class ApiClient {
  const ApiClient(this._dio);

  final Dio _dio;

  static const _connectTimeout = Duration(seconds: 15);
  static const _receiveTimeout = Duration(seconds: 30);

  static Dio buildDio({required String baseUrl}) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) =>
      _guard(() => _dio.get<T>(path,
          queryParameters: queryParameters, options: options));

  Future<Response<T>> post<T>(String path, {Object? data, Options? options}) =>
      _guard(() => _dio.post<T>(path, data: data, options: options));

  Future<Response<T>> put<T>(String path, {Object? data, Options? options}) =>
      _guard(() => _dio.put<T>(path, data: data, options: options));

  Future<Response<T>> patch<T>(String path, {Object? data, Options? options}) =>
      _guard(() => _dio.patch<T>(path, data: data, options: options));

  Future<Response<T>> delete<T>(String path, {Options? options}) =>
      _guard(() => _dio.delete<T>(path, options: options));

  /// Unwraps DioException so callers only ever see [ApiException].
  static Future<R> _guard<R>(Future<R> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    developer.log('[API →] ${options.method} ${options.uri}',
        name: 'medivitallink.api');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    developer.log(
        '[API ←] ${response.statusCode} ${response.requestOptions.uri}',
        name: 'medivitallink.api');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    developer.log(
      '[API ✗] ${err.response?.statusCode} ${err.requestOptions.uri}: ${err.message}',
      name: 'medivitallink.api',
      error: err,
    );
    handler.next(err);
  }
}

/// Adds the current access token to every request.
class _AuthHeaderInterceptor extends Interceptor {
  _AuthHeaderInterceptor(this._ref);
  final Ref _ref;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _ref.read(authViewModelProvider).session?.accessToken;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }
}

/// On 401, refreshes the token pair once and retries the original request.
///
/// Concurrent 401s share a single in-flight refresh. Requests to the auth
/// endpoints themselves are never retried, which prevents refresh loops.
class _TokenRefreshInterceptor extends Interceptor {
  _TokenRefreshInterceptor(this._ref, this._dio);
  final Ref _ref;
  final Dio _dio;

  static const _retriedKey = 'medivitallink.retried';
  Future<_Renewal>? _inFlightRefresh;

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final shouldRefresh = err.response?.statusCode == 401 &&
        options.extra[_retriedKey] != true &&
        !_isAuthEndpoint(options.path);
    if (!shouldRefresh) return handler.next(err);

    final renewal = await (_inFlightRefresh ??=
        _refresh().whenComplete(() => _inFlightRefresh = null));
    final newAccessToken = renewal.accessToken;
    if (renewal.failure case final failure?) {
      // Couldn't reach the server: fail this request with the real reason,
      // but stay signed in.
      return handler.next(err.copyWith(error: ApiException.fromDio(failure)));
    }
    if (newAccessToken == null) return handler.next(err);

    options.extra[_retriedKey] = true;
    options.headers['Authorization'] = 'Bearer $newAccessToken';
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Renews the token pair. Only a refresh token the server rejects (400/401)
  /// ends the session; a network error, timeout or 5xx doesn't, since signing
  /// a nurse out because of a brief outage would do more harm than good.
  ///
  /// Calls `/auth/refresh` on this Dio directly rather than through
  /// AuthRepository: the repository depends on this client, so going through
  /// it would be a provider cycle.
  Future<_Renewal> _refresh() async {
    final auth = _ref.read(authViewModelProvider.notifier);
    final refreshToken = _ref.read(authViewModelProvider).session?.refreshToken;
    if (refreshToken == null) return const _Renewal();

    try {
      developer.log('Access token rejected (401). Refreshing…',
          name: 'medivitallink.api');
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final accessToken = response.data!['access_token'] as String;
      final newRefreshToken = response.data!['refresh_token'] as String;
      await auth.updateTokens(
          accessToken: accessToken, refreshToken: newRefreshToken);
      return _Renewal(accessToken: accessToken);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        developer.log('Refresh token rejected. Ending session.',
            name: 'medivitallink.api');
        await auth.expireSession();
        return const _Renewal();
      }
      developer.log('Token refresh failed; keeping the session.',
          name: 'medivitallink.api', error: e);
      return _Renewal(failure: e);
    } catch (e, stackTrace) {
      developer.log(
          'Token refresh returned something unexpected. Ending session.',
          name: 'medivitallink.api',
          error: e,
          stackTrace: stackTrace);
      await auth.expireSession();
      return const _Renewal();
    }
  }

  static bool _isAuthEndpoint(String path) =>
      path.endsWith('/auth/login') || path.endsWith('/auth/refresh');
}

/// Outcome of a refresh: a new access token; a temporary [failure] (session
/// kept); or neither (session ended).
class _Renewal {
  const _Renewal({this.accessToken, this.failure});
  final String? accessToken;
  final DioException? failure;
}

/// Must be added last: converts whatever error survives the chain into an
/// [ApiException]. Uses `next` (not `reject`) so it never skips interceptors.
class _ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is ApiException) return handler.next(err);
    handler.next(err.copyWith(error: ApiException.fromDio(err)));
  }
}

/// Null in the app (Dio's default adapter is used). Override in tests to
/// fake HTTP responses while keeping the real interceptor chain.
@Riverpod(keepAlive: true)
HttpClientAdapter? httpClientAdapter(Ref ref) => null;

@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) {
  final dio = ApiClient.buildDio(baseUrl: AppConfig.apiBaseUrl);
  final adapter = ref.watch(httpClientAdapterProvider);
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.addAll([
    _LoggingInterceptor(),
    _AuthHeaderInterceptor(ref),
    _TokenRefreshInterceptor(ref, dio),
    _ErrorMappingInterceptor(),
  ]);
  return ApiClient(dio);
}
