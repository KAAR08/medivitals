import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:web_socket_channel/web_socket_channel.dart';

enum WebSocketStatus { disconnected, connecting, connected, error }

class WebSocketClient {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  String Function()? _urlBuilder;
  int _reconnectAttempts = 0;
  DateTime? _firstFailureTime;
  bool _disposed = false;

  static const _maxReconnectDelaySeconds = 60;
  static const _maxRetryDurationMinutes =
      120; // 2 hours of retrying before giving up

  final _statusController = StreamController<WebSocketStatus>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  WebSocketStatus _status = WebSocketStatus.disconnected;

  Stream<WebSocketStatus> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  WebSocketStatus get status => _status;

  /// Opens a JSON message stream backed by its own [WebSocketClient].
  ///
  /// The socket opens when the stream is listened to and closes when the
  /// subscription is cancelled, so each screen owns its connection.
  /// [urlBuilder] is re-evaluated on every reconnect, which lets a refreshed
  /// access token be picked up automatically.
  static Stream<Map<String, dynamic>> jsonStream(String Function() urlBuilder) {
    WebSocketClient? client;
    StreamSubscription<Map<String, dynamic>>? forward;
    late final StreamController<Map<String, dynamic>> controller;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        client = WebSocketClient();
        forward = client!.messageStream.listen(controller.add);
        client!.connect(urlBuilder);
      },
      onCancel: () async {
        await forward?.cancel();
        await client?.dispose();
      },
    );
    return controller.stream;
  }

  /// Connects using [urlBuilder], which is called again on every reconnect.
  Future<void> connect(String Function() urlBuilder) async {
    await _teardown(emitDisconnected: false);
    _urlBuilder = urlBuilder;
    _reconnectAttempts = 0;
    _firstFailureTime = null;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    final urlBuilder = _urlBuilder;
    if (urlBuilder == null || _disposed) return;

    // Drop any half-dead channel from a previous attempt before reconnecting.
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;

    _emit(WebSocketStatus.connecting);
    try {
      final channel = WebSocketChannel.connect(Uri.parse(urlBuilder()));
      _channel = channel;
      await channel.ready;
      if (_disposed || _channel != channel) {
        await channel.sink.close();
        return;
      }
      _emit(WebSocketStatus.connected);
      _reconnectAttempts = 0;
      _firstFailureTime = null;
      _subscription = channel.stream.listen(
        _handleData,
        onError: (Object error, StackTrace stackTrace) {
          developer.log(
            'WebSocket stream error',
            name: 'medivitallink.ws',
            error: error,
            stackTrace: stackTrace,
          );
          _scheduleReconnect();
        },
        onDone: () {
          developer.log('WebSocket stream closed', name: 'medivitallink.ws');
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e, stackTrace) {
      developer.log(
        'Failed to connect to WebSocket',
        name: 'medivitallink.ws',
        error: e,
        stackTrace: stackTrace,
      );
      _emit(WebSocketStatus.error);
      _scheduleReconnect();
    }
  }

  void _handleData(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      if (!_messageController.isClosed) _messageController.add(decoded);
    } catch (e, stackTrace) {
      developer.log(
        'Failed to decode WebSocket message',
        name: 'medivitallink.ws',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;

    // Check if we've been retrying for too long
    if (_firstFailureTime != null) {
      final elapsed = DateTime.now().difference(_firstFailureTime!);
      if (elapsed.inMinutes >= _maxRetryDurationMinutes) {
        developer.log(
          'Max retry duration exceeded. Giving up on reconnection.',
          name: 'medivitallink.ws',
        );
        _emit(WebSocketStatus.error);
        return;
      }
    } else {
      _firstFailureTime = DateTime.now();
    }

    _emit(WebSocketStatus.error);
    _reconnectAttempts++;

    // Exponential backoff: 2s, 4s, 8s, 16s, 32s, 60s, 60s, ...
    final backoffSeconds = (1 << _reconnectAttempts.clamp(0, 6))
        .clamp(1, _maxReconnectDelaySeconds);
    final delay = Duration(seconds: backoffSeconds);

    developer.log(
      'Scheduling reconnect: attempt $_reconnectAttempts after ${delay.inSeconds}s',
      name: 'medivitallink.ws',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _doConnect);
  }

  /// Sends [payload]; false if the socket isn't connected (nothing is queued).
  bool send(Map<String, dynamic> payload) {
    if (_status == WebSocketStatus.connected) {
      try {
        _channel?.sink.add(jsonEncode(payload));
        return true;
      } catch (e, stackTrace) {
        developer.log(
          'Failed to send WebSocket message',
          name: 'medivitallink.ws',
          error: e,
          stackTrace: stackTrace,
        );
      }
    } else {
      developer.log(
        'Cannot send message: WebSocket not connected (status: $_status)',
        name: 'medivitallink.ws',
      );
    }
    return false;
  }

  Future<void> disconnect() => _teardown(emitDisconnected: true);

  Future<void> _teardown({required bool emitDisconnected}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _firstFailureTime = null;

    try {
      await _subscription?.cancel();
    } catch (e, stackTrace) {
      developer.log(
        'Error cancelling subscription',
        name: 'medivitallink.ws',
        error: e,
        stackTrace: stackTrace,
      );
    }
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (e, stackTrace) {
      developer.log(
        'Error closing channel',
        name: 'medivitallink.ws',
        error: e,
        stackTrace: stackTrace,
      );
    }
    _channel = null;

    if (emitDisconnected) _emit(WebSocketStatus.disconnected);
  }

  void _emit(WebSocketStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _teardown(emitDisconnected: false);

    // Properly close and drain broadcast controllers to prevent memory leaks
    try {
      await _statusController.close();
      await _messageController.close();
    } catch (e, stackTrace) {
      developer.log(
        'Error disposing StreamControllers',
        name: 'medivitallink.ws',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
