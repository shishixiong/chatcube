// 无头集成测试：jsdom + 仓库自带的 three.min.js，跑真实 index.html / room-scene / room-app。
// WebGLRenderer 用桩替换（只保留 setSize / render / setAnimationLoop 等接口），其余（几何、射线拾取、
// 碰撞盒）全是真的，所以相机、碰撞、标签分档、方位语音都能在这里验证。
const { JSDOM, VirtualConsole } = require('jsdom');
const fs = require('fs');
const path = require('path');

const ROOT = process.argv[2] || path.resolve(__dirname, '../..');
const RAW = path.join(ROOT, 'entry/src/main/resources/rawfile/room3d');
const read = (p) => fs.readFileSync(path.join(RAW, p), 'utf8');

const results = [];
function check(name, fn) {
  try {
    const detail = fn();
    results.push({ name, ok: true, detail });
    console.log('PASS ' + name + (detail ? '  — ' + detail : ''));
  } catch (error) {
    results.push({ name, ok: false, detail: error.message });
    console.log('FAIL ' + name + '  — ' + error.message);
  }
}
function assert(cond, message) {
  if (!cond) throw new Error(message);
}

const html = read('index.html');
const virtualConsole = new VirtualConsole();
virtualConsole.on('jsdomError', (error) => {
  console.log('  [page error] ' + (error && error.message));
  if (error && error.detail) console.log('  [page detail] ' + String(error.detail.stack || error.detail));
});
const dom = new JSDOM(html, {
  runScripts: 'outside-only',
  pretendToBeVisual: true,
  url: 'https://localhost/room3d/',
  virtualConsole
});
const { window } = dom;
const { document } = window;

// ---------- 环境补齐 ----------
let clock = 10_000;
Object.defineProperty(window.performance, 'now', { value: () => clock });

window.devicePixelRatio = 2;
Object.defineProperty(window, 'innerWidth', { value: 390, configurable: true });
Object.defineProperty(window, 'innerHeight', { value: 844, configurable: true });

const mediaMap = {
  '(prefers-reduced-motion: reduce)': false,
  '(min-width: 700px)': false
};
window.matchMedia = (query) => ({
  matches: Boolean(mediaMap[query]),
  media: query,
  addListener() {},
  removeListener() {},
  addEventListener() {},
  removeEventListener() {},
  dispatchEvent() { return false; }
});
window.ResizeObserver = class {
  observe() {}
  unobserve() {}
  disconnect() {}
};

// 画布 2D：room-models 用它画窗帘/画框上的小图案，只要不报错就够了
const gradient = { addColorStop() {} };
const ctx2d = new Proxy(
  {
    measureText: (text) => ({ width: String(text).length * 7 }),
    createLinearGradient: () => gradient,
    createRadialGradient: () => gradient
  },
  {
    get(target, key) {
      if (key in target) return target[key];
      return () => {};
    },
    set(target, key, value) {
      target[key] = value;
      return true;
    }
  }
);
window.HTMLCanvasElement.prototype.getContext = function (kind) {
  if (kind === '2d') return ctx2d;
  return null;
};

// jsdom 没有 pointer capture 语义，直接给空实现，别让 setPointerCapture 抛错打断手势
window.Element.prototype.setPointerCapture = function () {};
window.Element.prototype.releasePointerCapture = function () {};

// 布局：jsdom 没有排版，按手机竖屏给一套固定尺寸
const stageSize = { width: 390, height: 600 };
window.Element.prototype.getBoundingClientRect = function () {
  if (this.id === 'stage' || this.id === 'scene-canvas') {
    return { x: 0, y: 0, left: 0, top: 0, width: stageSize.width, height: stageSize.height, right: stageSize.width, bottom: stageSize.height };
  }
  if (this.classList && this.classList.contains('scene-label')) {
    return { x: 120, y: 200, left: 120, top: 200, width: 64, height: 24, right: 184, bottom: 224 };
  }
  return { x: 0, y: 0, left: 0, top: 0, width: 0, height: 0, right: 0, bottom: 0 };
};

