import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../data/models/chat_message_model.dart';
import '../viewmodels/chat_viewmodel.dart';

class ChatRoomView extends ConsumerStatefulWidget {
  const ChatRoomView({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends ConsumerState<ChatRoomView> {
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() {
      final hasText = _inputCtrl.text.trim().isNotEmpty;
      if (hasText != _canSend) setState(() => _canSend = hasText);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (animate) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  void _send(String currentUserId) {
    final content = _inputCtrl.text.trim();
    if (content.isEmpty) return;
    _inputCtrl.clear();
    ref.read(chatViewModelProvider(widget.conversationId).notifier).sendMessage(
          content: content,
          senderId: currentUserId,
        );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final participantName = ref
            .watch(conversationProvider(widget.conversationId))
            ?.participantName ??
        'Conversation';
    final chatState = ref.watch(chatViewModelProvider(widget.conversationId));

    ref.listen(chatViewModelProvider(widget.conversationId), (prev, next) {
      if ((prev?.messages.length ?? 0) != next.messages.length) {
        _scrollToBottom(animate: prev?.isLoading == false);
      }
    });

    // Briefly null while signing out, before the router leaves this screen.
    if (currentUserId == null) return const Scaffold();

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _Initial(name: participantName, radius: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    participantName,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Secure medical channel',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: c.success),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () {},
            tooltip: 'Video call',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : chatState.messages.isEmpty
                    ? _EmptyConversation(
                        name: participantName,
                        errorMessage: chatState.errorMessage,
                      )
                    : _MessageList(
                        messages: chatState.messages,
                        currentUserId: currentUserId,
                        scrollCtrl: _scrollCtrl,
                        onRetry: (id) => ref
                            .read(chatViewModelProvider(widget.conversationId)
                                .notifier)
                            .retryMessage(id),
                      ),
          ),
          _InputBar(
            controller: _inputCtrl,
            canSend: _canSend,
            onSend: () => _send(currentUserId),
          ),
        ],
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name, required this.radius});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.brandLight,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
            fontSize: radius * 0.85,
            fontWeight: FontWeight.w600,
            color: c.brand),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.currentUserId,
    required this.scrollCtrl,
    required this.onRetry,
  });

  final List<ChatMessage> messages;
  final String currentUserId;
  final ScrollController scrollCtrl;
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[i];
        final isFromSelf = msg.senderId == currentUserId;
        final showDateDivider =
            i == 0 || !_isSameDay(messages[i - 1].timestamp, msg.timestamp);

        return Column(
          children: [
            if (showDateDivider) _DateDivider(date: msg.timestamp),
            _MessageBubble(
              message: msg,
              isFromSelf: isFromSelf,
              onRetry: msg.status == MessageStatus.failed
                  ? () => onRetry(msg.id)
                  : null,
            ),
          ],
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label =
        date.year == now.year && date.month == now.month && date.day == now.day
            ? 'Today'
            : '${date.day}/${date.month}/${date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.message, required this.isFromSelf, this.onRetry});

  final ChatMessage message;
  final bool isFromSelf;

  /// Non-null for failed messages: tapping the bubble re-sends it.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final timeLabel =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isFromSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: 4,
            left: isFromSelf ? 52 : 0,
            right: isFromSelf ? 0 : 52,
          ),
          child: GestureDetector(
            onTap: onRetry,
            child: Column(
              crossAxisAlignment: isFromSelf
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isFromSelf ? c.brand : c.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isFromSelf ? 16 : 4),
                      bottomRight: Radius.circular(isFromSelf ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          message.content,
                          style: TextStyle(
                            fontSize: 14,
                            color: isFromSelf ? c.textOnBrand : c.textPrimary,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color:
                                  isFromSelf ? Colors.white60 : c.textTertiary,
                            ),
                          ),
                          if (isFromSelf) ...[
                            const SizedBox(width: 4),
                            _StatusWidget(status: message.status),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (onRetry != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(
                      'Not sent. Tap to retry',
                      style: TextStyle(fontSize: 11, color: c.critical),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusWidget extends StatelessWidget {
  const _StatusWidget({required this.status});
  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MessageStatus.sending => const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Colors.white70),
        ),
      MessageStatus.sent =>
        const Icon(Icons.check_rounded, size: 13, color: Colors.white60),
      MessageStatus.delivered =>
        const Icon(Icons.done_all_rounded, size: 13, color: Colors.white60),
      MessageStatus.failed => const Icon(Icons.error_outline_rounded,
          size: 13, color: Colors.redAccent),
    };
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.name, this.errorMessage});
  final String name;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Initial(name: name, radius: 32),
            const SizedBox(height: 12),
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              errorMessage ?? 'No messages yet. Start the conversation.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar(
      {required this.controller, required this.canSend, required this.onSend});

  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 12, top: 10, bottom: 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: c.textTertiary),
                  filled: true,
                  fillColor: c.background,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: c.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: c.brand, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => canSend ? onSend() : null,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: canSend ? c.brand : c.border,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, size: 18),
                color: canSend ? c.textOnBrand : c.textTertiary,
                onPressed: canSend ? onSend : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
