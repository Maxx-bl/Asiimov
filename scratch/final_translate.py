#!/usr/bin/env python3
"""
Final comprehensive i18n translation script for ASIIMOV Flutter app.
1) Cleans up garbage keys from en.json and fr.json
2) Adds all new translation keys
3) Replaces hardcoded strings in Dart files with .tr() calls
4) Ensures easy_localization import is present
"""
import json
import os
import re

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EN_PATH = os.path.join(BASE_DIR, "assets", "translations", "en.json")
FR_PATH = os.path.join(BASE_DIR, "assets", "translations", "fr.json")
LIB_DIR = os.path.join(BASE_DIR, "lib")

# ============================================================
# STEP 1: Define clean translation dictionaries
# ============================================================

# Keys that are garbage (contain backslashes, code, multi-line values)
GARBAGE_KEYS = [
    "cancel_textbutton_onpressed_is",
    "cancel_textbutton_onpressed_as",
    "leave_group_body_streambuilder",
    "settings_style_textstyle_fontw",
    "groups_style_textstyle_fontwei",
    "ffffff",
    "eg_inappropriate_content_hate",
]

# All NEW translation keys to add
NEW_KEYS_EN = {
    "add_members": "Add Members",
    "video_label": "VIDEO",
    "tap_to_download": "Tap to download",
    "delete": "Delete",
    "copy": "Copy",
    "pin": "Pin",
    "unpin": "Unpin",
    "report": "Report",
    "edit": "Edit",
    "continue_action": "Continue",
    "pinned_prefix": "pinned • ",
    "edited_prefix": "edited • ",
    "status_seen": " • seen",
    "status_sent": " • sent",
    "post_unavailable": "Post unavailable",
    "view_post": "View post",
    "new_group": "New Group",
    "group_name_helper": "3-30 chars: a-z, 0-9, . , - , _",
    "creating": "Creating...",
    "create_group": "Create Group",
    "retake": "Retake",
    "send": "Send",
    "visible_to_close_friends": "Visible to Close Friends",
    "total_label": "Total: ",
    "why_reporting": "Why are you reporting this?",
    "shared_a_post": "Shared a post",
    "groups": "Groups",
    "delete_current_photo": "Delete Current Photo",
    "report_type_post": "Post",
    "report_type_comment": "Comment",
    "report_type_message": "Message",
    "remove_official_badge": "Remove Official Badge",
    "grant_official_badge": "Grant Official Badge",
    "unsuspend": "Unsuspend",
    "suspend": "Suspend",
    "delete_reported": "Delete Reported",
    "reason_for_deletion": "Reason for deletion",
    "admin": "Admin",
    "suspended_chip": "Suspended",
    "remove_badge": "Remove badge",
    "grant_badge": "Grant badge",
    "voice_message": "Voice message",
    "shared_post": "Shared post",
    "tab_all": "All",
    "tab_users": "Users",
    "tab_posts": "Posts",
    "tab_chats": "Chats",
    "status_dismissed": "Dismissed",
    "status_resolved": "Resolved",
    "send_attachment": "Send Attachment",
    "private_messages": "Private Messages",
    "instant_photo": "📸 Instant Photo",
    "instant_video": "📸 Instant Video",
    "voice_message_notification": "🎵 Voice Message",
    "close_friends_feature": "Close Friends Feature",
    "mutual_followers": "Mutual Followers",
    "choose_audience": "Choose Audience",
    "everyone": "Everyone",
    "post_button": "Post",
    "remove": "Remove",
    "forgot_password_title": "Forgot Password?",
    "send_link": "Send Link",
    "invalid_name": "Invalid name",
    "save": "Save",
    "add": "Add",
    "leave": "Leave",
    "members": "Members",
    "choose_notifications": "Choose which notifications you want to receive",
    "restricted_access": "Restricted Access",
    "close_friends_restricted": "This post is reserved for the author's close friends.",
    "public_account": "Public Account",
    "label_public": "(Public)",
    "label_private": "(Private)",
    "block_action": "Block",
    "account_suspended": "Account Suspended",
    "private_account": "Private Account",
    "label_enabled": "(Enabled)",
    "label_disabled": "(Disabled)",
    "change_password": "Change Password",
    "send_password_reset_link": "Send Password Reset Link",
    "account_suspended_title": "ACCOUNT SUSPENDED",
    "suspension_reason_label": "SUSPENSION REASON:",
    "hex_code_error": "Hex code must be 6 characters",
    "dark_mode": "Dark Mode",
    "dominant_color": "DOMINANT COLOR",
    "vibrant_palette": "Vibrant Palette",
    "custom_hex_code": "Custom Hex Code",
    "apply_custom_color": "Apply Custom Color",
    "resend_code": "Resend Code",
    "cancel_sign_out": "Cancel & Sign Out",
    "content_moderation_notice": "Content Moderation Notice",
    "moderated_item": "MODERATED ITEM",
    "reason_for_removal": "REASON FOR REMOVAL",
    "understand_accept": "I Understand & Accept",
    "check_inbox": "Check your inbox",
    "resend_email": "Resend Email",
    "no_reason_provided": "No reason provided.",
    "notif_sent_post": "📣 sent a post",
    "notif_sent_voice": "🎵 sent a voice message",
    "notif_sent_attachment": "📎 sent an attachment",
    "notif_shared_post": "Shared a post",
    "suspended_account_label": "Suspended",
}

