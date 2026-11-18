import fs from 'node:fs'
import vm from 'node:vm'
import { createRequire } from 'node:module'

/* 小词城 3D 场景静态验证：
   1. 数据 / 模型 / 场景 / UI 四层语法与依赖是否完整
   2. 50 个单词 id 是否与 CityEnglishValidation.ets 一致
   3. 场景规模（网格数、三角形数）是否仍在移动端 WebView 的安全区间
   4. 新增细节（夜景、巡游、合批、天空）的关键代码是否还在

   用法：node scripts/verify-city3d-scene.mjs
*/

const require = createRequire(import.meta.url)
const base = 'entry/src/main/resources/rawfile/city3d/assets/'

const read = (f) => fs.readFileSync(base + f, 'utf8')
const data = read('city-data.js')
const models = read('city-models.js')
const scene = read('city-scene.js')
const app = read('city-app.js')
const css = read('city.css')
const hunt = read('city-hunt.js')
const interior = read('city-interior.js')
const cssHunt = (() => {
  try { return fs.readFileSync(base + 'city-hunt.css', 'utf8') } catch (e) { return '' }
})()
const cssInterior = (() => {
  try { return fs.readFileSync(base + 'city-interior.css', 'utf8') } catch (e) { return '' }
})()
const html = fs.readFileSync('entry/src/main/resources/rawfile/city3d/index.html', 'utf8')
const validation = fs.readFileSync('entry/src/main/ets/utils/CityEnglishValidation.ets', 'utf8')

/* ---------- 1. 语法与依赖 ---------- */
global.window = global
global.self = global
const THREE = require('../' + base + 'vendor/three.min.js')
global.THREE = THREE
global.document = {
  createElement(tag) {
    if (tag !== 'canvas') return {}
    return {
      width: 0,
      height: 0,
      getContext() {
        const noop = () => {}
        return {
          fillStyle: '', strokeStyle: '', lineWidth: 1, globalAlpha: 1,
          font: '', textAlign: '', textBaseline: '',
          shadowColor: '', shadowBlur: 0,
          fillRect: noop, strokeRect: noop, fillText: noop, strokeText: noop,
          beginPath: noop, closePath: noop, moveTo: noop, lineTo: noop,
          arc: noop, arcTo: noop, fill: noop, stroke: noop, save: noop, restore: noop,
          translate: noop, rotate: noop, scale: noop,
          measureText: () => ({ width: 10 }),
          createLinearGradient: () => ({ addColorStop: noop }),
          createRadialGradient: () => ({ addColorStop: noop }),
          createPattern: () => ({})
        }
      }
    }
  }
}

let syntaxOk = true
for (const f of ['city-data.js', 'city-models.js', 'city-scene.js', 'city-app.js']) {
  try {
    new vm.Script(read(f))
  } catch (e) {
    console.log('FAIL 语法错误 ' + f + ': ' + e.message)
    syntaxOk = false
  }
}
console.log((syntaxOk ? 'PASS ' : 'FAIL ') + '四层脚本语法与依赖')

