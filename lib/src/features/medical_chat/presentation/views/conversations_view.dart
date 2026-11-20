import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/conversation_model.dart';
import '../viewmodels/chat_viewmodel.dart';
import '../../../../core/layout/responsive.dart';

/// The signed-in user's conversations (`/chat`).
class ConversationsView extends ConsumerWidget {
  const ConversationsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Messages')),
      body: ReadableWidth(
          child: RefreshIndicator(
        color: c.brand,
        onRefresh: () => ref.refresh(conversationsProvider.future),
        child: conversations.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Message(
            icon: Icons.cloud_off_outlined,
            text:
                e is ApiException ? e.message : 'Could not load conversations.',
            action: TextButton(
              onPressed: () => ref.invalidate(conversationsProvider),
              child: const Text('Retry'),
            ),
          ),
          data: (list) => list.isEmpty
              ? const _Message(
                  icon: Icons.forum_outlined, text: 'No conversations yet.')
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(indent: 72),
                  itemBuilder: (_, i) =>
                      _ConversationTile(conversation: list[i]),
                ),
        ),
      )),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = conversation.participantName;
    final time = conversation.lastMessageTime;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: c.brandLight,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: c.brand),
        ),
      ),
      title: Text(name, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(
        conversation.lastMessage ?? 'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: time == null
          ? null
          : Text(_formatTime(time),
              style: Theme.of(context).textTheme.labelSmall),
      onTap: () => context.push(AppRoutes.chatDetailPath(conversation.id)),
    );
  }

  static String _formatTime(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? DateFormat.Hm().format(t) : DateFormat('d MMM').format(t);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Scrollable so pull-to-refresh still works on empty/error states.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 48, color: c.textTertiary),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        if (action != null) ...[
          const SizedBox(height: 8),
          Center(child: action)
        ],
      ],
    );
  }
}
