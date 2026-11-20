#!/usr/bin/env python3
"""Pack raw preview GLBs into base64 JS data files + manifest + credits.

Usage: python3 tools/airport-assets/pack.py
"""
import base64
import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
RAW = HERE / 'raw'
OUT = ROOT / 'entry/src/main/resources/rawfile/airport3d'
MODELS = OUT / 'assets/models'


def glb_ok(path: Path) -> bool:
    try:
        data = path.read_bytes()
        if len(data) < 12:
            return False
        magic, version, total = struct.unpack('<III', data[:12])
        return magic == 0x46546C67 and version == 2 and total == len(data)
    except OSError:
        return False


def json_chunk(path: Path) -> dict:
    data = path.read_bytes()
    jlen, jtype = struct.unpack('<II', data[12:20])
    if jtype != 0x4E4F534A:
        raise ValueError(f'{path.name}: first chunk is not JSON')
    return json.loads(data[20:20 + jlen].decode('utf-8'))


def triangles(path: Path) -> int:
    j = json_chunk(path)
    total = 0
    for mesh in j.get('meshes', []):
        for prim in mesh.get('primitives', []):
            idx = prim.get('indices')
            if idx is None:
                continue
            total += j['accessors'][idx]['count'] // 3
    return total


def main() -> int:
    manifest = json.loads((HERE / 'manifest.json').read_text(encoding='utf-8'))
    MODELS.mkdir(parents=True, exist_ok=True)

    packed = []
    credits = [
        '3D models: Polyfork Airport Kit (https://polyfork.dev/kit/airport-43b137)',
        'License: CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)',
        'Changes: bundled offline as base64, repacked as JS data files, rendered with flat shading.',
        '',
    ]
    missing = []
    total_b64 = 0

    for entry in manifest:
        asset_id = entry['assetId']
        src = RAW / f'{asset_id}-preview.glb'
        if not src.exists() or not glb_ok(src):
            missing.append(asset_id)
            continue
        b64 = base64.b64encode(src.read_bytes()).decode('ascii')
        total_b64 += len(b64)
        js = (
            "window.AIRPORT_MODELS = window.AIRPORT_MODELS || {};\n"
            f"window.AIRPORT_MODELS['{asset_id}'] = '{b64}';\n"
        )
        (MODELS / f'{asset_id}.js').write_text(js, encoding='ascii')
        tris = triangles(src) or entry.get('triangles', 0)
        packed.append({
            'id': asset_id,
            'file': f'assets/models/{asset_id}.js',
            'wordId': entry.get('wordId', ''),
            'triangles': tris,
        })
        credits.append(
            f"{entry['title']} by Polyfork (https://polyfork.dev/asset/{asset_id}), CC BY 4.0")

    if missing:
        print('MISSING preview GLBs for: ' + ' '.join(missing), file=sys.stderr)
        print('Remove the affected words from word-models.json, airport-data.js and '
              'AIRPORT_WORD_IDS, or re-run download.py.', file=sys.stderr)
        return 1

    (OUT / 'assets/models-manifest.js').write_text(
        'window.AirportModelManifest = ' +
        json.dumps(packed, ensure_ascii=False, indent=2) + ';\n',
        encoding='utf-8')
    (OUT / 'credits.txt').write_text('\n'.join(credits) + '\n', encoding='utf-8')

    words = [p for p in packed if p['wordId']]
    print(f'PACK OK {len(packed)} assets, {len(words)} words, base64 {total_b64 / 1e6:.1f}MB')
    return 0


if __name__ == '__main__':
    sys.exit(main())