/* ---------- 2. 单词表一致性 ---------- */
// 只比对「街道」单词。室内词（zone: 'interior'）不在 ArkTS 侧的校验表里，
// 它们由 city-interior.js 单独管理。
const streetBlock = data.split('var indoorObjects =')[0]
const dataIds = [...streetBlock.matchAll(/\{ id: '([^']+)', word:/g)].map((m) => m[1])
const valBlock = validation.split('export const CITY_OBJECT_IDS: string[] = [')[1].split(']')[0]
const valIds = [...valBlock.matchAll(/'([^']+)'/g)].map((m) => m[1])
const uniqueData = new Set(dataIds).size === dataIds.length
const sameWords = dataIds.length === valIds.length && dataIds.every((id) => valIds.includes(id))
console.log((dataIds.length === 50 && uniqueData && sameWords ? 'PASS ' : 'FAIL ') +
  `单词表一致（scene ${dataIds.length} 个 / 校验层 ${valIds.length} 个）`)

/* ---------- 3. 场景规模 ---------- */
function loadScene() {
  vm.runInThisContext(read('city-data.js'))
  vm.runInThisContext(read('city-models.js'))
  return global.WordCityModels.buildWorld()
}
let built = null
try {
  built = loadScene()
} catch (e) {
  console.log('FAIL 场景构建失败: ' + e.message)
}
let meshes = 0, instanced = 0, triangles = 0, materials = new Set()
if (built) {
  built.root.traverse((o) => {
    if (!o.isMesh) return
    meshes++
    if (o.isInstancedMesh) instanced++
    const geo = o.geometry
    if (!geo) return
    const count = geo.index ? geo.index.count / 3 : (geo.attributes.position ? geo.attributes.position.count / 3 : 0)
    triangles += count * (o.isInstancedMesh ? o.count : 1)
    if (o.material) materials.add(o.material.uuid)
  })
  console.log('INFO meshes=' + meshes + ' instanced=' + instanced +
    ' triangles=' + Math.round(triangles) + ' materials=' + materials.size)
  // 预算：静态场景 ≤ 1250 网格。相比加天气系统前的 1191，新增约 24：
  // 水洼/雪堆/屋顶雪盖已改 InstancedMesh，增量来自街边雨伞（5 把 × 4 件）。
  console.log((meshes <= 1250 ? 'PASS ' : 'WARN ') + '静态网格数在移动端区间（≤ 1250）')
  console.log((triangles < 90000 ? 'PASS ' : 'WARN ') + '三角形数在移动端区间（< 90k）')
  // 场景层只注册静态对象；交通类单词（9 个移动载具，含河上的 boat）由 city-scene.js 在 buildTraffic 里补注册
  const vehicleBlock = data.split('vehicles: [')[1].split('],')[0]
  const vehicleWords = [...vehicleBlock.matchAll(/word: '([a-z_]+)'/g)].map((m) => m[1])
  const totalWords = built.words.size + vehicleWords.length
  console.log('INFO 静态单词 ' + built.words.size + ' + 载具单词 ' + vehicleWords.length +
    '（' + vehicleWords.join(', ') + '）= ' + totalWords)
  console.log((totalWords === 50 ? 'PASS ' : 'FAIL ') + `可点击单词注册数 ${totalWords}/50`)
}

/* ---------- 4. 关键实现是否在位 ---------- */
const checks = [
  ['建筑夜景窗户（emissiveMap）', /emissiveMap:\s*texPair\.glow/.test(models) && /props\.windows\[wi\]\.emissiveIntensity/.test(scene)],
  ['车灯夜间提亮', /headlampMats/.test(models) && /HEAD_NIGHT/.test(scene)],
  ['星空与月亮', /props\.stars/.test(models) && /moonSprite/.test(scene) && /radial-gradient/.test(css)],
  ['静态合批（mergeStatic）', /function mergeStatic/.test(models) && /mergeStatic\(staticBag\)/.test(models)],
  ['工地塔吊', /constructionSite/.test(models) && /craneJib/.test(scene)],
  ['停车场', /parkingLot/.test(models)],
  ['河边步道', /riverWalk/.test(models)],
  ['远景天际线', /skylineRing/.test(models) && /distantFacade/.test(models)],
  ['学校操场跑道', /RingGeometry\(5\.2, 7\.0/.test(models)],
  ['公园小径与栅栏', /parkDetails/.test(models) && /fenceRun/.test(models)],
  ['广场鸽子与猫', /pigeons/.test(models) && /wallCat/.test(models)],
  ['自动巡游 API', /S\.startTour/.test(scene) && /S\.stopTour/.test(scene) && /updateTour/.test(scene)],

  /* ---- 车辆跟车与防穿模 ---- */
  ['跟车逻辑存在', /function followSpeed/.test(scene) && /function leaderOf/.test(scene)],
  ['按车道分组避免全量比较', /function buildLaneGroups/.test(scene) && /var k = laneKey\(v\)/.test(scene)],
  ['每帧重排车道顺序', /每帧重排各车道的先后顺序/.test(scene) && /buildLaneGroups\(\);\s*\n\s*\n\s*for \(var i = 0; i < vehicles\.length/.test(scene)],
  ['前车判断用切向投影而非 u 差', /ahead = \(pb\.x - pa\.x\) \* tan\.x/.test(scene) && /if \(ahead <= 0\) \{ continue; \}/.test(scene)],
  ['硬性防穿模兜底', /硬性防穿模/.test(scene) && /shortfall/.test(scene)],
  ['车辆尺寸表含宽度', /var VEHICLE_LENGTH = \{/.test(scene) && /var VEHICLE_WIDTH = \{/.test(scene)],
  ['两轮车独立车道偏移', /var BIKE_LANE_OFFSET = 2\.9/.test(scene) && /function laneOffsetOf/.test(scene)],
  ['接缝处用稳定切向', /function stableTangent/.test(scene) && /稳定切向/.test(scene)],
  ['长车跟两轮车更保守', /var followDist = myLen >= 7 \? 12 : 9/.test(scene)],
  ['两轮车不参与硬性拉回（防死锁）', /isBikeType\(hardLead\.v\.cfg\.type\) && !isBikeType\(v\.cfg\.type\)/.test(scene)],
  ['调试推进接口（可自动化验证）', /S\.__debugStepTraffic = function/.test(scene) && /S\.__debugVehicles = function/.test(scene)],
  ['巡游按钮与 UI 同步', /id="btnTour"/.test(html) && /syncTourUI/.test(app)],
  ['深链参数', /applyDeepLink/.test(app) && /onboard=0/.test(app)],
  ['噪点质感贴图', /noiseTexture\('#FFFFFF'/.test(models) || /noiseTexture\(P\.road/.test(models)],
  ['接触阴影', /contactShadows/.test(models)],
  ['蝴蝶动画', /butterflies/.test(scene)],
  ['电线杆与电线', /powerLines/.test(models)],
  ['市集摊位', /marketStalls/.test(models)],
  ['云层不再遮挡街道', /cloudSpots = \[\s*\n\s*\[-84, 128/.test(models)],

  /* ---- 昼夜时间系统 ---- */
  ['时间关键帧（6 段插值）', /var SKY_KEYS = \[/.test(scene) && /function sampleSky/.test(scene) && (scene.match(/\{ \/\/ \d\d:\d\d /g) || []).length >= 6],
  ['时间采样 smoothstep 插值', /smoothstep/.test(scene) || /t \* t \* \(3 - 2 \* t\)/.test(scene)],
  ['setHour / getHour API', /S\.setHour = function/.test(scene) && /S\.getHour = function/.test(scene)],
  ['时间流动 setTimeFlow', /S\.setTimeFlow/.test(scene) && /S\.isTimeFlowing/.test(scene) && /updateTime\(dt\)/.test(scene)],
  ['旧 setNight 接口兼容', /S\.setNight = function[\s\S]{0,120}S\.setHour/.test(scene) && /setNight: function \(on\)/.test(app)],
  ['太阳/月亮随时辰移动', /props\.sunSprite\.group\.position\.set/.test(scene) && /moonAngle/.test(scene)],
  ['时段名 phaseOf', /function phaseOf/.test(scene) && /S\.getPhase/.test(scene)],
  ['CSS 昼夜变量驱动', /--night-op/.test(css) && /--warm-op/.test(css) && /setProperty\('--night-op'/.test(app)],

  /* ---- 天气系统 ---- */
  ['天气三态 API', /WEATHER = \{ CLEAR: 0, RAIN: 1, SNOW: 2 \}/.test(scene) && /S\.setWeather = function/.test(scene) && /S\.getWeather/.test(scene)],
  ['雨丝 LineSegments 粒子', /RAIN_COUNT/.test(scene) && /LineSegments/.test(scene) && /function buildRain/.test(scene)],
  ['雪花 Points 粒子', /SNOW_COUNT/.test(scene) && /function buildSnow/.test(scene) && /snowFlakes/.test(scene)],
  ['雨雪跟随镜头中心', /weatherCenter\.set\(cam\.target\.x, 0, cam\.target\.z\)/.test(scene)],
  ['天气影响光照与雾', /function applyWeatherLook/.test(scene) && /RAIN_SKY/.test(scene) && /SNOW_SKY/.test(scene)],
  ['雨天地面/路面变暗', /GRASS_RAIN/.test(scene) && /ROAD_RAIN/.test(scene) && /props\.groundMats/.test(scene)],
  ['雪天屋顶积雪', /M\.snowMat/.test(models) && /worldSnowCaps/.test(models) && /props\.snowCaps/.test(scene)],
  ['雨天水洼', /props\.puddleMesh/.test(models) && /props\.puddleMesh\.visible/.test(scene)],
  ['雨伞工厂与挂载', /M\.makeUmbrella/.test(models) && /function attachUmbrellasToPeople/.test(scene)],
  ['雨雪天车灯也亮', /Math\.max\(t, rainAmt \* 0\.55, snowAmt \* 0\.42\)/.test(scene)],
  ['天气 UI 三态按钮', /data-weather="rain"/.test(html) && /data-weather="snow"/.test(html) && /function setWeather\(kind/.test(app)],

  /* ---- 单词寻宝 ---- */
  ['寻宝模块存在且可初始化', /global\.WordCityHunt = \{/.test(hunt) && /init: init/.test(hunt) && /start: start/.test(hunt)],
  ['寻宝一轮 5 个词', /var ROUND_SIZE = 5/.test(hunt) && /function pickRound/.test(hunt)],
  ['分区轮换出题', /ZONE_ORDER = \['main_street', 'park_zone', 'school_zone', 'hospital_zone'\]/.test(hunt) && /zoneCursor/.test(hunt)],
  ['点错不扣分只提示', /function onWrong/.test(hunt) && /点错不该扣分/.test(hunt)],
  ['三级递进提示', /function escalateHint/.test(hunt) && /hintLevel >= 3/.test(hunt) && /hintLevel === 1/.test(hunt) && /hintLevel === 2/.test(hunt)],
  ['卡住自动给提示', /AUTO_HINT_1/.test(hunt) && /AUTO_HINT_2/.test(hunt) && /idle > AUTO_HINT_1/.test(hunt)],
  ['找到时爆闪反馈', /S\.burstAt = function/.test(scene) && /function ensureBurst/.test(scene)],
  ['寻宝光柱标记', /S\.setHuntTarget = function/.test(scene) && /function updateHunt/.test(scene)],
  ['寻宝时隐藏英文标签', /huntPrevLabels = state\.labelsOn/.test(app) && /setLabels\(false, false\)/.test(app)],
  ['寻宝时点击交给游戏判定', /huntActive\(\) && window\.WordCityHunt\.handlePick/.test(app)],
  ['寻宝 HUD 与结算面板', /id="hunt"/.test(html) && /id="huntResult"/.test(html) && /id="huntDots"/.test(html)],
  ['寻宝入口按钮', /id="btnHunt"/.test(html) && /btn-hunt/.test(cssHunt || '')],
  ['寻宝样式独立文件', /\.hunt-hud/.test(cssHunt || '') && /\.hres-card/.test(cssHunt || '')],
  ['寻宝时收起时间条与工具', /body\.is-hunting \.sky-bar/.test(cssHunt || '') && /classList\.toggle\('is-hunting'/.test(hunt)],

  /* ---- 屏幕外方向箭头 ---- */
  ['方向箭头 DOM', /id="huntPointer"/.test(html) && /hp-arrow/.test(html) && /id="huntPointerDist"/.test(html)],
  ['箭头仅在第 3 级提示出现', /hintLevel < 3\) \{\s*\n\s*hidePointer/.test(hunt)],
  ['目标在画面内时隐藏箭头', /if \(pos\.onScreen\) \{ hidePointer\(\); return; \}/.test(hunt)],
  ['边缘投射避开 HUD 与线索卡', /padTop = narrow \? 74 : 122/.test(hunt) && /padBottom = narrow \? 128 : 186/.test(hunt)],
  ['相机背后镜像翻转', /tmpV3\.copy\(tmpCenter\)\.applyMatrix4\(camera\.matrixWorldInverse\)/.test(scene) && /if \(behind\) \{\s*\n\s*nx = -nx/.test(scene)],
  ['箭头显示距离与近处变色', /distanceToWord/.test(hunt) && /is-near/.test(cssHunt || '')],
  ['箭头呼吸光晕动画', /hp-breathe/.test(cssHunt || '')],
  ['寻宝深链参数', /huntQ === '1'/.test(app) && /enterHuntMode\(\); \}, 420\)/.test(app)],
  ['竖屏分区镜头自动后退', /narrowBoost/.test(scene)],
  ['云层高于常规相机高度', /\[-84, 128, -70\]/.test(models)],

  /* ---- 建筑内部 ---- */
  ['室内模块存在', /global\.WordCityInterior = I/.test(interior) && /I\.enter = function/.test(interior)],
  ['两栋试点室内定义', /supermarket: \{[\s\S]{0,600}?library: \{/.test(data)],
  ['室内专属单词含 interior 归属', /interior: 'supermarket'/.test(data) && /interior: 'library'/.test(data)],
  ['indoor 分类已注册', /id: 'indoor'/.test(data) && /label: '室内'/.test(data)],
  ['超市建模含货架收银车篮', /function buildSupermarket/.test(interior) && /shelfUnit\(/.test(interior) && /shoppingCart\(/.test(interior)],
  ['图书馆建模含书架书桌', /function buildLibrary/.test(interior) && /bookShelf\(/.test(interior) && /readingDesk\(/.test(interior)],
  ['进出时街道根节点显隐', /ctx\.worldRoot\.visible = false/.test(interior) && /ctx\.worldRoot\.visible = true/.test(interior)],
  ['门口遮挡处理', /function addBackdrop/.test(interior) && /盖住相机上方的视野/.test(interior)],
  ['室内镜头按房间尺寸自适应', /eyeZ = Math\.min\(halfD/.test(scene) && /eyeY = Math\.min\(def\.h/.test(scene)],
  ['室内相机限制单独收紧', /camLimits\.minRadius = Math\.max\(7, diag/.test(scene)],
  ['退出恢复原镜头与限制', /savedCamLimits/.test(scene) && /savedCam = \{/.test(scene)],
  ['室内词拾取盒挂自身', /拾取盒挂在物件自身下/.test(scene)],
  ['标签按室内外隔离', /if \(item\.interior !== insideId\) \{ return; \}/.test(scene)],
  ['进出后立即刷新标签', /if \(labelsEnabled\) \{ emitLabels\(\); \}/.test(scene)],
  ['深链直接进屋', /insideQ && window\.WordCityScene/.test(app) && /enterInterior\(insideQ, true\)/.test(app)],
  ['词汇表按所在位置过滤', /o\.interior === interior\.id/.test(app)],
  ['室内 UI 元素齐全', /id="interiorBar"/.test(html) && /id="interiorBack"/.test(html) && /id="wcEnter"/.test(html)],
  ['室内样式独立文件', /\.interior-bar/.test(cssInterior || '') && /\.wc-enter/.test(cssInterior || '')]
]

let failed = 0
for (const [name, ok] of checks) {
  console.log((ok ? 'PASS ' : 'FAIL ') + name)
  if (!ok) failed++
}

const totalFail = failed + (syntaxOk ? 0 : 1) + (built ? 0 : 1)
console.log(totalFail ? `\n${totalFail} 项未通过` : '\n全部检查通过')
process.exit(totalFail ? 1 : 0)
