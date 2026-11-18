import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../data/models/chat_message_model.dart';
import '../../data/models/conversation_model.dart';
import '../../data/repositories/chat_repository.dart';

part 'chat_viewmodel.g.dart';

const _uuid = Uuid();

/// The signed-in user's conversations. Re-fetched whenever the user changes.
@riverpod
Future<List<Conversation>> conversations(Ref ref) {
  ref.watch(currentUserProvider);
  return ref.watch(chatRepositoryProvider).fetchConversations();
}

/// One conversation from [conversationsProvider], or null if not (yet) known.
@riverpod
Conversation? conversation(Ref ref, String conversationId) {
  final list = ref.watch(conversationsProvider).valueOrNull ?? const [];
  for (final c in list) {
    if (c.id == conversationId) return c;
  }
  return null;
}

@riverpod
class ChatViewModel extends _$ChatViewModel {
  int _generation = 0;

  @override
  ChatState build(String conversationId) {
    final gen = _generation;
    final sub = ref
        .watch(chatRepositoryProvider)
        .watchMessages(conversationId)
        .listen((m) {
      if (gen == _generation) _upsert(m);
    });
    ref.onDispose(() {
      _generation++;
      sub.cancel();
    });

    Future.microtask(() => _loadInitialMessages(gen));
    return const ChatState();
  }

  Future<void> _loadInitialMessages(int gen) async {
    try {
      final history =
          await ref.read(chatRepositoryProvider).fetchMessages(conversationId);
      if (gen != _generation) return;
      // Keep anything that arrived over the socket while history was loading.
      final known = {for (final m in history) m.id};
      final extra = state.messages.where((m) => !known.contains(m.id));
      state = ChatState(messages: [...history, ...extra], isLoading: false);
    } on ApiException catch (e) {
      if (gen == _generation) {
        state = state.copyWith(isLoading: false, errorMessage: e.message);
      }
    }
  }

  void _upsert(ChatMessage message) {
    final idx = state.messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      final updated = List<ChatMessage>.from(state.messages)..[idx] = message;
      state = state.copyWith(messages: updated);
    } else {
      state = state.copyWith(messages: [...state.messages, message]);
    }
  }

  Future<void> sendMessage(
      {required String content, required String senderId}) async {
    final tempId = _uuid.v4();
    final optimistic = ChatMessage(
      id: tempId,
      senderId: senderId,
      content: content,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );

    // Append immediately — user sees the message without waiting for the server
    state = state.copyWith(messages: [...state.messages, optimistic]);
    await _deliver(optimistic);
  }

  /// Re-sends a failed message in place (no duplicate bubble).
  Future<void> retryMessage(String messageId) async {
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0 || state.messages[idx].status != MessageStatus.failed) return;
    final retry = state.messages[idx].copyWith(status: MessageStatus.sending);
    _replace(messageId, retry);
    await _deliver(retry);
  }

  Future<void> _deliver(ChatMessage pending) async {
    try {
      final confirmed = await ref
          .read(chatRepositoryProvider)
          .sendMessage(conversationId, pending.content);
      // The socket may already have delivered the confirmed message.
      if (state.messages.any((m) => m.id == confirmed.id)) {
        state = state.copyWith(
          messages: state.messages.where((m) => m.id != pending.id).toList(),
        );
      } else {
        _replace(pending.id, confirmed);
      }
    } on ApiException catch (_) {
      _replace(pending.id, pending.copyWith(status: MessageStatus.failed));
    }
  }

  void _replace(String id, ChatMessage replacement) {
    state = state.copyWith(
      messages:
          state.messages.map((m) => m.id == id ? replacement : m).toList(),
    );
  }
}
