/// A conversation as seen by the current user (`GET /conversations`).
/// "Participant" is always the *other* person in the conversation.
class Conversation {
  const Conversation({
    required this.id,
    required this.participantId,
    required this.participantName,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  final String id;
  final String participantId;
  final String participantName;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final time = json['lastMessageTime'] as String?;
    return Conversation(
      id: json['id'] as String,
      participantId: json['participantId'] as String,
      participantName: json['participantName'] as String,
      lastMessage: json['lastMessage'] as String?,
      lastMessageTime: time != null ? DateTime.parse(time) : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'participantId': participantId,
        'participantName': participantName,
        if (lastMessage != null) 'lastMessage': lastMessage,
        if (lastMessageTime != null)
          'lastMessageTime': lastMessageTime!.toIso8601String(),
        'unreadCount': unreadCount,
      };
}
