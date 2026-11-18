import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../data/services/mock_api_service.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';

part 'chat_repository.g.dart';

/// Conversations and messages. Futures throw [ApiException].
abstract interface class ChatRepository {
  Future<List<Conversation>> fetchConversations();
  Future<List<ChatMessage>> fetchMessages(String conversationId);
  Future<ChatMessage> sendMessage(String conversationId, String content);

  /// New and updated messages pushed by the server.
  Stream<ChatMessage> watchMessages(String conversationId);
}

List<Conversation> _parseConversations(Map<String, dynamic> json) =>
    (json['conversations'] as List<dynamic>)
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .toList();

List<ChatMessage> _parseMessages(Map<String, dynamic> json) =>
    (json['messages'] as List<dynamic>)
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList();

/// Keeps `"type": "message"` events (other types, e.g. typing, are ignored).
Stream<ChatMessage> _parseMessageEvents(Stream<Map<String, dynamic>> raw) {
  return raw.transform(StreamTransformer.fromHandlers(handleData: (json, sink) {
    final type = json['type'] as String? ?? 'message';
    if (type != 'message') return;
    try {
      sink.add(ChatMessage.fromJson(json));
    } catch (e) {
      developer.log('Dropping malformed chat event: $json',
          name: 'medivitallink.chat', error: e);
    }
  }));
}

class RemoteChatRepository implements ChatRepository {
  const RemoteChatRepository(this._apiClient, this._accessToken);

  final ApiClient _apiClient;
  final String? Function() _accessToken;

  @override
  Future<List<Conversation>> fetchConversations() async {
    final response =
        await _apiClient.get<Map<String, dynamic>>('/conversations');
    return _parseConversations(response.data!);
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/conversations/$conversationId/messages',
      queryParameters: {'limit': 50, 'offset': 0},
    );
    return _parseMessages(response.data!);
  }

  @override
  Future<ChatMessage> sendMessage(String conversationId, String content) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/conversations/$conversationId/messages',
      data: {'content': content},
    );
    return ChatMessage.fromJson(response.data!);
  }

  @override
  Stream<ChatMessage> watchMessages(String conversationId) {
    return _parseMessageEvents(WebSocketClient.jsonStream(() {
      final token = _accessToken();
      final query =
          token == null ? '' : '?token=${Uri.encodeQueryComponent(token)}';
      return '${AppConfig.wsBaseUrl}/conversations/$conversationId/stream$query';
    }));
  }
}

class MockChatRepository implements ChatRepository {
  const MockChatRepository(this._api, this._currentUserId);

  final MockApiService _api;
  final String? Function() _currentUserId;

  String get _userId {
    final id = _currentUserId();
    if (id == null) throw ApiException.server(401, 'Not signed in');
    return id;
  }

  @override
  Future<List<Conversation>> fetchConversations() async =>
      _parseConversations(await _api.getConversations(_userId));

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId) async =>
      _parseMessages(await _api.getConversationMessages(conversationId));

  @override
  Future<ChatMessage> sendMessage(String conversationId, String content) async {
    final json = await _api.sendMessage(
      conversationId: conversationId,
      content: content,
      senderId: _userId,
    );
    return ChatMessage.fromJson(json);
  }

  @override
  Stream<ChatMessage> watchMessages(String conversationId) =>
      _parseMessageEvents(_api.streamConversationMessages(conversationId));
}

@Riverpod(keepAlive: true)
ChatRepository chatRepository(Ref ref) {
  if (AppConfig.useMockBackend) {
    return MockChatRepository(
      ref.watch(mockApiServiceProvider),
      () => ref.read(authViewModelProvider).session?.user.id,
    );
  }
  return RemoteChatRepository(
    ref.watch(apiClientProvider),
    () => ref.read(authViewModelProvider).session?.accessToken,
  );
}
