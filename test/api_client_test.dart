import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medivitallink/src/core/network/api_client.dart';
import 'package:medivitallink/src/features/auth/data/models/user_model.dart';
import 'package:medivitallink/src/features/auth/data/repositories/auth_repository.dart';
import 'package:medivitallink/src/features/auth/presentation/viewmodels/auth_viewmodel.dart';

/// Answers requests from [handle] and records them as "METHOD path token".
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handle);
  final FutureOr<ResponseBody> Function(RequestOptions options) handle;
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final auth = options.headers['Authorization'] as String?;
    requests.add(
        '${options.method} ${options.path} ${auth?.replaceFirst('Bearer ', '') ?? '-'}');
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

const _user = {
  'id': 'patient-001',
  'email': 'john@example.com',
  'name': 'John Doe',
  'role': 'patient',
};

/// Container wired to the *remote* repositories with a fake network.
ProviderContainer makeContainer(FakeAdapter adapter) {
  final container = ProviderContainer(overrides: [
    httpClientAdapterProvider.overrideWithValue(adapter),
    authRepositoryProvider.overrideWith(
        (ref) => RemoteAuthRepository(ref.watch(apiClientProvider))),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> signIn(ProviderContainer container) async {
  container.read(authViewModelProvider);
  await container.read(authViewModelProvider.notifier).login(
        email: 'john@example.com',
        password: 'secret1',
        role: UserRole.patient,
      );
}

ResponseBody loginOk() => jsonBody(200, {
      'user': _user,
      'access_token': 'old',
      'refresh_token': 'refresh-1',
    });

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('login stores both tokens from access_token / refresh_token', () async {
    final container = makeContainer(FakeAdapter((o) => loginOk()));
    await signIn(container);

    final session = container.read(authViewModelProvider).session!;
    expect(session.accessToken, 'old');
    expect(session.refreshToken, 'refresh-1');
    expect(session.user.name, 'John Doe');
  });

  test('login failure surfaces the server message, not a generic one',
      () async {
    final container = makeContainer(FakeAdapter((o) => jsonBody(401, {
          'error': 'Invalid credentials',
          'message': 'Email or password is incorrect',
        })));
    await signIn(container);

    final state = container.read(authViewModelProvider);
    expect(state, isA<AuthError>());
    expect((state as AuthError).message, 'Email or password is incorrect');
  });

  test('network failure maps to a friendly NetworkException', () async {
    final container =
        makeContainer(FakeAdapter((o) => throw DioException.connectionError(
              requestOptions: o,
              reason: 'Failed host lookup',
            )));
    await signIn(container);

    final state = container.read(authViewModelProvider) as AuthError;
    expect(state.message, const NetworkException().message);
  });

  test(
      '401 refreshes once (even for concurrent calls) and retries with the new token',
      () async {
    final adapter = FakeAdapter((o) {
      final token =
          (o.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
      return switch (o.path) {
        '/auth/login' => loginOk(),
        '/auth/refresh' =>
          jsonBody(200, {'access_token': 'new', 'refresh_token': 'refresh-2'}),
        _ when token == 'new' => jsonBody(200, {'patients': []}),
        _ => jsonBody(401, {'message': 'Access token has expired'}),
      };
    });
    final container = makeContainer(adapter);
    await signIn(container);

    final api = container.read(apiClientProvider);
    final responses = await Future.wait([
      api.get<Map<String, dynamic>>('/patients'),
      api.get<Map<String, dynamic>>('/conversations'),
    ]);

    expect(responses.map((r) => r.statusCode), [200, 200]);
    expect(adapter.requests.where((r) => r.startsWith('POST /auth/refresh')),
        hasLength(1));
    final session = container.read(authViewModelProvider).session!;
    expect(session.accessToken, 'new');
    expect(session.refreshToken, 'refresh-2');
  });

  test('rejected refresh token ends the session with an explanation', () async {
    final container = makeContainer(FakeAdapter((o) => switch (o.path) {
          '/auth/login' => loginOk(),
          '/auth/refresh' =>
            jsonBody(401, {'error': 'Invalid or expired refresh token'}),
          _ => jsonBody(401, {'message': 'Access token has expired'}),
        }));
    await signIn(container);

    await expectLater(
      container.read(apiClientProvider).get<void>('/patients'),
      throwsA(isA<ServerException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
    final state = container.read(authViewModelProvider);
    expect(state, isA<AuthError>());
    expect((state as AuthError).message, contains('session has expired'));
  });

  test('a server error during refresh fails the request but keeps the session',
      () async {
    final container = makeContainer(FakeAdapter((o) => switch (o.path) {
          '/auth/login' => loginOk(),
          '/auth/refresh' => jsonBody(503, {'message': 'Service unavailable'}),
          _ => jsonBody(401, {'message': 'Access token has expired'}),
        }));
    await signIn(container);

    await expectLater(
      container.read(apiClientProvider).get<void>('/patients'),
      throwsA(isA<ServerException>()
          .having((e) => e.statusCode, 'statusCode', 503)),
    );
    final state = container.read(authViewModelProvider);
    expect(state, isA<AuthAuthenticated>(), reason: 'a 5xx must not sign out');
    expect(state.session!.refreshToken, 'refresh-1');
  });

  test('no network during refresh keeps the session too', () async {
    final container = makeContainer(FakeAdapter((o) => switch (o.path) {
          '/auth/login' => loginOk(),
          '/auth/refresh' => throw DioException.connectionError(
              requestOptions: o, reason: 'Network is unreachable'),
          _ => jsonBody(401, {'message': 'Access token has expired'}),
        }));
    await signIn(container);

    await expectLater(
      container.read(apiClientProvider).get<void>('/patients'),
      throwsA(isA<NetworkException>()),
    );
    expect(container.read(authViewModelProvider), isA<AuthAuthenticated>());
  });
}
