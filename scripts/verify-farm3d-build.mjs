import fs from 'node:fs'
import vm from 'node:vm'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const base = 'entry/src/main/resources/rawfile/farm3d/assets/'

global.window = global
global.self = global
const THREE = require('../' + base + 'vendor/three.min.js')
global.THREE = THREE

vm.runInThisContext(fs.readFileSync(base + 'farm-data.js', 'utf8'))
vm.runInThisContext(fs.readFileSync(base + 'farm-models.js', 'utf8'))

const built = global.FarmModels.buildAll(new THREE.Scene())
let meshes = 0
let instanced = 0
let triangles = 0
built.root.traverse((o) => {
  if (!o.isMesh) return
  meshes++
  if (o.isInstancedMesh) instanced++
  const count = o.geometry && o.geometry.attributes.position
    ? o.geometry.attributes.position.count / 3
    : 0
  triangles += count * (o.isInstancedMesh ? o.count : 1)
})

const ids = new Set()
built.root.traverse((o) => {
  if (o.userData && o.userData.wordId) ids.add(o.userData.wordId)
})

const required = ['barn', 'farmhouse', 'stable', 'chicken_coop', 'pond', 'chick', 'duck', 'fence', 'hay']
const missing = required.filter((id) => !ids.has(id))
const objects = Object.keys(built.objects).length

console.log(`meshes=${meshes} instanced=${instanced} triangles=${Math.round(triangles)} objects=${objects}`)
if (missing.length) {
  console.log('FAIL missing word ids: ' + missing.join(', '))
  process.exit(1)
}
if (objects < 50) {
  console.log('FAIL object table unexpectedly small')
  process.exit(1)
}
if (meshes > 900) {
  console.log('FAIL mesh count ' + meshes + ' exceeds 900; merge more static groups or raise the budget deliberately')
  process.exit(1)
}
console.log('PASS farm3d headless build budget')
