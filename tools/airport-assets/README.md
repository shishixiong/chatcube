# Airport asset pipeline

Builds the offline 3D model bundle for `airport_english` from polyfork.dev's
free [Airport kit](https://polyfork.dev/kit/airport-43b137).

## One-time

```bash
npm --prefix tools/airport-assets install three@0.128.0
```

## Build

```bash
python3 tools/airport-assets/gen_manifest.py   # kit API -> manifest.json
python3 tools/airport-assets/download.py       # manifest -> raw/*-preview.glb
node    tools/airport-assets/verify_glb.mjs    # parse every GLB with three r128
python3 tools/airport-assets/pack.py           # raw -> airport3d/assets/models/*.js
```

`download.py` is safe to re-run; complete files are skipped and each file gets
5 retries (polyfork's CDN is occasionally slow or stalls). `pack.py` refuses to
build if a word's primary model is missing — remove that word from
`word-models.json`, `airport-data.js` and `AIRPORT_WORD_IDS` instead of
substituting an unrelated part.

## Licensing

Every preview GLB is CC BY 4.0. `pack.py` writes `credits.txt` with the full
line for each asset. Do not commit polyfork's `.mjs` source modules or HD
editions — they are not covered by CC BY 4.0.

## Files

- `word-models.json` — the only hand-edited file: word id → asset ids (primary first).
- `manifest.json` — generated: asset id, word id, title, preview URL, triangles.
- `raw/` — downloaded `*-preview.glb` (git-ignored).
- `entry/src/main/resources/rawfile/airport3d/assets/models/` — generated base64 JS.
