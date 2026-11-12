import fs from 'node:fs'

const root = 'entry/src/main/resources/rawfile/farm3d/assets/'
const scene = fs.readFileSync(root + 'farm-scene.js', 'utf8')
const models = fs.readFileSync(root + 'farm-models.js', 'utf8')
const agents = fs.readFileSync(root + 'farm-agents.js', 'utf8')
const data = fs.readFileSync(root + 'farm-data.js', 'utf8')
const validation = fs.readFileSync('entry/src/main/ets/utils/FarmEnglishValidation.ets', 'utf8')

const dataBlock = data.split('var objects = [')[1].split('];')[0]
const dataIds = [...dataBlock.matchAll(/\{ id: '([^']+)'/g)].map((m) => m[1])
const valBlock = validation.split('export const FARM_WORD_IDS: string[] = [')[1].split(']')[0]
const valIds = [...valBlock.matchAll(/'([^']+)'/g)].map((m) => m[1])
const unique = (arr) => new Set(arr).size === arr.length
const sameWordSet = dataIds.length === valIds.length && dataIds.every((id) => valIds.includes(id))

const checks = [
  ['selection follows moving agents', /FOLLOW_SELECTION_IDS[\s\S]{0,220}'chicken'/.test(scene)],
  ['field work routine exists', /buildFieldWorkRoutine/.test(scene)],
  ['pasture butterflies exist', /function makeButterfly/.test(models) && /updateButterflies/.test(scene)],
  ['orchard ecology exists', /function makeDragonfly/.test(models) && /ducklings/.test(models) && /lily/i.test(models)],
  ['render stats API exists', /getRenderStats/.test(scene)],
  ['homeward routine exists', /buildHomewardRoutine/.test(scene) && /grandma/.test(scene)],
  ['farmhouse door choreography', /houseDoor/.test(models) && /doorIsOpenEnough/.test(scene)],
  ['sheep pen exists', /function makeSheepPen/.test(models) && /buildSheepPenRoutine/.test(scene)],
  ['word tables match data', sameWordSet && unique(dataIds) && unique(valIds)],
  ['farm data has chick word', /id:\s*'chick'/.test(data)],
  ['chick model exists', /function makeChick/.test(models)],
  ['chick roots exported', /chickRoots/.test(models)],
  ['chick joins coop routines', /pushCoopRoutine\('chick'/.test(scene)],
  ['sky bodies ignore fog', /fog:\s*false/.test(scene)],
  ['rain API exists', /S\.setWeather\s*=/.test(scene)],
  ['pick skips invisible ancestors', /visible\s*===\s*false/.test(scene)],
  ['coop lamp exported', /coopLamp/.test(models)],
  ['porch roof present', /4\.4,\s*0\.12,\s*1\.75/.test(models)],
  ['setCoopBirdsAuto no teleport', !/S\.setCoopBirdsAuto[\s\S]{0,200}resetCoopBird/.test(scene)],
  ['environment recompute', /recomputeEnvironment/.test(agents)],
  ['rain change hook', /onWeatherChange/.test(agents)],
  ['coop birds excluded from sleep', /coopBird\)\s*continue|coopBird\).*continue/.test(agents)],
  ['zone stories skip rain', /zoneTimer <= 0 && !nightOn && !rainOn/.test(agents)],
  ['rooster shelter clear of trough', /localPoint\(1\.7,\s*2\.2\)/.test(scene)],
  ['coop exit is transition-driven', /wasForced/.test(scene)],
  ['instant scene apply is silent', /changed && !instant/.test(fs.readFileSync(root + 'farm-app.js', 'utf8'))]
]

let failed = 0
for (const [name, ok] of checks) {
  console.log((ok ? 'PASS ' : 'FAIL ') + name)
  if (!ok) failed++
}
const meshCalls = (models.match(/\bmesh\(/g) || []).length
console.log('INFO farm-models.js mesh() calls: ' + meshCalls)
if (meshCalls > 650) {
  console.log('WARN mesh() calls exceed 650; run FarmApp.stats() on device before adding more static detail')
}
process.exit(failed ? 1 : 0)
