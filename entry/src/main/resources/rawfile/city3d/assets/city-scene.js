/* ============================================================
   小词城 Word City · 3D 场景、交通、行人、相机与拾取
   导出 window.WordCityScene = { init, setView, focusWord, resetView,
                                 clearHighlight, setLabelsEnabled, releaseWord, setNight }
   ============================================================ */
(function () {
  'use strict';

  var THREE = window.THREE;
  var D = window.WordCityData;
  var MD = window.WordCityModels;
  var S = (window.WordCityScene = window.WordCityScene || {});

  if (!THREE || !D || !MD) {
    console.error('[WordCity] 场景依赖缺失（THREE / WordCityData / WordCityModels）。');
    return;
  }

  var el = null;
  var renderer = null;
  var scene = null;
  var camera = null;
  var clock = null;
  var world = null;
  var props = null;
  var words = new Map();
  var hitMeshes = [];
  var ring = null;
  var highlightId = null;
  var highlightBase = null;

  var labelsCb = null;
  var pickCb = null;
  var labelsEnabled = true;
  var ready = false;
  var running = false;
  var userPaused = false;
  var pageHidden = false;
  var reduced = false;

  var hemiLight = null;
  var ambLight = null;
  var dirLight = null;
  var lightingOn = false;
  var lightingBlend = 0;
  var LIGHT_DAY = {
    sky: new THREE.Color('#DDF3FF'), ground: new THREE.Color('#F0E6D2'),
    ambColor: new THREE.Color('#FFFFFF'), sun: new THREE.Color('#FFF4E0'),
    fog: new THREE.Color('#EAF7F4'),
    hemi: 1.35, amb: 0.22, sunI: 1.85, sunY: 98
  };
  var LIGHT_DUSK = {
    sky: new THREE.Color('#F2B48C'), ground: new THREE.Color('#5C4A63'),
    ambColor: new THREE.Color('#8C7898'), sun: new THREE.Color('#FFB173'),
    fog: new THREE.Color('#B08A95'),
    hemi: 1.02, amb: 0.34, sunI: 1.05, sunY: 45
  };
  var LAMP_DAY = new THREE.Color('#D8CDB6');
  var LAMP_DUSK = new THREE.Color('#FFF3C4');

  var elapsed = 0;
  var currentZone = 'overview';
  var labelTimer = 0;

  var cam = {
    target: new THREE.Vector3(0, 0, 0),
    radius: 160,
    theta: -0.5,
    phi: 0.7
  };
  var goal = null;
  var flying = false;

  var raycaster = new THREE.Raycaster();
  var ndc = new THREE.Vector2();
  var pointers = new Map();
  var pinchState = null;
  var tap = { candidate: false, pointerId: -1, x: 0, y: 0, moved: 0, time: 0 };
  var dragButton = 0;

  var tmpV = new THREE.Vector3();
  var tmpV2 = new THREE.Vector3();
  var tmpBox = new THREE.Box3();
  var tmpSize = new THREE.Vector3();
  var tmpCenter = new THREE.Vector3();

  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function easeInOutCubic(t) {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  }

  function fitDist(spanX, spanZ) {
    var vf = (camera.fov * Math.PI) / 180;
    var aspect = camera.aspect || 1;
    var rX = (spanX * 0.5) / (Math.tan(vf / 2) * aspect);
    var rZ = (spanZ * 0.5) / Math.tan(vf / 2);
    return Math.max(rX, rZ) * 1.12;
  }

  function updateCamera() {
    cam.phi = clamp(cam.phi, D.camera.minPhi, D.camera.maxPhi);
    cam.radius = clamp(cam.radius, D.camera.minRadius, D.camera.maxRadius);
    var sp = Math.sin(cam.phi);
    camera.position.set(
      cam.target.x + cam.radius * sp * Math.sin(cam.theta),
      Math.max(2.6, cam.target.y + cam.radius * Math.cos(cam.phi)),
      cam.target.z + cam.radius * sp * Math.cos(cam.theta)
    );
    camera.lookAt(cam.target);
  }

  function applyLighting() {
    if (!hemiLight || !ambLight || !dirLight || !scene) { return; }
    var t = clamp(lightingBlend, 0, 1);
    var d = LIGHT_DAY;
    var n = LIGHT_DUSK;
    hemiLight.color.lerpColors(d.sky, n.sky, t);
    hemiLight.groundColor.lerpColors(d.ground, n.ground, t);
    hemiLight.intensity = lerp(d.hemi, n.hemi, t);
    ambLight.color.lerpColors(d.ambColor, n.ambColor, t);
    ambLight.intensity = lerp(d.amb, n.amb, t);
    dirLight.color.lerpColors(d.sun, n.sun, t);
    dirLight.intensity = lerp(d.sunI, n.sunI, t);
    dirLight.position.y = lerp(d.sunY, n.sunY, t);
    if (scene.fog) { scene.fog.color.lerpColors(d.fog, n.fog, t); }
    if (props) {
      if (props.lamps) {
        for (var i = 0; i < props.lamps.length; i++) {
          var mat = props.lamps[i];
          if (mat && mat.color) { mat.color.lerpColors(LAMP_DAY, LAMP_DUSK, t); }
        }
      }
      if (props.lampGlowMat) { props.lampGlowMat.opacity = 0.72 * t; }
      if (props.lampPoolMat) { props.lampPoolMat.opacity = 0.3 * t; }
    }
  }

  function flyTo(target, radius, phi, theta, dur) {
    var to = {
      target: target.clone(),
      radius: radius,
      phi: phi,
      theta: theta
    };
    if (reduced || !dur) {
      cam.target.copy(to.target);
      cam.radius = to.radius;
      cam.phi = to.phi;
      cam.theta = to.theta;
      flying = false;
      goal = null;
      updateCamera();
      return;
    }
    goal = {
      t: 0,
      dur: dur,
      from: {
        target: cam.target.clone(),
        radius: cam.radius,
        phi: cam.phi,
        theta: cam.theta
      },
      to: to
    };
    flying = true;
    if (renderer) { renderer.domElement.classList.add('is-flying'); }
  }

  function updateFlight(dt) {
    if (!goal) { return; }
    goal.t += dt * 1000;
    var k = clamp(goal.t / goal.dur, 0, 1);
    var e = easeInOutCubic(k);
    cam.target.lerpVectors(goal.from.target, goal.to.target, e);
    cam.radius = lerp(goal.from.radius, goal.to.radius, e);
    cam.phi = lerp(goal.from.phi, goal.to.phi, e);
    cam.theta = lerp(goal.from.theta, goal.to.theta, e);
    if (k >= 1) {
      goal = null;
      flying = false;
      if (renderer) { renderer.domElement.classList.remove('is-flying'); }
    }
  }

  function applyView(id, immediate) {
    var v = D.views[id];
    if (!v) { return; }
    currentZone = id;
    var target = new THREE.Vector3(v.target[0], v.target[1], v.target[2]);
    var radius;
    if (v.fit) {
      radius = fitDist(v.fit[0], v.fit[1]);
    } else {
      radius = v.radius * (camera.aspect < 0.85 ? 1.45 : 1);
    }
    radius = clamp(radius, D.camera.minRadius, D.camera.maxRadius);
    flyTo(target, radius, v.phi, v.theta, immediate ? 0 : D.camera.flightMs);
  }

  /* ---------------- 拾取与高亮 ---------------- */

  function pickAt(clientX, clientY) {
    if (!renderer) { return; }
    var rect = renderer.domElement.getBoundingClientRect();
    ndc.x = ((clientX - rect.left) / Math.max(1, rect.width)) * 2 - 1;
    ndc.y = -((clientY - rect.top) / Math.max(1, rect.height)) * 2 + 1;
    raycaster.setFromCamera(ndc, camera);
    raycaster.layers.enableAll();
    var hits = raycaster.intersectObjects(hitMeshes, false);
    if (!hits.length) {
      if (pickCb) { pickCb(null); }
      return;
    }
    var id = hits[0].object.userData.wordId;
    if (id && pickCb) { pickCb(id); }
  }

  function ensureRing() {
    if (ring) { return; }
    ring = new THREE.Mesh(
      new THREE.RingGeometry(0.84, 1, 40),
      new THREE.MeshBasicMaterial({
        color: '#FFD08A', transparent: true, opacity: 0.8,
        side: THREE.DoubleSide, depthWrite: false
      })
    );
    ring.rotation.x = -Math.PI / 2;
    ring.visible = false;
    scene.add(ring);
  }

  function highlight(id) {
    if (highlightId === id) { return; }
    var prev = highlightId ? words.get(highlightId) : null;
    if (prev && prev.node) {
      if (highlightBase) { prev.node.scale.copy(highlightBase); }
      if (prev.vehicle) { prev.vehicle.hold = false; }
    }
    highlightId = null;
    highlightBase = null;
    if (ring) { ring.visible = false; }

    if (!id) { return; }
    var w = words.get(id);
    if (!w || !w.node) { return; }
    highlightId = id;
    highlightBase = w.node.scale.clone();
    ensureRing();
    var bb = new THREE.Box3().setFromObject(w.node);
    if (!bb.isEmpty()) {
      bb.getCenter(tmpCenter);
      bb.getSize(tmpSize);
      var rs = Math.max(tmpSize.x, tmpSize.z) * 0.78;
      if (rs < 40 && rs > 0.8) {
        ring.visible = true;
        ring.position.set(tmpCenter.x, Math.max(0.13, bb.min.y + 0.1), tmpCenter.z);
        ring.scale.set(rs, rs, 1);
        ring.userData.baseR = rs;
      }
    }
    if (w.vehicle) {
      w.vehicle.hold = true;
      w.vehicle.pauseUntil = Math.max(w.vehicle.pauseUntil, elapsed + 1.5);
    }
  }

  function emitLabels() {
    if (!labelsCb) { return; }
    var w = renderer.domElement.clientWidth;
    var h = renderer.domElement.clientHeight;
    if (!w || !h) { return; }
    camera.updateMatrixWorld();
    camera.getWorldDirection(tmpV2);
    var list = [];
    words.forEach(function (item, id) {
      var node = item.node;
      if (!node || !node.parent) { return; }
      tmpV.copy(item.labelOffset);
      node.localToWorld(tmpV);
      tmpCenter.copy(tmpV).sub(camera.position);
      if (tmpCenter.dot(tmpV2) <= 0) { return; }
      var dist = tmpCenter.length();
      tmpV.project(camera);
      if (tmpV.z < -1 || tmpV.z > 1) { return; }
      var x = (tmpV.x * 0.5 + 0.5) * w;
      var y = (-tmpV.y * 0.5 + 0.5) * h;
      if (x < -100 || x > w + 100 || y < -80 || y > h + 80) { return; }
      list.push({ id: id, x: x, y: y, dist: dist });
    });
    list.sort(function (a, b) { return a.dist - b.dist; });
    labelsCb(list);
  }

  /* ---------------- 相机控制 ---------------- */

  function pointerPos(e) { return { x: e.clientX, y: e.clientY }; }

  function measurePointers() {
    var pts = Array.from(pointers.values());
    if (pts.length < 2) { return null; }
    var a = pts[0];
    var b = pts[1];
    return {
      dist: Math.hypot(a.x - b.x, a.y - b.y),
      x: (a.x + b.x) / 2,
      y: (a.y + b.y) / 2
    };
  }

  function onPointerDown(e) {
    if (!renderer || flying) { return; }
    if (e.button === 2) { e.preventDefault(); }
    var canvas = renderer.domElement;
    try { canvas.setPointerCapture(e.pointerId); } catch (err) { /* 忽略 */ }
    pointers.set(e.pointerId, pointerPos(e));
    dragButton = e.button;
    if (pointers.size === 1) {
      tap = {
        candidate: true, pointerId: e.pointerId,
        x: e.clientX, y: e.clientY, moved: 0, time: performance.now()
      };
      canvas.classList.add('is-dragging');
    } else {
      tap.candidate = false;
      pinchState = measurePointers();
    }
  }

  function onPointerMove(e) {
    if (!pointers.has(e.pointerId)) { return; }
    var p = pointers.get(e.pointerId);
    var dx = e.clientX - p.x;
    var dy = e.clientY - p.y;
    p.x = e.clientX;
    p.y = e.clientY;

    if (tap.candidate && e.pointerId === tap.pointerId) {
      tap.moved += Math.abs(dx) + Math.abs(dy);
    }

    if (pointers.size >= 2) {
      var now = measurePointers();
      if (now && pinchState && now.dist > 4) {
        cam.radius = clamp(
          cam.radius * (pinchState.dist / now.dist),
          D.camera.minRadius,
          D.camera.maxRadius
        );
        panBy(now.x - pinchState.x, now.y - pinchState.y);
        pinchState = now;
      }
      return;
    }

    if (!tap.candidate || tap.moved < 6) { return; }
    var isPan = dragButton === 2 || e.shiftKey;
    if (isPan) {
      panBy(dx, dy);
    } else {
      cam.theta -= dx * 0.006;
      cam.phi = clamp(cam.phi + dy * 0.005, D.camera.minPhi, D.camera.maxPhi);
    }
    updateCamera();
  }

  function onPointerUp(e) {
    if (!pointers.has(e.pointerId)) { return; }
    pointers.delete(e.pointerId);
    if (renderer) { renderer.domElement.classList.remove('is-dragging'); }
    pinchState = null;
    if (tap.candidate && e.pointerId === tap.pointerId) {
      var quick = performance.now() - tap.time < 700;
      if (tap.moved < 6 && quick) {
        pickAt(e.clientX, e.clientY);
      }
      tap.candidate = false;
    }
  }

  function panBy(dx, dy) {
    var scale = cam.radius * 0.0015;
    var right = new THREE.Vector3(Math.cos(cam.theta), 0, -Math.sin(cam.theta));
    var forward = new THREE.Vector3(-Math.sin(cam.theta), 0, -Math.cos(cam.theta));
    cam.target.addScaledVector(right, -dx * scale);
    cam.target.addScaledVector(forward, dy * scale);
    cam.target.x = clamp(cam.target.x, -72, 72);
    cam.target.z = clamp(cam.target.z, -55, 55);
    updateCamera();
  }

  function onWheel(e) {
    if (flying) { return; }
    e.preventDefault();
    cam.radius = clamp(
      cam.radius * Math.exp(e.deltaY * 0.0012),
      D.camera.minRadius,
      D.camera.maxRadius
    );
    updateCamera();
  }

  function bindControls() {
    var canvas = renderer.domElement;
    canvas.addEventListener('pointerdown', onPointerDown);
    canvas.addEventListener('pointermove', onPointerMove);
    canvas.addEventListener('pointerup', onPointerUp);
    canvas.addEventListener('pointercancel', onPointerUp);
    canvas.addEventListener('pointerleave', onPointerUp);
    canvas.addEventListener('wheel', onWheel, { passive: false });
    canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    canvas.addEventListener('dblclick', function () {
      if (!flying) { applyView(currentZone, false); }
    });
  }

  /* ---------------- 初始化 ---------------- */

  S.init = function (opts) {
    opts = opts || {};
    el = opts.container;
    if (!el) { throw new Error('缺少 3D 容器'); }
    labelsCb = opts.onLabels || null;
    pickCb = opts.onPick || null;
    reduced = !!opts.reducedMotion;
    labelsEnabled = opts.labels !== false;

    renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      powerPreference: 'high-performance'
    });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(Math.max(1, el.clientWidth), Math.max(1, el.clientHeight), false);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.domElement.setAttribute('role', 'img');
    renderer.domElement.setAttribute(
      'aria-label',
      '小词城 3D 城市场景。可以拖动旋转、双指或滚轮缩放，点击建筑、车辆、人物和小动物听英文单词。'
    );
    renderer.domElement.setAttribute('aria-describedby', 'sceneDesc');
    el.appendChild(renderer.domElement);

    scene = new THREE.Scene();
    scene.fog = new THREE.Fog('#EAF7F4', 330, 640);
    camera = new THREE.PerspectiveCamera(
      45,
      Math.max(0.2, el.clientWidth / Math.max(1, el.clientHeight)),
      0.5,
      760
    );

    hemiLight = new THREE.HemisphereLight('#DDF3FF', '#F0E6D2', 1.35);
    scene.add(hemiLight);
    ambLight = new THREE.AmbientLight('#FFFFFF', 0.22);
    scene.add(ambLight);

    dirLight = new THREE.DirectionalLight('#FFF4E0', 1.85);
    dirLight.position.set(68, 98, 44);
    dirLight.castShadow = true;
    var small = window.innerWidth < 760;
    dirLight.shadow.mapSize.set(small ? 1024 : 2048, small ? 1024 : 2048);
    dirLight.shadow.camera.left = -96;
    dirLight.shadow.camera.right = 96;
    dirLight.shadow.camera.top = 88;
    dirLight.shadow.camera.bottom = -88;
    dirLight.shadow.camera.near = 10;
    dirLight.shadow.camera.far = 280;
    dirLight.shadow.bias = -0.0006;
    dirLight.shadow.normalBias = 0.35;
    dirLight.target.position.set(0, 0, 0);
    scene.add(dirLight);
    scene.add(dirLight.target);

    world = MD.buildWorld();
    scene.add(world.root);
    props = world.props;
    world.words.forEach(function (v, k) { words.set(k, v); });
    lightingBlend = lightingOn ? 1 : 0;
    applyLighting();

    buildTraffic();
    buildPedestrians();
    buildCrossers();
    buildHitboxes();
    buildKiteString();

    bindControls();

    clock = new THREE.Clock();
    clock.start();
    running = true;
    ready = true;

    applyView('overview', true);
    updateCamera();
    resize();

    if (typeof ResizeObserver !== 'undefined') {
      var ro = new ResizeObserver(function () { resize(); });
      ro.observe(el);
    } else {
      window.addEventListener('resize', resize);
    }

    document.addEventListener('visibilitychange', function () {
      pageHidden = document.hidden;
      if (!pageHidden && clock) { clock.getDelta(); }
    });

    // 首帧
    renderer.render(scene, camera);
    requestAnimationFrame(loop);
    return true;
  };

  function resize() {
    if (!renderer || !el) { return; }
    var w = Math.max(1, el.clientWidth);
    var h = Math.max(1, el.clientHeight);
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }

  function loop() {
    if (!running) { return; }
    requestAnimationFrame(loop);
    if (pageHidden) { return; }
    var dt = Math.min(clock.getDelta(), 0.05);
    if (!userPaused) { elapsed += dt; }

    updateFlight(dt);
    updateCamera();

    if (!userPaused) {
      var lightTarget = lightingOn ? 1 : 0;
      if (reduced) {
        if (lightingBlend !== lightTarget) {
          lightingBlend = lightTarget;
          applyLighting();
        }
      } else if (Math.abs(lightTarget - lightingBlend) > 0.001) {
        lightingBlend += (lightTarget - lightingBlend) * Math.min(1, dt * 2.4);
        applyLighting();
      }
      updateTraffic(dt);
      updatePedestrians(dt);
      updateCrossers(dt);
      updateProps(dt);
      updateSignals(dt);
      updateHighlightPulse();
    }

    renderer.render(scene, camera);

    if (labelsEnabled && labelsCb) {
      labelTimer += dt;
      if (labelTimer >= 0.05) {
        labelTimer = 0;
        emitLabels();
      }
    }
  }

  function updateHighlightPulse() {
    if (!highlightId || !highlightBase) { return; }
    var w = words.get(highlightId);
    if (!w || !w.node) { return; }
    var k = 1 + Math.sin(elapsed * 6) * 0.035;
    w.node.scale.set(highlightBase.x * k, highlightBase.y * k, highlightBase.z * k);
    if (ring && ring.visible) {
      ring.material.opacity = 0.45 + 0.3 * (0.5 + 0.5 * Math.sin(elapsed * 5));
      var s = 1 + Math.sin(elapsed * 5) * 0.04;
      ring.scale.x = ring.userData.baseR * s;
      ring.scale.y = ring.userData.baseR * s;
    }
  }

  /* ---------------- 公开 API ---------------- */

  S.setView = function (id, immediate) {
    if (!D.views[id]) { return; }
    applyView(id, !!immediate);
  };

  S.focusWord = function (id) {
    var w = words.get(id);
    if (!w || !w.node) { return false; }
    highlight(id);
    world.root.updateMatrixWorld(true);
    tmpBox.setFromObject(w.node);
    if (tmpBox.isEmpty()) { return false; }
    tmpBox.getCenter(tmpCenter);
    tmpBox.getSize(tmpSize);
    var maxDim = Math.max(tmpSize.x, tmpSize.y, tmpSize.z);
    var radius = clamp(maxDim * 1.8 + 9, 24, 54);
    if (camera.aspect < 0.85) { radius *= 1.28; }
    flyTo(
      new THREE.Vector3(tmpCenter.x, tmpCenter.y, tmpCenter.z),
      radius,
      1.0,
      cam.theta,
      780
    );
    return true;
  };

  S.clearHighlight = function () { highlight(null); };

  S.releaseWord = function (id) {
    var w = id ? words.get(id) : null;
    if (w && w.vehicle) { w.vehicle.hold = false; }
  };

  S.resetView = function () { applyView(currentZone, false); };

  S.setLabelsEnabled = function (on) { labelsEnabled = !!on; };

  S.setNight = function (on) {
    lightingOn = !!on;
    if (reduced) {
      lightingBlend = lightingOn ? 1 : 0;
      applyLighting();
    }
  };

  S.setPaused = function (on) { userPaused = !!on; };

  S.isReady = function () { return ready; };

  S.getZone = function () { return currentZone; };

  S.getWordCount = function () { return words.size; };

  S.updateCamera = updateCamera;

  /* ---------------- 交通 ---------------- */

  var vehicles = [];
  var peds = [];
  var crossers = [];
  var kiteLine = null;

  function makeLoop(points, closed) {
    var pts = points.map(function (p) { return new THREE.Vector3(p[0], 0, p[1]); });
    if (closed && pts.length > 2) {
      var a = pts[0];
      var b = pts[pts.length - 1];
      if (Math.abs(a.x - b.x) < 0.01 && Math.abs(a.z - b.z) < 0.01) { pts.pop(); }
    }
    var curve = new THREE.CatmullRomCurve3(pts, !!closed, 'catmullrom', 0.12);
    curve.arcLengthDivisions = 1000;
    return curve;
  }

  function buildTraffic() {
    var loops = {
      A: makeLoop(D.traffic.loops.A, true),
      B: makeLoop(D.traffic.loops.B, true),
      river: makeLoop(D.traffic.riverPath, false)
    };
    D.traffic.vehicles.forEach(function (cfg) {
      var built = MD.buildVehicle(cfg.type, cfg.color);
      built.group.traverse(function (o) {
        if (o.isMesh && o.material && o.material.colorWrite !== false) {
          o.castShadow = true;
        }
      });
      world.root.add(built.group);
      var curve = loops[cfg.loop] || loops.A;
      var v = {
        cfg: cfg,
        obj: built,
        curve: curve,
        len: Math.max(1, curve.getLength()),
        u: cfg.offset || 0,
        dir: 1,
        speed: cfg.speed || 6,
        hold: false,
        pauseUntil: 0,
        dwellUntil: 0,
        nextStopAt: 0,
        doorOpen: 0,
        yaw: 0,
        bobPhase: (cfg.offset || 0) * 12
      };
      vehicles.push(v);
      var p0 = v.curve.getPointAt(clamp(v.u, 0, 1));
      var t0 = v.curve.getTangentAt(clamp(v.u, 0, 1));
      var lane0 = cfg.type === 'bicycle' ? 1.25 : 0;
      built.group.position.set(
        p0.x - t0.z * lane0,
        cfg.loop === 'river' ? 0.12 : 0.035,
        p0.z + t0.x * lane0
      );
      v.yaw = Math.atan2(t0.x, t0.z);
      built.group.rotation.y = v.yaw;
      if (cfg.word) {
        world.root.updateMatrixWorld(true);
        var bb = new THREE.Box3().setFromObject(built.group);
        var c = bb.getCenter(new THREE.Vector3());
        var local = built.group.worldToLocal(new THREE.Vector3(c.x, bb.max.y + 1.6, c.z));
        words.set(cfg.word, {
          node: built.group,
          labelOffset: local,
          vehicle: v
        });
      }
    });
  }

  function signalPhase(offset) {
    var c = (((elapsed + offset) % 25) + 25) % 25;
    if (c < 12) { return 'green'; }
    if (c < 15) { return 'yellow'; }
    return 'red';
  }

  function guardPhase() {
    var t = ((elapsed % D.traffic.guard.cycle) + D.traffic.guard.cycle) % D.traffic.guard.cycle;
    return t >= D.traffic.guard.stopFrom && t < D.traffic.guard.stopTo;
  }

  function mustStop(v, p, tan) {
    var look = 4.5 + v.speed * 0.85;
    var lx = p.x + tan.x * look;
    var lz = p.z + tan.z * look;
    var onMain = Math.abs(p.z) < 4.6;
    for (var i = 0; i < D.traffic.lights.length; i++) {
      var L = D.traffic.lights[i];
      if (Math.abs(lx - L.x) < 6.2 && Math.abs(lz - L.z) < 6.2) {
        var inBox = Math.abs(p.x - L.x) < 6.2 && Math.abs(p.z - L.z) < 6.2;
        var st = signalPhase(L.offset);
        var allowed = onMain ? st === 'green' : st === 'red';
        if (!inBox && !allowed) { return true; }
      }
    }
    var g = D.traffic.guard;
    var inGuard = Math.abs(p.x - g.x) < 6.4 && Math.abs(p.z) < 5;
    if (onMain && !inGuard && Math.abs(lx - g.x) < 6.4 && Math.abs(lz - g.z) < 6.4) {
      if (guardPhase()) { return true; }
    }
    return false;
  }

  function checkStop(v) {
    if (v.dwellUntil > elapsed) { return true; }
    if (elapsed < v.nextStopAt) { return false; }
    for (var i = 0; i < D.traffic.stops.length; i++) {
      var stop = D.traffic.stops[i];
      if (stop.loop !== v.cfg.loop) { continue; }
      if (stop.types.indexOf(v.cfg.type) < 0) { continue; }
      var gx = v.obj.group.position.x;
      var gz = v.obj.group.position.z;
      if (Math.hypot(gx - stop.x, gz - stop.z) < 1.6) {
        v.dwellUntil = elapsed + stop.dwell;
        v.nextStopAt = elapsed + 32;
        return true;
      }
    }
    return false;
  }

  function updateTraffic(dt) {
    for (var i = 0; i < vehicles.length; i++) {
      var v = vehicles[i];
      var group = v.obj.group;
      var p = v.curve.getPointAt(clamp(v.u, 0, 1));
      var tan = v.curve.getTangentAt(clamp(v.u, 0, 1));

      if (v.cfg.loop === 'river') {
        if (!v.hold && elapsed >= v.pauseUntil) {
          v.u += v.dir * (v.speed * dt) / v.len;
        }
        if (v.u > 0.96) { v.u = 0.96; v.dir = -1; }
        if (v.u < 0.04) { v.u = 0.04; v.dir = 1; }
        var bp = v.curve.getPointAt(v.u);
        group.position.set(bp.x, 0.12 + Math.sin(elapsed * 1.4 + i) * 0.05, bp.z);
        var byaw = Math.atan2(tan.x * v.dir, tan.z * v.dir);
        group.rotation.y = byaw;
        group.rotation.z = Math.sin(elapsed * 1.2 + i) * 0.02;
        continue;
      }

      var targetSpeed = v.cfg.speed;
      if (v.hold || elapsed < v.pauseUntil) {
        targetSpeed = 0;
      } else if (checkStop(v)) {
        targetSpeed = 0;
      } else if (mustStop(v, p, tan)) {
        targetSpeed = 0;
      }

      var accel = targetSpeed > v.speed ? 4.5 : 16;
      var diff = targetSpeed - v.speed;
      v.speed += clamp(diff, -accel * dt, accel * dt);

      if (v.speed > 0.02) {
        v.u = (v.u + (v.speed * dt) / v.len) % 1;
      }

      var pp = v.curve.getPointAt(v.u);
      var tt = v.curve.getTangentAt(v.u);
      var lane = v.cfg.type === 'bicycle' ? 1.25 : 0;
      group.position.set(pp.x - tt.z * lane, 0.035, pp.z + tt.x * lane);

      var desired = Math.atan2(tt.x, tt.z);
      var delta = Math.atan2(Math.sin(desired - v.yaw), Math.cos(desired - v.yaw));
      v.yaw += delta * Math.min(1, dt * 5.5);
      group.rotation.y = v.yaw;

      if (v.cfg.type !== 'bicycle') {
        group.position.y = 0.035 + Math.sin(elapsed * 6 + v.bobPhase) * 0.012;
      }

      if (v.obj.wheels.length && v.cfg.type !== 'bicycle') {
        for (var wi = 0; wi < v.obj.wheels.length; wi++) {
          v.obj.wheels[wi].rotation.x -= (v.speed * dt) / 0.45;
        }
      }

      var wantDoor = v.dwellUntil > elapsed ? 1 : 0;
      v.doorOpen += (wantDoor - v.doorOpen) * Math.min(1, dt * 5);
      if (v.obj.door) { v.obj.door.rotation.y = -1.15 * v.doorOpen; }

      if (v.obj.beacons.length) {
        for (var bi = 0; bi < v.obj.beacons.length; bi++) {
          var b = v.obj.beacons[bi];
          var on = Math.sin(elapsed * 7 + bi * Math.PI) > 0;
          b.mat.color.set(on ? b.base : '#3A2A2A');
        }
      }
    }
  }

  /* ---------------- 行人 ---------------- */

  function buildPedestrians() {
    D.traffic.pedestrians.forEach(function (cfg, idx) {
      var curve = makeLoop(D.traffic.pedestrianLoops[cfg.loop], true);
      var person = MD.buildPerson(cfg.type);
      person.group.scale.setScalar(0.96);
      world.root.add(person.group);
      peds.push({
        cfg: cfg,
        curve: curve,
        len: Math.max(1, curve.getLength()),
        u: cfg.offset || 0,
        speed: cfg.speed || 1.2,
        obj: person,
        yaw: 0,
        phase: idx * 1.7
      });
    });
  }

  function animatePerson(person, speed, phase) {
    var swing = speed > 0.1 ? Math.sin(elapsed * 7.5 + phase) * 0.55 : 0;
    person.leftLeg.rotation.x = swing;
    person.rightLeg.rotation.x = -swing;
    person.leftArm.rotation.x = -swing * 0.8;
    person.rightArm.rotation.x = swing * 0.8;
  }

  function updatePedestrians(dt) {
    for (var i = 0; i < peds.length; i++) {
      var p = peds[i];
      var resting = Math.sin(elapsed * 0.33 + p.phase) > 0.945;
      var speed = resting ? 0 : p.speed;
      p.u = (p.u + (speed * dt) / p.len) % 1;
      var pos = p.curve.getPointAt(p.u);
      var tan = p.curve.getTangentAt(p.u);
      p.obj.group.position.set(pos.x, 0.03 + Math.abs(Math.sin(elapsed * 7.5 + p.phase)) * (speed > 0.1 ? 0.02 : 0), pos.z);
      var desired = Math.atan2(tan.x, tan.z);
      var delta = Math.atan2(Math.sin(desired - p.yaw), Math.cos(desired - p.yaw));
      p.yaw += delta * Math.min(1, dt * 6);
      p.obj.group.rotation.y = p.yaw;
      animatePerson(p.obj, speed, p.phase);
    }
  }

  function buildCrossers() {
    var defs = [
      { type: 'parent', x: 10.0, side: 1, guard: true },
      { type: 'student', x: 8.9, side: -1, guard: true },
      { type: 'office', x: -8.9, side: 1, signal: 0 },
      { type: 'student', x: -11.1, side: -1, signal: 0 },
      { type: 'parent', x: 36.1, side: 1, signal: 7 },
      { type: 'child', x: 33.9, side: -1, signal: 7 }
    ];
    defs.forEach(function (d, idx) {
      var person = MD.buildPerson(d.type);
      person.group.scale.setScalar(0.94);
      world.root.add(person.group);
      crossers.push({
        obj: person,
        x: d.x,
        side: d.side,
        z: d.side > 0 ? 6.2 : -6.2,
        crossing: false,
        dir: 0,
        locked: false,
        phase: idx * 1.3,
        guard: !!d.guard,
        signal: d.signal || 0
      });
    });
  }

  function updateCrossers(dt) {
    for (var i = 0; i < crossers.length; i++) {
      var c = crossers[i];
      var open;
      if (c.guard) {
        open = guardPhase();
      } else {
        var ph = (((elapsed + c.signal) % 25) + 25) % 25;
        open = ph >= 15 && ph < 22;
      }
      c.open = open;
      if (open && !c.crossing && !c.locked) {
        c.crossing = true;
        c.dir = c.side > 0 ? -1 : 1;
        c.locked = true;
      }
      if (!open) { c.locked = false; }
      if (c.crossing) {
        c.z += c.dir * 1.85 * dt;
        if ((c.dir < 0 && c.z <= -6.2) || (c.dir > 0 && c.z >= 6.2)) {
          c.z = clamp(c.z, -6.2, 6.2);
          c.crossing = false;
          c.side = -c.side;
          c.locked = true;
        }
      }
      c.obj.group.position.set(c.x, 0.04, c.z);
      c.obj.group.rotation.y = c.dir < 0 ? Math.PI : 0;
      animatePerson(c.obj, c.crossing ? 1.8 : 0, c.phase);
    }
  }

  /* ---------------- 命中区 ---------------- */

  function buildHitboxes() {
    world.root.updateMatrixWorld(true);
    var hitMat = new THREE.MeshBasicMaterial({
      colorWrite: false, depthWrite: false
    });
    words.forEach(function (w, id) {
      if (!w.node) { return; }
      var bb = new THREE.Box3().setFromObject(w.node);
      if (bb.isEmpty()) { return; }
      bb.getSize(tmpSize);
      bb.getCenter(tmpCenter);
      var local = w.node.worldToLocal(tmpCenter.clone());
      var hx = Math.max(tmpSize.x * 1.18, 0.9);
      var hy = Math.max(tmpSize.y * 1.18, 0.9);
      var hz = Math.max(tmpSize.z * 1.18, 0.9);
      if (id === 'road') { hy = 0.3; }
      var hit = new THREE.Mesh(new THREE.BoxGeometry(hx, hy, hz), hitMat);
      hit.layers.set(2);
      hit.userData.wordId = id;
      // 会移动或旋转的单词对象把命中盒挂在自身；静态对象挂到根节点，
      // 避免平面（如 road 绕 X 轴旋转）把命中盒一起转成竖直的墙。
      if (w.vehicle || id === 'duck' || id === 'bird' || id === 'kite') {
        hit.position.copy(local);
        w.node.add(hit);
      } else {
        hit.position.copy(tmpCenter);
        world.root.add(hit);
      }
      w.hit = hit;
      hitMeshes.push(hit);
    });

    // 红绿灯单词允许点击任意一根灯杆；镜头仍聚焦主实例。
    var primary = words.get('traffic_light');
    props.signals.forEach(function (s) {
      if (!primary || s.group === primary.node) { return; }
      var sbox = new THREE.Box3().setFromObject(s.group);
      if (sbox.isEmpty()) { return; }
      sbox.getSize(tmpSize);
      sbox.getCenter(tmpCenter);
      var sh = new THREE.Mesh(
        new THREE.BoxGeometry(Math.max(tmpSize.x * 1.2, 0.9), Math.max(tmpSize.y * 1.1, 1.2), Math.max(tmpSize.z * 1.2, 0.9)),
        hitMat
      );
      sh.position.copy(tmpCenter);
      sh.layers.set(2);
      sh.userData.wordId = 'traffic_light';
      world.root.add(sh);
      hitMeshes.push(sh);
    });
  }

  function buildKiteString() {
    if (!props.kite) { return; }
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(6), 3));
    var mat = new THREE.LineBasicMaterial({ color: '#F8F5EA', transparent: true, opacity: 0.8 });
    kiteLine = new THREE.Line(geo, mat);
    kiteLine.frustumCulled = false;
    scene.add(kiteLine);
  }

  /* ---------------- 环境动画 ---------------- */

  function updateProps(dt) {
    var t = elapsed;
    var i;

    if (props.fountainPoints) {
      var fp = props.fountainPoints;
      for (i = 0; i < fp.count; i++) {
        var sd = fp.seeds[i];
        var k = (sd.p + t * 0.55 * sd.s) % 1;
        var hgt = Math.sin(k * Math.PI) * 2.0;
        var rad = sd.r * (1 - k * 0.22);
        fp.positions[i * 3] = Math.cos(sd.a) * rad;
        fp.positions[i * 3 + 1] = hgt;
        fp.positions[i * 3 + 2] = Math.sin(sd.a) * rad;
      }
      fp.geo.attributes.position.needsUpdate = true;
    }

    for (i = 0; i < props.ducks.length; i++) {
      var d = props.ducks[i];
      var a = t * 0.22 + d.phase;
      var cx = 46.5 + Math.cos(a) * d.r;
      var cz = 25 + Math.sin(a) * d.r * 0.62;
      d.group.position.set(cx, 0.06 + Math.sin(t * 1.8 + i) * 0.03, cz);
      var tx = -Math.sin(a);
      var tz = Math.cos(a) * 0.62;
      d.group.rotation.y = Math.atan2(tx, tz);
    }

    if (props.kite) {
      var kb = props.kite.base;
      var kx = kb.x;
      var ky = kb.y;
      var kz = kb.z;
      if (!reduced) {
        kx = kb.x + Math.sin(t * 0.32) * 4.5;
        kz = kb.z + Math.cos(t * 0.24) * 3.2;
        ky = kb.y + Math.sin(t * 0.5) * 1.2;
        props.kite.group.position.set(kx, ky, kz);
        props.kite.group.rotation.z = Math.sin(t * 0.62) * 0.16;
        props.kite.group.rotation.y = Math.sin(t * 0.2) * 0.22;
      }
      if (kiteLine) {
        var arr = kiteLine.geometry.attributes.position.array;
        arr[0] = 24;
        arr[1] = 1.4;
        arr[2] = 22;
        arr[3] = kx;
        arr[4] = ky;
        arr[5] = kz;
        kiteLine.geometry.attributes.position.needsUpdate = true;
        kiteLine.geometry.boundingSphere = null;
      }
    }

    for (i = 0; i < props.birds.length; i++) {
      var b = props.birds[i];
      var ba = t * 0.18 + b.phase;
      b.group.position.set(
        Math.cos(ba) * b.r,
        b.y + Math.sin(t * 0.6 + b.phase) * 1.1,
        Math.sin(ba) * b.r * 0.72 - 8
      );
      b.group.rotation.y = -ba + Math.PI * 0.5;
      var flap = Math.sin(t * 5 + b.phase) * 0.6;
      b.wingL.rotation.z = 0.18 + flap;
      b.wingR.rotation.z = -0.18 - flap;
    }

    if (!reduced) {
      for (i = 0; i < props.clouds.length; i++) {
        var cl = props.clouds[i];
        cl.group.position.x += cl.speed * dt;
        if (cl.group.position.x > 92) { cl.group.position.x = -92; }
      }
      for (i = 0; i < props.trees.length; i++) {
        var tr = props.trees[i];
        tr.group.rotation.z = Math.sin(t * 0.7 + tr.phase) * tr.amp;
      }
    }

    for (i = 0; i < props.flags.length; i++) {
      props.flags[i].rotation.y = Math.sin(t * 2.1 + i) * 0.3;
    }

    for (i = 0; i < props.smoke.length; i++) {
      var sm = props.smoke[i];
      var sk = (t * 0.17 + sm.phase) % 1;
      sm.mesh.position.set(
        -36.6 + Math.sin(sk * 6 + i) * 0.35,
        6.4 + sk * 3.4,
        11.4 + sk * 0.7
      );
      sm.mesh.scale.setScalar(0.55 + sk * 1.4);
      sm.mesh.material.opacity = 0.55 * (1 - sk);
    }

    if (props.swingSeat) {
      props.swingSeat.rotation.x = reduced ? 0 : Math.sin(t * 1.55) * 0.38;
    }
    if (props.seesawBeam) {
      props.seesawBeam.rotation.z = reduced ? 0.05 : Math.sin(t * 1.1) * 0.17;
    }
    if (props.dog) {
      props.dog.tail.rotation.y = Math.sin(t * 8) * 0.4;
      props.dog.tail.rotation.x = Math.sin(t * 6) * 0.15;
    }
    if (props.river) {
      props.river.tex.offset.x -= dt * 0.012;
    }
  }

  function updateSignals() {
    var dim = { red: '#4A2022', yellow: '#4A3A1C', green: '#1E3F30' };
    for (var i = 0; i < props.signals.length; i++) {
      var s = props.signals[i];
      var st = signalPhase(s.offset);
      for (var b = 0; b < s.bulbs.length; b++) {
        var bulb = s.bulbs[b];
        bulb.mat.color.set(bulb.name === st ? bulb.color : dim[bulb.name]);
      }
      var redPhase = st === 'red';
      var phase = (((elapsed + s.offset) % 25) + 25) % 25;
      var blink = redPhase && phase > 22;
      var greenOn = redPhase && (!blink || Math.floor(elapsed * 4) % 2 === 0);
      s.pedGreen.color.set(greenOn ? '#4CD58C' : '#234A38');
      s.pedRed.color.set(redPhase ? '#3A2424' : '#FF6B6B');
    }
    if (props.guard) {
      var arm = props.guard.person.rightArm;
      var target = guardPhase() ? -1.5 : 0;
      arm.rotation.x += (target - arm.rotation.x) * 0.12;
    }
  }

})();
