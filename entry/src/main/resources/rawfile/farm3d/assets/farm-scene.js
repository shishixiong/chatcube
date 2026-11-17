(function (global) {
  'use strict';

  var THREE = global.THREE;
  var D = global.FarmData;
  var S = global.FarmScene || (global.FarmScene = {});

  var DAY = {
    sky: 0xDDF3FF,
    fog: 0xDDF3FF,
    hemiSky: 0xDCF2FF,
    hemiGround: 0xA8C686,
    hemiI: 0.40,
    dirColor: 0xFFF3D6,
    dirI: 0.88
  };
  var NIGHT = {
    sky: 0x2B2745,
    fog: 0x332E4E,
    hemiSky: 0x6A6790,
    hemiGround: 0x35482F,
    hemiI: 0.44,
    dirColor: 0xFFB577,
    dirI: 0.34
  };
  var RAIN_DAY = {
    sky: 0x9AA9B4, fog: 0x9AA9B4, hemiSky: 0xB9C6CC, hemiGround: 0x7B8668,
    hemiI: 0.50, dirColor: 0xC9D4DC, dirI: 0.35
  };
  var RAIN_NIGHT = {
    sky: 0x1E2230, fog: 0x232838, hemiSky: 0x515A70, hemiGround: 0x2B3428,
    hemiI: 0.26, dirColor: 0x9AA6C4, dirI: 0.12
  };
  var RAIN_COUNT = 700;
  var RAIN_AREA_X = 70;
  var RAIN_AREA_Z = 55;
  var RAIN_TOP = 38;

  var scene = null;
  var camera = null;
  var renderer = null;
  var clock = null;
  var canvasEl = null;
  var hooks = {};
  var built = null;

  var hemi = null;
  var dir = null;

  var raycaster = null;
  var pointer = null;

  var raf = 0;
  var frameCount = 0;
  var running = false;
  var started = false;
  var elapsed = 0;

  var goal = { theta: 0.8, phi: 0.96, radius: 150, target: new THREE.Vector3(0, 2, 0) };
  var cam = { theta: 0.8, phi: 0.96, radius: 150, target: new THREE.Vector3(0, 2, 0) };
  var tween = null;

  var night = 0;
  var nightTarget = 0;
  var rain = 0;
  var rainTarget = 0;
  var rainMesh = null;
  var rainMaterial = null;
  var rainDrops = [];
  var starField = null;
  var sunDisc = null;
  var moonDisc = null;
  var skyDome = null;
  var reduceMotion = false;
  try {
    reduceMotion = !!(global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches);
  } catch (e) {}

  var ring = null;
  var selectedId = null;
  var selectedObj = null;
  var selectedBase = 1;
  var FOLLOW_SELECTION_IDS = [
    'tractor', 'trailer', 'farmer', 'child', 'dog', 'rabbit', 'harvester', 'grandma', 'sheep', 'goat',
    'chicken', 'rooster', 'chick', 'horse', 'duck', 'goose', 'cat', 'bee', 'bird'
  ];

  var labelsVisible = false;

  var ripples = [];
  var beeBase = null;
  var fireflyBase = [];
  var rabbitAuto = true;
  var fieldWork = null;
  var homeward = null;
  var sheepPen = null;
  var horseHome = null;

  var tmpV = new THREE.Vector3();
  var tmpS = new THREE.Vector3();
  var projV = new THREE.Vector3();
  var daySkyColor = new THREE.Color(DAY.sky);
  var nightSkyColor = new THREE.Color(NIGHT.sky);
  var dayFogColor = new THREE.Color(DAY.fog);
  var nightFogColor = new THREE.Color(NIGHT.fog);
  var dayHemiSky = new THREE.Color(DAY.hemiSky);
  var nightHemiSky = new THREE.Color(NIGHT.hemiSky);
  var dayHemiGround = new THREE.Color(DAY.hemiGround);
  var nightHemiGround = new THREE.Color(NIGHT.hemiGround);
  var dayDir = new THREE.Color(DAY.dirColor);
  var nightDir = new THREE.Color(NIGHT.dirColor);

  function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }

  function byId(id) {
    var list = D.objects;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i];
    }
    return null;
  }

  function createRing() {
    var geo = new THREE.RingGeometry(0.88, 1, 44);
    var mat = new THREE.MeshBasicMaterial({
      color: 0xFFFFFF,
      transparent: true,
      opacity: 0,
      side: THREE.DoubleSide,
      depthWrite: false
    });
    ring = new THREE.Mesh(geo, mat);
    ring.rotation.x = -Math.PI / 2;
    ring.visible = false;
    ring.renderOrder = 3;
    scene.add(ring);
  }

  function createRipples() {
    var pond = D.layout.pond;
    for (var i = 0; i < 3; i++) {
      var m = new THREE.Mesh(
        new THREE.RingGeometry(0.82, 1, 30),
        new THREE.MeshBasicMaterial({
          color: 0xD8F2FA,
          transparent: true,
          opacity: 0,
          side: THREE.DoubleSide,
          depthWrite: false
        })
      );
      m.rotation.x = -Math.PI / 2;
      m.position.set(pond.x, 0.19, pond.z);
      m.scale.setScalar(1);
      scene.add(m);
      ripples.push({ mesh: m, offset: i / 3 });
    }
  }

  function createRain() {
    var positions = new Float32Array(RAIN_COUNT * 6);
    rainDrops = [];
    for (var i = 0; i < RAIN_COUNT; i++) {
      rainDrops.push({
        x: (Math.random() - 0.5) * 2 * RAIN_AREA_X,
        y: Math.random() * RAIN_TOP,
        z: (Math.random() - 0.5) * 2 * RAIN_AREA_Z,
        speed: 24 + Math.random() * 8,
        len: 0.55
      });
    }
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    rainMaterial = new THREE.LineBasicMaterial({
      color: 0xCFE0EC,
      transparent: true,
      opacity: 0,
      depthWrite: false
    });
    rainMesh = new THREE.LineSegments(geo, rainMaterial);
    rainMesh.frustumCulled = false;
    rainMesh.visible = false;
    scene.add(rainMesh);
  }

  function createSkyBodies() {
    var starPositions = new Float32Array(500 * 3);
    for (var i = 0; i < 500; i++) {
      var theta = Math.random() * Math.PI * 2;
      var phi = Math.acos(0.08 + Math.random() * 0.92);
      var rr = 420;
      starPositions[i * 3] = rr * Math.sin(phi) * Math.cos(theta);
      starPositions[i * 3 + 1] = rr * Math.cos(phi);
      starPositions[i * 3 + 2] = rr * Math.sin(phi) * Math.sin(theta);
    }
    var starGeo = new THREE.BufferGeometry();
    starGeo.setAttribute('position', new THREE.BufferAttribute(starPositions, 3));
    var starMat = new THREE.PointsMaterial({
      color: 0xFFFFFF,
      size: 1.6,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      fog: false
    });
    starField = new THREE.Points(starGeo, starMat);
    starField.visible = false;
    starField.renderOrder = -2;
    scene.add(starField);

    sunDisc = new THREE.Mesh(
      new THREE.SphereGeometry(12, 12, 10),
      new THREE.MeshBasicMaterial({ color: 0xFFF2C4, fog: false })
    );
    sunDisc.position.set(180, 160, -240);
    sunDisc.visible = false;
    sunDisc.renderOrder = -2;
    scene.add(sunDisc);

    moonDisc = new THREE.Mesh(
      new THREE.SphereGeometry(9, 12, 10),
      new THREE.MeshBasicMaterial({ color: 0xF6F1D5, fog: false })
    );
    moonDisc.position.set(-180, 150, -240);
    moonDisc.visible = false;
    moonDisc.renderOrder = -2;
    scene.add(moonDisc);
  }

  // 天空渐变球：纯色背景让场景像贴在纸上，加一层自上而下的渐变才有空间感。
  // 用 CanvasTexture 而非 shader，兼容性最好，且能随昼夜改色（见 applySceneColors）。
  function createSkyDome() {
    // 无 DOM 环境（Node 侧构建校验脚本）跳过：没有 canvas 就没有渐变色，
    // 场景退回纯色背景，不影响其余逻辑。
    if (typeof document === 'undefined' || !document.createElement) return null;
    var cv = document.createElement('canvas');
    cv.width = 8;
    cv.height = 256;
    var ctx = cv.getContext('2d');
    var grad = ctx.createLinearGradient(0, 0, 0, 256);
    grad.addColorStop(0.0, '#BFE6FA');
    grad.addColorStop(0.42, '#D7F0FD');
    grad.addColorStop(0.72, '#EAF8FE');
    grad.addColorStop(1.0, '#F7FCFF');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 8, 256);
    var tex = new THREE.CanvasTexture(cv);
    if (THREE.sRGBEncoding !== undefined && 'encoding' in tex) tex.encoding = THREE.sRGBEncoding;
    var mat = new THREE.MeshBasicMaterial({ map: tex, side: THREE.BackSide, fog: false, depthWrite: false });
    var geo = new THREE.SphereGeometry(520, 24, 16);
    var dome = new THREE.Mesh(geo, mat);
    dome.renderOrder = -3;
    scene.add(dome);
    return { mesh: dome, tex: tex, mat: mat };
  }

  function createPuddles() {
    var spots = [
      { x: -20, z: -10, rx: 2.4, rz: 1.5 },
      { x: 6, z: 8, rx: 1.8, rz: 1.2 },
      { x: 30, z: -12, rx: 2.6, rz: 1.7 },
      { x: -38, z: 6, rx: 2.0, rz: 1.4 },
      { x: 14, z: 26, rx: 2.2, rz: 1.6 },
      { x: 44, z: 20, rx: 1.7, rz: 1.1 }
    ];
    var mat = new THREE.MeshBasicMaterial({
      color: 0xBFD8E8,
      transparent: true,
      opacity: 0,
      depthWrite: false
    });
    for (var i = 0; i < spots.length; i++) {
      var m = new THREE.Mesh(new THREE.CircleGeometry(1, 20), mat);
      m.rotation.x = -Math.PI / 2;
      m.position.set(spots[i].x, 0.02, spots[i].z);
      m.scale.set(spots[i].rx, spots[i].rz, 1);
      m.visible = true;
      scene.add(m);
    }
    built.puddleMat = mat;
  }

  S.isReady = function () { return !!started; };

  S.init = function (canvas, options) {
    if (!THREE) throw new Error('THREE is not available');
    if (!D) throw new Error('FarmData is not available');
    if (!global.FarmModels) throw new Error('FarmModels is not available');

    canvasEl = canvas;
    hooks = options || {};
    raycaster = new THREE.Raycaster();
    pointer = new THREE.Vector2();

    renderer = new THREE.WebGLRenderer({
      canvas: canvas,
      antialias: true,
      alpha: false,
      powerPreference: 'high-performance'
    });
    renderer.setPixelRatio(Math.min(global.devicePixelRatio || 1, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.shadowMap.autoUpdate = false;
    renderer.shadowMap.needsUpdate = true;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(DAY.sky);
    scene.backgroundIntensity = 1;
    scene.fog = new THREE.Fog(DAY.fog, 110, 310);

    camera = new THREE.PerspectiveCamera(46, 1, 0.1, 720);

    hemi = new THREE.HemisphereLight(DAY.hemiSky, DAY.hemiGround, DAY.hemiI);
    scene.add(hemi);

    dir = new THREE.DirectionalLight(DAY.dirColor, DAY.dirI);
    dir.position.set(58, 96, 44);
    dir.castShadow = true;
    dir.shadow.mapSize.set(2048, 2048);
    dir.shadow.camera.left = -95;
    dir.shadow.camera.right = 95;
    dir.shadow.camera.top = 95;
    dir.shadow.camera.bottom = -95;
    dir.shadow.camera.near = 10;
    dir.shadow.camera.far = 280;
    dir.shadow.bias = -0.0008;
    dir.shadow.normalBias = 0.03;
    scene.add(dir);
    scene.add(dir.target);

    built = global.FarmModels.buildAll(scene);
    built.pickRoots = collectPickRoots();
    for (var ii = 0; ii < built.idles.length; ii++) {
      built.idles[ii].baseY = built.idles[ii].root.position.y;
    }
    buildRabbitTrips();
    buildHorseRoutine();
    buildCoopBirdRoutine();
    buildFieldWorkRoutine();
    buildHomewardRoutine();
    buildSheepPenRoutine();
    buildHorseHomeRoutine();
    buildLazyCatRoutine();
    buildGrainCycle();
    beeBase = built.bee.position.clone();
    for (var i = 0; i < built.fireflies.length; i++) {
      fireflyBase.push({ x: built.fireflies[i].x0, y: built.fireflies[i].baseY, z: built.fireflies[i].z0, phase: built.fireflies[i].phase, r: built.fireflies[i].r });
    }
    createRing();
    createRipples();
    createRain();
    createSkyBodies();
    skyDome = createSkyDome();
    createPuddles();

    if (global.FarmAgents && global.FarmAgents.init) {
      global.FarmAgents.init({
        THREE: THREE,
        data: D,
        scene: scene,
        camera: camera,
        canvas: canvasEl,
        built: built,
        getTime: function () { return elapsed; },
        isReduceMotion: function () { return reduceMotion; },
        getNight: function () { return nightTarget > 0.5; },
        getNightAmount: function () { return night; },
        getGrainState: S.getGrainState,
        getRabbitState: S.getRabbitState,
        setRabbitAuto: S.setRabbitAuto,
        setHorseAuto: S.setHorseAuto,
        setCoopBirdsAuto: S.setCoopBirdsAuto,
        holdActor: S.holdActor,
        project: S.project
      });
    }

    clock = new THREE.Clock();
    bindEvents();
    // 先按真实画布尺寸算好 camera.aspect，再定初始机位：
    // 否则竖屏判定会拿到 aspect=1 的默认值，竖屏补偿就完全不生效。
    S.resize();
    applyView('overview', true);
    placeActors(0);
    applySceneColors(0, 0);

    started = true;
    start();
    if (hooks.onReady) hooks.onReady();
    return true;
  };

  function bindEvents() {
    canvasEl.addEventListener('pointerdown', onPointerDown);
    canvasEl.addEventListener('pointermove', onPointerMove);
    canvasEl.addEventListener('pointerup', onPointerUp);
    canvasEl.addEventListener('pointercancel', onPointerUp);
    canvasEl.addEventListener('wheel', onWheel, { passive: false });
    canvasEl.addEventListener('contextmenu', preventDefault);
    global.addEventListener('resize', S.resize);
    global.addEventListener('orientationchange', S.resize);
    document.addEventListener('visibilitychange', onVisibility);
    global.addEventListener('pagehide', S.dispose);
  }

  function unbindEvents() {
    if (!canvasEl) return;
    canvasEl.removeEventListener('pointerdown', onPointerDown);
    canvasEl.removeEventListener('pointermove', onPointerMove);
    canvasEl.removeEventListener('pointerup', onPointerUp);
    canvasEl.removeEventListener('pointercancel', onPointerUp);
    canvasEl.removeEventListener('wheel', onWheel);
    canvasEl.removeEventListener('contextmenu', preventDefault);
    global.removeEventListener('resize', S.resize);
    global.removeEventListener('orientationchange', S.resize);
    document.removeEventListener('visibilitychange', onVisibility);
    global.removeEventListener('pagehide', S.dispose);
  }

  function preventDefault(e) { e.preventDefault(); }

  var activePointers = {};
  var dragging = false;
  var moved = 0;
  var downAt = 0;
  var lastX = 0;
  var lastY = 0;
  var pinch = null;

  function pointerDistance() {
    var ids = Object.keys(activePointers);
    if (ids.length < 2) return 0;
    var a = activePointers[ids[0]];
    var b = activePointers[ids[1]];
    var dx = a.x - b.x;
    var dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function onPointerDown(e) {
    if (!renderer) return;
    if (canvasEl.setPointerCapture) {
      try { canvasEl.setPointerCapture(e.pointerId); } catch (_) {}
    }
    activePointers[e.pointerId] = { x: e.clientX, y: e.clientY };
    var count = Object.keys(activePointers).length;
    tween = null;
    if (count === 1) {
      dragging = true;
      moved = 0;
      downAt = (global.performance && global.performance.now) ? global.performance.now() : Date.now();
      lastX = e.clientX;
      lastY = e.clientY;
    } else if (count === 2) {
      dragging = false;
      pinch = { dist: pointerDistance(), radius: goal.radius };
    }
  }

  function onPointerMove(e) {
    if (!renderer) return;
    var p = activePointers[e.pointerId];
    if (!p) return;
    var count = Object.keys(activePointers).length;
    if (count >= 2 && pinch) {
      p.x = e.clientX;
      p.y = e.clientY;
      var d = pointerDistance();
      if (d > 10 && pinch.dist > 10) {
        goal.radius = clamp(pinch.radius * (pinch.dist / d), D.camera.minRadius, D.camera.maxRadius);
      }
      moved += 4;
      return;
    }
    var dx = e.clientX - p.x;
    var dy = e.clientY - p.y;
    p.x = e.clientX;
    p.y = e.clientY;
    if (dragging) {
      moved += Math.abs(dx) + Math.abs(dy);
      goal.theta -= dx * 0.0055;
      goal.phi = clamp(goal.phi - dy * 0.0045, D.camera.minPhi, D.camera.maxPhi);
    }
  }

  function onPointerUp(e) {
    if (!activePointers[e.pointerId]) return;
    delete activePointers[e.pointerId];
    var count = Object.keys(activePointers).length;
    if (count < 2) pinch = null;
    if (dragging && count === 0) {
      dragging = false;
      var now = (global.performance && global.performance.now) ? global.performance.now() : Date.now();
      if (moved < 9 && now - downAt < 650) {
        pickAt(e.clientX, e.clientY);
      }
    }
  }

  function onWheel(e) {
    e.preventDefault();
    tween = null;
    var k = 1 + e.deltaY * 0.0012;
    goal.radius = clamp(goal.radius * k, D.camera.minRadius, D.camera.maxRadius);
  }

  function pickAt(clientX, clientY) {
    if (!built) return;
    var rect = canvasEl.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    var hits = raycaster.intersectObjects(built.pickRoots, true);
    var id = null;
    var target = null;
    var point = null;
    for (var hi = 0; hi < hits.length; hi++) {
      var obj = hits[hi].object;
      var visible = true;
      var walk = obj;
      while (walk) {
        if (walk.visible === false) { visible = false; break; }
        walk = walk.parent;
      }
      if (!visible) continue;
      while (obj) {
        if (obj.userData && obj.userData.wordId) { id = obj.userData.wordId; target = obj; break; }
        obj = obj.parent;
      }
      if (id) { point = hits[hi].point; break; }
    }
    if (hooks.onPick) hooks.onPick(id, target, point);
  }

  S.setView = function (name) {
    applyView(name, false);
  };

  S.resetView = function () {
    applyView('overview', false);
  };

  // 点中物体后把相机中心平滑移到它身上，并拉近到能看清的距离。
  // 之后的双指缩放/滚轮都会围绕这个新中心，不再被分区中心（谷仓）锁住。
  var FOCUS_DURATION = 760;

  function flyTo(target, radius) {
    tween = {
      t: 0,
      dur: FOCUS_DURATION,
      from: {
        theta: goal.theta,
        phi: goal.phi,
        radius: goal.radius,
        target: goal.target.clone()
      },
      to: {
        theta: goal.theta,
        phi: clamp(goal.phi, D.camera.minPhi, D.camera.maxPhi),
        radius: clamp(radius, D.camera.minRadius, D.camera.maxRadius),
        target: target.clone()
      }
    };
  }

  function focusObject(id, root, point) {
    if (!built) return false;
    var entry = built.objects[id];
    var obj = root || (entry && entry.root);
    if (!obj) return false;
    var target = new THREE.Vector3();
    var radius = 20;
    if (obj.isInstancedMesh && point) {
      // 成片作物 / 边界围栏：以点中的那一株/那一段为中心
      target.copy(point);
    } else {
      var box = new THREE.Box3().setFromObject(obj);
      if (box.isEmpty()) {
        obj.getWorldPosition(target);
      } else {
        box.getCenter(target);
        var size = new THREE.Vector3();
        box.getSize(size);
        // 按包围球和当前画面的较小视场角算距离：竖屏手机也能把宽建筑装进画面。
        // 1.2 是整体放宽系数：点选后既把物体放到画面中心，又保留一点周边环境。
        var bound = 0.5 * Math.sqrt(size.x * size.x + size.y * size.y + size.z * size.z);
        var halfV = Math.tan((camera.fov || 46) * Math.PI / 360);
        var halfH = halfV * (camera.aspect || 1.6);
        radius = bound / Math.min(halfV, halfH) * 1.2 + 3;
      }
    }
    if (!isFinite(target.y)) target.y = 2;
    target.y = Math.max(target.y, 0.8);
    flyTo(target, radius);
    return true;
  }

  S.focus = function (id, root, point) {
    return focusObject(id, root, point);
  };

  // 竖屏（手机）时横向视场远小于纵向：同一半径下农场两侧会被裁掉。
  // 处理办法不是单纯把相机拉远（那样农场会缩成一小条），而是：
  //   1) 抬高俯仰角，让画面从"横向长条"变成"纵向梯田"式构图；
  //   2) 再按宽高比补一点距离，保证左右边界刚好入画。
  function isNarrow() {
    var a = camera && camera.aspect ? camera.aspect : 1.6;
    return a < 1.0;
  }

  function aspectRadiusScale() {
    var a = camera && camera.aspect ? camera.aspect : 1.6;
    var ref = 1.45;
    if (a >= ref) return 1;
    return Math.min(1.45, Math.pow(ref / a, 0.34));
  }

  function aspectPhi(basePhi) {
    // 越窄的屏幕越往下压视角，农场沿纵深铺开，正好填满竖屏
    if (!isNarrow()) return basePhi;
    var a = camera.aspect;
    var t = Math.min(1, (1.0 - a) / 0.55);
    return clamp(basePhi + 0.16 * t, D.camera.minPhi, D.camera.maxPhi);
  }

  function applyView(name, instant) {
    var v = D.views[name];
    if (!v) return;
    var to = {
      theta: v.theta,
      phi: clamp(aspectPhi(v.phi), D.camera.minPhi, D.camera.maxPhi),
      radius: clamp(v.radius * aspectRadiusScale(), D.camera.minRadius, D.camera.maxRadius),
      target: new THREE.Vector3(v.target[0], v.target[1], v.target[2])
    };
    if (isNarrow()) {
      // 农场沿 x 轴铺开（约 140 单位），沿 z 轴只有 110。
      // 竖屏的空间在纵向，因此从"东南角"斜看，让 x 轴斜投影进竖屏对角线。
      var a = camera.aspect;
      var t2 = Math.min(1, (1.0 - a) / 0.62);
      to.theta = v.theta + 0.52 * t2;
      to.radius = clamp(v.radius * (1 + 0.24 * t2), D.camera.minRadius, D.camera.maxRadius);
      to.target.x = v.target[0] * (1 - 0.35 * t2) + 4 * t2;
      to.target.z = v.target[2] * (1 - 0.18 * t2) + 2 * t2;
    }
    if (instant) {
      goal.theta = to.theta;
      goal.phi = to.phi;
      goal.radius = to.radius;
      goal.target.copy(to.target);
      cam.theta = to.theta;
      cam.phi = to.phi;
      cam.radius = to.radius;
      cam.target.copy(to.target);
      tween = null;
    } else {
      tween = {
        t: 0,
        dur: 900,
        from: {
          theta: goal.theta,
          phi: goal.phi,
          radius: goal.radius,
          target: goal.target.clone()
        },
        to: to
      };
      if (global.FarmAgents && global.FarmAgents.isReady && global.FarmAgents.isReady()) {
        global.FarmAgents.onZoneChange(name);
      }
    }
  }

  S.setNight = function (on, instant) {
    var next = on ? 1 : 0;
    var changed = next !== nightTarget;
    nightTarget = next;
    if (instant) {
      night = nightTarget;
      applySceneColors(night, rain);
    }
    if (changed && global.FarmAgents && global.FarmAgents.isReady && global.FarmAgents.isReady() &&
      global.FarmAgents.onNightChange) {
      global.FarmAgents.onNightChange(!!on);
    }
  };

  S.getNight = function () { return nightTarget > 0.5; };

  S.setWeather = function (on, instant) {
    var next = on ? 1 : 0;
    var changed = next !== rainTarget;
    rainTarget = next;
    if (instant) {
      rain = rainTarget;
      applySceneColors(night, rain);
    }
    if (changed && global.FarmAgents && global.FarmAgents.isReady && global.FarmAgents.isReady() &&
      global.FarmAgents.onWeatherChange) {
      global.FarmAgents.onWeatherChange(!!on);
    }
  };

  S.getWeather = function () { return rainTarget > 0.5; };

  S.getRenderStats = function () {
    var info = renderer && renderer.info ? renderer.info : null;
    return {
      calls: info ? info.render.calls : 0,
      triangles: info ? info.render.triangles : 0,
      geometries: info ? info.memory.geometries : 0,
      textures: info ? info.memory.textures : 0,
      meshes: built ? built.meshCount : 0,
      frame: frameCount,
      night: Math.round(night * 100) / 100,
      rain: Math.round(rain * 100) / 100
    };
  };

  S.select = function (id, overrideRoot) {
    if (!built) return false;
    var entry = built.objects[id];
    if (!entry) return false;
    var root = (overrideRoot && overrideRoot.userData && overrideRoot.userData.wordId === id) ? overrideRoot : entry.root;
    clearSelection();
    selectedId = id;
    selectedObj = root;
    var item = byId(id);
    var cat = item ? D.categories[item.category] : null;
    ring.material.color.set(cat ? cat.color : '#F2C14E');
    if (id === 'fence') {
      // 马厩前的小牧场围栏和场地边界围栏共用 fence 词条：
      // 点牧场围栏时高亮环落在牧场本身，而不是场地边界。
      if (overrideRoot && !overrideRoot.isInstancedMesh) {
        var fenceBox = new THREE.Box3().setFromObject(root);
        fenceBox.getCenter(tmpV);
        fenceBox.getSize(tmpS);
        ring.position.set(tmpV.x, 0.09, tmpV.z);
        selectedBase = Math.max(tmpS.x, tmpS.z) * 0.55 + 0.9;
      } else {
        ring.position.set(0, 0.09, -52);
        selectedBase = 6;
      }
    } else if (entry.instanced) {
      root.getWorldPosition(tmpV);
      ring.position.set(tmpV.x, 0.09, tmpV.z);
      selectedBase = 4.4;
    } else {
      var box = new THREE.Box3().setFromObject(root);
      box.getCenter(tmpV);
      box.getSize(tmpS);
      ring.position.set(tmpV.x, id === 'pond' ? 0.22 : 0.09, tmpV.z);
      if (id === 'hill') selectedBase = Math.max(tmpS.x, tmpS.z) * 0.5;
      else selectedBase = Math.max(tmpS.x, tmpS.z) * 0.55 + 0.9;
    }
    ring.userData.base = selectedBase;
    ring.visible = true;
    ring.material.opacity = 0.72;
    ring.scale.setScalar(selectedBase);
    if (!entry.instanced) {
      if (root.userData.homeScale == null) root.userData.homeScale = root.scale.x || 1;
    }
    return true;
  };

  function clearSelection() {
    if (selectedObj && built) {
      var entry = built.objects[selectedId];
      if (entry && !entry.instanced) {
        var hs = selectedObj.userData.homeScale;
        if (hs) selectedObj.scale.setScalar(hs);
      }
    }
    selectedObj = null;
    selectedId = null;
    if (ring) ring.visible = false;
  }

  S.clearSelection = clearSelection;

  S.setLabelsVisible = function (visible) {
    labelsVisible = !!visible;
  };

  S.getLabels = function () {
    if (!labelsVisible || !built || !camera) return [];
    var out = [];
    var w = canvasEl.clientWidth;
    var h = canvasEl.clientHeight;
    for (var i = 0; i < built.labels.length; i++) {
      var l = built.labels[i];
      if (!l.root) continue;
      if (l.root.visible === false) continue;
      if (l.anchor) tmpV.copy(l.anchor);
      else {
        l.root.getWorldPosition(tmpV);
        tmpV.y += l.offset || 2;
      }
      var dist = camera.position.distanceTo(tmpV);
      tmpV.project(camera);
      if (tmpV.z > 1 || tmpV.z < -1) continue;
      out.push({
        id: l.id,
        x: (tmpV.x * 0.5 + 0.5) * w,
        y: (-tmpV.y * 0.5 + 0.5) * h,
        dist: dist
      });
    }
    return out;
  };

  // 智能体气泡用的世界坐标 → CSS 像素投影（不依赖英文标签开关）
  S.project = function (x, y, z) {
    if (!camera || !canvasEl) return { x: 0, y: 0, visible: false, dist: 0 };
    var w = canvasEl.clientWidth || 1;
    var h = canvasEl.clientHeight || 1;
    projV.set(x, y, z);
    var dist = camera.position.distanceTo(projV);
    projV.project(camera);
    return {
      x: (projV.x * 0.5 + 0.5) * w,
      y: (-projV.y * 0.5 + 0.5) * h,
      visible: projV.z >= -1 && projV.z <= 1,
      dist: dist
    };
  };

  S.resize = function () {
    if (!renderer || !canvasEl) return;
    var w = canvasEl.clientWidth || 1;
    var h = canvasEl.clientHeight || 1;
    renderer.setSize(w, h, false);
    if (camera) {
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    }
  };

  function placeActors(dt) {
    if (!built) return;
    var actors = built.actors;
    for (var i = 0; i < actors.length; i++) {
      var a = actors[i];
      if (a.held || a.homeMode) continue;
      a.angle += a.speed * dt;
      var x = Math.cos(a.angle) * 24.8;
      var z = Math.sin(a.angle) * 18.3;
      var dx = -Math.sin(a.angle) * 24.8;
      var dz = Math.cos(a.angle) * 18.3;
      a.obj.position.set(x, 0.05, z);
      a.obj.rotation.y = Math.atan2(dx, dz);
    }
    if (built.actors.length) {
      var walker = built.actors[2];
      var walker2 = built.actors[3];
      var dog = built.actors[4];
      if (walker && !walker.held && !walker.homeMode) walker.obj.position.y = 0.05 + Math.abs(Math.sin(elapsed * 4.2)) * 0.06;
      if (walker2 && !walker2.held && !walker2.homeMode) walker2.obj.position.y = 0.05 + Math.abs(Math.sin(elapsed * 4.6 + 1)) * 0.06;
      if (dog && !dog.held && !dog.homeMode) dog.obj.position.y = 0.05 + Math.abs(Math.sin(elapsed * 6.0 + 2)) * 0.08;
    }
  }

  // 智能体小剧场用：把环形 actor 冻在当前位置（只改朝向/小起伏，不搬离环）
  S.holdActor = function (id, on) {
    if (!built) return false;
    for (var i = 0; i < built.actors.length; i++) {
      if (built.actors[i].id === id) {
        built.actors[i].held = !!on;
        return true;
      }
    }
    return false;
  };

  // ---------------------------------------------------------------
  // 兔子吃萝卜小剧场：原地待一会儿 → 蹦到菜园 → 低头啃掉一棵胡萝卜
  // → 蹦回窝 → 再等一段时间。吃完的胡萝卜过一会儿慢慢长回来。
  // ---------------------------------------------------------------
  var RABBIT_RUN_SPEED = 3.1;
  var RABBIT_EAT_TIME = 2.9;
  var CARROT_REGROW_TIME = 55;
  var rabbitTrips = [];

  function setRabbitEars(cfg, now, swing) {
    if (cfg.earL) cfg.earL.rotation.z = 0.12 + Math.sin(now * 2.2 + cfg.phase) * swing;
    if (cfg.earR) cfg.earR.rotation.z = -0.12 + Math.sin(now * 2.2 + cfg.phase + 0.6) * swing;
  }

  function buildRabbitTrips() {
    rabbitTrips = [];
    if (!built || !built.carrotGarden) return;
    var entry = built.objects.rabbit;
    if (!entry || !entry.root || !entry.root.userData.idle) return;
    var rabbit = entry.root;
    var garden = built.carrotGarden;
    var gp = garden.group.position;
    var ry = garden.group.rotation.y;
    var cs = Math.cos(ry);
    var sn = Math.sin(ry);
    var carrots = [];
    for (var i = 0; i < garden.carrots.length; i++) {
      var node = garden.carrots[i].group;
      var lp = node.position;
      carrots.push({
        node: node,
        lx: lp.x,
        lz: lp.z,
        x: gp.x + lp.x * cs + lp.z * sn,
        z: gp.z - lp.x * sn + lp.z * cs,
        front: lp.z > 0,
        state: 'ready',
        grow: 1,
        regen: 0
      });
    }
    rabbitTrips.push({
      root: rabbit,
      cfg: rabbit.userData.idle,
      carrots: carrots,
      gardenX: gp.x,
      gardenZ: gp.z,
      cs: cs,
      sn: sn,
      homeX: rabbit.position.x,
      homeY: rabbit.position.y,
      homeZ: rabbit.position.z,
      homeYaw: rabbit.rotation.y,
      state: 'wait',
      timer: 5.5,
      target: null,
      fromX: 0,
      fromZ: 0,
      toX: 0,
      toZ: 0,
      travelT: 0,
      travelDur: 1
    });
  }

  function chooseCarrot(trip) {
    var best = null;
    var bestScore = Infinity;
    for (var i = 0; i < trip.carrots.length; i++) {
      var c = trip.carrots[i];
      // 只啃靠敞口那一排：后排被土床和木栅栏挡着，兔子站过去会踩进菜畦里
      if (c.state !== 'ready' || c.grow < 0.5 || !c.front) continue;
      var dx = c.x - trip.homeX;
      var dz = c.z - trip.homeZ;
      var score = Math.sqrt(dx * dx + dz * dz);
      if (score < bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  function updateCarrots(carrots, dt) {
    for (var i = 0; i < carrots.length; i++) {
      var c = carrots[i];
      if (c.state === 'eaten') {
        c.grow = Math.max(0, c.grow - dt / 0.32);
        c.regen -= dt;
        if (c.grow <= 0 && c.regen <= 0) {
          c.state = 'ready';
          c.grow = 0.02;
        }
      } else if (c.grow < 1) {
        c.grow = Math.min(1, c.grow + dt / 0.8);
      }
      c.node.visible = c.grow > 0.02;
      c.node.scale.setScalar(Math.max(0.02, c.grow));
    }
  }

  function updateRabbitTrips(dt, now) {
    for (var i = 0; i < rabbitTrips.length; i++) {
      var trip = rabbitTrips[i];
      var root = trip.root;
      var cfg = trip.cfg;
      updateCarrots(trip.carrots, dt);
      if (!rabbitAuto) continue;

      if (trip.state === 'wait') {
        trip.timer -= dt;
        root.position.set(trip.homeX, trip.homeY, trip.homeZ);
        // 闲着的时候慢慢左右张望
        root.rotation.y = trip.homeYaw + Math.sin(now * 0.42 + 1.3) * 0.16;
        if (cfg.head) cfg.head.rotation.x = 0;
        setRabbitEars(cfg, now, 0.06);
        if (trip.timer <= 0) {
          var pick = chooseCarrot(trip);
          if (!pick) {
            trip.timer = 4;
            continue;
          }
          trip.target = pick;
          trip.fromX = root.position.x;
          trip.fromZ = root.position.z;
          var standLz = pick.lz + 0.85;
          trip.toX = trip.gardenX + pick.lx * trip.cs + standLz * trip.sn;
          trip.toZ = trip.gardenZ - pick.lx * trip.sn + standLz * trip.cs;
          var dx = trip.toX - trip.fromX;
          var dz = trip.toZ - trip.fromZ;
          trip.travelDur = Math.max(0.5, Math.sqrt(dx * dx + dz * dz) / RABBIT_RUN_SPEED);
          trip.travelT = 0;
          trip.state = 'run';
        }
      } else if (trip.state === 'run' || trip.state === 'back') {
        trip.travelT = Math.min(trip.travelDur, trip.travelT + dt);
        var k = trip.travelT / trip.travelDur;
        root.position.x = trip.fromX + (trip.toX - trip.fromX) * k;
        root.position.z = trip.fromZ + (trip.toZ - trip.fromZ) * k;
        root.position.y = trip.homeY + Math.abs(Math.sin(now * 9.0)) * 0.16;
        root.rotation.y = Math.atan2(trip.toX - trip.fromX, trip.toZ - trip.fromZ);
        if (cfg.head) cfg.head.rotation.x = 0;
        setRabbitEars(cfg, now, 0.18);
        if (trip.travelT >= trip.travelDur) {
          root.position.x = trip.toX;
          root.position.z = trip.toZ;
          root.position.y = trip.homeY;
          if (trip.state === 'run') {
            trip.state = 'eat';
            trip.timer = RABBIT_EAT_TIME;
          } else {
            trip.state = 'wait';
            trip.timer = 9 + Math.random() * 8;
            root.position.set(trip.homeX, trip.homeY, trip.homeZ);
            root.rotation.y = trip.homeYaw;
          }
        }
      } else if (trip.state === 'eat') {
        trip.timer -= dt;
        var c = trip.target;
        if (c) {
          root.rotation.y = Math.atan2(c.x - root.position.x, c.z - root.position.z);
          // 低头一顿一顿地啃，身子跟着一伏一起
          if (cfg.head) cfg.head.rotation.x = -0.62 + Math.sin(now * 11.0) * 0.12;
          root.position.y = trip.homeY - 0.03 + Math.abs(Math.sin(now * 11.0)) * 0.035;
          if (c.state === 'ready' && trip.timer <= RABBIT_EAT_TIME * 0.35) {
            c.state = 'eaten';
            c.regen = CARROT_REGROW_TIME;
          }
        }
        setRabbitEars(cfg, now, 0.05);
        if (trip.timer <= 0) {
          trip.state = 'back';
          trip.fromX = root.position.x;
          trip.fromZ = root.position.z;
          trip.toX = trip.homeX;
          trip.toZ = trip.homeZ;
          var bdx = trip.toX - trip.fromX;
          var bdz = trip.toZ - trip.fromZ;
          trip.travelDur = Math.max(0.5, Math.sqrt(bdx * bdx + bdz * bdz) / RABBIT_RUN_SPEED);
          trip.travelT = 0;
          trip.target = null;
        }
      }
    }
  }

  // 智能体接管兔子时暂停自动巡游；恢复时回到窝边重新等待
  S.setRabbitAuto = function (on) {
    rabbitAuto = !!on;
    if (!rabbitAuto) return false;
    for (var i = 0; i < rabbitTrips.length; i++) {
      var trip = rabbitTrips[i];
      trip.state = 'wait';
      trip.timer = 6 + Math.random() * 6;
      trip.target = null;
      trip.root.position.set(trip.homeX, trip.homeY, trip.homeZ);
      trip.root.rotation.y = trip.homeYaw;
      if (trip.cfg.head) trip.cfg.head.rotation.x = 0;
      if (trip.cfg.earL) trip.cfg.earL.rotation.z = 0.12;
      if (trip.cfg.earR) trip.cfg.earR.rotation.z = -0.12;
    }
    return true;
  };

  S.getRabbitState = function () {
    var trip = rabbitTrips.length ? rabbitTrips[0] : null;
    return { state: trip ? trip.state : 'none', auto: rabbitAuto };
  };

  // ---------------------------------------------------------------
  // 马厩小剧场：马在牧场里待一会儿 → 走到草料架低头吃草 →
  // 走到水槽低头喝水 → 走回原位。走路时四条腿摆动。
  // 点击马（智能体小跑）或天黑时暂停，回到原位。
  // ---------------------------------------------------------------
  var HORSE_WALK_SPEED = 1.55;
  var HORSE_EAT_TIME = 5.5;
  var HORSE_DRINK_TIME = 4.2;
  var horseAuto = true;
  var horseRoutine = null;

  function horseLegsPose(cfg, phase) {
    if (!cfg || !cfg.legs || cfg.legs.length < 4) return;
    var legs = cfg.legs;
    legs[0].rotation.x = Math.sin(phase) * 0.36;
    legs[1].rotation.x = Math.sin(phase + Math.PI) * 0.36;
    legs[2].rotation.x = Math.sin(phase + Math.PI) * 0.3;
    legs[3].rotation.x = Math.sin(phase) * 0.3;
  }

  function horseLegsRest(cfg) {
    if (!cfg || !cfg.legs) return;
    for (var i = 0; i < cfg.legs.length; i++) cfg.legs[i].rotation.x = 0;
  }

  function buildHorseRoutine() {
    horseRoutine = null;
    var horse = built && built.stableHorse;
    if (!horse || !horse.userData.stableHome || !horse.userData.stableSpots) return;
    var home = horse.userData.stableHome;
    horseRoutine = {
      root: horse,
      cfg: horse.userData.idle,
      home: new THREE.Vector3(home.x, 0, home.z),
      homeYaw: home.yaw,
      spots: horse.userData.stableSpots,
      state: 'wait',
      timer: 7 + Math.random() * 6,
      target: null,
      faceYaw: home.yaw,
      after: 'home',
      walkPhase: 0
    };
    horseAuto = true;
  }

  function updateHorseRoutine(dt, now) {
    var r = horseRoutine;
    if (!r) return;
    // 智能体故事接管时不要抢位置
    if (!horseAuto) return;
    var root = r.root;
    var cfg = r.cfg;

    if (nightTarget > 0.5 || reduceMotion) {
      root.position.x = r.home.x;
      root.position.z = r.home.z;
      root.rotation.set(0, r.homeYaw, 0);
      horseLegsRest(cfg);
      if (cfg.head) {
        cfg.head.rotation.x = 0;
        if (cfg.headBaseY != null) cfg.head.position.y = cfg.headBaseY;
      }
      r.state = 'wait';
      return;
    }

    if (r.state === 'wait') {
      root.position.x = r.home.x;
      root.position.z = r.home.z;
      root.rotation.y = r.homeYaw + Math.sin(now * 0.35) * 0.14;
      horseLegsRest(cfg);
      if (cfg.head) {
        cfg.head.rotation.x = Math.sin(now * 0.8) * 0.03;
        if (cfg.headBaseY != null) cfg.head.position.y = cfg.headBaseY;
      }
      r.timer -= dt;
      if (r.timer <= 0) {
        r.target = r.spots.hay;
        r.faceYaw = r.spots.hay.yaw;
        r.after = 'eat';
        r.state = 'walk';
      }
    } else if (r.state === 'walk') {
      var dx = r.target.x - root.position.x;
      var dz = r.target.z - root.position.z;
      var dist = Math.sqrt(dx * dx + dz * dz);
      var step = HORSE_WALK_SPEED * dt;
      if (dist <= step) {
        root.position.x = r.target.x;
        root.position.z = r.target.z;
        root.rotation.y = r.faceYaw;
        horseLegsRest(cfg);
        if (r.after === 'eat') {
          r.state = 'eat';
          r.timer = HORSE_EAT_TIME;
        } else if (r.after === 'drink') {
          r.state = 'drink';
          r.timer = HORSE_DRINK_TIME;
        } else {
          r.state = 'wait';
          r.timer = 9 + Math.random() * 8;
          r.after = 'home';
        }
      } else {
        root.position.x += dx / dist * step;
        root.position.z += dz / dist * step;
        root.rotation.y = Math.atan2(dx, dz);
        r.walkPhase += dt * 9.2;
        horseLegsPose(cfg, r.walkPhase);
        if (cfg.head) {
          cfg.head.rotation.x = Math.sin(r.walkPhase * 0.5) * 0.035;
          if (cfg.headBaseY != null) cfg.head.position.y = cfg.headBaseY;
        }
      }
    } else if (r.state === 'eat') {
      root.rotation.y = r.faceYaw;
      horseLegsRest(cfg);
      if (cfg.head) {
        cfg.head.rotation.x = 0.95 + Math.sin(now * 8.0) * 0.1;
        if (cfg.headBaseY != null) cfg.head.position.y = cfg.headBaseY - 0.22;
      }
      r.timer -= dt;
      if (r.timer <= 0) {
        r.target = r.spots.trough;
        r.faceYaw = r.spots.trough.yaw;
        r.after = 'drink';
        r.state = 'walk';
      }
    } else if (r.state === 'drink') {
      root.rotation.y = r.faceYaw;
      horseLegsRest(cfg);
      if (cfg.head) {
        cfg.head.rotation.x = 0.8 + Math.sin(now * 5.0) * 0.06;
        if (cfg.headBaseY != null) cfg.head.position.y = cfg.headBaseY - 0.18;
      }
      r.timer -= dt;
      if (r.timer <= 0) {
        r.target = { x: r.home.x, z: r.home.z };
        r.faceYaw = r.homeYaw;
        r.after = 'home';
        r.state = 'walk';
      }
    }
  }

  // 智能体接管马时暂停自动巡游；恢复时回到原位重新等待
  S.setHorseAuto = function (on) {
    horseAuto = !!on;
    var r = horseRoutine;
    if (!r) return false;
    r.state = 'wait';
    r.timer = on ? 6 + Math.random() * 5 : 8;
    r.target = null;
    r.after = 'home';
    if (!on) {
      r.root.position.set(r.home.x, 0, r.home.z);
      r.root.rotation.set(0, r.homeYaw, 0);
      horseLegsRest(r.cfg);
      if (r.cfg && r.cfg.head) {
        r.cfg.head.rotation.x = 0;
        if (r.cfg.headBaseY != null) r.cfg.head.position.y = r.cfg.headBaseY;
      }
    }
    return true;
  };

  // ---------------------------------------------------------------
  // 鸡舍小剧场：小鸡在门前闲庭信步、低头啄虫子，偶尔走回鸡舍里待一会儿再出来。
  // 故事接管（chicken_peck / rooster_crow / grandma_feed）或天黑时暂停。
  // ---------------------------------------------------------------
  var CHICKEN_WALK_SPEED = 0.62;
  var coopBirdAuto = true;
  var coopBirdRoutines = [];
  var wasForceNight = false;
  var pendingCrow = false;
  var coopBirdWormMat = null;

  function makeCoopWorm() {
    if (!coopBirdWormMat) {
      coopBirdWormMat = new THREE.MeshPhongMaterial({
        color: 0xC06A57,
        flatShading: true,
        shininess: 0,
        specular: 0x000000
      });
    }
    var w = new THREE.Group();
    var segGeo = new THREE.SphereGeometry(0.085, 6, 4);
    for (var i = 0; i < 3; i++) {
      var m = new THREE.Mesh(segGeo, coopBirdWormMat);
      m.position.set(Math.sin(i * 1.3) * 0.05, 0.02, i * 0.12);
      m.scale.set(1, 0.78, 1.35);
      m.castShadow = false;
      m.receiveShadow = false;
      w.add(m);
    }
    w.visible = false;
    scene.add(w);
    return w;
  }

  function coopLegsPose(cfg, phase, amp) {
    if (!cfg || !cfg.legs || cfg.legs.length < 2) return;
    cfg.legs[0].rotation.x = Math.sin(phase) * amp;
    cfg.legs[1].rotation.x = Math.sin(phase + Math.PI) * amp;
  }

  function coopLegsRest(cfg) {
    if (!cfg || !cfg.legs) return;
    for (var i = 0; i < cfg.legs.length; i++) cfg.legs[i].rotation.x = 0;
  }

  function resetCoopBird(r) {
    r.state = 'wait';
    r.timer = 1 + Math.random() * 3;
    r.target = null;
    r.worm.visible = false;
    r.wormTimer = 0;
    r.root.visible = true;
    r.root.scale.setScalar(1);
    r.root.position.set(r.home.x, r.home.y, r.home.z);
    r.root.rotation.set(0, r.home.yaw, 0);
    coopLegsRest(r.cfg);
  }

  function coopIsBusy(except) {
    for (var i = 0; i < coopBirdRoutines.length; i++) {
      var r = coopBirdRoutines[i];
      if (r === except) continue;
      if (r.state === 'toCoop' || r.state === 'enter' || r.state === 'inside' || r.state === 'exit') return true;
    }
    return false;
  }

  function pickCoopTarget(r) {
    var a = Math.random() * Math.PI * 2;
    var rr = Math.sqrt(Math.random());
    return {
      x: r.center.x + Math.cos(a) * rr * r.rx,
      z: r.center.z + Math.sin(a) * rr * r.rz
    };
  }

  function startCoopPeck(r) {
    r.state = 'peck';
    r.timer = 2.2 + Math.random() * 1.8;
    r.wormTimer = 1.1 + Math.random() * 0.6;
    var yaw = r.root.rotation.y;
    var fx = Math.sin(yaw);
    var fz = Math.cos(yaw);
    r.worm.position.set(r.root.position.x + fx * 0.5, 0.05, r.root.position.z + fz * 0.5);
    r.worm.rotation.set(0, yaw, 0);
    r.worm.visible = Math.random() < 0.75;
  }

  function buildCoopBirdRoutine() {
    coopBirdRoutines = [];
    wasForceNight = false;
    pendingCrow = false;
    if (!built || !built.objects || !D.layout.chicken_coop) return;
    var coop = D.layout.chicken_coop;
    var ry = coop.ry || 0;
    var cs = Math.cos(ry);
    var sn = Math.sin(ry);
    function localPoint(x, z) {
      return { x: coop.x + x * cs + z * sn, z: coop.z - x * sn + z * cs };
    }
    var door = localPoint(0, 1.82);
    var stage = localPoint(0, 3.15);

    function pushCoopRoutine(id, root, shelter, enterChance, order) {
      if (!root || !root.userData || !root.userData.idle) return;
      root.userData.coopBird = true;
      coopBirdRoutines.push({
        id: id,
        root: root,
        cfg: root.userData.idle,
        baseY: root.position.y,
        home: { x: root.position.x, y: root.position.y, z: root.position.z, yaw: root.rotation.y },
        door: door,
        stage: stage,
        shelter: shelter,
        center: localPoint(0, 4.4),
        rx: 4.0,
        rz: 1.9,
        enterChance: enterChance,
        state: 'wait',
        timer: 1.5 + Math.random() * 3,
        target: null,
        faceYaw: root.rotation.y,
        walkPhase: Math.random() * 6,
        travelT: 0,
        travelDur: 1,
        fromX: 0,
        fromZ: 0,
        toX: 0,
        toZ: 0,
        forceDelay: order * 0.8,
        roostedForNight: false,
        wasForced: false,
        worm: makeCoopWorm(),
        wormTimer: 0
      });
    }

    var ids = ['chicken', 'rooster'];
    var shelters = [localPoint(-1.6, 2.6), localPoint(1.7, 2.2)];
    for (var i = 0; i < ids.length; i++) {
      var entry = built.objects[ids[i]];
      if (!entry || !entry.root) continue;
      pushCoopRoutine(ids[i], entry.root, shelters[i], i === 0 ? 0.2 : 0.08, coopBirdRoutines.length);
    }

    var chickRoots = built.chickRoots || [];
    var chickShelters = [localPoint(-1.9, 2.15), localPoint(-1.0, 2.25), localPoint(1.3, 1.95)];
    for (var ci = 0; ci < chickRoots.length; ci++) {
      pushCoopRoutine('chick', chickRoots[ci], chickShelters[ci % chickShelters.length], 0.12,
        coopBirdRoutines.length);
    }
    coopBirdAuto = true;
  }

  var FIELD_WORK_SPEED = 1.8;

  function buildFieldWorkRoutine() {
    fieldWork = null;
    if (!built || !built.objects || !built.objects.harvester) return;
    var root = built.objects.harvester.root;
    var waypoints = [
      { x: 58, z: -14 }, { x: 58, z: -30 }, { x: 40, z: -30 }, { x: 40, z: -14 }
    ];
    var count = 24;
    var positions = new Float32Array(count * 3);
    for (var i = 0; i < count; i++) positions[i * 3 + 1] = -10;
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    var dustMat = new THREE.PointsMaterial({
      color: 0xD8C29A,
      size: 0.75,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      sizeAttenuation: true
    });
    var dust = new THREE.Points(geo, dustMat);
    dust.frustumCulled = false;
    dust.visible = false;
    scene.add(dust);
    fieldWork = {
      root: root,
      home: { x: root.position.x, z: root.position.z, yaw: root.rotation.y },
      waypoints: waypoints,
      index: 0,
      dust: dust,
      dustMat: dustMat,
      dustPos: positions,
      dustLife: [],
      dustTimer: 0
    };
    for (var j = 0; j < count; j++) {
      fieldWork.dustLife.push({ x: 0, y: -10, z: 0, vy: 0, life: 0 });
    }
  }

  function updateButterflies(t) {
    var list = built.butterflies || [];
    var hidden = nightTarget > 0.5 || rainTarget > 0.5 || reduceMotion;
    for (var i = 0; i < list.length; i++) {
      var b = list[i];
      var obj = b.obj;
      if (hidden) {
        obj.visible = false;
        continue;
      }
      obj.visible = true;
      var tt = t * b.speed + b.phase;
      obj.position.x = b.x + Math.sin(tt) * b.r;
      obj.position.z = b.z + Math.cos(tt * 0.8) * b.r * 0.7;
      obj.position.y = 1.15 + Math.sin(tt * 2.3) * 0.22;
      obj.rotation.y = tt * 0.7;
      var flap = Math.sin(t * 16 + b.phase) * 0.45;
      obj.userData.wings.left.rotation.z = flap;
      obj.userData.wings.right.rotation.z = -flap;
    }
  }

  function updateDragonflies(t) {
    var list = built.dragonflies || [];
    var hidden = nightTarget > 0.5 || rainTarget > 0.5 || reduceMotion;
    for (var i = 0; i < list.length; i++) {
      var d = list[i];
      var obj = d.obj;
      if (hidden) {
        obj.visible = false;
        continue;
      }
      obj.visible = true;
      var tt = t * d.speed + d.phase;
      obj.position.x = d.x + Math.sin(tt) * d.r;
      obj.position.z = d.z + Math.cos(tt * 0.9) * d.r * 0.7;
      obj.position.y = 1.35 + Math.sin(tt * 1.8) * 0.18;
      obj.rotation.y = tt * 0.5;
      var flap = Math.sin(t * 22 + d.phase) * 0.55;
      obj.userData.wings.left.rotation.z = 0.35 + flap;
      obj.userData.wings.right.rotation.z = -0.35 - flap;
    }
  }

  function updateDucklings(dt, t) {
    var list = built.ducklings || [];
    var duck = built.duckRoot;
    if (!duck || !list.length) return;
    var hidden = nightTarget > 0.5;
    for (var i = 0; i < list.length; i++) {
      var dl = list[i];
      dl.visible = !hidden;
      if (hidden) continue;
      var yaw = duck.rotation.y;
      var back = 0.9 + i * 0.75;
      var side = i % 2 === 0 ? -0.35 : 0.35;
      var bx = duck.position.x - Math.sin(yaw) * back + Math.cos(yaw) * side;
      var bz = duck.position.z - Math.cos(yaw) * back - Math.sin(yaw) * side;
      var k = Math.min(1, dt * 3.2);
      dl.position.x += (bx - dl.position.x) * k;
      dl.position.z += (bz - dl.position.z) * k;
      dl.position.y = Math.max(0.1, duck.position.y - 0.02) + Math.abs(Math.sin(t * 3.4 + i)) * 0.02;
      dl.rotation.y = yaw;
    }
  }

  function updateFieldWork(dt, now) {
    var fw = fieldWork;
    if (!fw) return;
    var root = fw.root;
    var parked = nightTarget > 0.5 || rainTarget > 0.5 || reduceMotion;
    if (parked) {
      var hx = fw.home.x - root.position.x;
      var hz = fw.home.z - root.position.z;
      var hd = Math.sqrt(hx * hx + hz * hz);
      if (hd > 0.08) {
        var hs = Math.min(hd, FIELD_WORK_SPEED * dt);
        root.position.x += hx / hd * hs;
        root.position.z += hz / hd * hs;
        root.rotation.y = Math.atan2(hx, hz);
      } else {
        root.position.x = fw.home.x;
        root.position.z = fw.home.z;
        root.rotation.y = fw.home.yaw;
      }
      root.position.y = 0;
      fw.dustMat.opacity = 0;
      fw.dust.visible = false;
      return;
    }

    var wp = fw.waypoints[fw.index];
    var dx = wp.x - root.position.x;
    var dz = wp.z - root.position.z;
    var dist = Math.sqrt(dx * dx + dz * dz);
    if (dist < 0.6) {
      fw.index = (fw.index + 1) % fw.waypoints.length;
      wp = fw.waypoints[fw.index];
      dx = wp.x - root.position.x;
      dz = wp.z - root.position.z;
      dist = Math.sqrt(dx * dx + dz * dz);
    }
    if (dist > 0.001) {
      var step = FIELD_WORK_SPEED * dt;
      root.position.x += dx / dist * step;
      root.position.z += dz / dist * step;
      root.rotation.y = Math.atan2(dx, dz);
    }
    root.position.y = 0.02 + Math.sin(now * 9) * 0.012;

    fw.dustMat.opacity = 0.45;
    fw.dust.visible = true;
    fw.dustTimer -= dt;
    if (fw.dustTimer <= 0) {
      fw.dustTimer = 0.12;
      var fwdX = Math.sin(root.rotation.y);
      var fwdZ = Math.cos(root.rotation.y);
      for (var d = 0; d < fw.dustLife.length; d++) {
        var part = fw.dustLife[d];
        if (part.life > 0) continue;
        part.x = root.position.x - fwdX * 2.2 + (Math.random() - 0.5) * 1.4;
        part.y = 0.35 + Math.random() * 0.5;
        part.z = root.position.z - fwdZ * 2.2 + (Math.random() - 0.5) * 1.4;
        part.vy = 0.5 + Math.random() * 0.6;
        part.life = 1;
        break;
      }
    }
    for (var j = 0; j < fw.dustLife.length; j++) {
      var p = fw.dustLife[j];
      if (p.life > 0) {
        p.life -= dt * 0.8;
        p.y += p.vy * dt;
        p.vy *= 0.96;
        if (p.life <= 0) {
          p.life = 0;
          p.y = -10;
        }
      }
      var idx = j * 3;
      fw.dustPos[idx] = p.x;
      fw.dustPos[idx + 1] = p.life > 0 ? p.y : -10;
      fw.dustPos[idx + 2] = p.z;
    }
    fw.dust.geometry.attributes.position.needsUpdate = true;
  }

  var FARMHOUSE = D.layout.farmhouse;
  var FH_C = Math.cos(FARMHOUSE.ry || 0);
  var FH_S = Math.sin(FARMHOUSE.ry || 0);

  function farmhousePoint(lx, lz) {
    return {
      x: FARMHOUSE.x + lx * FH_C + lz * FH_S,
      z: FARMHOUSE.z - lx * FH_S + lz * FH_C
    };
  }

  var HOME_APPROACH = farmhousePoint(0, 6.1);
  var HOME_DOOR = farmhousePoint(0, 3.7);
  var HOME_INSIDE = farmhousePoint(0, 1.8);
  var HOME_SPEED = 3.0;
  var DOOR_OPEN_ANGLE = 1.5;
  var DOOR_SPEED = 2.4;

  function buildHomewardRoutine() {
    homeward = { cast: [], door: null, doorOpen: false, entryBusy: false, exitBusy: false };
    var farmhouse = built.objects.farmhouse;
    if (farmhouse && farmhouse.root && farmhouse.root.userData && farmhouse.root.userData.door) {
      homeward.door = farmhouse.root.userData.door;
    }
    var defs = [
      { id: 'farmer', kind: 'ring', staging: farmhousePoint(1.6, 5.7) },
      { id: 'child', kind: 'ring', staging: farmhousePoint(2.7, 5.7) },
      { id: 'grandma', kind: 'base', staging: farmhousePoint(-2.8, 5.7) },
      { id: 'dog', kind: 'ring', staging: farmhousePoint(3.8, 5.7) },
      { id: 'cat', kind: 'base', staging: farmhousePoint(-1.2, 5.7) }
    ];
    for (var i = 0; i < defs.length; i++) {
      var def = defs[i];
      var root = null;
      var ringActor = null;
      var base = null;
      if (def.kind === 'ring') {
        for (var j = 0; j < built.actors.length; j++) {
          if (built.actors[j].id === def.id) {
            ringActor = built.actors[j];
            root = ringActor.obj;
            break;
          }
        }
      } else {
        var entry = built.objects[def.id];
        if (entry && entry.root) {
          root = entry.root;
          base = { x: root.position.x, z: root.position.z };
        }
      }
      if (!root) continue;
      if (ringActor) ringActor.homeMode = '';
      homeward.cast.push({
        id: def.id,
        kind: def.kind,
        root: root,
        ringActor: ringActor,
        staging: def.staging,
        base: base,
        mode: '',
        stage: 0
      });
    }
  }

  function moveHomeward(root, tx, tz, speed, dt) {
    var dx = tx - root.position.x;
    var dz = tz - root.position.z;
    var d = Math.sqrt(dx * dx + dz * dz);
    if (d < 0.14) {
      root.position.x = tx;
      root.position.z = tz;
      return true;
    }
    var step = Math.min(d, speed * dt);
    root.position.x += dx / d * step;
    root.position.z += dz / d * step;
    root.rotation.y = Math.atan2(dx, dz);
    return false;
  }

  function doorIsOpenEnough() {
    if (!homeward.door) return true;
    return homeward.door.rotation.y > 0.95;
  }

  function updateHomewardDoor(dt) {
    var door = homeward.door;
    if (!door) return;
    var target = homeward.doorOpen ? DOOR_OPEN_ANGLE : 0;
    var current = door.rotation.y;
    var step = DOOR_SPEED * dt;
    if (Math.abs(target - current) <= step) {
      door.rotation.y = target;
    } else {
      door.rotation.y += target > current ? step : -step;
    }
  }

  function humanWaitingAtDoor() {
    for (var i = 0; i < homeward.cast.length; i++) {
      var c = homeward.cast[i];
      if ((c.id === 'farmer' || c.id === 'child' || c.id === 'grandma') &&
        (c.mode === 'waitDoor' || c.mode === 'entering' || c.mode === 'inside')) {
        return true;
      }
    }
    return false;
  }

  function updateHomeward(dt) {
    if (!homeward) return;
    var goHome = nightTarget > 0.5 || rainTarget > 0.5;
    var cast = homeward.cast;
    var i;
    var c;

    if (goHome) {
      for (i = 0; i < cast.length; i++) {
        c = cast[i];
        if (c.mode === 'exiting' || c.mode === 'toReturn') {
          c.mode = 'toStaging';
        }
        if (c.mode === '' || c.mode === 'toStaging') {
          c.mode = 'toStaging';
          c.root.visible = true;
          if (moveHomeward(c.root, c.staging.x, c.staging.z, HOME_SPEED, dt)) {
            c.mode = 'waitDoor';
            c.root.rotation.y = Math.atan2(HOME_DOOR.x - c.staging.x, HOME_DOOR.z - c.staging.z);
          }
        }
      }
      if (!homeward.doorOpen && humanWaitingAtDoor()) {
        homeward.doorOpen = true;
      }
      if (homeward.doorOpen && doorIsOpenEnough()) {
        if (!homeward.entryBusy) {
          for (i = 0; i < cast.length; i++) {
            c = cast[i];
            if (c.mode === 'waitDoor') {
              c.mode = 'entering';
              c.stage = 0;
              homeward.entryBusy = true;
              break;
            }
          }
        }
        for (i = 0; i < cast.length; i++) {
          c = cast[i];
          if (c.mode !== 'entering') continue;
          if (c.stage === 0) {
            if (moveHomeward(c.root, HOME_APPROACH.x, HOME_APPROACH.z, HOME_SPEED, dt)) {
              c.stage = 1;
            }
          } else if (c.stage === 1) {
            if (moveHomeward(c.root, HOME_DOOR.x, HOME_DOOR.z, HOME_SPEED, dt)) {
              c.stage = 2;
            }
          } else if (moveHomeward(c.root, HOME_INSIDE.x, HOME_INSIDE.z, HOME_SPEED, dt)) {
            c.root.visible = false;
            c.mode = 'inside';
            homeward.entryBusy = false;
          }
        }
      }
      var allInside = true;
      for (i = 0; i < cast.length; i++) {
        if (cast[i].mode !== 'inside') {
          allInside = false;
          break;
        }
      }
      if (allInside) homeward.doorOpen = false;
    } else {
      var anyInside = false;
      var anyEntering = false;
      for (i = 0; i < cast.length; i++) {
        c = cast[i];
        if (c.mode === 'inside' || c.mode === 'exiting') anyInside = true;
        if (c.mode === 'entering') anyEntering = true;
      }
      if (anyInside || anyEntering) homeward.doorOpen = true;
      if (homeward.doorOpen && doorIsOpenEnough()) {
        if (!homeward.exitBusy) {
          for (i = 0; i < cast.length; i++) {
            c = cast[i];
            if (c.mode === 'inside') {
              c.mode = 'exiting';
              c.stage = 0;
              c.root.visible = true;
              c.root.position.x = HOME_INSIDE.x;
              c.root.position.z = HOME_INSIDE.z;
              homeward.exitBusy = true;
              break;
            }
          }
        }
        for (i = 0; i < cast.length; i++) {
          c = cast[i];
          if (c.mode !== 'exiting') continue;
          if (c.stage === 0) {
            if (moveHomeward(c.root, HOME_DOOR.x, HOME_DOOR.z, HOME_SPEED, dt)) {
              c.stage = 1;
            }
          } else if (c.stage === 1) {
            if (moveHomeward(c.root, HOME_APPROACH.x, HOME_APPROACH.z, HOME_SPEED, dt)) {
              c.stage = 2;
            }
          } else if (moveHomeward(c.root, c.staging.x, c.staging.z, HOME_SPEED, dt)) {
            c.mode = 'toReturn';
            homeward.exitBusy = false;
          }
        }
      }
      for (i = 0; i < cast.length; i++) {
        c = cast[i];
        if (c.mode === 'toStaging' || c.mode === 'waitDoor' || c.mode === 'entering') {
          c.mode = 'toReturn';
          c.root.visible = true;
        }
      }
      var stillInside = false;
      var blockedDoorway = false;
      for (i = 0; i < cast.length; i++) {
        if (cast[i].mode === 'inside' || cast[i].mode === 'exiting') {
          stillInside = true;
        }
        if (cast[i].mode === 'toReturn') {
          var ddx = cast[i].root.position.x - HOME_DOOR.x;
          var ddz = cast[i].root.position.z - HOME_DOOR.z;
          if (Math.sqrt(ddx * ddx + ddz * ddz) < 1.4) blockedDoorway = true;
        }
      }
      if (!stillInside && !blockedDoorway) homeward.doorOpen = false;
      for (i = 0; i < cast.length; i++) {
        c = cast[i];
        if (c.mode !== 'toReturn') continue;
        if (c.kind === 'ring') {
          var ang = Math.atan2(c.root.position.z / 18.3, c.root.position.x / 24.8);
          var tx = Math.cos(ang) * 24.8;
          var tz = Math.sin(ang) * 18.3;
          if (moveHomeward(c.root, tx, tz, HOME_SPEED, dt)) {
            c.ringActor.angle = ang;
            c.mode = '';
          }
        } else if (moveHomeward(c.root, c.base.x, c.base.z, HOME_SPEED * 0.8, dt)) {
          c.mode = '';
        }
      }
    }

    for (i = 0; i < cast.length; i++) {
      c = cast[i];
      if (!c.ringActor) continue;
      c.ringActor.homeMode = c.mode === '' ? '' : (goHome ? 'toHouse' : 'toRing');
    }
    updateHomewardDoor(dt);
  }

  var SHEEP_PEN_HOMES = [
    [-3.2, 1.4], [-1.6, 1.6], [0.0, 1.4], [1.8, 1.6],
    [3.2, 1.2], [-2.8, -1.4], [-0.8, -1.6], [1.4, -1.4]
  ];

  function buildSheepPenRoutine() {
    sheepPen = { cast: [], gate: null, gateOpen: false };
    var pen = D.layout.sheep_pen;
    if (!pen || !built.sheepRoots) return;
    var cs = Math.cos(pen.ry || 0);
    var sn = Math.sin(pen.ry || 0);
    function penPoint(lx, lz) {
      return { x: pen.x + lx * cs + lz * sn, z: pen.z - lx * sn + lz * cs };
    }
    var entry = built.objects.sheep_pen;
    if (entry && entry.root && entry.root.userData && entry.root.userData.gate) {
      sheepPen.gate = entry.root.userData.gate;
      sheepPen.gateClosedX = sheepPen.gate.position.x;
      sheepPen.gateOpenX = sheepPen.gateClosedX + 1.9;
    }
    var animals = (built.sheepRoots || []).concat(built.goatRoots || []);
    for (var i = 0; i < animals.length; i++) {
      var root = animals[i];
      var home = SHEEP_PEN_HOMES[i % SHEEP_PEN_HOMES.length];
      sheepPen.cast.push({
        root: root,
        base: { x: root.position.x, z: root.position.z },
        approach: penPoint(-0.9 + i * 0.25, 4.8),
        insideGate: penPoint(0, 3.0),
        home: penPoint(home[0], home[1]),
        mode: ''
      });
    }
  }

  function updateSheepPen(dt) {
    var pen = sheepPen;
    if (!pen) return;
    var goHome = nightTarget > 0.5 || rainTarget > 0.5;
    var cast = pen.cast;
    var i;
    var c;
    if (goHome) {
      for (i = 0; i < cast.length; i++) {
        c = cast[i];
        c.root.visible = true;
        if (c.mode === '' || c.mode === 'toBase' || c.mode === 'toGateOut' || c.mode === 'toInsideOut') {
          c.mode = 'toGate';
        }
        if (c.mode === 'toGate') {
          if (moveHomeward(c.root, c.approach.x, c.approach.z, HOME_SPEED * 0.7, dt)) {
            c.mode = 'toInside';
          }
        } else if (c.mode === 'toInside') {
          if (moveHomeward(c.root, c.insideGate.x, c.insideGate.z, HOME_SPEED * 0.55, dt)) {
            c.mode = 'toPen';
          }
        } else if (c.mode === 'toPen') {
          if (moveHomeward(c.root, c.home.x, c.home.z, HOME_SPEED * 0.55, dt)) {
            c.mode = 'inside';
          }
        }
      }
    } else {
      for (i = 0; i < cast.length; i++) {
        c = cast[i];
        if (c.mode === 'toGate') c.mode = 'toBase';
        if (c.mode === 'inside' || c.mode === 'toPen' || c.mode === 'toInside') {
          c.mode = 'toInsideOut';
        }
        if (c.mode === 'toInsideOut') {
          if (moveHomeward(c.root, c.insideGate.x, c.insideGate.z, HOME_SPEED * 0.55, dt)) {
            c.mode = 'toGateOut';
          }
        } else if (c.mode === 'toGateOut') {
          if (moveHomeward(c.root, c.approach.x, c.approach.z, HOME_SPEED * 0.6, dt)) {
            c.mode = 'toBase';
          }
        } else if (c.mode === 'toBase') {
          if (moveHomeward(c.root, c.base.x, c.base.z, HOME_SPEED * 0.7, dt)) {
            c.mode = '';
          }
        }
      }
    }
    var allInside = true;
    var anyInsideOrOut = false;
    for (i = 0; i < cast.length; i++) {
      if (cast[i].mode !== 'inside') allInside = false;
      if (cast[i].mode === 'inside' || cast[i].mode === 'toInsideOut' || cast[i].mode === 'toGateOut') {
        anyInsideOrOut = true;
      }
    }
    pen.gateOpen = goHome ? !allInside : anyInsideOrOut;
    if (pen.gate) {
      var targetX = pen.gateOpen ? pen.gateOpenX : pen.gateClosedX;
      var gdx = targetX - pen.gate.position.x;
      var gstep = 2.4 * dt;
      if (Math.abs(gdx) <= gstep) pen.gate.position.x = targetX;
      else pen.gate.position.x += gdx > 0 ? gstep : -gstep;
    }
  }

  var HORSE_STABLE_SPOTS = [
    { x: -50.6, z: -29.6, yaw: Math.PI },
    { x: -45.4, z: -29.6, yaw: Math.PI }
  ];
  var HORSE_STABLE_GATE = { x: -41.0, z: -26.0 };

  function buildHorseHomeRoutine() {
    horseHome = { cast: [] };
    var roots = built.horseRoots || [];
    for (var i = 0; i < roots.length; i++) {
      horseHome.cast.push({
        root: roots[i],
        base: { x: roots[i].position.x, z: roots[i].position.z },
        spot: HORSE_STABLE_SPOTS[i % HORSE_STABLE_SPOTS.length],
        gate: HORSE_STABLE_GATE,
        mode: '',
        stage: 0
      });
    }
  }

  function updateHorseHome(dt) {
    var hh = horseHome;
    if (!hh) return;
    var goHome = nightTarget > 0.5 || rainTarget > 0.5;
    for (var i = 0; i < hh.cast.length; i++) {
      var c = hh.cast[i];
      if (goHome) {
        if (c.mode === '' || c.mode === 'toBase' || c.mode === 'toGateOut') c.mode = 'toGate';
        if (c.mode === 'toGate') {
          if (moveHomeward(c.root, c.gate.x, c.gate.z, 4.2, dt)) c.mode = 'toStable';
        } else if (c.mode === 'toStable') {
          if (moveHomeward(c.root, c.spot.x, c.spot.z, 3.6, dt)) {
            c.mode = 'atStable';
            c.root.rotation.y = c.spot.yaw;
          }
        }
      } else {
        if (c.mode === 'atStable' || c.mode === 'toStable') c.mode = 'toGateOut';
        if (c.mode === 'toGateOut') {
          if (moveHomeward(c.root, c.gate.x, c.gate.z, 3.6, dt)) c.mode = 'toBase';
        } else if (c.mode === 'toBase') {
          if (moveHomeward(c.root, c.base.x, c.base.z, 4.2, dt)) c.mode = '';
        }
      }
    }
  }

  function startCoopExit(r) {
    r.root.visible = true;
    r.root.position.set(r.door.x, r.baseY, r.door.z);
    r.root.scale.setScalar(0.58);
    r.root.rotation.set(0, r.faceYaw, 0);
    r.fromX = r.door.x;
    r.fromZ = r.door.z;
    r.toX = r.stage.x;
    r.toZ = r.stage.z;
    r.travelT = 0;
    r.travelDur = 0.7;
    r.state = 'exit';
  }

  function updateCoopBirds(dt, now) {
    if (!coopBirdRoutines.length) return;
    var forceNight = nightTarget > 0.5;
    var forceRain = !forceNight && rainTarget > 0.5;
    if (forceNight && !wasForceNight) {
      for (var fi = 0; fi < coopBirdRoutines.length; fi++) {
        coopBirdRoutines[fi].forceDelay = fi * 0.8;
      }
    }
    wasForceNight = forceNight;

    for (var i = 0; i < coopBirdRoutines.length; i++) {
      var r = coopBirdRoutines[i];
      var root = r.root;
      var cfg = r.cfg;

      if (forceNight) {
        r.worm.visible = false;
        r.wasForced = true;
        if (r.state === 'inside') {
          root.visible = false;
          r.roostedForNight = true;
          continue;
        }
        if (r.state !== 'toCoop' && r.state !== 'enter') {
          if (r.forceDelay > 0) {
            r.forceDelay -= dt;
            continue;
          }
          r.target = r.stage;
          r.faceYaw = Math.atan2(r.door.x - r.stage.x, r.door.z - r.stage.z);
          r.state = 'toCoop';
        }
      } else if (forceRain) {
        r.worm.visible = false;
        r.wasForced = true;
        if (r.state === 'inside') {
          startCoopExit(r);
          continue;
        }
        if (r.state !== 'toShelter' && r.state !== 'shelter' && r.state !== 'exit' && r.state !== 'enter') {
          r.target = r.shelter;
          r.faceYaw = Math.atan2(r.shelter.x - root.position.x, r.shelter.z - root.position.z);
          r.state = 'toShelter';
        }
      } else {
        if (r.state === 'shelter') {
          r.state = 'wait';
          r.timer = 0.5;
          root.rotation.x = 0;
          root.rotation.z = 0;
          r.wasForced = false;
        }
        if (r.state === 'toShelter') {
          r.state = 'wait';
          r.timer = 0.5;
          root.rotation.x = 0;
          root.rotation.z = 0;
          r.wasForced = false;
        }
        if (r.state === 'inside' && r.wasForced) {
          r.wasForced = false;
          startCoopExit(r);
          continue;
        }
        if (r.wasForced && r.state !== 'toCoop' && r.state !== 'enter') {
          r.wasForced = false;
        }
      }

      if (!coopBirdAuto && !forceNight && !forceRain) {
        continue;
      }
      if (reduceMotion && !forceNight && !forceRain) {
        resetCoopBird(r);
        continue;
      }
      if (r.worm.visible) {
        r.worm.rotation.y = Math.sin(now * 9) * 0.35;
        r.worm.position.y = 0.05 + Math.abs(Math.sin(now * 7)) * 0.03;
      }

      if (r.state === 'wait') {
        root.rotation.x = 0;
        root.rotation.z = Math.sin(now * 2 + cfg.phase) * 0.02;
        root.position.y = r.baseY + Math.abs(Math.sin(now * 3.4 + cfg.phase)) * 0.02;
        coopLegsRest(cfg);
        r.timer -= dt;
        if (r.timer <= 0) {
          var roll = Math.random();
          if (roll < r.enterChance && !coopIsBusy(r)) {
            r.target = r.stage;
            r.faceYaw = Math.atan2(r.door.x - r.stage.x, r.door.z - r.stage.z);
            r.state = 'toCoop';
          } else if (roll < r.enterChance + 0.25) {
            startCoopPeck(r);
          } else {
            r.target = pickCoopTarget(r);
            r.faceYaw = root.rotation.y;
            r.state = 'walk';
          }
        }
      } else if (r.state === 'walk' || r.state === 'toCoop' || r.state === 'toShelter') {
        var dx = r.target.x - root.position.x;
        var dz = r.target.z - root.position.z;
        var dist = Math.sqrt(dx * dx + dz * dz);
        var step = CHICKEN_WALK_SPEED * dt;
        if (dist <= step) {
          root.position.x = r.target.x;
          root.position.z = r.target.z;
          coopLegsRest(cfg);
          if (r.state === 'toCoop') {
            root.rotation.y = r.faceYaw;
            r.state = 'enter';
            r.fromX = root.position.x;
            r.fromZ = root.position.z;
            r.toX = r.door.x;
            r.toZ = r.door.z;
            r.travelT = 0;
            r.travelDur = 0.65;
          } else if (r.state === 'toShelter') {
            r.state = 'shelter';
            root.rotation.x = 0.18;
            root.rotation.z = 0;
          } else if (Math.random() < 0.65) {
            startCoopPeck(r);
          } else {
            r.state = 'wait';
            r.timer = 1 + Math.random() * 2.5;
          }
        } else {
          root.position.x += dx / dist * step;
          root.position.z += dz / dist * step;
          root.rotation.y = Math.atan2(dx, dz);
          r.walkPhase += dt * 10.5;
          coopLegsPose(cfg, r.walkPhase, 0.45);
          root.rotation.x = 0;
          root.rotation.z = Math.sin(r.walkPhase) * 0.07;
          root.position.y = r.baseY + Math.abs(Math.sin(r.walkPhase * 2)) * 0.035;
        }
      } else if (r.state === 'peck') {
        root.rotation.x = 0.32 + Math.abs(Math.sin(now * 9.5)) * 0.22;
        root.rotation.z = Math.sin(now * 3.2) * 0.02;
        root.position.y = r.baseY + Math.abs(Math.sin(now * 9.5)) * 0.015;
        coopLegsRest(cfg);
        r.timer -= dt;
        if (r.wormTimer > 0) {
          r.wormTimer -= dt;
          if (r.wormTimer <= 0) r.worm.visible = false;
        }
        if (r.timer <= 0) {
          r.worm.visible = false;
          root.rotation.x = 0;
          r.state = 'wait';
          r.timer = 1.2 + Math.random() * 3;
        }
      } else if (r.state === 'shelter') {
        root.rotation.x = 0.18;
        root.rotation.z = reduceMotion ? 0 : Math.sin(now * 18 + cfg.phase) * 0.012;
        root.position.y = r.baseY;
        coopLegsRest(cfg);
      } else if (r.state === 'enter' || r.state === 'exit') {
        r.travelT = Math.min(r.travelDur, r.travelT + dt);
        var k = r.travelT / r.travelDur;
        var e = k * k * (3 - 2 * k);
        var nx = r.fromX + (r.toX - r.fromX) * e;
        var nz = r.fromZ + (r.toZ - r.fromZ) * e;
        if (r.state === 'enter') {
          root.position.set(nx, r.baseY + 0.3 * e, nz);
          root.scale.setScalar(1 - 0.42 * e);
        } else {
          root.position.set(nx, r.baseY + 0.3 * (1 - e), nz);
          root.scale.setScalar(0.58 + 0.42 * e);
        }
        root.rotation.set(0, r.faceYaw, 0);
        coopLegsRest(cfg);
        if (r.travelT >= r.travelDur) {
          if (r.state === 'enter') {
            root.visible = false;
            root.scale.setScalar(1);
            r.state = 'inside';
            r.timer = 3 + Math.random() * 3.5;
            if (forceNight) {
              r.roostedForNight = true;
            }
          } else {
            root.scale.setScalar(1);
            root.position.y = r.baseY;
            r.state = 'wait';
            r.timer = 1.5 + Math.random() * 3;
            if (r.roostedForNight) {
              r.roostedForNight = false;
              if (r.id === 'rooster' && rainTarget < 0.5 && !reduceMotion) {
                pendingCrow = true;
              }
            }
          }
        }
      } else if (r.state === 'inside') {
        root.visible = false;
        r.timer -= dt;
        if (r.timer <= 0) {
          root.visible = true;
          root.position.set(r.door.x, r.baseY, r.door.z);
          root.scale.setScalar(0.58);
          root.rotation.set(0, r.faceYaw, 0);
          r.fromX = r.door.x;
          r.fromZ = r.door.z;
          r.toX = r.stage.x;
          r.toZ = r.stage.z;
          r.travelT = 0;
          r.travelDur = 0.7;
          r.state = 'exit';
        }
      }
    }

    if (pendingCrow && global.FarmAgents && global.FarmAgents.isStoryActive &&
      !global.FarmAgents.isStoryActive() && global.FarmAgents.trigger) {
      pendingCrow = false;
      global.FarmAgents.trigger('rooster_crow');
    }
  }

  // 故事接管鸡舍的小鸡时暂停自动巡游；恢复时回到原位重新等待
  S.setCoopBirdsAuto = function (on) {
    coopBirdAuto = !!on;
    return true;
  };

  // ---------------------------------------------------------------
  // 懒猫小剧场：睡觉（呼吸/尾巴轻摆）→ 醒来睁眼 → 抻懒腰打哈欠
  // → 地上打滚 → 再睡回去。天黑时一直睡；白天循环。
  // ---------------------------------------------------------------
  var lazyCatRoutine = null;

  function setLazyCatEyes(cfg, open) {
    if (!cfg) return;
    if (cfg.eyesClosed) {
      for (var i = 0; i < cfg.eyesClosed.length; i++) cfg.eyesClosed[i].visible = !open;
    }
    if (cfg.eyesOpen) {
      for (var j = 0; j < cfg.eyesOpen.length; j++) cfg.eyesOpen[j].visible = open;
    }
  }

  function resetLazyCatPose(r, sleeping) {
    var cfg = r.cfg;
    var root = r.root;
    root.rotation.set(0, r.homeYaw, 0);
    root.position.y = r.baseY;
    if (cfg.head) {
      cfg.head.rotation.set(0, 0, 0);
      cfg.head.position.set(0, r.headY, r.headZ);
    }
    if (cfg.paws) {
      for (var i = 0; i < cfg.paws.length; i++) cfg.paws[i].position.z = cfg.pawZ;
    }
    if (cfg.yawn) cfg.yawn.visible = false;
    setLazyCatEyes(cfg, !sleeping);
  }

  function buildLazyCatRoutine() {
    lazyCatRoutine = null;
    var cat = built && built.lazyCat;
    if (!cat || !cat.userData.idle) return;
    var cfg = cat.userData.idle;
    var head = cfg.head;
    lazyCatRoutine = {
      root: cat,
      cfg: cfg,
      baseY: cat.position.y,
      homeYaw: cat.rotation.y,
      headY: head ? head.position.y : 0,
      headZ: head ? head.position.z : 0,
      state: 'sleep',
      timer: 7 + Math.random() * 8,
      t: 0,
      rollPhase: 0,
      rollDur: 3.2,
      settleZ: 0,
      settleX: 0
    };
    resetLazyCatPose(lazyCatRoutine, true);
  }

  function updateLazyCat(dt, now) {
    var r = lazyCatRoutine;
    if (!r) return;
    var cfg = r.cfg;
    var root = r.root;
    var head = cfg.head;

    if (nightTarget > 0.5 || reduceMotion) {
      resetLazyCatPose(r, true);
      r.state = 'sleep';
      r.timer = 6 + Math.random() * 5;
      return;
    }

    if (r.state === 'sleep') {
      root.rotation.x = 0;
      root.rotation.z = 0;
      root.position.y = r.baseY + Math.sin(now * 1.4) * 0.008;
      if (head) {
        head.rotation.x = Math.sin(now * 0.9) * 0.015;
        head.rotation.z = 0;
        head.position.set(0, r.headY, r.headZ);
      }
      if (cfg.tail) cfg.tail.rotation.y = Math.sin(now * 1.1) * 0.24;
      if (cfg.paws) {
        for (var i = 0; i < cfg.paws.length; i++) cfg.paws[i].position.z = cfg.pawZ;
      }
      if (cfg.yawn) cfg.yawn.visible = false;
      setLazyCatEyes(cfg, false);
      r.timer -= dt;
      if (r.timer <= 0) {
        r.state = 'wake';
        r.t = 0;
      }
    } else if (r.state === 'wake') {
      r.t += dt;
      var k = Math.min(1, r.t / 1.2);
      var e = k * k * (3 - 2 * k);
      root.position.y = r.baseY + 0.012 * e;
      if (head) {
        head.rotation.x = -0.3 * e;
        head.position.set(0, r.headY, r.headZ);
      }
      setLazyCatEyes(cfg, true);
      if (cfg.tail) cfg.tail.rotation.y = Math.sin(now * 2.2) * 0.3;
      if (k >= 1) {
        r.state = 'stretch';
        r.t = 0;
      }
    } else if (r.state === 'stretch') {
      r.t += dt;
      var ks = Math.min(1, r.t / 2.4);
      var arch = Math.sin(Math.PI * ks);
      root.rotation.x = -0.14 * arch;
      root.position.y = r.baseY + 0.02 * arch;
      if (head) {
        head.rotation.x = -0.3 - 0.16 * arch;
        head.position.set(0, r.headY, r.headZ + 0.05 * arch);
      }
      if (cfg.paws) {
        for (var pi = 0; pi < cfg.paws.length; pi++) cfg.paws[pi].position.z = cfg.pawZ + 0.1 * arch;
      }
      if (cfg.tail) cfg.tail.rotation.y = Math.sin(now * 3) * 0.3;
      if (cfg.yawn) cfg.yawn.visible = ks > 0.18 && ks < 0.72;
      setLazyCatEyes(cfg, true);
      if (ks >= 1) {
        r.state = 'roll';
        r.t = 0;
        r.rollPhase = 0;
        r.rollDur = 3.2;
      }
    } else if (r.state === 'roll') {
      r.t += dt;
      r.rollPhase += dt * 5.4;
      var wob = Math.sin(r.rollPhase);
      root.rotation.z = wob * 0.85;
      root.rotation.x = 0.02 * Math.sin(r.rollPhase * 0.5);
      root.position.y = r.baseY + 0.012 + Math.abs(wob) * 0.05;
      if (head) {
        head.rotation.x = -0.12;
        head.rotation.z = -wob * 0.22;
        head.position.set(0, r.headY, r.headZ);
      }
      if (cfg.paws) {
        for (var pj = 0; pj < cfg.paws.length; pj++) cfg.paws[pj].position.z = cfg.pawZ + Math.abs(wob) * 0.04;
      }
      if (cfg.tail) cfg.tail.rotation.y = Math.sin(r.rollPhase * 1.7) * 0.5;
      if (cfg.yawn) cfg.yawn.visible = false;
      setLazyCatEyes(cfg, true);
      if (r.t >= r.rollDur) {
        r.state = 'settle';
        r.t = 0;
        r.settleZ = root.rotation.z;
        r.settleX = root.rotation.x;
      }
    } else if (r.state === 'settle') {
      r.t += dt;
      var kt = Math.min(1, r.t / 1.8);
      var et = kt * kt * (3 - 2 * kt);
      root.rotation.z = r.settleZ * (1 - et);
      root.rotation.x = r.settleX * (1 - et);
      root.position.y = r.baseY + 0.012 * (1 - et);
      if (head) {
        head.rotation.x = -0.12 * (1 - et);
        head.rotation.z = 0;
        head.position.set(0, r.headY, r.headZ);
      }
      if (cfg.paws) {
        for (var pk = 0; pk < cfg.paws.length; pk++) cfg.paws[pk].position.z = cfg.pawZ;
      }
      if (cfg.tail) cfg.tail.rotation.y = Math.sin(now * 1.2) * 0.24;
      if (kt >= 0.6) setLazyCatEyes(cfg, false);
      if (kt >= 1) {
        r.state = 'sleep';
        r.timer = 8 + Math.random() * 8;
      }
    }
  }

  // ---------------------------------------------------------------
  // 运粮小剧场：拖拉机拉着拖车每绕农场一圈，都会在谷仓门口的土路岔口停一次。
  // 停稳 → 谷仓门打开 → 农夫推着满满一车粮食走到拖车旁倒进去 →
  // 推空车回谷仓、把门关上 → 拖拉机才继续往前开。
  // 全程躲着兔子走，不会从它身上碾过去。
  // ---------------------------------------------------------------
  var GRAIN_BAY_ANGLE = 3.93;      // 拖车停车点（椭圆参数角，正好落在通往谷仓的土路口）
  var GRAIN_TRACTOR_GAP = 0.15;    // 拖拉机比拖车领先的角度
  var GRAIN_WALK_SPEED = 2.0;
  var GRAIN_DOOR_SPEED = 1.9;
  var GRAIN_POUR_TIME = 2.4;
  var GRAIN_RABBIT_CLEAR = 2.0;    // 农夫和兔子之间的最小距离
  var grainCycle = null;

  S.getGrainState = function () {
    return {
      active: !!(grainCycle && grainCycle.state && grainCycle.state !== 'idle'),
      state: grainCycle ? grainCycle.state : 'idle'
    };
  };

  function buildGrainCycle() {
    grainCycle = null;
    if (!built || !built.grainFarmer) return;
    var tEntry = built.objects.trailer;
    var kEntry = built.objects.tractor;
    var bEntry = built.objects.barn;
    if (!tEntry || !kEntry || !bEntry) return;
    var farmer = built.grainFarmer;
    var doors = bEntry.root.userData.doors;
    if (!doors || !farmer.userData.barrowPivot || !farmer.userData.barrow) return;
    var tractorActor = null;
    var trailerActor = null;
    for (var i = 0; i < built.actors.length; i++) {
      if (built.actors[i].id === 'tractor') tractorActor = built.actors[i];
      if (built.actors[i].id === 'trailer') trailerActor = built.actors[i];
    }
    if (!tractorActor || !trailerActor) return;
    var barn = bEntry.root;

    // 倒粮时空中飞过的小谷粒：从独轮车斗划一道弧线，翻过拖车挡板落进车斗里。
    // 场景根挂在原点，谷粒直接挂上去按世界坐标摆放即可。
    var bits = [];
    var bitMat = new THREE.MeshPhongMaterial({
      color: 0xF2C14E, flatShading: true, shininess: 0, specular: 0x000000
    });
    var bitGeo = new THREE.BoxGeometry(0.1, 0.1, 0.1);
    for (var nb = 0; nb < 7; nb++) {
      var bit = new THREE.Mesh(bitGeo, bitMat);
      bit.visible = false;
      built.root.add(bit);
      bits.push(bit);
    }

    grainCycle = {
      tractor: kEntry.root,
      trailer: tEntry.root,
      tractorActor: tractorActor,
      trailerActor: trailerActor,
      tractorSpeed: tractorActor.speed,
      trailerSpeed: trailerActor.speed,
      doors: doors,
      farmer: farmer,
      pivot: farmer.userData.barrowPivot,
      barrowHeap: farmer.userData.barrow.userData.heap,
      trailerHeap: tEntry.root.userData.heap,
      doorX: barn.position.x + Math.sin(barn.rotation.y) * 4.95,
      doorZ: barn.position.z + Math.cos(barn.rotation.y) * 4.95,
      intoX: Math.sin(barn.rotation.y),
      intoZ: Math.cos(barn.rotation.y),
      state: 'idle',
      doorT: 0,
      walk: 0,
      total: 0,
      path: [],
      pourT: 0,
      standX: 0,
      standZ: 0,
      bits: bits,
      fromX: 0, fromY: 0, fromZ: 0,
      toX: 0, toY: 0, toZ: 0
    };
    if (grainCycle.trailerHeap) grainCycle.trailerHeap.scale.set(1, 0.12, 1);
    if (grainCycle.barrowHeap) grainCycle.barrowHeap.scale.set(1, 1, 1);
    for (var b = 0; b < bits.length; b++) bits[b].visible = false;
  }

  function startGrainTrip(gc) {
    // 拖车停在哪，就在它靠谷仓那一侧找个位置倒粮
    var tp = gc.trailer.position;
    var ry = gc.trailer.rotation.y;
    var lx = Math.cos(ry);
    var lz = -Math.sin(ry);
    var dx = gc.doorX - tp.x;
    var dz = gc.doorZ - tp.z;
    var dd = Math.sqrt(dx * dx + dz * dz) || 1;
    var side = (lx * (dx / dd) + lz * (dz / dd)) >= 0 ? 1 : -1;
    // 站得离拖车远一点，整辆独轮车（连车头轮子）都留在挡板外面，不会插进车斗
    gc.standX = tp.x + lx * side * 2.85;
    gc.standZ = tp.z + lz * side * 2.85;

    // 倒粮弧线：从独轮车车斗顶划一道弧线，翻过挡板落进拖车斗里
    var yawTo = Math.atan2(tp.x - gc.standX, tp.z - gc.standZ);
    gc.fromX = gc.standX + Math.sin(yawTo) * 1.28;
    gc.fromZ = gc.standZ + Math.cos(yawTo) * 1.28;
    gc.fromY = 1.34;
    var sx = Math.sin(ry);
    var cx = Math.cos(ry);
    gc.toX = tp.x + lx * side * 0.45 - sx * 1.0;
    gc.toZ = tp.z + lz * side * 0.45 - cx * 1.0;
    gc.toY = 1.5;

    // 从谷仓门口顺着通往谷仓的土路走到拖车旁边
    var pts = [
      { x: gc.doorX, z: gc.doorZ },
      { x: -33.5, z: -22.3 },
      { x: -30.5, z: -20.6 },
      { x: -26.5, z: -17.9 },
      { x: -22.8, z: -15.2 },
      { x: gc.standX, z: gc.standZ }
    ];
    var total = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      var ax = pts[i + 1].x - pts[i].x;
      var az = pts[i + 1].z - pts[i].z;
      pts[i].len = Math.sqrt(ax * ax + az * az);
      total += pts[i].len;
    }
    gc.path = pts;
    gc.total = total;
    gc.walk = 0;
    gc.pourT = 0;
    gc.doorT = 0;

    // 门开到一半再把农夫露出来，免得他从门板里穿出来
    gc.farmer.position.set(gc.doorX, 0.05, gc.doorZ);
    gc.farmer.rotation.y = Math.atan2(pts[1].x - gc.doorX, pts[1].z - gc.doorZ);
    gc.farmer.visible = false;
    gc.pivot.rotation.x = 0;
    if (gc.barrowHeap) gc.barrowHeap.scale.set(1, 1, 1);
    if (gc.trailerHeap) gc.trailerHeap.scale.set(1, 0.12, 1);
  }

  function grainPathPos(gc, dist) {
    var pts = gc.path;
    var d = dist;
    for (var i = 0; i < pts.length - 1; i++) {
      var seg = pts[i].len || 0;
      if (d <= seg || i === pts.length - 2) {
        var k = seg > 0.0001 ? clamp(d / seg, 0, 1) : 0;
        return {
          x: pts[i].x + (pts[i + 1].x - pts[i].x) * k,
          z: pts[i].z + (pts[i + 1].z - pts[i].z) * k,
          yaw: Math.atan2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z)
        };
      }
      d -= seg;
    }
    return { x: pts[0].x, z: pts[0].z, yaw: 0 };
  }

  function placeGrainFarmer(gc, x, z, yaw, now, walking) {
    // 兔子可能在路上歇着，农夫绕着它走，绝不从它身上压过去
    var rb = built.objects.rabbit;
    if (rb) {
      var rx = x - rb.root.position.x;
      var rz = z - rb.root.position.z;
      var rd = Math.sqrt(rx * rx + rz * rz);
      if (rd < GRAIN_RABBIT_CLEAR && rd > 0.0001) {
        var push = GRAIN_RABBIT_CLEAR - rd;
        x += (rx / rd) * push;
        z += (rz / rd) * push;
      }
    }
    var bob = walking ? Math.abs(Math.sin(now * 4.6)) * 0.06 : 0;
    gc.farmer.position.set(x, 0.05 + bob, z);
    gc.farmer.rotation.y = yaw;
  }

  function updateGrainCycle(dt, now) {
    if (!grainCycle) return;
    var gc = grainCycle;

    if (gc.state === 'idle') {
      // 拖车开到岔口就刹住（也把拖拉机一起停住）
      var ta = gc.trailerActor;
      var lap = Math.floor((ta.angle - GRAIN_BAY_ANGLE) / (Math.PI * 2)) + 1;
      var bay = GRAIN_BAY_ANGLE + lap * Math.PI * 2;
      if (ta.angle + ta.speed * dt < bay) return;
      ta.angle = bay;
      gc.tractorActor.angle = bay + GRAIN_TRACTOR_GAP;
      ta.speed = 0;
      gc.tractorActor.speed = 0;
      startGrainTrip(gc);
      gc.state = 'opening';
      return;
    }

    if (gc.state === 'opening') {
      gc.doorT = Math.min(1, gc.doorT + dt * GRAIN_DOOR_SPEED);
      if (gc.doorT >= 0.7) gc.farmer.visible = true;
      if (gc.doorT >= 1) gc.state = 'walkOut';
    } else if (gc.state === 'walkOut') {
      gc.walk = Math.min(gc.total, gc.walk + GRAIN_WALK_SPEED * dt);
      var pos = grainPathPos(gc, gc.walk);
      placeGrainFarmer(gc, pos.x, pos.z, pos.yaw, now, true);
      if (gc.walk >= gc.total) {
        gc.pourT = 0;
        gc.state = 'pour';
      }
    } else if (gc.state === 'pour') {
      gc.pourT += dt;
      var k = clamp(gc.pourT / GRAIN_POUR_TIME, 0, 1);
      var tip = k < 0.22 ? k / 0.22 : (k > 0.82 ? (1 - k) / 0.18 : 1);
      gc.pivot.rotation.x = tip * 0.42;
      if (gc.barrowHeap) gc.barrowHeap.scale.set(1, Math.max(0.04, 1 - Math.min(1, k * 1.5)), 1);
      if (gc.trailerHeap) gc.trailerHeap.scale.set(1, 0.12 + 0.88 * k, 1);
      // 谷粒顺着弧线翻过挡板落进车斗
      var pouring = k > 0.06 && k < 0.95;
      for (var b = 0; b < gc.bits.length; b++) {
        var bit = gc.bits[b];
        bit.visible = pouring;
        if (!pouring) continue;
        var u = (gc.pourT / 0.8 + b / gc.bits.length) % 1;
        var lift = Math.sin(Math.PI * u) * 0.7;
        bit.position.set(
          gc.fromX + (gc.toX - gc.fromX) * u,
          gc.fromY + (gc.toY - gc.fromY) * u + lift,
          gc.fromZ + (gc.toZ - gc.fromZ) * u);
        bit.rotation.x = u * 6;
        bit.rotation.z = u * 4;
      }
      var tp = gc.trailer.position;
      placeGrainFarmer(gc, gc.standX, gc.standZ,
        Math.atan2(tp.x - gc.standX, tp.z - gc.standZ), now, false);
      if (gc.pourT >= GRAIN_POUR_TIME) {
        gc.pivot.rotation.x = 0;
        for (var hb = 0; hb < gc.bits.length; hb++) gc.bits[hb].visible = false;
        gc.state = 'walkBack';
      }
    } else if (gc.state === 'walkBack') {
      gc.walk = Math.max(0, gc.walk - GRAIN_WALK_SPEED * dt);
      var bp = grainPathPos(gc, gc.walk);
      placeGrainFarmer(gc, bp.x, bp.z, bp.yaw + Math.PI, now, true);
      if (gc.walk <= 0) gc.state = 'closing';
    } else if (gc.state === 'closing') {
      gc.doorT = Math.max(0, gc.doorT - dt * GRAIN_DOOR_SPEED);
      // 趁机退回谷仓里，让门板在他身后合上，而不是从他身上扫过去
      var back = (1 - gc.doorT) * 2.2;
      gc.farmer.position.set(
        gc.doorX - gc.intoX * back, 0.05, gc.doorZ - gc.intoZ * back);
      gc.farmer.rotation.y = Math.atan2(-gc.intoX, -gc.intoZ);
      if (gc.doorT <= 0) {
        gc.doorT = 0;
        gc.farmer.visible = false;
        if (gc.barrowHeap) gc.barrowHeap.scale.set(1, 1, 1);
        gc.trailerActor.speed = gc.trailerSpeed;
        gc.tractorActor.speed = gc.tractorSpeed;
        gc.state = 'idle';
      }
    }

    gc.doors.left.rotation.y = -gc.doorT * 1.9;
    gc.doors.right.rotation.y = gc.doorT * 1.9;
  }

  function updateCamera(dt) {
    if (tween) {
      tween.t += dt * 1000;
      var k = Math.min(1, tween.t / tween.dur);
      var e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
      goal.theta = tween.from.theta + (tween.to.theta - tween.from.theta) * e;
      goal.phi = tween.from.phi + (tween.to.phi - tween.from.phi) * e;
      goal.radius = tween.from.radius + (tween.to.radius - tween.from.radius) * e;
      goal.target.copy(tween.from.target).lerp(tween.to.target, e);
      if (k >= 1) tween = null;
    }
    var f = Math.min(1, dt * 8.5);
    cam.theta += (goal.theta - cam.theta) * f;
    cam.phi += (goal.phi - cam.phi) * f;
    cam.radius += (goal.radius - cam.radius) * f;
    cam.target.lerp(goal.target, f);
    cam.phi = clamp(cam.phi, D.camera.minPhi, D.camera.maxPhi);
    cam.radius = clamp(cam.radius, D.camera.minRadius, D.camera.maxRadius);

    tmpS.setFromSphericalCoords(cam.radius, cam.phi, cam.theta);
    camera.position.copy(cam.target).add(tmpS);
    camera.lookAt(cam.target);
  }

  function updateScene(dt) {
    var t = elapsed;

    var wm = built.objects.windmill;
    if (wm && wm.root.userData.spin && !reduceMotion) {
      wm.root.userData.spin.rotation.z -= dt * 0.85;
      wm.root.userData.vane.rotation.y = Math.sin(t * 1.3) * 0.28;
    }

    for (var s = 0; s < built.swayers.length; s++) {
      var sw = built.swayers[s];
      sw.obj.rotation.z = Math.sin(t * 1.15 + sw.phase) * sw.amp;
    }

    for (var i = 0; i < built.idles.length; i++) {
      var it = built.idles[i];
      var cfg = it.cfg;
      var o = it.root;
      var baseY = it.baseY == null ? o.position.y : it.baseY;
      if (cfg.kind === 'cow') {
        if (cfg.tail) cfg.tail.rotation.x = 0.5 + Math.sin(t * 2.1 + cfg.phase) * 0.22;
        if (cfg.head) cfg.head.rotation.x = 0.06 + Math.max(0, Math.sin(t * 0.5 + cfg.phase)) * 0.26;
        o.position.y = baseY + Math.sin(t * 1.7 + cfg.phase) * 0.02;
      } else if (cfg.kind === 'sheep') {
        if (cfg.head) cfg.head.rotation.x = 0.06 + Math.max(0, Math.sin(t * 0.45 + cfg.phase)) * 0.34;
        o.position.y = baseY + Math.sin(t * 1.5 + cfg.phase) * 0.02;
        o.rotation.z = Math.sin(t * 0.9 + cfg.phase) * 0.015;
      } else if (cfg.kind === 'horse') {
        if (cfg.tail) {
          cfg.tail.rotation.z = Math.sin(t * 1.4 + cfg.phase) * 0.28;
          cfg.tail.rotation.y = Math.sin(t * 0.8 + cfg.phase) * 0.14;
        }
        if (cfg.head) cfg.head.rotation.x = Math.sin(t * 0.9 + cfg.phase) * 0.04;
        if (cfg.earL) cfg.earL.rotation.z = 0.22 + Math.sin(t * 1.7 + cfg.phase) * 0.05;
        if (cfg.earR) cfg.earR.rotation.z = -0.22 - Math.sin(t * 1.7 + cfg.phase + 0.7) * 0.05;
        o.position.y = baseY + Math.sin(t * 1.2 + cfg.phase) * 0.02;
        o.rotation.z = Math.sin(t * 0.7 + cfg.phase) * 0.008;
      } else if (cfg.kind === 'pig') {
        o.rotation.z = Math.sin(t * 1.8 + cfg.phase) * 0.02;
        if (cfg.tail) cfg.tail.rotation.z = Math.sin(t * 2.6 + cfg.phase) * 0.14;
      } else if (cfg.kind === 'goat') {
        if (cfg.head) cfg.head.rotation.x = 0.05 + Math.max(0, Math.sin(t * 0.52 + cfg.phase)) * 0.3;
        o.rotation.z = Math.sin(t * 1.1 + cfg.phase) * 0.018;
      } else if (cfg.kind === 'chicken' || cfg.kind === 'rooster' || cfg.kind === 'chick') {
        o.position.y = baseY + Math.abs(Math.sin(t * 3.4 + cfg.phase)) * 0.05;
        o.rotation.z = Math.sin(t * 2.0 + cfg.phase) * 0.02;
      } else if (cfg.kind === 'duck' || cfg.kind === 'goose') {
        o.position.y = baseY + Math.sin(t * 1.3 + cfg.phase) * 0.03;
      } else if (cfg.kind === 'rabbit') {
        // 不再原地蹦跳：站立时由 updateRabbitTrips 接管位置（等一会儿就跑向胡萝卜地），
        // 这里只留耳朵的轻微抖动兜底（reduceMotion 时也能保持一点生气）。
        if (cfg.earL) cfg.earL.rotation.z = 0.12 + Math.sin(t * 1.9 + cfg.phase) * 0.06;
        if (cfg.earR) cfg.earR.rotation.z = -0.12 + Math.sin(t * 1.9 + cfg.phase + 0.7) * 0.06;
      } else if (cfg.kind === 'rabbit_graze') {
        // 牧场里的装饰兔：一会儿抬头、一会儿低头闻草，不再跳
        if (cfg.head) cfg.head.rotation.x = -0.28 - Math.max(0, Math.sin(t * 0.45 + cfg.phase)) * 0.34;
        if (cfg.earL) cfg.earL.rotation.z = 0.12 + Math.sin(t * 2.1 + cfg.phase) * 0.08;
        if (cfg.earR) cfg.earR.rotation.z = -0.12 + Math.sin(t * 2.1 + cfg.phase + 0.5) * 0.08;
      } else if (cfg.kind === 'cat') {
        o.rotation.z = Math.sin(t * 1.6 + cfg.phase) * 0.02;
        // 尾巴慢慢摆、耳朵时不时抖一下
        if (cfg.tail) cfg.tail.rotation.y = Math.sin(t * 1.2 + cfg.phase) * 0.07;
        if (cfg.earL) cfg.earL.rotation.z = 0.22 + Math.sin(t * 0.9 + cfg.phase) * 0.045;
        if (cfg.earR) cfg.earR.rotation.z = -0.22 + Math.sin(t * 0.9 + cfg.phase + 0.8) * 0.045;
      } else if (cfg.kind === 'lazy_cat') {
        if (cfg.tail) cfg.tail.rotation.y = Math.sin(t * 1.1 + cfg.phase) * 0.28;
        o.position.y = baseY + Math.sin(t * 0.8 + cfg.phase) * 0.012;
      } else if (cfg.kind === 'dog') {
        if (cfg.tail) cfg.tail.rotation.z = Math.sin(t * 8 + cfg.phase) * 0.45;
        if (cfg.earL) cfg.earL.rotation.z = -0.35 + Math.sin(t * 1.5 + cfg.phase) * 0.05;
        if (cfg.earR) cfg.earR.rotation.z = 0.35 - Math.sin(t * 1.5 + cfg.phase + 0.5) * 0.05;
      } else if (cfg.kind === 'bird') {
        o.position.y = baseY + Math.sin(t * 1.8 + cfg.phase) * 0.12;
        o.rotation.y = Math.sin(t * 0.6 + cfg.phase) * 0.3;
      }
    }

    if (!reduceMotion) {
      updateRabbitTrips(dt, t);
      updateGrainCycle(dt, t);
    }

    updateHorseRoutine(dt, t);
    updateCoopBirds(dt, t);
    updateFieldWork(dt, t);
    updateButterflies(t);
    updateDragonflies(t);
    updateDucklings(dt, t);
    updateLazyCat(dt, t);

    if (built.bee) {
      built.bee.position.x = beeBase.x + Math.sin(t * 0.62) * 3.2;
      built.bee.position.z = beeBase.z + Math.cos(t * 0.48) * 2.6;
      built.bee.position.y = beeBase.y + Math.sin(t * 2.1) * 0.4;
    }

    if (!reduceMotion) {
      for (var c = 0; c < built.clouds.length; c++) {
        var cl = built.clouds[c];
        cl.obj.position.x += cl.speed * dt;
        if (cl.obj.position.x > 125) cl.obj.position.x = -125;
      }
    }

    for (var r = 0; r < ripples.length; r++) {
      var rp = ripples[r];
      var k = (t * 0.22 + rp.offset) % 1;
      rp.mesh.scale.setScalar(1.2 + k * 8.5);
      rp.mesh.material.opacity = (1 - k) * 0.4;
    }

    if (night !== nightTarget) {
      var step = dt / 1.2;
      if (Math.abs(nightTarget - night) <= step) night = nightTarget;
      else night += (nightTarget > night ? step : -step);
      applySceneColors(night, rain);
    }

    if (rain !== rainTarget) {
      var rainStep = dt / 1.5;
      if (Math.abs(rainTarget - rain) <= rainStep) rain = rainTarget;
      else rain += (rainTarget > rain ? rainStep : -rainStep);
      applySceneColors(night, rain);
    }

    for (var f = 0; f < built.fireflies.length; f++) {
      var fl = built.fireflies[f];
      var fb = fireflyBase[f];
      fl.obj.position.x = fb.x + Math.sin(t * 0.5 + fb.phase) * fb.r;
      fl.obj.position.z = fb.z + Math.cos(t * 0.42 + fb.phase) * fb.r;
      fl.obj.position.y = fb.y + Math.sin(t * 1.6 + fb.phase) * 0.35;
      fl.obj.visible = night > 0.08 && rain < 0.5;
    }
    built.fireflyMat.opacity = night * 0.9 * (1 - rain);
    built.fireflyGroup.visible = night > 0.05 && rain < 0.5;

    if (rain < 0.01) {
      rainMesh.visible = false;
    } else {
      rainMesh.visible = true;
      rainMaterial.opacity = 0.55 * rain;
      var rainArr = rainMesh.geometry.attributes.position.array;
      for (var ri = 0; ri < RAIN_COUNT; ri++) {
        var d = rainDrops[ri];
        d.y -= d.speed * dt;
        if (d.y < 0) d.y = RAIN_TOP;
        var idx = ri * 6;
        rainArr[idx] = d.x;
        rainArr[idx + 1] = d.y;
        rainArr[idx + 2] = d.z;
        rainArr[idx + 3] = d.x - 0.12;
        rainArr[idx + 4] = d.y + d.len + 0.35 * rain;
        rainArr[idx + 5] = d.z;
      }
      rainMesh.geometry.attributes.position.needsUpdate = true;
    }

    if (selectedObj && ring && ring.visible) {
      var pulse = 1 + 0.07 * Math.sin(t * 4.2);
      ring.scale.setScalar((ring.userData.base || selectedBase) * pulse);
      ring.material.opacity = 0.48 + 0.28 * Math.sin(t * 4.2);
      var entry = built.objects[selectedId];
      if (entry && !entry.instanced) {
        var hs = selectedObj.userData.homeScale || 1;
        selectedObj.scale.setScalar(hs * (1.02 + 0.012 * Math.sin(t * 4.2)));
      }
      if (FOLLOW_SELECTION_IDS.indexOf(selectedId) >= 0) {
        selectedObj.getWorldPosition(tmpV);
        ring.position.x = tmpV.x;
        ring.position.z = tmpV.z;
      }
    }

    if (global.FarmAgents && global.FarmAgents.isReady && global.FarmAgents.isReady()) {
      global.FarmAgents.update(dt, reduceMotion ? 0 : dt, t);
    }

    updateHomeward(dt);
    updateSheepPen(dt);
    updateHorseHome(dt);
    placeActors(reduceMotion ? 0 : dt);
  }

  function lerpC(a, b, t) { return a.clone().lerp(b, t); }

  function applySceneColors(n, r) {
    if (!built || !scene) return;
    var rainPal = n > 0.5 ? RAIN_NIGHT : RAIN_DAY;
    var sky = lerpC(daySkyColor, nightSkyColor, n).lerp(new THREE.Color(rainPal.sky), r);
    var fog = lerpC(dayFogColor, nightFogColor, n).lerp(new THREE.Color(rainPal.fog), r);
    scene.background.copy(sky);
    if (skyDome) {
      skyDome.mat.color.copy(lerpC(new THREE.Color(0xFFFFFF), new THREE.Color(0x8E8CB0), n))
        .lerp(new THREE.Color(0x7C868F), r * 0.8);
    }
    scene.fog.color.copy(fog);
    scene.fog.near = 130 - 26 * r;
    scene.fog.far = 360 - 110 * r;
    hemi.color.copy(lerpC(dayHemiSky, nightHemiSky, n).lerp(new THREE.Color(rainPal.hemiSky), r * 0.75));
    hemi.groundColor.copy(lerpC(dayHemiGround, nightHemiGround, n).lerp(new THREE.Color(rainPal.hemiGround), r * 0.75));
    hemi.intensity = (DAY.hemiI + (NIGHT.hemiI - DAY.hemiI) * n) * (1 - 0.28 * r);
    dir.color.copy(lerpC(dayDir, nightDir, n).lerp(new THREE.Color(rainPal.dirColor), r * 0.7));
    dir.intensity = (DAY.dirI + (NIGHT.dirI - DAY.dirI) * n) * (1 - 0.65 * r);
    for (var i = 0; i < built.windowMats.length; i++) {
      built.windowMats[i].emissiveIntensity = n * 1.15;
    }
    for (var j = 0; j < built.lampMats.length; j++) {
      built.lampMats[j].emissiveIntensity = n * 1.5;
    }
    if (built.coopLamp) built.coopLamp.intensity = 6.5 * n * (1 - 0.25 * r);
    if (built.groundMat) {
      built.groundMat.color.copy(new THREE.Color(0x8FBF6A).lerp(new THREE.Color(0x5E8347), r * 0.7));
      built.groundMat.shininess = 18 * r;
    }
    if (built.cloudMats) {
      for (var c = 0; c < built.cloudMats.length; c++) {
        // 雨天云要变"厚"而不是变"黑"：深灰会让低多边形云看起来像漂浮的石头
        var cloudCol = new THREE.Color(0xFFFDF6)
          .lerp(new THREE.Color(0xE2E8EC), r * 0.7)
          .lerp(new THREE.Color(0x8E93A8), n * 0.55);
        built.cloudMats[c].color.copy(cloudCol);
        built.cloudMats[c].emissive.copy(cloudCol);
        built.cloudMats[c].emissiveIntensity = 0.72 * (1 - n * 0.15);
        built.cloudMats[c].opacity = 0.94;
      }
    }
    if (built.puddleMat) built.puddleMat.opacity = 0.35 * r;
    // 白天的草色差异在夜里毫无意义，只会变成一块块亮斑，随夜色淡出
    if (built.patchMats) {
      for (var pm = 0; pm < built.patchMats.length; pm++) {
        built.patchMats[pm].opacity = (pm % 2 === 0 ? 0.30 : 0.34) * (1 - n * 0.92) * (1 - r * 0.55);
      }
    }
    if (starField) {
      starField.visible = n > 0.02 && r < 0.5;
      starField.material.opacity = 0.9 * n * (1 - r);
    }
    if (sunDisc) sunDisc.visible = n < 0.5 && r < 0.55;
    if (moonDisc) moonDisc.visible = n > 0.05 && r < 0.6;
    if (built.bee) built.bee.visible = r < 0.5;
  }

  function loop() {
    if (!running) return;
    raf = global.requestAnimationFrame(loop);
    var dt = Math.min(clock.getDelta(), 0.06);
    elapsed += reduceMotion ? 0 : dt;
    frameCount++;
    if (frameCount % 6 === 0) renderer.shadowMap.needsUpdate = true;
    updateCamera(dt);
    updateScene(dt);
    renderer.render(scene, camera);
    if (hooks.onFrame) hooks.onFrame();
  }

  function start() {
    if (running || !renderer) return;
    running = true;
    if (clock) clock.getDelta();
    loop();
  }

  function stop() {
    running = false;
    if (raf) {
      global.cancelAnimationFrame(raf);
      raf = 0;
    }
  }

  function onVisibility() {
    if (document.hidden) stop();
    else start();
  }

  function collectPickRoots() {
    var roots = [];
    built.root.traverse(function (o) {
      if (o.userData && o.userData.wordId) {
        if (o.isMesh || o.isGroup) roots.push(o);
      }
    });
    return roots;
  }

  S.initPicker = function () {};

  var pickRootsReady = false;

  S.dispose = function () {
    stop();
    if (global.FarmAgents && global.FarmAgents.dispose) {
      try { global.FarmAgents.dispose(); } catch (e) {}
    }
    unbindEvents();
    if (scene) {
      scene.traverse(function (o) {
        if (o.geometry && o.geometry.dispose) o.geometry.dispose();
        if (o.material) {
          if (Array.isArray(o.material)) {
            for (var i = 0; i < o.material.length; i++) o.material[i].dispose();
          } else if (o.material.dispose) {
            o.material.dispose();
          }
        }
      });
    }
    if (renderer) {
      renderer.dispose();
      renderer = null;
    }
    scene = null;
    camera = null;
    built = null;
    rabbitTrips = [];
    grainCycle = null;
    started = false;
  };

  var originalBuildAll = null;

  S.getHooks = function () { return hooks; };

  S.afterBuild = function () {};

  S.collectPickRoots = collectPickRoots;

  S.pickRoots = function () {
    if (!built) return [];
    if (!pickRootsReady) {
      built.pickRoots = collectPickRoots();
      pickRootsReady = true;
    }
    return built.pickRoots;
  };

  if (global.FarmModels) {
    originalBuildAll = global.FarmModels.buildAll;
  }
})(window);
