// Verify every downloaded polyfork preview GLB parses with three r128 GLTFLoader.
// Usage: node tools/airport-assets/verify_glb.mjs
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const rawDir = path.join(here, 'raw');

const files = fs.existsSync(rawDir)
  ? fs.readdirSync(rawDir).filter((f) => f.endsWith('-preview.glb')).sort()
  : [];

if (files.length === 0) {
  console.error('FAIL no *-preview.glb files in ' + rawDir);
  process.exit(1);
}

let failed = 0;
let pending = files.length;

function parseOne(file) {
  return new Promise((resolve) => {
    const buf = fs.readFileSync(path.join(rawDir, file));
    const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
    new GLTFLoader().parse(
      ab,
      '',
      (gltf) => {
        let meshes = 0;
        let skinned = 0;
        let tris = 0;
        gltf.scene.traverse((o) => {
          if (o.isMesh) {
            meshes += 1;
            if (o.isSkinnedMesh) skinned += 1;
            const g = o.geometry;
            tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
          }
        });
        const anims = gltf.animations.map((a) => a.name).join('/');
        console.log(
          'OK ' + file.replace('-preview.glb', '') +
          ' meshes=' + meshes + ' skinned=' + skinned +
          ' tris=' + Math.round(tris) + ' anims=' + (anims || '-')
        );
        resolve();
      },
      (e) => {
        console.error('FAIL ' + file + ': ' + (e && e.message ? e.message : String(e)));
        failed += 1;
        resolve();
      }
    );
  });
}

for (const f of files) {
  await parseOne(f);
  pending -= 1;
}

console.log('ALL ' + (failed === 0 ? 'OK' : 'FAILED') + ' ' + files.length + ' files, ' + failed + ' failed');
process.exit(failed === 0 ? 0 : 1);
