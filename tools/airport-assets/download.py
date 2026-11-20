#!/usr/bin/env python3
"""Download every preview GLB in manifest.json, with retries and resume-by-skip.

Usage: python3 tools/airport-assets/download.py
Safe to re-run: complete files are skipped.
"""
import json
import struct
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW = HERE / 'raw'
UA = 'chatcube-airport-assets/1.0 (+https://github.com/chatcube)'
WORKERS = 4
ATTEMPTS = 5
TIMEOUT = 180


def glb_ok(path: Path) -> bool:
    try:
        data = path.read_bytes()
        if len(data) < 12:
            return False
        magic, version, total = struct.unpack('<III', data[:12])
        return magic == 0x46546C67 and version == 2 and total == len(data)
    except OSError:
        return False


def fetch_one(asset_id: str, url: str, dest: Path) -> bool:
    if dest.exists() and glb_ok(dest):
        return True
    last = None
    for i in range(ATTEMPTS):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                data = resp.read()
            dest.write_bytes(data)
            if glb_ok(dest):
                return True
            last = RuntimeError(f'bad GLB ({len(data)} bytes)')
        except Exception as exc:  # noqa: BLE001 - retry
            last = exc
        time.sleep(2 * (i + 1))
    print(f'FAIL {asset_id}: {last}', file=sys.stderr)
    return False


def main() -> int:
    manifest = json.loads((HERE / 'manifest.json').read_text(encoding='utf-8'))
    RAW.mkdir(exist_ok=True)
    todo = [m for m in manifest]
    ok = 0
    failed = []
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {
            pool.submit(fetch_one, m['assetId'], m['previewUrl'],
                        RAW / f"{m['assetId']}-preview.glb"): m['assetId']
            for m in todo
        }
        for fut in as_completed(futures):
            asset_id = futures[fut]
            if fut.result():
                ok += 1
                print(f'OK {ok}/{len(todo)} {asset_id}', flush=True)
            else:
                failed.append(asset_id)

    if failed:
        print(f'FAILED {len(failed)}/{len(todo)}: ' + ' '.join(failed))
        return 1
    print(f'DOWNLOAD OK {ok}/{len(todo)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
