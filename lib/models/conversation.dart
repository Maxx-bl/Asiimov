

class Conversation {
  final String id;
  final Map<String, dynamic> userData; // In groups, this will be empty or generic
  final Map<String, dynamic>? lastMessage;
  final int unreadCount;
  final DateTime lastActive;
  
  // Group specific
  final bool isGroup;
  final String? groupName;
  final List<String>? members;
  final String? creatorId;
  final String? groupIconUrl;

  Conversation({
    required this.id,
    required this.userData,
    this.lastMessage,
    required this.unreadCount,
    required this.lastActive,
    this.isGroup = false,
    this.groupName,
    this.members,
    this.creatorId,
    this.groupIconUrl,
  });

  String get otherUserId => id;
  String get otherUsername => isGroup ? (groupName ?? 'Group') : (userData['username'] ?? 'Unknown');
}