// 原生桥：记录 Web 说过的每一句话
const bridgeCalls = [];
window.RoomNativeBridge = {
  speak(text, zh) { bridgeCalls.push({ name: 'speak', text: String(text), zh: String(zh) }); return 'true'; },
  stopSpeak() { bridgeCalls.push({ name: 'stopSpeak' }); return 'true'; },
  onReady() { bridgeCalls.push({ name: 'onReady' }); return 'true'; },
  onSelect(id, word) { bridgeCalls.push({ name: 'onSelect', id, word }); return 'true'; },
  onProgress(ids) { bridgeCalls.push({ name: 'onProgress', ids }); return 'true'; },
  onMode(mode) { bridgeCalls.push({ name: 'onMode', mode }); return 'true'; }
};

// ---------- 加载 three + 场景脚本 ----------
const run = (code) => window.eval(code);
run(read('assets/vendor/three.min.js'));
assert(window.THREE, 'three.js 没有挂到 window 上');

// 渲染器桩：几何/相机/阴影全用真的，只把 GPU 那一段替换掉
let frameLoop = null;
let renderCount = 0;
const FakeRenderer = class {
  constructor(options) {
    this.domElement = options.canvas;
    this.shadowMap = { enabled: false, type: 0 };
    this.outputColorSpace = 0;
    this.toneMapping = 0;
    this.toneMappingExposure = 1;
  }
  setClearColor() {}
  setPixelRatio() {}
  setSize() {}
  render() { renderCount += 1; }
  setAnimationLoop(callback) { frameLoop = callback; }
  dispose() {}
};
// three 的导出是 getter-only 且不可重定义（UMD 打包），只能换一个浅克隆的 THREE
const realThree = window.THREE;
const patchedThree = {};
for (const key of Object.getOwnPropertyNames(realThree)) {
  if (key === 'WebGLRenderer') continue;
  Object.defineProperty(patchedThree, key, Object.getOwnPropertyDescriptor(realThree, key));
}
Object.defineProperty(patchedThree, 'WebGLRenderer', { value: FakeRenderer, writable: true, configurable: true });
Object.defineProperty(window, 'THREE', { value: patchedThree, writable: true, configurable: true });

for (const file of [
  'assets/scene-data.js',
  'assets/room-layout.js',
  'assets/walk-camera.js',
  'assets/room-models.js',
  'assets/wall-culling.js',
  'assets/room-scene.js'
]) {
  run(read(file));
}
assert(window.RoomExperience, 'RoomExperience 没有注册');

// 探针：room-app 把 RoomExperience 关在闭包里，测试需要相机/碰撞盒，就给构造函数套一层
window.__rooms = [];
const RealRoomExperience = window.RoomExperience;
window.RoomExperience = new Proxy(RealRoomExperience, {
  construct(target, argsList) {
    const instance = Reflect.construct(target, argsList);
    instance.canvas.__scene = instance;
    window.__rooms.push(instance);
    return instance;
  }
});

run(read('assets/room-app.js'));
assert(window.WordRoomApp, 'WordRoomApp 没有启动');

// 启动 app：jsdom 解析完会自己发 DOMContentLoaded，不能手动补发。
// 补发会让 boot 跑两遍：bindUI 绑两次，按钮点一下切两次 = 看起来「点了没反应」。

const app = window.WordRoomApp;
const scene = () => window.__room || null;

function tick(ms) {
  clock += ms;
  if (frameLoop) frameLoop();
}
function frames(count, dt = 16) {
  for (let i = 0; i < count; i += 1) tick(dt);
}
function sleep(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }
function waitFor(predicate, timeout) {
  const started = Date.now();
  return new Promise((resolve) => {
    const poll = () => {
      if (predicate() || Date.now() - started > timeout) resolve();
      else setTimeout(poll, 10);
    };
    poll();
  });
}
function key(type, keyName) {
  document.dispatchEvent(new window.KeyboardEvent(type, { key: keyName, bubbles: true, cancelable: true }));
}
function pointer(type, x, y, extra = {}) {
  const event = new window.MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: x,
    clientY: y,
    button: 0
  });
  Object.defineProperty(event, 'pointerId', { value: extra.pointerId || 1 });
  Object.defineProperty(event, 'pointerType', { value: extra.pointerType || 'touch' });
  Object.defineProperty(event, 'isPrimary', { value: true });
  return event;
}