NEW_KEYS_FR = {
    "add_members": "Ajouter des membres",
    "video_label": "VIDÉO",
    "tap_to_download": "Appuyer pour télécharger",
    "delete": "Supprimer",
    "copy": "Copier",
    "pin": "Épingler",
    "unpin": "Désépingler",
    "report": "Signaler",
    "edit": "Modifier",
    "continue_action": "Continuer",
    "pinned_prefix": "épinglé • ",
    "edited_prefix": "modifié • ",
    "status_seen": " • vu",
    "status_sent": " • envoyé",
    "post_unavailable": "Post indisponible",
    "view_post": "Voir le post",
    "new_group": "Nouveau groupe",
    "group_name_helper": "3-30 car. : a-z, 0-9, . , - , _",
    "creating": "Création...",
    "create_group": "Créer le groupe",
    "retake": "Reprendre",
    "send": "Envoyer",
    "visible_to_close_friends": "Visible par les Amis Proches",
    "total_label": "Total : ",
    "why_reporting": "Pourquoi signalez-vous ceci ?",
    "shared_a_post": "A partagé un post",
    "groups": "Groupes",
    "delete_current_photo": "Supprimer la photo actuelle",
    "report_type_post": "Post",
    "report_type_comment": "Commentaire",
    "report_type_message": "Message",
    "remove_official_badge": "Retirer le badge officiel",
    "grant_official_badge": "Accorder le badge officiel",
    "unsuspend": "Rétablir",
    "suspend": "Suspendre",
    "delete_reported": "Supprimer le contenu signalé",
    "reason_for_deletion": "Raison de la suppression",
    "admin": "Admin",
    "suspended_chip": "Suspendu",
    "remove_badge": "Retirer le badge",
    "grant_badge": "Accorder le badge",
    "voice_message": "Message vocal",
    "shared_post": "Post partagé",
    "tab_all": "Tout",
    "tab_users": "Utilisateurs",
    "tab_posts": "Posts",
    "tab_chats": "Discussions",
    "status_dismissed": "Rejeté",
    "status_resolved": "Résolu",
    "send_attachment": "Envoyer la pièce jointe",
    "private_messages": "Messages privés",
    "instant_photo": "📸 Photo instantanée",
    "instant_video": "📸 Vidéo instantanée",
    "voice_message_notification": "🎵 Message vocal",
    "close_friends_feature": "Fonctionnalité Amis Proches",
    "mutual_followers": "Abonnés mutuels",
    "choose_audience": "Choisir l'audience",
    "everyone": "Tout le monde",
    "post_button": "Publier",
    "remove": "Retirer",
    "forgot_password_title": "Mot de passe oublié ?",
    "send_link": "Envoyer le lien",
    "invalid_name": "Nom invalide",
    "save": "Enregistrer",
    "add": "Ajouter",
    "leave": "Quitter",
    "members": "Membres",
    "choose_notifications": "Choisissez les notifications que vous souhaitez recevoir",
    "restricted_access": "Accès restreint",
    "close_friends_restricted": "Ce post est réservé aux amis proches de l'auteur.",
    "public_account": "Compte public",
    "label_public": "(Public)",
    "label_private": "(Privé)",
    "block_action": "Bloquer",
    "account_suspended": "Compte suspendu",
    "private_account": "Compte privé",
    "label_enabled": "(Activée)",
    "label_disabled": "(Désactivée)",
    "change_password": "Changer le mot de passe",
    "send_password_reset_link": "Envoyer le lien de réinitialisation",
    "account_suspended_title": "COMPTE SUSPENDU",
    "suspension_reason_label": "RAISON DE LA SUSPENSION :",
    "hex_code_error": "Le code hex doit contenir 6 caractères",
    "dark_mode": "Mode sombre",
    "dominant_color": "COULEUR DOMINANTE",
    "vibrant_palette": "Palette vibrante",
    "custom_hex_code": "Code hex personnalisé",
    "apply_custom_color": "Appliquer la couleur",
    "resend_code": "Renvoyer le code",
    "cancel_sign_out": "Annuler et se déconnecter",
    "content_moderation_notice": "Avis de modération de contenu",
    "moderated_item": "ÉLÉMENT MODÉRÉ",
    "reason_for_removal": "RAISON DU RETRAIT",
    "understand_accept": "Je comprends et j'accepte",
    "check_inbox": "Vérifiez votre boîte de réception",
    "resend_email": "Renvoyer l'e-mail",
    "no_reason_provided": "Aucune raison fournie.",
    "notif_sent_post": "📣 a envoyé un post",
    "notif_sent_voice": "🎵 a envoyé un message vocal",
    "notif_sent_attachment": "📎 a envoyé une pièce jointe",
    "notif_shared_post": "A partagé un post",
    "suspended_account_label": "Suspendu",
}


