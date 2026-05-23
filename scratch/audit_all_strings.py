import os
import re

dart_files = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

# Patterns for user-facing strings (single and double quotes)
# We look for strings that do NOT already have .tr() after them
results = []

for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Skip comments, imports, debugPrint, print, keys, collection paths
        if stripped.startswith('//') or stripped.startswith('import ') or stripped.startswith('///'):
            continue
        if 'debugPrint' in line or 'print(' in line:
            continue
        if '.doc(' in line or '.collection(' in line or "FirebaseFirestore" in line:
            continue
        if "dotenv" in line or "SharedPreferences" in line:
            continue
        if "route" in line.lower() and "MaterialPageRoute" not in line:
            continue
        
        # Skip lines that already have .tr()
        if '.tr()' in line:
            continue
            
        # Find all single-quoted strings
        for match in re.finditer(r"'([^'\\]{2,})'", line):
            text = match.group(1)
            # Skip non-user-facing strings
            if any(skip in text for skip in [
                'http', 'assets/', 'package:', '.dart', '.json', '.png', '.jpg', '.svg',
                'firebase', 'users/', 'posts/', 'chats/', 'reports/', 'notifications/',
                'senderID', 'receiverID', 'messageType', 'timestamp', 'isRead',
                'username', 'email', 'uid', 'token', 'fcmToken', 'profilePicUrl',
                'lastMessage', 'members', 'groupName', 'groupIcon', 'creatorId',
                'isSuspended', 'suspensionReason', 'activeWarning', 'official',
                'isPrivate', 'followRequests', 'following', 'followers',
                'blockedUsers', 'content', 'authorId', 'postId', 'commentPath',
                'chatRoomId', 'messageId', 'status', 'pending', 'resolved',
                'action', 'deleted', 'dismissed', 'reason', 'type',
                'text', 'photo', 'audio', 'video', 'instant_photo', 'instant_video',
                'shared_post', 'reply', 'attachment', 'attachments',
                'post', 'comment', 'message', 'user', 'chat_message',
                'follow', 'follow_request', 'follow_accept',
                'reportsCount', 'resolvedAt', 'reportReasons',
                'upvotes', 'downvotes', 'shares', 'commentsCount',
                'unreadBy', 'lastMessageRead', 'lastMessageTime',
                'groupId', 'isGroup', 'senderUsername', 'groupName',
                'parentPath', 'docPath', '/', '.', '_', '-',
                'email-already-in-use', 'username-already-in-use',
                'user-not-found', 'wrong-password', 'weak-password',
                'notificationSettings', 'twoFactorEnabled', 'twoFactorSecret',
                'data', 'error', 'success', 'result', 'value', 'key', 'id',
                'image', 'file', 'url', 'path', 'name', 'title', 'body',
                'topic', 'channel', 'sound', 'priority', 'click_action',
                'default', 'high', 'max', 'importance',
                'senderId', 'receiverId', 'chatId',
                'pinnedMessages', 'pinnedBy', 'pinnedAt',
                'reportedContent', 'postAuthorId', 'commentAuthorId', 'messageOwnerId',
                'contentType', 'attachmentTypes', 'messageType',
                'SharedPreferences', 'prefs',
            ]):
                continue
            
            # Skip very short strings (likely keys/codes) or format strings
            if len(text) < 3:
                continue
            # Skip strings that look like variable/code references
            if text.startswith('$') or '${' in text:
                continue
            # Skip strings that are all lowercase with underscores (likely keys)
            if re.match(r'^[a-z_]+$', text):
                continue
            # Skip hex colors
            if re.match(r'^0x[0-9a-fA-F]+$', text) or re.match(r'^#[0-9a-fA-F]+$', text):
                continue
                
            results.append((file_path, i+1, text, line.strip()))
    
    # Also find double-quoted strings
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('//') or stripped.startswith('import ') or stripped.startswith('///'):
            continue
        if 'debugPrint' in line or 'print(' in line:
            continue
        if '.doc(' in line or '.collection(' in line:
            continue
        if '.tr()' in line:
            continue
            
        for match in re.finditer(r'"([^"\\]{2,})"', line):
            text = match.group(1)
            if any(skip in text for skip in [
                'http', 'assets/', 'package:', '.dart', '.json', '.png', '.jpg',
                'firebase', 'users/', 'posts/', 'chats/', 'reports/',
                'senderID', 'receiverID', 'messageType', 'timestamp',
                'username', 'email', 'uid', 'token', 'fcmToken',
                'lastMessage', 'members', 'groupName', 'isSuspended',
                'isPrivate', 'content', 'authorId', 'postId',
                'status', 'pending', 'resolved', 'action', 'type',
                'text', 'photo', 'audio', 'video', 'shared_post',
                'upvotes', 'downvotes', 'shares', 'commentsCount',
                'unreadBy', 'lastMessageRead', 'data', 'error',
                'email-already-in-use', 'username-already-in-use',
                'notificationSettings', 'twoFactorEnabled',
                'pinnedMessages', 'reportedContent',
                'SharedPreferences', 'click_action',
            ]):
                continue
            if len(text) < 3:
                continue
            if text.startswith('$') or '${' in text:
                continue
            if re.match(r'^[a-z_]+$', text):
                continue
            if re.match(r'^0x[0-9a-fA-F]+$', text):
                continue
                
            results.append((file_path, i+1, text, line.strip()))

# Deduplicate
seen = set()
unique = []
for r in results:
    key = (r[0], r[1], r[2])
    if key not in seen:
        seen.add(key)
        unique.append(r)

unique.sort()
for file_path, line, text, context in unique:
    print(f"{file_path}:{line}: [{text}]")
    print(f"    {context}")
    print()

print(f"\nTotal: {len(unique)} untranslated strings found")
