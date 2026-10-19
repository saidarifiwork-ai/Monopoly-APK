#!/usr/bin/env python3
"""Package the original renderer; never regenerate or redesign its board."""
from pathlib import Path
import hashlib
import json
import re
import shutil

mobile = Path(__file__).resolve().parents[1]
root = mobile.parent
target = mobile / 'assets' / 'game'
target.mkdir(parents=True, exist_ok=True)
for name in ('app.js', 'art.js', 'style.css'):
    shutil.copyfile(root / name, target / name)
html = (root / 'index.html').read_text()
html = html.replace('<html lang="fr">', '<html lang="fr" class="quartiers-mobile">')
# The large desktop welcome photograph is unused by the native welcome screen.
html = re.sub(r'data:image/jpeg;base64,[A-Za-z0-9+/=]+',
              'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==', html)
html = html.replace('</head>', '<link rel="stylesheet" href="mobile.css"></head>')
html = re.sub(r'<script src="app\.js[^"<>]*"></script>',
              '<script src="mobile-bootstrap.js"></script>', html)
(target / 'index.html').write_text(html)
manifest = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
            for name in ('app.js', 'art.js', 'style.css')}
(target / 'original-sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Original board, illustrations and animations packaged without changes.')
