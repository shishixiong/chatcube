#!/usr/bin/env python3
"""Build manifest.json from polyfork's public Airport kit API.

Usage: python3 tools/airport-assets/gen_manifest.py
"""
import gzip
import json
import sys
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
KIT_ID = 'airport-43b137'
API = f'https://polyfork.dev/api/assets?kit={KIT_ID}&per_page=100'
UA = 'chatcube-airport-assets/1.0 (+https://github.com/chatcube)'


def fetch_json(url: str, attempts: int = 5) -> dict:
    last = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers={
                'User-Agent': UA,
                'Accept-Encoding': 'gzip',
                'Accept': 'application/json',
            })
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read()
                if resp.headers.get('Content-Encoding') == 'gzip':
                    raw = gzip.decompress(raw)
                return json.loads(raw.decode('utf-8'))
        except Exception as exc:  # noqa: BLE001 - report and retry
            last = exc
            print(f'  fetch attempt {i + 1} failed: {exc}', file=sys.stderr)
            time.sleep(2 * (i + 1))
    raise SystemExit(f'cannot fetch {url}: {last}')


def main() -> int:
    spec = json.loads((HERE / 'word-models.json').read_text(encoding='utf-8'))
    data = fetch_json(API)
    rows = {row['id']: row for row in data.get('assets', [])}
    if len(rows) < 90:
        raise SystemExit(f'kit API returned only {len(rows)} parts; expected ~97')

    manifest = []
    missing = []
    seen = set()
    for entry in spec:
        word_id = entry['wordId']
        for idx, asset_id in enumerate(entry['assets']):
            if asset_id in seen:
                raise SystemExit(f'duplicate asset id in word-models.json: {asset_id}')
            seen.add(asset_id)
            row = rows.get(asset_id)
            if row is None:
                missing.append(asset_id)
                continue
            manifest.append({
                'assetId': asset_id,
                'wordId': word_id if idx == 0 else '',
                'title': row.get('title') or asset_id,
                'previewUrl': f'https://polyfork.dev/cdn/{asset_id}-preview.glb',
                'triangles': row.get('triangles', 0),
            })

    if missing:
        print('missing asset ids (not in kit API):', file=sys.stderr)
        for m in missing:
            print('  ' + m, file=sys.stderr)
        return 1

    primary = [m for m in manifest if m['wordId']]
    expected_primary = len([e for e in spec if e['wordId'] and e['assets']])
    if len(primary) != expected_primary:
        raise SystemExit(
            f'primary model count {len(primary)} != words with models {expected_primary}')
    word_count = len([e for e in spec if e['wordId']])
    if word_count == 0:
        raise SystemExit('word-models.json has no words')

    (HERE / 'manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'MANIFEST OK {len(manifest)} assets, {word_count} words ({len(primary)} with models)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