// room-app 通过闭包持有 room，测试里拿不到，用 onMode 回调之外的公开 API 观察。
// 为了验证相机本身，从 canvas 上找 RoomExperience：room-app 没有把它挂到 window，这里从
// WordRoomApp 的方法返回值反推（getWalkRange 等），相机数值则通过 canvas 的 __scene 引用。
// room-scene 里 this.canvas 就是 #scene-canvas，给它挂一个反向引用。
function attachSceneProbe() {
  const canvas = document.getElementById('scene-canvas');
  const originalAdd = canvas.addEventListener.bind(canvas);
  canvas.addEventListener = (type, handler, opts) => {
    canvas.__handlers = canvas.__handlers || {};
    (canvas.__handlers[type] = canvas.__handlers[type] || []).push(handler);
    return originalAdd(type, handler, opts);
  };
}
attachSceneProbe();

(async () => {
  await waitFor(() => window.__rooms.length > 0, 2000);
  await sleep(80);

  // 场景只有一个实例：多一个就说明 boot 跑了两次，后面的按钮测试全部不可信
  check('场景只初始化一次（bindUI 不会重复绑定）', () => {
    assert(window.__rooms.length === 1, 'RoomExperience 建了 ' + window.__rooms.length + ' 个');
  });

  const canvas = document.getElementById('scene-canvas');
  const walkToggle = document.getElementById('walkToggle');
  const labelToggle = document.getElementById('labelToggle');

  check('场景启动并回调 onReady', () => {
    assert(bridgeCalls.some((call) => call.name === 'onReady'), '没有 onReady');
    assert(canvas.__scene, '场景实例没有建立');
    assert(canvas.__scene.objects.length > 60, '物品数量不对：' + canvas.__scene.objects.length);
  });

  check('全屋视图默认上帝视角，走进去按钮隐藏', () => {
    assert(app.getMode() === 'orbit', 'mode=' + app.getMode());
    assert(walkToggle.hidden === true, 'walkToggle.hidden=' + walkToggle.hidden);
  });

  check('切换到客餐厅后出现走进去按钮', () => {
    app.setRoom('main');
    assert(document.querySelector('.room-tab[data-room="main"]').classList.contains('is-active'), '房间标签没切');
    assert(walkToggle.hidden === false, 'walkToggle 仍然隐藏');
    assert(labelToggle.disabled === false, '标签开关仍被禁用');
  });

  check('全屋视图拒绝进入第一人称', () => {
    app.setRoom('overview');
    const mode = app.setMode('walk');
    assert(mode === 'orbit', 'overview 竟然能走：' + mode);
    assert(app.getMode() === 'orbit', 'getMode 不是 orbit');
    app.setRoom('main');
  });

  let stage;
  check('单间房进入第一人称，视角落在出生点', () => {
    const mode = app.setMode('walk');
    assert(mode === 'walk', 'mode=' + mode);
    assert(walkToggle.getAttribute('aria-pressed') === 'true', '按钮没反映状态');
    assert(document.getElementById('walkControls').hidden === false, '走路控件没出现');
    assert(document.getElementById('resetView').hidden === true, '重置视角没让位');
    // 相机位置只能通过 WebGL 帧确认：跑一帧再读相机
    frames(2);
    assert(renderCount > 0, '没有渲染');
    // RoomExperience 没有导出，借 canvas 上的 raycaster 结果反推不现实；
    // 用 walk-camera 的公开状态替代：getWalkRange / getMode 已验证，
    // 相机位置交给后面的「按住前进会移动」来间接验证。
    return 'mode=' + mode;
  });

  check('走进去时英文标签按「看见多远」出现在视野里', () => {
    frames(2);
    const anchors = canvas.__scene.getLabelAnchors();
    const visible = anchors.filter((a) => a.visible && a.distance !== null);
    assert(visible.length > 0, '视野里一个锚点都没有');
    const layer = document.getElementById('label-layer');
    assert(layer.hidden === false, '标签层被藏起来了');
    const shown = Array.from(document.querySelectorAll('.scene-label')).filter(
      (label) => label.style.visibility === 'visible'
    );
    assert(shown.length > 0, '一个标签都没摆出来（视野内 ' + visible.length + ' 个锚点）');
    return visible.length + ' 个锚点 / ' + shown.length + ' 个标签';
  });

  check('拖动环顾改变朝向（世界坐标方位随之变化）', () => {
    const before = readNearestDirection();
    canvas.dispatchEvent(pointer('pointerdown', 200, 300));
    for (let i = 1; i <= 10; i += 1) {
      canvas.dispatchEvent(pointer('pointermove', 200 + i * 18, 300));
      tick(16);
    }
    canvas.dispatchEvent(pointer('pointerup', 380, 300));
    frames(20);
    const after = readNearestDirection();
    assert(before !== null && after !== null, '拿不到方位');
    assert(before !== after, '转了 180° 方位没变：' + before + ' / ' + after);
    return before + ' → ' + after;
  });

  check('按住前进会移动，松手会停', () => {
    const p1 = cameraPosition();
    document.getElementById('walkForward').dispatchEvent(pointer('pointerdown', 0, 0, { pointerType: 'mouse' }));
    frames(60);
    document.getElementById('walkForward').dispatchEvent(pointer('pointerup', 0, 0, { pointerType: 'mouse' }));
    frames(10);
    const p2 = cameraPosition();
    const moved = Math.hypot(p2.x - p1.x, p2.z - p1.z);
    assert(moved > 0.5, '走了 ' + moved.toFixed(2) + ' 米，太少了');
    frames(30);
    const p3 = cameraPosition();
    const drift = Math.hypot(p3.x - p2.x, p3.z - p2.z);
    assert(drift < 0.05, '松手后还在漂：' + drift.toFixed(3));
    return moved.toFixed(2) + ' m';
  });

  check('撞墙会停住，不会走出房间', () => {
    key('keydown', 'w');
    frames(240); // 约 4 秒
    key('keyup', 'w');
    frames(5);
    const p = cameraPosition();
    const bounds = walkBounds();
    const inside =
      p.x > bounds.minX && p.x < bounds.maxX && p.z > bounds.minZ && p.z < bounds.maxZ;
    assert(inside, `相机跑到房间外 (${p.x.toFixed(2)}, ${p.z.toFixed(2)}) bounds=${JSON.stringify(bounds)}`);
    return `stop at (${p.x.toFixed(2)}, ${p.z.toFixed(2)})`;
  });

  check('不会穿进家具（脚底始终在家具盒外）', () => {
    const walker = walkerRef();
    const p = cameraPosition();
    let inside = null;
    walker.obstacles.forEach((o) => {
      if (p.x > o.minX - 0.2 && p.x < o.maxX + 0.2 && p.z > o.minZ - 0.2 && p.z < o.maxZ + 0.2) {
        inside = o;
      }
    });
    assert(!inside, '站在家具里：' + JSON.stringify(inside));
    return walker.obstacles.length + ' 个碰撞盒';
  });

  check('看见多远分档：1.5m 比 8m 少', () => {
    const near = countVisibleLabels(1.5);
    const far = countVisibleLabels(8);
    assert(near === 0, '1.5m 还看得见 ' + near + ' 个，应该全藏起来');
    assert(far > near, `1.5m=${near} 8m=${far}`);
    return `1.5m ${near} 个 / 8m ${far} 个`;
  });

  check('站定后报方位（「左手边」「正前方」之类）', () => {
    bridgeCalls.length = 0;
    frames(60); // 站定 0.45s
    const spoken = bridgeCalls.filter((call) => call.name === 'speak').map((call) => call.text);
    const hit = spoken.find((text) => /正前方|左前方|右前方|左手边|右手边|身后|就在手边|米外|房间另一头/.test(text));
    assert(hit, '没有方位播报，实际：' + JSON.stringify(spoken));
    return hit;
  });

  check('关掉方位提示后站定不再说话', () => {
    app.setWalkHint(false);
    bridgeCalls.length = 0;
    // 先走两步再停，确保触发 settle
    key('keydown', 'a');
    frames(20);
    key('keyup', 'a');
    frames(90);
    const spoken = bridgeCalls.filter((call) => call.name === 'speak');
    assert(spoken.length === 0, '仍然播报：' + JSON.stringify(spoken.map((s) => s.text)));
    app.setWalkHint(true);
  });

  check('走进去时点物品仍然打开单词卡', () => {
    bridgeCalls.length = 0;
    // 回到出生点，确保视野里有家具（前面的撞墙测试可能正对着墙）
    app.setMode('orbit');
    app.setMode('walk');
    frames(5);
    const target = findPickablePoint();
    canvas.dispatchEvent(pointer('pointerdown', target.x, target.y));
    canvas.dispatchEvent(pointer('pointerup', target.x, target.y));
    frames(3);
    const selected = bridgeCalls.find((call) => call.name === 'onSelect');
    assert(selected, '轻点没有选中物品');
    assert(document.getElementById('wordView').hidden === false, '单词卡没打开');
    return selected.word;
  });

  check('走路时换房间直接落在新房间', () => {
    app.setRoom('child');
    frames(2);
    const p = cameraPosition();
    const bounds = walkBounds();
    assert(app.getMode() === 'walk', '换房后不在 walk：' + app.getMode());
    assert(p.x > bounds.minX && p.x < bounds.maxX && p.z > bounds.minZ && p.z < bounds.maxZ,
      `新房间落点越界 (${p.x.toFixed(2)}, ${p.z.toFixed(2)}) ${JSON.stringify(bounds)}`);
    return `child (${p.x.toFixed(2)}, ${p.z.toFixed(2)})`;
  });

  check('回到全屋自动退回上帝视角', () => {
    app.setRoom('overview');
    frames(2);
    assert(app.getMode() === 'orbit', 'mode=' + app.getMode());
    assert(walkToggle.hidden === true, '按钮没隐藏');
    return 'orbit';
  });

  check('原生 setMode 在换房后补进第一人称（pendingWalk）', () => {
    app.setRoom('overview');
    const first = app.setMode('walk');
    assert(first === 'orbit', 'overview 应该拒绝');
    app.setRoom('master');
    frames(2);
    const mode = app.getMode();
    assert(mode === 'walk', '换房后没有自动走进去：' + mode);
    return mode;
  });

  check('回到上帝视角后相机取景复位', () => {
    app.setMode('orbit');
    frames(30);
    assert(app.getMode() === 'orbit', 'mode=' + app.getMode());
    assert(document.getElementById('walkControls').hidden === true, '控件没收起');
    assert(document.getElementById('resetView').hidden === false, '重置视角没回来');
    return 'orbit';
  });

  // ---------- 采样工具：利用 canvas 上注册的事件和 walker 反查 ----------
  // room-app 闭包里的 room 拿不到，但 RoomExperience 把 canvas 存成了 this.canvas；
  // 用事件监听器闭包也取不到。改为：从 window.WordRoomApp 的公开方法 + DOM 属性断言相机行为，
  // 相机数值通过 canvas 上 room-scene 自己挂的 __sceneProbe（下面由 patch 之外的方式注入）——
  // 这里退一步：用 walk-camera 单元测试验证数值，集成测试只验证模式与业务。

  check('「走进去 / 回到全景」文案跟着视角翻', () => {
    app.setRoom('main');
    app.setMode('orbit');
    frames(2);
    const toggle = document.getElementById('walkToggle');
    const label = () => toggle.querySelector('.walk-toggle-copy span').textContent;
    const orbitText = label();
    app.setMode('walk');
    frames(2);
    const walkText = label();
    app.setMode('orbit');
    frames(2);
    const backText = label();
    assert(orbitText === '走进去', '上帝视角文案：' + orbitText);
    assert(walkText === '回到全景', '第一人称文案：' + walkText);
    assert(backText === '走进去', '退出后没还原：' + backText);
    return orbitText + ' → ' + walkText + ' → ' + backText;
  });

  check('开始带逛/答题会自动退出第一人称', () => {
    app.setRoom('main');
    app.setMode('walk');
    frames(2);
    assert(app.getMode() === 'walk', '前置：没进第一人称');
    app.setLessonMode(true);
    frames(2);
    assert(app.getMode() === 'orbit', '上带逛后仍在第一人称');
    app.setLessonMode(false);
    return 'walk → orbit';
  });

  check('四间房出生点都在可行走区域、不压家具', () => {
    const rooms = ['main', 'child', 'master', 'balcony'];
    const report = [];
    rooms.forEach((id) => {
      app.setMode('orbit');
      app.setRoom(id);
      app.setMode('walk');
      frames(3);
      const walker = canvas.__scene.walker;
      const p = cameraPosition();
      const b = walker.bounds;
      assert(p.x > b.minX && p.x < b.maxX && p.z > b.minZ && p.z < b.maxZ,
        id + ' 出生点越界 (' + p.x.toFixed(2) + ', ' + p.z.toFixed(2) + ')');
      walker.obstacles.forEach((o) => {
        assert(!(p.x > o.minX - 0.1 && p.x < o.maxX + 0.1 && p.z > o.minZ - 0.1 && p.z < o.maxZ + 0.1),
          id + ' 出生点压在家具里 ' + JSON.stringify(o));
      });
      assert(Math.abs(p.y - 1.25) < 0.02, id + ' 视线高度不对 ' + p.y.toFixed(2));
      report.push(id + '(' + p.x.toFixed(1) + ',' + p.z.toFixed(1) + ')');
    });
    return report.join(' ');
  });

  check('WASD 四个方向都能走，斜着走不会更快', () => {
    const walk = (keys) => {
      app.setMode('orbit');
      app.setRoom('main');
      app.setMode('walk');
      frames(3);
      app.setWalkRange(8);
      const from = cameraPosition();
      keys.forEach((k) => key('keydown', k));
      frames(30); // 固定 30 帧 × 16ms = 0.48s，比按墙钟跑帧数稳定
      keys.forEach((k) => key('keyup', k));
      const to = cameraPosition();
      frames(2);
      return Math.hypot(to.x - from.x, to.z - from.z);
    };
    const forward = walk(['w']);
    const back = walk(['s']);
    const left = walk(['a']);
    const diagonal = walk(['w', 'd']);
    // 0.95 m/s × 0.48s ≈ 0.46m；留 20% 余量给出生点附近可能的推挤
    assert(forward > 0.35 && forward < 0.6, 'W 距离不对：' + forward.toFixed(2));
    assert(back > 0.35, 'S 没退：' + back.toFixed(2));
    assert(left > 0.35, 'A 没平移：' + left.toFixed(2));
    // 斜向两轴各降 1/√2：合成速度应与直走相当，不能变成 1.41 倍
    assert(diagonal < forward * 1.1, '斜着走变快了：' + diagonal.toFixed(2) + ' vs ' + forward.toFixed(2));
    return ['W ' + forward.toFixed(2), 'S ' + back.toFixed(2), 'A ' + left.toFixed(2), 'WD ' + diagonal.toFixed(2)].join(' / ');
  });

  check('按住 W 时切走/切视角，回来不会自己走', () => {
    app.setRoom('main');
    app.setMode('walk');
    frames(2);
    key('keydown', 'w');
    frames(10);
    const p1 = cameraPosition();
    window.dispatchEvent(new window.Event('blur'));
    frames(10);
    const p2 = cameraPosition();
    const drifted = Math.hypot(p2.x - p1.x, p2.z - p1.z);
    key('keyup', 'w');
    assert(drifted < 0.02, '切走后还在走 ' + drifted.toFixed(2) + ' 米');

    key('keydown', 'w');
    frames(10);
    app.setMode('orbit');
    frames(2);
    app.setMode('walk');
    frames(2);
    const p3 = cameraPosition();
    frames(20);
    const p4 = cameraPosition();
    key('keyup', 'w');
    const ghost = Math.hypot(p4.x - p3.x, p4.z - p3.z);
    assert(ghost < 0.02, '重新进来后幽灵前进 ' + ghost.toFixed(2) + ' 米');
    return 'blur ' + drifted.toFixed(3) + ' / 重进 ' + ghost.toFixed(3);
  });

  check('蹲下把视线降到沙发高度，再点站起来', () => {
    app.setRoom('main');
    app.setMode('walk');
    frames(2);
    document.getElementById('walkEye').click();
    frames(40);
    const low = cameraPosition().y;
    assert(low < 0.9, '蹲下后还这么高：' + low.toFixed(2));
    document.getElementById('walkEye').click();
    frames(40);
    const high = cameraPosition().y;
    assert(high > 1.2, '站起来没恢复：' + high.toFixed(2));
    return low.toFixed(2) + ' → ' + high.toFixed(2) + ' m';
  });

  check('滚轮调节「看见多远」', () => {
    app.setWalkRange(5);
    const before = canvas.__scene.walker.targetRange;
    canvas.dispatchEvent(new window.WheelEvent('wheel', { deltaY: -100, bubbles: true, cancelable: true }));
    frames(2);
    const after = canvas.__scene.walker.targetRange;
    assert(after > before, '滚轮没调节：' + before + ' → ' + after);
    return before.toFixed(1) + ' → ' + after.toFixed(1) + ' m';
  });

  check('方位几何：6 个档位落在预期边界', () => {
    const d = window.WordRoomWalk.direction;
    const cases = [
      [0, '正前方'], [10, '正前方'], [-10, '正前方'],
      [30, '右前方'], [-30, '左前方'], [45, '右前方'],
      [60, '右手边'], [-60, '左手边'], [90, '右手边'], [-90, '左手边'],
      [135, '身后'], [-135, '身后'], [180, '身后']
    ];
    const bad = cases.filter(([angle, want]) => d((angle * Math.PI) / 180) !== want);
    assert(bad.length === 0, '边界不对：' + JSON.stringify(bad));
    return cases.length + ' 个角度';
  });

  check('方位措辞分三档，高低单独补一句', () => {
    const fake = new window.WordRoomWalk.WalkCamera(
      { camera: { position: { set() {} }, lookAt() {} }, root: { updateMatrixWorld() {} } },
      {}
    );
    fake.walk = { x: 0, y: 1.25, z: 0 };
    fake.yaw = 0;
    const near = fake.describe({ x: 0, y: 1.25, z: 0.8 }, 0);
    const middle = fake.describe({ x: 0, y: 1.25, z: 2 }, 0);
    const far = fake.describe({ x: 0, y: 1.25, z: 6 }, 0);
    const up = fake.describe({ x: 0, y: 2.6, z: 3 }, 1.35);
    const down = fake.describe({ x: 0, y: 0.05, z: 3 }, -1.2);
    assert(/就在手边/.test(near), near);
    assert(/在2米外/.test(middle), middle);
    assert(/房间另一头/.test(far), far);
    assert(/抬头/.test(up), up);
    assert(/低头/.test(down), down);
    return [near, middle, far, up, down].join(' | ');
  });

  check('标签分档：near / middle / hidden', () => {
    const tier = window.WordRoomWalk.labelTier;
    const t = [tier(4, 8), tier(5.2, 8), tier(9, 8)];
    assert(t[0] === 'near' && t[1] === 'middle' && t[2] === 'hidden', JSON.stringify(t));
    return t.join('/');
  });

  check('词汇表打开时 WASD 不会带着相机走', () => {
    app.setMode('walk');
    frames(2);
    const p1 = cameraPosition();
    document.getElementById('openGlossary').click();
    frames(2);
    key('keydown', 'w');
    frames(20);
    const p2 = cameraPosition();
    const moved = Math.hypot(p2.x - p1.x, p2.z - p1.z);
    assert(moved < 0.02, '弹层背后走了 ' + moved.toFixed(2) + ' 米');
    key('keyup', 'w');
    document.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    frames(1);
    return 'moved=' + moved.toFixed(3);
  });

  // 异步：第二次点同一件物品，等 3.2 秒补一句方位（要和刚念过的单词错开）
  try {
    app.setMode('orbit');
    app.setMode('walk');
    frames(5);
    const tap = (target) => {
      canvas.dispatchEvent(pointer('pointerdown', target.x, target.y));
      canvas.dispatchEvent(pointer('pointerup', target.x, target.y));
    };
    const target = findPickablePoint();
    tap(target);
    frames(4);
    const selected = bridgeCalls.filter((call) => call.name === 'onSelect').pop();
    bridgeCalls.length = 0;
    tap(target);
    frames(4);
    const immediate = bridgeCalls.filter((call) => call.name === 'speak').length;
    assert(immediate === 0, '第二次点击立刻说话了：' + immediate);
    await sleep(3400);
    const spoken = bridgeCalls.filter((call) => call.name === 'speak').map((call) => call.text);
    const hit = spoken.find((text) => /正前方|左前方|右前方|左手边|右手边|身后/.test(text) && /米|手边|另一头/.test(text));
    assert(hit, '3.2 秒后没补方位，实际：' + JSON.stringify(spoken));
    results.push({ name: '再点同一件，3.2 秒后补一句方位', ok: true, detail: hit });
    console.log('PASS 再点同一件，3.2 秒后补一句方位  — ' + hit + ' (' + (selected && selected.word) + ')');
  } catch (error) {
    results.push({ name: '再点同一件，3.2 秒后补一句方位', ok: false, detail: error.message });
    console.log('FAIL 再点同一件，3.2 秒后补一句方位  — ' + error.message);
  }

  console.log('\n' + (results.every((r) => r.ok) ? '✓ 集成测试全部通过' : '✗ ' + results.filter((r) => !r.ok).length + ' 项失败'));
  process.exit(results.every((r) => r.ok) ? 0 : 1);
})();

