#!/usr/bin/env python3
"""Re-download the pinned upstream files, verifying their recorded SHA-256 hashes.
Run from any directory: python3 tools/aircraft_fetch.py
Existing correct files are skipped. GPL notices and source are preserved alongside assets.
"""
from pathlib import Path
import hashlib, json, urllib.request
BASE=Path(__file__).resolve().parents[1]/'simulator/assets/aircraft'
for aircraft in json.loads((BASE/'sources.json').read_text()):
    for item in aircraft['files']:
        target=BASE/aircraft['id']/'source'/item['path']
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()==item['sha256']:
            continue
        payload=urllib.request.urlopen(item['url'],timeout=45).read()
        if hashlib.sha256(payload).hexdigest()!=item['sha256']:
            raise RuntimeError('Source checksum mismatch: '+item['url'])
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(payload)
        print('Restored', aircraft['id'], item['path'])
print('All aircraft source files verified.')
