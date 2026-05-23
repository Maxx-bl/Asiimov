import os
import re
import json

# 1. Load the translations mapping
with open('scratch/translations_mapping.json', 'r', encoding='utf-8') as f:
    mapping = json.load(f)

# Update en.json and fr.json
with open('assets/translations/en.json', 'r', encoding='utf-8') as f:
    en_json = json.load(f)
with open('assets/translations/fr.json', 'r', encoding='utf-8') as f:
    fr_json = json.load(f)

for original, data in mapping.items():
    key = data['key']
    en_json[key] = data['en']
    fr_json[key] = data['fr']

with open('assets/translations/en.json', 'w', encoding='utf-8') as f:
    json.dump(en_json, f, indent=2, ensure_ascii=False)
with open('assets/translations/fr.json', 'w', encoding='utf-8') as f:
    json.dump(fr_json, f, indent=2, ensure_ascii=False)

# 2. Modify dart files
dart_files = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

# Compile patterns for replacement
# We will do simple string replacement for known matches to be safe
replacements = {}
for original, data in mapping.items():
    key = data['key']
    # Escape quotes in original string to avoid matching issues
    # But since it's a direct string match, we can just replace exact known segments.
    # Text('...') -> Text('key'.tr())
    
    # Single quotes
    orig_sq = original.replace("'", "\\'")
    # Double quotes
    orig_dq = original.replace('"', '\\"')

    # Build exact string chunks to replace
    replacements[f"Text('{orig_sq}')"] = f"Text('{key}'.tr())"
    replacements[f'Text("{orig_dq}")'] = f"Text('{key}'.tr())"
    
    replacements[f"hintText: '{orig_sq}'"] = f"hintText: '{key}'.tr()"
    replacements[f'hintText: "{orig_dq}"'] = f"hintText: '{key}'.tr()"
    
    replacements[f"SnackBar(content: Text('{orig_sq}'))"] = f"SnackBar(content: Text('{key}'.tr()))"
    replacements[f'SnackBar(content: Text("{orig_dq}"))'] = f"SnackBar(content: Text('{key}'.tr()))"

    replacements[f"text: '{orig_sq}'"] = f"text: '{key}'.tr()"
    replacements[f'text: "{orig_dq}"'] = f"text: '{key}'.tr()"

for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    new_content = content
    modified = False

    for old_str, new_str in replacements.items():
        if old_str in new_content:
            new_content = new_content.replace(old_str, new_str)
            modified = True

    if modified:
        # Check if easy_localization is imported
        if "import 'package:easy_localization/easy_localization.dart';" not in new_content:
            # Insert after the first import or at the top
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
