(function (global) {
  'use strict';

  var THREE = global.THREE;
  var D = global.FarmData;
  var S = global.FarmScene || (global.FarmScene = {});

  var DAY = {
    sky: 0xDDF3FF,
    fog: 0xDDF3FF,
    hemiSky: 0xEAF7FF,
    hemiGround: 0xA8C686,
    hemiI: 0.66,
    dirColor: 0xFFF3D6,
    dirI: 0.72
  };
  var NIGHT = {
    sky: 0x2B2745,
    fog: 0x332E4E,
    hemiSky: 0x6A6790,
    hemiGround: 0x35482F,
    hemiI: 0.32,
    dirColor: 0xFFB577,
    dirI: 0.20
  };

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
  var reduceMotion = false;
  try {
    reduceMotion = !!(global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches);
  } catch (e) {}

  var ring = null;
  var selectedId = null;
  var selectedObj = null;
  var selectedBase = 1;

  var labelsVisible = false;

  var ripples = [];
  var beeBase = null;
  var fireflyBase = [];

  var tmpV = new THREE.Vector3();
  var tmpS = new THREE.Vector3();
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
    scene.fog = new THREE.Fog(DAY.fog, 110, 310);

    camera = new THREE.PerspectiveCamera(46, 1, 0.1, 720);

    hemi = new THREE.HemisphereLight(DAY.hemiSky, DAY.hemiGround, DAY.hemiI);
    scene.add(hemi);

    dir = new THREE.DirectionalLight(DAY.dirColor, DAY.dirI);
    dir.position.set(58, 96, 44);
    dir.castShadow = true;
    dir.shadow.mapSize.set(1024, 1024);
    dir.shadow.camera.left = -95;
    dir.shadow.camera.right = 95;
    dir.shadow.camera.top = 95;
    dir.shadow.camera.bottom = -95;
    dir.shadow.camera.near = 10;
    dir.shadow.camera.far = 280;
    dir.shadow.bias = -0.0015;
    scene.add(dir);
    scene.add(dir.target);

    built = global.FarmModels.buildAll(scene);
    built.pickRoots = collectPickRoots();
    for (var ii = 0; ii < built.idles.length; ii++) {
      built.idles[ii].baseY = built.idles[ii].root.position.y;
    }
    beeBase = built.bee.position.clone();
    for (var i = 0; i < built.fireflies.length; i++) {
      fireflyBase.push({ x: built.fireflies[i].x0, y: built.fireflies[i].baseY, z: built.fireflies[i].z0, phase: built.fireflies[i].phase, r: built.fireflies[i].r });
    }
    createRing();
    createRipples();

    clock = new THREE.Clock();
    bindEvents();
    applyView('overview', true);
    placeActors(0);
    applyNightColors(0);

    S.resize();
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
    if (hits.length) {
      var obj = hits[0].object;
      while (obj) {
        if (obj.userData && obj.userData.wordId) { id = obj.userData.wordId; target = obj; break; }
        obj = obj.parent;
      }
    }
    if (hooks.onPick) hooks.onPick(id, target);
  }

  S.setView = function (name) {
    applyView(name, false);
  };

  S.resetView = function () {
    applyView('overview', false);
  };

  function applyView(name, instant) {
    var v = D.views[name];
    if (!v) return;
    var to = {
      theta: v.theta,
      phi: clamp(v.phi, D.camera.minPhi, D.camera.maxPhi),
      radius: clamp(v.radius, D.camera.minRadius, D.camera.maxRadius),
      target: new THREE.Vector3(v.target[0], v.target[1], v.target[2])
    };
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
    }
  }

  S.setNight = function (on) {
    nightTarget = on ? 1 : 0;
  };

  S.getNight = function () { return nightTarget > 0.5; };

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
      ring.position.set(0, 0.09, -52);
      selectedBase = 6;
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
      if (walker) walker.obj.position.y = 0.05 + Math.abs(Math.sin(elapsed * 4.2)) * 0.06;
      if (walker2) walker2.obj.position.y = 0.05 + Math.abs(Math.sin(elapsed * 4.6 + 1)) * 0.06;
      if (dog) dog.obj.position.y = 0.05 + Math.abs(Math.sin(elapsed * 6.0 + 2)) * 0.08;
    }
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
        o.position.y = baseY + Math.sin(t * 1.7 + cfg.phase) * 0.02;
      } else if (cfg.kind === 'sheep') {
        o.position.y = baseY + Math.sin(t * 1.5 + cfg.phase) * 0.02;
        o.rotation.z = Math.sin(t * 0.9 + cfg.phase) * 0.015;
      } else if (cfg.kind === 'horse') {
        if (cfg.tail) cfg.tail.rotation.z = Math.sin(t * 1.4 + cfg.phase) * 0.3;
        o.position.y = baseY + Math.sin(t * 1.2 + cfg.phase) * 0.02;
      } else if (cfg.kind === 'pig') {
        o.rotation.z = Math.sin(t * 1.8 + cfg.phase) * 0.02;
      } else if (cfg.kind === 'goat') {
        o.rotation.z = Math.sin(t * 1.1 + cfg.phase) * 0.018;
      } else if (cfg.kind === 'chicken' || cfg.kind === 'rooster') {
        o.position.y = baseY + Math.abs(Math.sin(t * 3.4 + cfg.phase)) * 0.05;
        o.rotation.z = Math.sin(t * 2.0 + cfg.phase) * 0.02;
      } else if (cfg.kind === 'duck' || cfg.kind === 'goose') {
        o.position.y = baseY + Math.sin(t * 1.3 + cfg.phase) * 0.03;
      } else if (cfg.kind === 'rabbit') {
        o.position.y = baseY + Math.abs(Math.sin(t * 2.3 + cfg.phase)) * 0.42;
      } else if (cfg.kind === 'cat') {
        o.rotation.z = Math.sin(t * 1.6 + cfg.phase) * 0.02;
      } else if (cfg.kind === 'lazy_cat') {
        if (cfg.tail) cfg.tail.rotation.y = Math.sin(t * 1.1 + cfg.phase) * 0.28;
        o.position.y = baseY + Math.sin(t * 0.8 + cfg.phase) * 0.012;
      } else if (cfg.kind === 'dog') {
        if (cfg.tail) cfg.tail.rotation.z = Math.sin(t * 8 + cfg.phase) * 0.5;
      } else if (cfg.kind === 'bird') {
        o.position.y = baseY + Math.sin(t * 1.8 + cfg.phase) * 0.12;
        o.rotation.y = Math.sin(t * 0.6 + cfg.phase) * 0.3;
      }
    }

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

    for (var f = 0; f < built.fireflies.length; f++) {
      var fl = built.fireflies[f];
      var fb = fireflyBase[f];
      fl.obj.position.x = fb.x + Math.sin(t * 0.5 + fb.phase) * fb.r;
      fl.obj.position.z = fb.z + Math.cos(t * 0.42 + fb.phase) * fb.r;
      fl.obj.position.y = fb.y + Math.sin(t * 1.6 + fb.phase) * 0.35;
      fl.obj.visible = night > 0.08;
    }
    built.fireflyMat.opacity = night * 0.9;
    built.fireflyGroup.visible = night > 0.05;

    if (night !== nightTarget) {
      var step = dt / 1.2;
      if (Math.abs(nightTarget - night) <= step) night = nightTarget;
      else night += (nightTarget > night ? step : -step);
      applyNightColors(night);
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
      if (selectedId === 'tractor' || selectedId === 'trailer' || selectedId === 'farmer' || selectedId === 'child' || selectedId === 'dog') {
        selectedObj.getWorldPosition(tmpV);
        ring.position.x = tmpV.x;
        ring.position.z = tmpV.z;
      }
    }

    placeActors(reduceMotion ? 0 : dt);
  }

  function applyNightColors(n) {
    scene.background.copy(daySkyColor).lerp(nightSkyColor, n);
    scene.fog.color.copy(dayFogColor).lerp(nightFogColor, n);
    hemi.color.copy(dayHemiSky).lerp(nightHemiSky, n);
    hemi.groundColor.copy(dayHemiGround).lerp(nightHemiGround, n);
    hemi.intensity = DAY.hemiI + (NIGHT.hemiI - DAY.hemiI) * n;
    dir.color.copy(dayDir).lerp(nightDir, n);
    dir.intensity = DAY.dirI + (NIGHT.dirI - DAY.dirI) * n;
    for (var i = 0; i < built.windowMats.length; i++) {
      built.windowMats[i].emissiveIntensity = n * 1.15;
    }
    for (var j = 0; j < built.lampMats.length; j++) {
      built.lampMats[j].emissiveIntensity = n * 1.5;
    }
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
