#!/usr/bin/env python3
"""Writes FILE.meta.json for the catalog.
Usage: write-meta.py type file dataDate dataSource license.txt [extra_json]"""
import hashlib, json, os, sys
from datetime import datetime, timezone

kind, path, data_date, data_source, license_file = sys.argv[1:6]
extra = json.loads(sys.argv[6]) if len(sys.argv) > 6 else {}
h = hashlib.sha256()
with open(path, 'rb') as f:
    for block in iter(lambda: f.read(1 << 20), b''):
        h.update(block)
with open(license_file, encoding='utf-8') as f:
    text = f.read().strip()
m = {'type': kind, 'name': os.path.basename(path), 'size': os.path.getsize(path), 'sha256': h.hexdigest(),
     'dataDate': data_date, 'dataSource': data_source,
     'produced': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), 'licenseText': text}
m.update(extra)
with open(os.path.splitext(path)[0] + '.meta.json', 'w', encoding='utf-8') as f:
    json.dump(m, f, ensure_ascii=False, indent=1)
    f.write('\n')
