import os
import re

files_to_fix = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            files_to_fix.append(os.path.join(root, f))

patterns = [
    re.compile(r"const\s+SnackBar\("),
    re.compile(r"const\s+Center\("),
    re.compile(r"const\s+TextSpan\("),
    re.compile(r"return\s+const\s+Scaffold\("),
    re.compile(r"const\s+InputDecoration\("),
    re.compile(r"const\s+Text\("),
    re.compile(r"const\s+BottomNavigationBarItem\("),
    re.compile(r"const\s+ListTile\("),
]

for file_path in files_to_fix:
    if not os.path.exists(file_path):
        continue
        
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    new_content = content
    modified = False
    
    for pattern in patterns:
        if pattern.search(new_content):
            new_content = pattern.sub(lambda m: m.group(0).replace('const ', '').replace('const\t', ''), new_content)
            modified = True
            
    if modified:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Fixed {file_path}")
