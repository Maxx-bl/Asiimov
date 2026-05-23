import os
import re
import json

dart_files = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

patterns = [
    re.compile(r"Text\(\s*'([^'\$\\]+)'\s*\)"),
    re.compile(r"Text\(\s*\"([^\”\$\\]+)\"\s*\)"),
    re.compile(r"label:\s*'([^'\$\\]+)'"),
    re.compile(r"label:\s*\"([^\”\$\\]+)\""),
    re.compile(r"tooltip:\s*'([^'\$\\]+)'"),
    re.compile(r"tooltip:\s*\"([^\”\$\\]+)\""),
    re.compile(r"title:\s*'([^'\$\\]+)'"),
    re.compile(r"text:\s*'([^'\$\\]+)'"),
    re.compile(r"hintText:\s*'([^'\$\\]+)'"),
    re.compile(r"SnackBar\(\s*content:\s*Text\('([^'\$\\]+)'\)"),
]

missing_strings = set()

for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    for pattern in patterns:
        for match in pattern.findall(content):
            if len(match) > 1 and not match.startswith('http') and not match.startswith('assets/'):
                missing_strings.add(match)

# Plus hardcoded ones from main_scaffold:
missing_strings.update(['Feed', 'Messages', 'Profile'])

# Create mapping dictionary
mapping = {}
for s in missing_strings:
    # generate key
    key = re.sub(r'[^a-zA-Z0-9]+', '_', s).strip('_').lower()
    if not key:
        continue
    # Keep first 30 chars
    key = key[:30]
    
    mapping[s] = {
        'key': key,
        'en': s,
        'fr': s # We will translate this manually in python!
    }

translations_fr = {
    "Cancel": "Annuler",
    "Report Message": "Signaler le message",
    "Report Comment": "Signaler le commentaire",
    "Upvotes": "Votes positifs",
    "Downvotes": "Votes négatifs",
    "Shares": "Partages",
    "Report Post": "Signaler le post",
    "Users": "Utilisateurs",
    "Suspended": "Suspendus",
    "Reports": "Signalements",
    "History": "Historique",
    "Reinstate": "Rétablir",
    "Dismiss": "Ignorer",
    "Confirm": "Confirmer",
    "Documents": "Documents",
    "Error": "Erreur",
    "Refresh": "Actualiser",
    "Loading...": "Chargement...",
    "Save": "Sauvegarder",
    "Leave Group": "Quitter le groupe",
    "Add": "Ajouter",
    "Franais": "Français",
    "Français": "Français",
    "English": "Anglais",
    "Notifications": "Notifications",
    "Messages": "Messages",
    "Private messages and group chats": "Messages privés et de groupe",
    "Followers": "Abonnés",
    "New followers and follow requests": "Nouveaux abonnés et requêtes",
    "Comments": "Commentaires",
    "Comments on your posts": "Commentaires sur vos posts",
    "Post": "Publier",
    "Privacy": "Confidentialité",
    "Report User": "Signaler l'utilisateur",
    "Following": "Abonnements",
    "Security": "Sécurité",
    "Theme": "Thème",
    "Verify": "Vérifier",
    "Feed": "Fil d'actualité",
    "Profile": "Profil"
}

# Apply French translations
for s, data in mapping.items():
    if s in translations_fr:
        data['fr'] = translations_fr[s]

# Add to JSON
with open('assets/translations/en.json', 'r', encoding='utf-8') as f:
    en_json = json.load(f)
with open('assets/translations/fr.json', 'r', encoding='utf-8') as f:
    fr_json = json.load(f)

for s, data in mapping.items():
    key = data['key']
    if key not in en_json:
        en_json[key] = data['en']
        fr_json[key] = data['fr']

with open('assets/translations/en.json', 'w', encoding='utf-8') as f:
    json.dump(en_json, f, indent=2, ensure_ascii=False)
with open('assets/translations/fr.json', 'w', encoding='utf-8') as f:
    json.dump(fr_json, f, indent=2, ensure_ascii=False)

# Write mapping to file to be able to debug
with open('scratch/missing_mapping.json', 'w', encoding='utf-8') as f:
    json.dump(mapping, f, indent=2, ensure_ascii=False)

print("Updated JSON files")

# Now replace in Dart files
for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    new_content = content
    modified = False

    for original, data in mapping.items():
        key = data['key']
        orig_sq = original.replace("'", "\\'")
        orig_dq = original.replace('"', '\\"')

        # Only replace if the file contains the exact string in a UI context
        # We can just do a replace for known wrappers, or even better, simple text match if safe
        
        replacements = [
            (f"Text('{orig_sq}')", f"Text('{key}'.tr())"),
            (f"label: '{orig_sq}'", f"label: '{key}'.tr()"),
            (f"tooltip: '{orig_sq}'", f"tooltip: '{key}'.tr()"),
            (f"title: '{orig_sq}'", f"title: '{key}'.tr()"),
            (f"text: '{orig_sq}'", f"text: '{key}'.tr()"),
            (f"hintText: '{orig_sq}'", f"hintText: '{key}'.tr()"),
            (f"SnackBar(content: Text('{orig_sq}'))", f"SnackBar(content: Text('{key}'.tr()))"),
            (f"_buildNavItem(0, Icons.home_outlined, Icons.home, 'Feed')", f"_buildNavItem(0, Icons.home_outlined, Icons.home, 'feed'.tr())"),
            (f"_buildNavItem(1, Icons.chat_bubble_outline, Icons.chat_bubble, 'Messages')", f"_buildNavItem(1, Icons.chat_bubble_outline, Icons.chat_bubble, 'messages'.tr())"),
            (f"_buildNavItem(2, Icons.person_outline, Icons.person, 'Profile')", f"_buildNavItem(2, Icons.person_outline, Icons.person, 'profile'.tr())")
        ]
        
        for old_str, new_str in replacements:
            if old_str in new_content:
                new_content = new_content.replace(old_str, new_str)
                modified = True

    if modified:
        # Check if easy_localization is imported
        if "import 'package:easy_localization/easy_localization.dart';" not in new_content:
            lines = new_content.split('\n')
            last_import = -1
            for i, line in enumerate(lines):
                if line.startswith('import '):
                    last_import = i
            
            if last_import != -1:
                lines.insert(last_import + 1, "import 'package:easy_localization/easy_localization.dart';")
            else:
                lines.insert(0, "import 'package:easy_localization/easy_localization.dart';")
            
            new_content = '\n'.join(lines)

        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated {file_path}")

print("Done replacing.")