def load_and_clean_json(path):
    """Load JSON and remove garbage keys."""
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # Remove garbage keys
    for key in GARBAGE_KEYS:
        if key in data:
            print(f"  Removing garbage key: {key}")
            del data[key]
    
    # Also remove any key whose value contains backslashes or is absurdly long (code dumps)
    keys_to_remove = []
    for key, value in data.items():
        if isinstance(value, str) and (len(value) > 200 or '\\n' in value and 'TextButton' in value):
            keys_to_remove.append(key)
    for key in keys_to_remove:
        if key not in GARBAGE_KEYS:
            print(f"  Removing long/code key: {key}")
            del data[key]
    
    return data


def write_json(path, data):
    """Write JSON with consistent formatting."""
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


# ============================================================
# STEP 2: Clean and rebuild JSON files
# ============================================================

print("=" * 60)
print("STEP 1: Cleaning and rebuilding translation JSON files")
print("=" * 60)

print("\nProcessing en.json...")
en_data = load_and_clean_json(EN_PATH)
for key, value in NEW_KEYS_EN.items():
    if key not in en_data:
        en_data[key] = value
        print(f"  Added: {key} = {value}")
    else:
        print(f"  Already exists: {key}")
write_json(EN_PATH, en_data)
print(f"  Written {len(en_data)} keys to en.json")

print("\nProcessing fr.json...")
fr_data = load_and_clean_json(FR_PATH)
for key, value in NEW_KEYS_FR.items():
    if key not in fr_data:
        fr_data[key] = value
        print(f"  Added: {key} = {value}")
    else:
        print(f"  Already exists: {key}")
write_json(FR_PATH, fr_data)
print(f"  Written {len(fr_data)} keys to fr.json")


# ============================================================
# STEP 3: Replace hardcoded strings in Dart files
# ============================================================

EASY_LOC_IMPORT = "import 'package:easy_localization/easy_localization.dart';"

def ensure_import(content, filepath):
    """Ensure easy_localization import is present."""
    if EASY_LOC_IMPORT in content:
        return content
    
    # Find a good place to insert (after last import)
    lines = content.split('\n')
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.strip().startswith('import '):
            last_import_idx = i
    
    if last_import_idx >= 0:
        lines.insert(last_import_idx + 1, EASY_LOC_IMPORT)
        print(f"  Added easy_localization import to {os.path.basename(filepath)}")
        return '\n'.join(lines)
    
    return content