function walkerRef() {
  const canvas = document.getElementById('scene-canvas');
  return canvas.__scene && canvas.__scene.walker ? canvas.__scene.walker : window.__walker;
}
function cameraPosition() {
  const canvas = document.getElementById('scene-canvas');
  const cam = canvas.__scene && canvas.__scene.camera;
  assert(cam, '拿不到相机');
  return { x: cam.position.x, y: cam.position.y, z: cam.position.z };
}
function walkBounds() {
  const canvas = document.getElementById('scene-canvas');
  const sc = canvas.__scene;
  assert(sc && sc.walker, '拿不到 walker');
  return sc.walker.bounds;
}
function readNearestDirection() {
  const canvas = document.getElementById('scene-canvas');
  const sc = canvas.__scene;
  if (!sc || !sc.walker) return null;
  const anchors = sc.getLabelAnchors();
  let best = null;
  anchors.forEach((a) => {
    if (!a.world) return;
    if (!best || a.distance < best.distance) best = a;
  });
  if (!best) return null;
  return sc.walker.direction(sc.walker.bearing(best.world));
}
function countVisibleLabels(range) {
  // 撞墙测试之后相机会贴在墙角，先回到出生点再数，数字才有可比性
  app.setMode('orbit');
  app.setMode('walk');
  frames(3);
  app.setWalkRange(range);
  const layer = document.getElementById('label-layer');
  frames(2);
  let visible = 0;
  layer.querySelectorAll('.scene-label').forEach((label) => {
    if (label.style.visibility !== 'hidden' && label.style.opacity !== '0') visible += 1;
  });
  return visible;
}
function findPickablePoint() {
  const canvas = document.getElementById('scene-canvas');
  const sc = canvas.__scene;
  assert(sc, '拿不到场景');
  for (let y = 120; y <= 520; y += 18) {
    for (let x = 16; x <= 374; x += 18) {
      const id = sc.pickAt(x, y);
      if (id) return { x, y, id };
    }
  }
  throw new Error('屏幕上找不到任何可点物品');
}

function screenPointOfNearestObject() {
  const canvas = document.getElementById('scene-canvas');
  const sc = canvas.__scene;
  assert(sc, '拿不到场景');
  const rect = { width: stageSize.width, height: stageSize.height };
  let best = null;
  sc.getRoomObjects().forEach((group) => {
    group.traverse((node) => {
      if (!node.isMesh || !node.userData || !node.userData.isHitbox) return;
      const v = new window.THREE.Vector3();
      node.getWorldPosition(v);
      const projected = v.clone().project(sc.camera);
      if (projected.z < -1 || projected.z > 1) return;
      if (Math.abs(projected.x) > 0.75 || Math.abs(projected.y) > 0.75) return;
      const x = (projected.x * 0.5 + 0.5) * rect.width;
      const y = (-projected.y * 0.5 + 0.5) * rect.height;
      const distance = Math.hypot(x - rect.width / 2, y - rect.height / 2);
      if (!best || distance < best.distance) best = { x, y, distance, id: group.userData.objectId };
    });
  });
  assert(best, '视野里没有可点的物品');
  return best;
}
