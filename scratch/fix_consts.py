import os
import re

dart_files = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

for file_path in dart_files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    modified = False
    
    # We will do an iterative approach for simple known wrappers.
    # Replace:
    # const Text('...'.tr()) -> Text('...'.tr())
    # const Center(child: Text('...'.tr())) -> Center(child: Text('...'.tr()))
    # const SnackBar(content: Text('...'.tr())) -> SnackBar(content: Text('...'.tr()))
    
    # It might be safer to just remove 'const ' from any line that contains '.tr()'
    # Because if a line has .tr(), it CANNOT contain a const that applies to the tr().
    # Note: This might remove valid consts on the same line if they are separate arguments,
    # e.g., padding: const EdgeInsets.all(8), child: Text('...'.tr())
    # So a simple line-based replace is a bit risky.
    
    # Let's use regex to target specific wrappers:
    patterns = [
        (re.compile(r"const\s+Text\(([^)]+\.tr\(\))\)"), r"Text(\1)"),
        (re.compile(r"const\s+Center\(\s*child:\s*Text\(([^)]+\.tr\(\))\)\s*\)"), r"Center(child: Text(\1))"),
        (re.compile(r"const\s+SnackBar\(\s*content:\s*Text\(([^)]+\.tr\(\))\)\s*\)"), r"SnackBar(content: Text(\1))"),
        # Catch other common ones
        (re.compile(r"const\s+([A-Za-z]+)\(\s*([a-zA-Z]+):\s*Text\(([^)]+\.tr\(\))\)\s*\)"), r"\1(\2: Text(\3))"),
    ]
    
    new_content = content
    for pattern, replacement in patterns:
        if pattern.search(new_content):
            new_content = pattern.sub(replacement, new_content)
            modified = True

    # If there are still 'const ' on the same line as '.tr()', let's manually check them.
    if modified:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated {file_path}")