def replace_in_file(filepath, replacements):
    """Apply a list of (old, new) string replacements to a file."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    
    for old, new in replacements:
        replaced = False
        if old in content:
            content = content.replace(old, new)
            print(f"  Replaced: {repr(old[:60])}...")
            replaced = True
        
        # Try different quotes
        if not replaced and old.startswith('"') and old.endswith('"'):
            single_quoted = "'" + old[1:-1] + "'"
            if single_quoted in content:
                content = content.replace(single_quoted, new)
                print(f"  Replaced (single-quoted): {repr(single_quoted[:60])}...")
                replaced = True
        elif not replaced and old.startswith("'") and old.endswith("'"):
            double_quoted = '"' + old[1:-1] + '"'
            if double_quoted in content:
                content = content.replace(double_quoted, new)
                print(f"  Replaced (double-quoted): {repr(double_quoted[:60])}...")
                replaced = True
                
        if not replaced:
            print(f"  WARNING: Not found in {os.path.basename(filepath)}: {repr(old[:60])}...")
    
    # Ensure import
    content = ensure_import(content, filepath)
    
    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"  ✅ Updated: {os.path.basename(filepath)}")
    else:
        print(f"  ⏭️  No changes: {os.path.basename(filepath)}")


print("\n" + "=" * 60)
print("STEP 2: Replacing hardcoded strings in Dart files")
print("=" * 60)

# --- add_members_sheet.dart ---
print("\n--- add_members_sheet.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "add_members_sheet.dart"), [
    ('\"Add Members\"', "'add_members'.tr()"),
    ("'search_following'.tr().tr()", "'search_following'.tr()"),
])

# --- chat_attachment_viewer.dart ---
print("\n--- chat_attachment_viewer.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "chat_attachment_viewer.dart"), [
    ("Text('VIDEO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))",
     "Text('video_label'.tr(), style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))"),
    ('Text("Tap to download", style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold))',
     "Text('tap_to_download'.tr(), style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold))"),
])

# --- chat_bubble.dart ---
print("\n--- chat_bubble.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "chat_bubble.dart"), [
    # Delete buttons (3 occurrences - line 186, 218, 364)
    ("Text('Delete', style: TextStyle(color: Colors.red))",
     "Text('delete'.tr(), style: TextStyle(color: Colors.red))"),
    ("Text('Delete',\n                         style: TextStyle(color: Colors.red))",
     "Text('delete'.tr(),\n                         style: TextStyle(color: Colors.red))"),
    # Copy - line 311
    ('\"Copy\"', "'copy'.tr()"),
    # Pin/Unpin - line 330
    ('widget.isPinned ? \"Unpin\" : \"Pin\"',
     "widget.isPinned ? 'unpin'.tr() : 'pin'.tr()"),
    # Report - line 343
    ('\"Report\",', "'report'.tr(),"),
    # Edit - line 354
    ('\"Edit\",', "'edit'.tr(),"),
    # Continue - line 626
    ("Text('Continue', style: TextStyle(color: Theme.of(context).primaryColor))",
     "Text('continue_action'.tr(), style: TextStyle(color: Theme.of(context).primaryColor))"),
    # pinned prefix - line 668
    ("'pinned • ',", "'pinned_prefix'.tr(),"),
    # edited prefix - line 677
    ("(widget.isEdited ? 'edited • ' : '')",
     "(widget.isEdited ? 'edited_prefix'.tr() : '')"),
    # seen/sent status - line 682
    ("(widget.isSeen ? ' • seen' : ' • sent')",
     "(widget.isSeen ? 'status_seen'.tr() : 'status_sent'.tr())"),
    # Post unavailable - line 908
    ('Text("Post unavailable", style: TextStyle(fontStyle: FontStyle.italic))',
     "Text('post_unavailable'.tr(), style: TextStyle(fontStyle: FontStyle.italic))"),
    # View post - line 956
    ('Text("View post", style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold))',
     "Text('view_post'.tr(), style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold))"),
])

# --- comment_tile.dart ---
print("\n--- comment_tile.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "comment_tile.dart"), [
    # Delete button in dialog - line 185
    ("Text('Delete', style: TextStyle(color: Colors.red))",
     "Text('delete'.tr(), style: TextStyle(color: Colors.red))"),
    # Delete in popup menu - line 244  
    ("Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13))",
     "Text('delete'.tr(), style: TextStyle(color: Colors.redAccent, fontSize: 13))"),
    # Report in popup menu - line 254
    ("Text('Report', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 13))",
     "Text('report'.tr(), style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 13))"),
    # Continue in leaving app dialog - line 279
    ("Text('Continue', style: TextStyle(color: Theme.of(context).primaryColor))",
     "Text('continue_action'.tr(), style: TextStyle(color: Theme.of(context).primaryColor))"),
])

# --- group_creation_sheet.dart ---
print("\n--- group_creation_sheet.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "group_creation_sheet.dart"), [
    ('\"New Group\"', "'new_group'.tr()"),
    ('helperText: "3-30 chars: a-z, 0-9, . , - , _"',
     "helperText: 'group_name_helper'.tr()"),
    ("'group_name'.tr().tr()", "'group_name'.tr()"),
    ("'search_following'.tr().tr()", "'search_following'.tr()"),
    ('Text(_isLoading ? \"Creating...\" : \"Create Group (${_selectedUserIds.length})\")',
     "Text(_isLoading ? 'creating'.tr() : '${'create_group'.tr()} (${_selectedUserIds.length})')"),
])

# --- instant_camera_screen.dart ---
print("\n--- instant_camera_screen.dart ---")
filepath = os.path.join(LIB_DIR, "components", "instant_camera_screen.dart")
replace_in_file(filepath, [
    ('label: Text("Retake", style: TextStyle(fontSize: 16))',
     "label: Text('retake'.tr(), style: TextStyle(fontSize: 16))"),
    ('label: Text("Send", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))',
     "label: Text('send'.tr(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))"),
])

# --- logout_confirmation_dialog.dart ---
print("\n--- logout_confirmation_dialog.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "logout_confirmation_dialog.dart"), [
    ("'Log out',", "'log_out'.tr(),"),
])

# --- post_card.dart ---
print("\n--- post_card.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "post_card.dart"), [
    # Visible to Close Friends - line 136
    ("title: 'Visible to Close Friends',",
     "title: 'visible_to_close_friends'.tr(),"),
    # Delete in dialog - line 179
    ("Text('Delete', style: TextStyle(color: Colors.red))",
     "Text('delete'.tr(), style: TextStyle(color: Colors.red))"),
    # Delete in popup menu - line 235
    ("Text('Delete', style: TextStyle(color: Colors.redAccent))",
     "Text('delete'.tr(), style: TextStyle(color: Colors.redAccent))"),
    # Report in popup menu - line 245
    ("Text('Report', style: TextStyle(color: Theme.of(context).primaryColor))",
     "Text('report'.tr(), style: TextStyle(color: Theme.of(context).primaryColor))"),
    # Continue buttons (two occurrences) - line 334, 395
    ("Text('Continue', style: TextStyle(color: Theme.of(context).primaryColor))",
     "Text('continue_action'.tr(), style: TextStyle(color: Theme.of(context).primaryColor))"),
])

# --- profile_post_card.dart ---
print("\n--- profile_post_card.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "profile_post_card.dart"), [
    ("Text('Delete',\n                       style: TextStyle(color: Colors.red))",
     "Text('delete'.tr(),\n                       style: TextStyle(color: Colors.red))"),
    ("'Total: ',", "'total_label'.tr(),"),
])

# --- report_reason_dialog.dart ---
print("\n--- report_reason_dialog.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "report_reason_dialog.dart"), [
    ("'Why are you reporting this?',", "'why_reporting'.tr(),"),
    ("'describe_the_issue'.tr().tr()", "'describe_the_issue'.tr()"),
    ("'Report',", "'report'.tr(),"),
])

# --- share_sheet.dart ---
print("\n--- share_sheet.dart ---")
replace_in_file(os.path.join(LIB_DIR, "components", "share_sheet.dart"), [
    ('\"Shared a post\"', "'shared_a_post'.tr()"),
    ("'search_user'.tr().tr()", "'search_user'.tr()"),
    ('Text(\"Groups\", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))',
     "Text('groups'.tr(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))"),
])

# --- image_service.dart ---
print("\n--- image_service.dart ---")
replace_in_file(os.path.join(LIB_DIR, "services", "image", "image_service.dart"), [
    ("Text('Delete Current Photo', style: TextStyle(color: Colors.redAccent))",
     "Text('delete_current_photo'.tr(), style: TextStyle(color: Colors.redAccent))"),
])


# ============================================================
# STEP 4: Process Pages
# ============================================================

print("\n" + "=" * 60)
print("STEP 3: Processing page files")
print("=" * 60)

# --- admin_dashboard_page.dart ---
print("\n--- admin_dashboard_page.dart ---")
admin_path = os.path.join(LIB_DIR, "pages", "admin_dashboard_page.dart")
if os.path.exists(admin_path):
    with open(admin_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content

    # Exact replacements for admin_dashboard_page.dart
    replacements = [
        # Report types
        ("'Post'", "'report_type_post'.tr()"),
        ("'Comment'", "'report_type_comment'.tr()"),
        ("'Message'", "'report_type_message'.tr()"),
        # Badge actions
        ("'Remove Official Badge'", "'remove_official_badge'.tr()"),
        ("'Grant Official Badge'", "'grant_official_badge'.tr()"),
        # Unsuspend / Suspend
        ("'Unsuspend'", "'unsuspend'.tr()"),
        # Delete Reported
        ("'Delete Reported'", "'delete_reported'.tr()"),
        # Reason for deletion
        ("'Reason for deletion'", "'reason_for_deletion'.tr()"),
        # Admin label
        ("'Admin'", "'admin'.tr()"),
        # Suspended chip
        ("'Suspended'", "'suspended_chip'.tr()"),
        # Remove/Grant badge (short versions)
        ("'Remove badge'", "'remove_badge'.tr()"),
        ("'Grant badge'", "'grant_badge'.tr()"),
        # Reinstate / Suspend (short versions)  
        ("'Reinstate'", "'reinstate'.tr()"),
        ("'Suspend'", "'suspend'.tr()"),
        # Voice message
        ("'Voice message'", "'voice_message'.tr()"),
        # Shared post
        ("'Shared post'", "'shared_post'.tr()"),
        # Tab labels
        ("'All'", "'tab_all'.tr()"),
        ("'Users'", "'tab_users'.tr()"),
        ("'Posts'", "'tab_posts'.tr()"),
        ("'Chats'", "'tab_chats'.tr()"),
        # Dismissed/Resolved
        ("'Dismissed'", "'status_dismissed'.tr()"),
        ("'Resolved'", "'status_resolved'.tr()"),
        # Delete button
        ("'Delete'", "'delete'.tr()"),
    ]
    
    # admin_dashboard is complex - do targeted replacements with context
    # Read file by lines for more precise replacements
    lines = content.split('\n')
    new_lines = []
    for i, line in enumerate(lines):
        original_line = line
        
        # Line-specific replacements to avoid collisions
        # Report type labels (around line 151-155)
        if "'Post'" in line and ('reportType' in line or 'case' in line or '==' in line):
            # Don't replace case labels or field comparisons
            pass
        elif "'Post'" in line and ('Text(' in line or 'label' in line.lower()):
            line = line.replace("'Post'", "'report_type_post'.tr()")
            
        if "'Comment'" in line and ('Text(' in line or 'label' in line.lower()):
            line = line.replace("'Comment'", "'report_type_comment'.tr()")
        
        if "'Message'" in line and ('Text(' in line or 'label' in line.lower()) and 'reportType' not in line:
            line = line.replace("'Message'", "'report_type_message'.tr()")
        
        if "'Remove Official Badge'" in line:
            line = line.replace("'Remove Official Badge'", "'remove_official_badge'.tr()")
        if "'Grant Official Badge'" in line:
            line = line.replace("'Grant Official Badge'", "'grant_official_badge'.tr()")
        
        if "'Unsuspend'" in line:
            line = line.replace("'Unsuspend'", "'unsuspend'.tr()")
            
        if "'Delete Reported'" in line:
            line = line.replace("'Delete Reported'", "'delete_reported'.tr()")
            
        if "'Reason for deletion'" in line:
            line = line.replace("'Reason for deletion'", "'reason_for_deletion'.tr()")
            
        if "'Suspended'" in line and 'isSuspended' not in line and 'Chip' in content[max(0,content.find(line)-200):content.find(line)+200]:
            line = line.replace("'Suspended'", "'suspended_chip'.tr()")
            
        if "'Remove badge'" in line:
            line = line.replace("'Remove badge'", "'remove_badge'.tr()")
        if "'Grant badge'" in line:
            line = line.replace("'Grant badge'", "'grant_badge'.tr()")
        
        if "'Reinstate'" in line and 'Text(' in line:
            line = line.replace("'Reinstate'", "'reinstate'.tr()")
        if "'Suspend'" in line and 'Text(' in line and 'suspend_author' not in line and 'isSuspend' not in line and 'unsuspend' not in line.lower():
            line = line.replace("'Suspend'", "'suspend'.tr()")
            
        if "'Voice message'" in line:
            line = line.replace("'Voice message'", "'voice_message'.tr()")
            
        if "'Shared post'" in line:
            line = line.replace("'Shared post'", "'shared_post'.tr()")
            
        if "'Admin'" in line and 'Text(' in line and 'isAdmin' not in line:
            line = line.replace("'Admin'", "'admin'.tr()")
            
        if "'Dismissed'" in line:
            line = line.replace("'Dismissed'", "'status_dismissed'.tr()")
        if "'Resolved'" in line:
            line = line.replace("'Resolved'", "'status_resolved'.tr()")
            
        if "'Delete'" in line and 'Text(' in line:
            line = line.replace("'Delete'", "'delete'.tr()")
            
        # Tab labels - be very careful
        if "'All'" in line and ('Tab(' in line or 'text:' in line.lower() or 'label' in line.lower()):
            line = line.replace("'All'", "'tab_all'.tr()")
        if "'Users'" in line and ('Tab(' in line or 'text:' in line.lower() or 'label' in line.lower()):
            line = line.replace("'Users'", "'tab_users'.tr()")
        if "'Posts'" in line and ('Tab(' in line or 'text:' in line.lower() or 'label' in line.lower()):
            line = line.replace("'Posts'", "'tab_posts'.tr()")
        if "'Chats'" in line and ('Tab(' in line or 'text:' in line.lower() or 'label' in line.lower()):
            line = line.replace("'Chats'", "'tab_chats'.tr()")
        
        if line != original_line:
            print(f"  Line {i+1}: replaced")
        new_lines.append(line)
    
    content = '\n'.join(new_lines)
    content = ensure_import(content, admin_path)
    
    if content != original:
        with open(admin_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"  ✅ Updated: admin_dashboard_page.dart")

# --- chat_page.dart ---
print("\n--- chat_page.dart ---")
chat_page_path = os.path.join(LIB_DIR, "pages", "chat_page.dart")
if os.path.exists(chat_page_path):
    replace_in_file(chat_page_path, [
        ('"Send Attachment"', "'send_attachment'.tr()"),
        ('"You"', "'you'.tr()"),
        ('"Private Messages"', "'private_messages'.tr()"),
        ('"📸 Instant Photo"', "'instant_photo'.tr()"),
        ('"📸 Instant Video"', "'instant_video'.tr()"),
        ('"🎵 Voice Message"', "'voice_message_notification'.tr()"),
        ('"🎤 Voice Message"', "'voice_message_notification'.tr()"),
    ])

# --- close_friends_page.dart ---
print("\n--- close_friends_page.dart ---")
cf_path = os.path.join(LIB_DIR, "pages", "close_friends_page.dart")
if os.path.exists(cf_path):
    replace_in_file(cf_path, [
        ('"Close Friends Feature"', "'close_friends_feature'.tr()"),
        ('"Mutual Followers"', "'mutual_followers'.tr()"),
    ])

# --- create_post_page.dart ---
print("\n--- create_post_page.dart ---")
cp_path = os.path.join(LIB_DIR, "pages", "create_post_page.dart")
if os.path.exists(cp_path):
    replace_in_file(cp_path, [
        ('"Choose Audience"', "'choose_audience'.tr()"),
        ('"Everyone"', "'everyone'.tr()"),
        ('"Followers"', "'followers'.tr()"),
        ('"Post"', "'post_button'.tr()"),
    ])

# --- follow_list_page.dart ---
print("\n--- follow_list_page.dart ---")
fl_path = os.path.join(LIB_DIR, "pages", "follow_list_page.dart")
if os.path.exists(fl_path):
    replace_in_file(fl_path, [
        ('"Remove"', "'remove'.tr()"),
    ])

# --- forgot_password_page.dart ---
print("\n--- forgot_password_page.dart ---")
fp_path = os.path.join(LIB_DIR, "pages", "forgot_password_page.dart")
if os.path.exists(fp_path):
    replace_in_file(fp_path, [
        ('"Forgot Password?"', "'forgot_password_title'.tr()"),
        ('"Send Link"', "'send_link'.tr()"),
    ])

# --- group_settings_page.dart ---
print("\n--- group_settings_page.dart ---")
gs_path = os.path.join(LIB_DIR, "pages", "group_settings_page.dart")
if os.path.exists(gs_path):
    replace_in_file(gs_path, [
        ('"Invalid name"', "'invalid_name'.tr()"),
        ('"Settings"', "'settings'.tr()"),
        ('"Members"', "'members'.tr()"),
        ('"Admin"', "'admin'.tr()"),
        ('"Add"', "'add'.tr()"),
        ('"Leave"', "'leave'.tr()"),
        ('"Remove"', "'remove'.tr()"),
        ('"Save"', "'save'.tr()"),
    ])

# --- notification_settings_page.dart ---
print("\n--- notification_settings_page.dart ---")
ns_path = os.path.join(LIB_DIR, "pages", "notification_settings_page.dart")
if os.path.exists(ns_path):
    replace_in_file(ns_path, [
        ('"Choose which notifications you want to receive"',
         "'choose_notifications'.tr()"),
    ])

# --- post_detail_page.dart ---
print("\n--- post_detail_page.dart ---")
pd_path = os.path.join(LIB_DIR, "pages", "post_detail_page.dart")
if os.path.exists(pd_path):
    replace_in_file(pd_path, [
        ('"Restricted Access"', "'restricted_access'.tr()"),
        ("\"This post is reserved for the author's close friends.\"",
         "'close_friends_restricted'.tr()"),
    ])

# --- privacy_settings_page.dart ---
print("\n--- privacy_settings_page.dart ---")
ps_path = os.path.join(LIB_DIR, "pages", "privacy_settings_page.dart")
if os.path.exists(ps_path):
    replace_in_file(ps_path, [
        ('"Public Account"', "'public_account'.tr()"),
        ('"(Public)"', "'label_public'.tr()"),
        ('"(Private)"', "'label_private'.tr()"),
    ])

# --- profile_page.dart ---
print("\n--- profile_page.dart ---")
pp_path = os.path.join(LIB_DIR, "pages", "profile_page.dart")
if os.path.exists(pp_path):
    replace_in_file(pp_path, [
        ('"Block"', "'block_action'.tr()"),
        ('"Suspended"', "'suspended_account_label'.tr()"),
        ('"Account Suspended"', "'account_suspended'.tr()"),
        ('"Private Account"', "'private_account'.tr()"),
    ])

# --- security_settings_page.dart ---
print("\n--- security_settings_page.dart ---")
ss_path = os.path.join(LIB_DIR, "pages", "security_settings_page.dart")
if os.path.exists(ss_path):
    replace_in_file(ss_path, [
        ('"(Enabled)"', "'label_enabled'.tr()"),
        ('"(Disabled)"', "'label_disabled'.tr()"),
        ('"Change Password"', "'change_password'.tr()"),
        ('"Send Password Reset Link"', "'send_password_reset_link'.tr()"),
    ])

# --- suspended_account_page.dart ---
print("\n--- suspended_account_page.dart ---")
sa_path = os.path.join(LIB_DIR, "pages", "suspended_account_page.dart")
if os.path.exists(sa_path):
    replace_in_file(sa_path, [
        ('"ACCOUNT SUSPENDED"', "'account_suspended_title'.tr()"),
        ('"SUSPENSION REASON:"', "'suspension_reason_label'.tr()"),
    ])

# --- theme_settings_page.dart ---
print("\n--- theme_settings_page.dart ---")
ts_path = os.path.join(LIB_DIR, "pages", "theme_settings_page.dart")
if os.path.exists(ts_path):
    replace_in_file(ts_path, [
        ('"Hex code must be 6 characters"', "'hex_code_error'.tr()"),
        ('"Dark Mode"', "'dark_mode'.tr()"),
        ('"DOMINANT COLOR"', "'dominant_color'.tr()"),
        ('"Vibrant Palette"', "'vibrant_palette'.tr()"),
        ('"Custom Hex Code"', "'custom_hex_code'.tr()"),
        ('"Apply Custom Color"', "'apply_custom_color'.tr()"),
    ])

# --- two_factor_verification_page.dart ---
print("\n--- two_factor_verification_page.dart ---")
tfv_path = os.path.join(LIB_DIR, "pages", "two_factor_verification_page.dart")
if os.path.exists(tfv_path):
    replace_in_file(tfv_path, [
        ('"Resend Code"', "'resend_code'.tr()"),
        ('"Cancel & Sign Out"', "'cancel_sign_out'.tr()"),
    ])

# --- user_warning_page.dart ---
print("\n--- user_warning_page.dart ---")
uw_path = os.path.join(LIB_DIR, "pages", "user_warning_page.dart")
if os.path.exists(uw_path):
    replace_in_file(uw_path, [
        ('"Content Moderation Notice"', "'content_moderation_notice'.tr()"),
        ('"MODERATED ITEM"', "'moderated_item'.tr()"),
        ('"REASON FOR REMOVAL"', "'reason_for_removal'.tr()"),
        ('"I Understand & Accept"', "'understand_accept'.tr()"),
    ])

# --- verify_email_page.dart ---
print("\n--- verify_email_page.dart ---")
ve_path = os.path.join(LIB_DIR, "pages", "verify_email_page.dart")
if os.path.exists(ve_path):
    replace_in_file(ve_path, [
        ('"Check your inbox"', "'check_inbox'.tr()"),
        ('"Resend Email"', "'resend_email'.tr()"),
        ('"Cancel & Sign Out"', "'cancel_sign_out'.tr()"),
    ])

# --- auth_gate.dart ---
print("\n--- auth_gate.dart ---")
ag_path = os.path.join(LIB_DIR, "services", "auth", "auth_gate.dart")
if os.path.exists(ag_path):
    replace_in_file(ag_path, [
        ('"No reason provided."', "'no_reason_provided'.tr()"),
    ])

# --- chat_service.dart --- (notification strings)
print("\n--- chat_service.dart ---")
cs_path = os.path.join(LIB_DIR, "services", "chat", "chat_service.dart")
if os.path.exists(cs_path):
    with open(cs_path, 'r', encoding='utf-8') as f:
        content = f.read()
    original = content
    
    # These are notification strings - replace carefully
    # Line 660: post share notification
    content = content.replace('notificationBody = "📜 sent a post"',
                              "notificationBody = 'notif_sent_post'.tr()")
    # Line 664: voice message notification 
    content = content.replace('notificationBody = "🎤 sent a voice message"',
                              "notificationBody = 'notif_sent_voice'.tr()")
    # Line 681: attachment notification
    content = content.replace('notificationBody = "📁 sent an attachment"',
                              "notificationBody = 'notif_sent_attachment'.tr()")
    # Line 743: shared post message text
    content = content.replace('"Shared a post"', "'shared_a_post'.tr()")
    
    content = ensure_import(content, cs_path)
    
    if content != original:
        with open(cs_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"  ✅ Updated: chat_service.dart")

print("\n" + "=" * 60)
print("DONE! All translations applied.")
print("=" * 60)
print("\nNext steps:")
print("  1. Run: python scratch/fix_multiline_consts.py")
print("  2. Run: flutter build web --no-tree-shake-icons")
