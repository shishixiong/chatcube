// Verify airport-data.js against models-manifest.js.
// Usage: node tools/airport-assets/verify_data.mjs
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');

const dataFile = path.join(root, 'entry/src/main/resources/rawfile/airport3d/assets/airport-data.js');
const manifestFile = path.join(root, 'entry/src/main/resources/rawfile/airport3d/assets/models-manifest.js');

const sandbox = { window: {} };
vm.createContext(sandbox);
for (const file of [dataFile, manifestFile]) {
  if (!fs.existsSync(file)) {
    console.error('FAIL missing ' + path.relative(root, file));
    process.exit(1);
  }
  vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox, { filename: file });
}

const data = sandbox.window.AirportData;
const manifest = sandbox.window.AirportModelManifest;
if (!data || !Array.isArray(data.objects)) {
  console.error('FAIL window.AirportData.objects missing');
  process.exit(1);
}
if (!Array.isArray(manifest)) {
  console.error('FAIL window.AirportModelManifest missing');
  process.exit(1);
}

const etsFile = path.join(root, 'entry/src/main/ets/utils/AirportEnglishValidation.ets');
const ets = fs.readFileSync(etsFile, 'utf8');
const arrMatch = /AIRPORT_WORD_IDS: string\[\] = \[([\s\S]*?)\]/.exec(ets);
if (!arrMatch) {
  console.error('FAIL AIRPORT_WORD_IDS not found in ' + etsFile);
  process.exit(1);
}
const nativeIds = [...arrMatch[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
if (nativeIds.length !== data.objects.length) {
  console.error('FAIL native ids ' + nativeIds.length + ' != catalog ' + data.objects.length);
  process.exit(1);
}
for (let i = 0; i < nativeIds.length; i++) {
  if (nativeIds[i] !== data.objects[i].id) {
    console.error('FAIL id order mismatch at ' + i + ': ' + nativeIds[i] + ' vs ' + data.objects[i].id);
    process.exit(1);
  }
}

const CATEGORIES = ['places', 'aircraft', 'vehicles', 'people', 'facilities'];
const ZONES = ['overview', 'terminal_zone', 'apron_zone', 'runway_zone', 'hangar_zone'];
const errors = [];
const seen = new Set();

for (const o of data.objects) {
  const tag = o && o.id ? o.id : JSON.stringify(o).slice(0, 40);
  for (const key of ['id', 'word', 'phonetic', 'zh', 'kidDefinition', 'example']) {
    if (typeof o[key] !== 'string' || o[key].trim() === '') errors.push(tag + ': empty ' + key);
  }
  if (seen.has(o.id)) errors.push(tag + ': duplicate id');
  seen.add(o.id);
  if (!CATEGORIES.includes(o.category)) errors.push(tag + ': bad category ' + o.category);
  if (!ZONES.includes(o.zone)) errors.push(tag + ': bad zone ' + o.zone);
  if (data.byId[o.id] !== o) errors.push(tag + ': byId mismatch');
}

const wordIdsFromModels = new Set(manifest.filter((m) => m.wordId).map((m) => m.wordId));
for (const id of wordIdsFromModels) {
  if (!seen.has(id)) errors.push('manifest wordId not in catalog: ' + id);
}

if (data.objects.length !== 50) errors.push('expected 50 words, got ' + data.objects.length);

// The only procedural (non-GLB) word targets are the three ground surfaces.
const PROCEDURAL = ['runway', 'taxiway', 'apron'];
for (const id of PROCEDURAL) {
  if (!seen.has(id)) errors.push('missing procedural word ' + id);
}
for (const id of seen) {
  const hasModel = manifest.some((m) => m.wordId === id);
  if (!hasModel && !PROCEDURAL.includes(id)) errors.push('word has no model or ground target: ' + id);
}

if (errors.length > 0) {
  console.error('DATA FAIL\n' + errors.join('\n'));
  process.exit(1);
}
console.log('DATA OK ' + data.objects.length + ' words, ' + manifest.length + ' models');
