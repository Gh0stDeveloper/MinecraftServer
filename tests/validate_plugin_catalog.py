#!/usr/bin/env python3
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
data=json.loads((ROOT/'config/plugins.json').read_text())
for p in data['plugins']:
    if p['source_type']=='git-gradle':
        assert re.fullmatch(r'[0-9a-f]{40}',p['ref']),p['id']
        assert p['source'].startswith('https://github.com/')
    assert p['license']
print('Plugin catalog is pinned and structurally valid.')
