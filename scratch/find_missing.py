import os
import re

dart_files = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

# Look for user-facing string literals that do NOT have .tr()
# Text('...')
# label: '...'
# tooltip: '...'
# hintText: '...'
# text: '...'
# content: Text('...')
# AppBar(title: Text('...'))

patterns = [
    re.compile(r"Text\(\s*'([^'\$\\]+)'\s*\)"),
    re.compile(r"Text\(\s*\"([^\”\$\\]+)\"\s*\)"),
    re.compile(r"label:\s*'([^'\$\\]+)'"),
    re.compile(r"label:\s*\"([^\”\$\\]+)\""),
    re.compile(r"tooltip:\s*'([^'\$\\]+)'"),
    re.compile(r"tooltip:\s*\"([^\”\$\\]+)\""),
    re.compile(r"title:\s*'([^'\$\\]+)'"),
    re.compile(r"text:\s*'([^'\$\\]+)'"),
]

missing = set()

for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    for i, line in enumerate(lines):
        # Ignore lines that already have .tr()
        if '.tr()' in line:
            continue
            
        for pattern in patterns:
            for match in pattern.findall(line):
                # ignore single char, empty, or typical non-user strings
                if len(match) > 1 and not match.startswith('http') and not match.startswith('assets/'):
                    missing.add((file_path, i+1, match))

for file_path, line, text in sorted(list(missing)):
    print(f"{file_path}:{line}: {text}")

