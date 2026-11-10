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
for name in ('app.js', 'auth-web.js', 'art.js', 'style.css', 'offer-refused.mp3', 'welcome-background.png'):
    shutil.copyfile(root / name, target / name)
html = (root / 'index.html').read_text()
html = html.replace('<html lang="fr">', '<html lang="fr" class="quartiers-mobile">')
html = html.replace('</head>', '<link rel="stylesheet" href="mobile.css"></head>')
html = re.sub(r'<script src="app\.js[^"<>]*"></script>',
              '<script src="mobile-bootstrap.js"></script>', html)
(target / 'index.html').write_text(html)
manifest = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
            for name in ('app.js', 'auth-web.js', 'art.js', 'style.css', 'offer-refused.mp3', 'welcome-background.png')}
(target / 'original-sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Original board, illustrations and animations packaged without changes.')
