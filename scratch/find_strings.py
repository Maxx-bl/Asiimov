import os
import re
import json

dart_files = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

found_strings = set()

# Pattern for Text('...') or Text("...")
# It must not contain variables like $ or ${}
pattern1 = re.compile(r"Text\(\s*'([^'\$]+?)'\s*\)")
pattern2 = re.compile(r'Text\(\s*"([^"\$]+?)"\s*\)')

# Pattern for hintText: '...'
pattern3 = re.compile(r"hintText:\s*'([^'\$]+?)'")
pattern4 = re.compile(r'hintText:\s*"([^"\$]+?)"')

for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
        for p in [pattern1, pattern2, pattern3, pattern4]:
            for match in p.finditer(content):
                text = match.group(1)
                # Ignore if it looks like a translation key (e.g., lowercase with underscores)
                # or if it's already translated
                if not text.endswith('.tr()') and ' ' in text and text.strip() != '':
                    found_strings.add(text)

print(f"Found {len(found_strings)} unique strings.")
print(list(found_strings)[:20])
