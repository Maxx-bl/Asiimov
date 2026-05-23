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
pattern1 = re.compile(r"Text\(\s*'([^'\$]+?)'\s*\)")
pattern2 = re.compile(r'Text\(\s*"([^"\$]+?)"\s*\)')

# Pattern for hintText: '...'
pattern3 = re.compile(r"hintText:\s*'([^'\$]+?)'")
pattern4 = re.compile(r'hintText:\s*"([^"\$]+?)"')

# Pattern for SnackBar(content: Text('...'))
pattern5 = re.compile(r"SnackBar\(\s*content:\s*Text\(\s*'([^'\$]+?)'\s*\)\s*\)")
pattern6 = re.compile(r'SnackBar\(\s*content:\s*Text\(\s*"([^"\$]+?)"\s*\)\s*\)')

for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
        for p in [pattern1, pattern2, pattern3, pattern4, pattern5, pattern6]:
            for match in p.finditer(content):
                text = match.group(1)
                if not text.endswith('.tr()') and ' ' in text and text.strip() != '':
                    found_strings.add(text)

# Also find some common buttons/labels
pattern_button1 = re.compile(r"text:\s*'([^'\$]+?)'")
pattern_button2 = re.compile(r'text:\s*"([^"\$]+?)"')

for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        for p in [pattern_button1, pattern_button2]:
            for match in p.finditer(content):
                text = match.group(1)
                if not text.endswith('.tr()') and ' ' in text and text.strip() != '':
                    found_strings.add(text)

def to_snake_case(s):
    # Very basic snake case
    s = re.sub(r'[^\w\s]', '', s)
    s = s.strip().replace(' ', '_').lower()
    return s[:30] # Limit length

result = {}
for s in sorted(list(found_strings)):
    key = to_snake_case(s)
    # handle duplicates
    original_key = key
    counter = 1
    while key in [v['key'] for v in result.values()]:
        key = f"{original_key}_{counter}"
        counter += 1
    
    result[s] = {
        'key': key,
        'en': s,
        'fr': ''
    }

with open('scratch/strings.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
