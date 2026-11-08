(function (global) {
  'use strict';

  var THREE = global.THREE;
  var D = global.FarmData;

  var C = {
    cream: 0xFFF8E7,
    creamDeep: 0xF2E4C4,
    white: 0xFFFDF6,
    grass: 0x8FBF6A,
    sage: 0xA8C686,
    grassDark: 0x76A857,
    wheat: 0xF2C14E,
    wheatDeep: 0xE0A93A,
    barn: 0xC8553D,
    barnDeep: 0xA8452F,
    soil: 0xC9A66B,
    soilDark: 0xB08F58,
    sky: 0xDDF3FF,
    water: 0x7EC8E3,
    waterDeep: 0x5FB3D1,
    wood: 0xB08968,
    woodDark: 0x8C6A4A,
    stone: 0xD8D2C4,
    gray: 0x9AA3AD,
    trunk: 0x9C6B4A,
    leaf: 0x6FAE5B,
    leafDark: 0x5A9748,
    pink: 0xF2A7B8,
    red: 0xD9534F,
    orange: 0xE88B3E,
    yellow: 0xF6D06B,
    brown: 0x8B5E3C,
    ink: 0x3D3527,
    purple: 0xB79CE8,
    blue: 0x6FA8DC,
    teal: 0x8FC7B0
  };

  var matCache = {};
  var windowMats = [];
  var lampMats = [];
  var rngSeed = 20240516;

  function buildMat(color, opts) {
    var m = new THREE.MeshPhongMaterial({
      color: color,
      flatShading: true,
      shininess: 0,
      specular: 0x000000
    });
    if (opts && opts.opacity != null && opts.opacity < 1) {
      m.transparent = true;
      m.opacity = opts.opacity;
      m.depthWrite = false;
    }
    if (opts && opts.emissive) {
      m.emissive = new THREE.Color(opts.emissive);
      m.emissiveIntensity = opts.emissiveIntensity || 0;
    }
    return m;
  }

  function material(color, opts) {
    if (opts && opts.unique) return buildMat(color, opts);
    var key = color + '|' + (opts && opts.opacity != null ? opts.opacity : 1);
    if (!matCache[key]) matCache[key] = buildMat(color, opts);
    return matCache[key];
  }

  function windowMaterial() {
    var m = new THREE.MeshPhongMaterial({
      color: 0xCFE9F4,
      flatShading: true,
      shininess: 0,
      specular: 0x000000,
      emissive: new THREE.Color(0xFFC46B),
      emissiveIntensity: 0
    });
    windowMats.push(m);
    return m;
  }

  function lampMaterial() {
    var m = new THREE.MeshPhongMaterial({
      color: 0xFFF1C9,
      flatShading: true,
      shininess: 0,
      specular: 0x000000,
      emissive: new THREE.Color(0xFFB24D),
      emissiveIntensity: 0
    });
    lampMats.push(m);
    return m;
  }

  function mesh(parent, geo, color, x, y, z, opts) {
    opts = opts || {};
    var m;
    if (color && color.isMaterial) m = new THREE.Mesh(geo, color);
    else m = new THREE.Mesh(geo, material(color, opts));
    m.position.set(x || 0, y || 0, z || 0);
    if (opts.rx) m.rotation.x = opts.rx;
    if (opts.ry) m.rotation.y = opts.ry;
    if (opts.rz) m.rotation.z = opts.rz;
    m.castShadow = opts.cast !== false;
    m.receiveShadow = opts.receive !== false;
    parent.add(m);
    return m;
  }

  function box(w, h, d) { return new THREE.BoxGeometry(w, h, d); }
  function cyl(rt, rb, h, seg) { return new THREE.CylinderGeometry(rt, rb, h, seg || 7); }
  function cone(r, h, seg) { return new THREE.ConeGeometry(r, h, seg || 6); }
  function sph(r, ws, hs) { return new THREE.SphereGeometry(r, ws || 8, hs || 6); }

  function gable(parent, w, d, h, color, y) {
    var s = Math.atan2(h, w / 2);
    var len = Math.sqrt((w / 2) * (w / 2) + h * h) + 0.5;
    mesh(parent, box(len, 0.44, d), color, -w / 4, y + h / 2, 0, { rz: s });
    mesh(parent, box(len, 0.44, d), color, w / 4, y + h / 2, 0, { rz: -s });
    mesh(parent, box(0.5, 0.5, d + 0.2), color, 0, y + h, 0);
  }

  function makeRng(seed) {
    var s = seed % 2147483647;
    if (s <= 0) s += 2147483646;
    return function () {
      s = (s * 16807) % 2147483647;
      return (s - 1) / 2147483646;
    };
  }

  function makeBarn() {
    var g = new THREE.Group();
    mesh(g, box(13, 6.2, 9.4), C.barn, 0, 3.1, 0);
    gable(g, 14.6, 10.6, 3.6, C.barnDeep, 6.2);
    // 门框
    mesh(g, box(4.2, 0.36, 0.34), C.cream, 0, 4.62, 4.8);
    mesh(g, box(0.36, 4.6, 0.34), C.cream, -2.1, 2.3, 4.8);
    mesh(g, box(0.36, 4.6, 0.34), C.cream, 2.1, 2.3, 4.8);

    // 门里的暗部和几袋粮食：门一开就能看见里面堆着的东西
    mesh(g, box(3.9, 4.4, 0.05), 0x4A3426, 0, 2.22, 4.72, { cast: false, receive: false });
    mesh(g, box(1.4, 0.78, 0.09), C.wheatDeep, -0.72, 0.39, 4.79, { cast: false });
    mesh(g, box(1.15, 0.62, 0.09), C.creamDeep, 0.58, 0.31, 4.79, { cast: false });
    mesh(g, box(0.8, 0.46, 0.09), C.wheat, 0.04, 0.72, 4.79, { cast: false });

    // 两扇向外开的谷仓门，各挂在左右门框上（farm-scene.js 运粮时会推开、关回去）
    var doorL = new THREE.Group();
    doorL.position.set(-1.92, 0, 4.86);
    mesh(doorL, box(1.92, 4.42, 0.1), C.cream, 0.96, 2.21, 0);
    mesh(doorL, box(0.2, 4.6, 0.06), C.cream, 0.96, 2.21, 0.07, { rz: -0.4 });
    g.add(doorL);
    var doorR = new THREE.Group();
    doorR.position.set(1.92, 0, 4.86);
    mesh(doorR, box(1.92, 4.42, 0.1), C.cream, -0.96, 2.21, 0);
    mesh(doorR, box(0.2, 4.6, 0.06), C.cream, -0.96, 2.21, 0.07, { rz: 0.4 });
    g.add(doorR);
    g.userData.doors = { left: doorL, right: doorR };

    mesh(g, box(13.4, 0.34, 0.22), C.cream, 0, 6.02, 4.84);
    mesh(g, box(1.1, 1.1, 0.16), windowMaterial(), -5.2, 4.4, 4.78);
    mesh(g, box(1.1, 1.1, 0.16), windowMaterial(), 5.2, 4.4, 4.78);
    return g;
  }

  function makeFarmhouse() {
    var g = new THREE.Group();
    mesh(g, box(9.6, 4.4, 7.2), C.cream, 0, 2.2, 0);
    gable(g, 10.8, 8.4, 2.9, C.barn, 4.4);
    mesh(g, box(1.6, 3, 0.24), C.wood, 0, 1.5, 3.66);
    mesh(g, box(1.15, 1.15, 0.16), windowMaterial(), -2.7, 2.5, 3.62);
    mesh(g, box(1.15, 1.15, 0.16), windowMaterial(), 2.7, 2.5, 3.62);
    mesh(g, box(0.9, 2.4, 0.9), C.stone, 2.5, 5.6, -1.2);
    mesh(g, box(0.9, 0.4, 1.2), 0x6A5A4A, 2.5, 6.9, -1.2);
    mesh(g, box(3.6, 0.22, 2.0), C.barnDeep, -1.3, 3.5, 4.5);
    mesh(g, cyl(0.12, 0.12, 2.4, 6), C.wood, -2.9, 2.3, 5.2);
    mesh(g, cyl(0.12, 0.12, 2.4, 6), C.wood, 0.2, 2.3, 5.2);
    return g;
  }

  function makeSilo() {
    var g = new THREE.Group();
    mesh(g, cyl(2.7, 2.9, 10.4, 10), C.stone, 0, 5.2, 0);
    mesh(g, new THREE.SphereGeometry(2.7, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), C.gray, 0, 10.4, 0);
    mesh(g, cyl(2.94, 2.94, 0.2, 10), C.gray, 0, 2.6, 0);
    mesh(g, cyl(2.94, 2.94, 0.2, 10), C.gray, 0, 5.4, 0);
    mesh(g, cyl(2.94, 2.94, 0.2, 10), C.gray, 0, 8.2, 0);
    mesh(g, box(1.2, 2.2, 0.2), C.woodDark, 0, 1.1, 2.86);
    return g;
  }

  function makeWindmill() {
    var g = new THREE.Group();
    mesh(g, cyl(1.25, 2.5, 11, 8), C.cream, 0, 5.5, 0);
    mesh(g, cone(2.35, 2.4, 8), C.barn, 0, 12.2, 0);
    mesh(g, box(1.1, 1.5, 0.18), C.wood, 0, 1.1, 2.42);
    var hub = new THREE.Group();
    hub.position.set(0, 10.6, 2.55);
    g.add(hub);
    mesh(hub, sph(0.55, 8, 6), C.woodDark, 0, 0, 0);
    for (var i = 0; i < 4; i++) {
      var arm = new THREE.Group();
      arm.rotation.z = i * Math.PI / 2;
      hub.add(arm);
      mesh(arm, box(0.32, 5.2, 0.26), C.wood, 0, 2.7, 0);
      mesh(arm, box(0.95, 4.2, 0.08), C.cream, 0, 2.85, 0.17);
    }
    var vane = new THREE.Group();
    vane.position.set(0, 11.4, -1.9);
    g.add(vane);
    mesh(vane, box(0.14, 0.14, 2.2), C.woodDark, 0, 0, 0);
    mesh(vane, box(1.2, 0.9, 0.1), C.barn, 0, 0.2, -1.0);
    g.userData.spin = hub;
    g.userData.vane = vane;
    return g;
  }

  function makeWell() {
    var g = new THREE.Group();
    mesh(g, cyl(1.7, 1.8, 1.3, 8), C.stone, 0, 0.65, 0);
    mesh(g, cyl(1.76, 1.76, 0.16, 8), C.gray, 0, 1.36, 0);
    mesh(g, cyl(1.2, 1.2, 0.1, 8), 0x2F3B4A, 0, 1.4, 0);
    mesh(g, box(0.22, 2.6, 0.22), C.wood, -1.4, 2.6, 0);
    mesh(g, box(0.22, 2.6, 0.22), C.wood, 1.4, 2.6, 0);
    gable(g, 3.6, 2.2, 1.1, C.barn, 3.9);
    mesh(g, cyl(0.1, 0.1, 2.7, 6), C.woodDark, 0, 3.2, 0, { rz: Math.PI / 2 });
    mesh(g, cyl(0.34, 0.4, 0.5, 6), C.barnDeep, 0, 2.3, 0);
    return g;
  }

  function makeCoop() {
    var g = new THREE.Group();
    mesh(g, box(4.6, 1.9, 3.2), C.wood, 0, 0.95, 0);
    gable(g, 5.2, 3.8, 1.0, C.barnDeep, 1.9);
    mesh(g, box(0.8, 0.9, 0.14), 0x4A3A2C, 0, 0.55, 1.62);
    mesh(g, box(1.4, 0.08, 1.3), C.woodDark, 0, 0.3, 2.2, { rx: -0.34 });
    mesh(g, cyl(0.05, 0.05, 0.6, 5), C.woodDark, 0.7, 1.7, 1.2);
    return g;
  }

  function makeStable() {
    var g = new THREE.Group();
    mesh(g, box(8.6, 3.6, 5.4), C.wood, 0, 1.8, 0);
    gable(g, 9.6, 6.4, 2.3, C.barnDeep, 3.6);
    mesh(g, box(2.0, 2.6, 0.16), C.cream, -2.0, 1.3, 2.74);
    mesh(g, box(2.0, 2.6, 0.16), C.cream, 2.0, 1.3, 2.74);
    mesh(g, box(8.7, 0.3, 0.2), C.cream, 0, 3.3, 2.72);
    mesh(g, box(0.9, 0.9, 0.14), windowMaterial(), 0, 4.4, 2.66);
    return g;
  }

  function makeGreenhouse() {
    var g = new THREE.Group();
    var glass = new THREE.MeshPhongMaterial({
      color: 0xBFE8D8,
      flatShading: true,
      shininess: 0,
      specular: 0x000000,
      transparent: true,
      opacity: 0.32,
      depthWrite: false,
      side: THREE.DoubleSide
    });
    mesh(g, box(11.4, 3.3, 6.4), glass, 0, 1.65, 0, { cast: false, receive: false });
    for (var i = -2; i <= 2; i++) {
      mesh(g, box(0.15, 3.4, 0.15), C.white, i * 2.6, 1.7, 3.2, { cast: false });
      mesh(g, box(0.15, 3.4, 0.15), C.white, i * 2.6, 1.7, -3.2, { cast: false });
    }
    mesh(g, box(11.6, 0.15, 0.15), C.white, 0, 3.35, 3.2, { cast: false });
    mesh(g, box(11.6, 0.15, 0.15), C.white, 0, 3.35, -3.2, { cast: false });
    var rs = Math.atan2(2.0, 6.0);
    mesh(g, box(6.7, 0.12, 7.0), glass, -3.0, 4.3, 0, { rz: rs, cast: false, receive: false });
    mesh(g, box(6.7, 0.12, 7.0), glass, 3.0, 4.3, 0, { rz: -rs, cast: false, receive: false });
    mesh(g, box(0.14, 0.14, 7.0), C.white, 0, 5.28, 0, { cast: false });
    for (var j = 0; j < 4; j++) {
      mesh(g, box(0.7, 0.55, 0.7), C.leaf, -3.6 + j * 2.1, 0.28, 0.9, { cast: false });
    }
    return g;
  }

  function makeGate() {
    var g = new THREE.Group();
    mesh(g, box(0.5, 2.9, 0.5), C.woodDark, -3.2, 1.45, 0);
    mesh(g, box(0.5, 2.9, 0.5), C.woodDark, 3.2, 1.45, 0);
    mesh(g, box(6.0, 0.2, 0.16), C.wood, 0, 0.8, 0);
    mesh(g, box(6.0, 0.2, 0.16), C.wood, 0, 1.5, 0);
    mesh(g, box(6.0, 0.2, 0.16), C.wood, 0, 2.2, 0);
    mesh(g, box(0.18, 2.5, 0.16), C.wood, -1.2, 1.5, 0, { rz: 0.9 });
    return g;
  }

  function makeToolShed() {
    var g = new THREE.Group();
    mesh(g, box(4.6, 2.6, 3.8), C.wood, 0, 1.3, 0);
    gable(g, 5.2, 4.4, 1.3, C.barnDeep, 2.6);
    mesh(g, box(1.1, 1.7, 0.14), C.woodDark, 0, 0.85, 1.92);
    return g;
  }

  function makeTractor() {
    var g = new THREE.Group();
    mesh(g, box(1.9, 1.0, 2.6), C.barn, 0, 1.05, 0);
    mesh(g, box(1.3, 1.15, 1.1), C.cream, 0, 2.0, -0.35);
    mesh(g, box(1.32, 0.55, 0.42), 0x9EC8E0, 0, 2.1, 0.12);
    mesh(g, box(1.7, 0.55, 0.9), C.barnDeep, 0, 0.95, 1.35);
    mesh(g, box(1.2, 0.16, 0.16), C.cream, 0, 1.75, 1.7);
    mesh(g, cyl(0.78, 0.78, 0.36, 10), C.ink, -1.0, 0.8, -0.7, { rz: Math.PI / 2 });
    mesh(g, cyl(0.78, 0.78, 0.36, 10), C.ink, 1.0, 0.8, -0.7, { rz: Math.PI / 2 });
    mesh(g, cyl(0.5, 0.5, 0.3, 10), C.ink, -0.98, 0.55, 1.0, { rz: Math.PI / 2 });
    mesh(g, cyl(0.5, 0.5, 0.3, 10), C.ink, 0.98, 0.55, 1.0, { rz: Math.PI / 2 });
    mesh(g, cyl(0.09, 0.09, 1.3, 5), 0x5B5B5B, 0.62, 1.95, 0.8);
    mesh(g, cyl(0.16, 0.16, 0.14, 6), 0x3D3527, 0.62, 2.62, 0.8);
    mesh(g, sph(0.16, 8, 6), 0xFFF3C4, 0, 2.1, 1.55, { cast: false });
    return g;
  }

  function makeTrailer() {
    var g = new THREE.Group();
    mesh(g, box(2.2, 0.35, 4.0), C.wood, 0, 0.95, 0);
    mesh(g, box(2.2, 0.85, 0.16), C.wood, 0, 1.42, 1.92);
    mesh(g, box(2.2, 0.85, 0.16), C.wood, 0, 1.42, -1.92);
    mesh(g, box(0.16, 0.85, 4.0), C.wood, -1.06, 1.42, 0);
    mesh(g, box(0.16, 0.85, 4.0), C.wood, 1.06, 1.42, 0);
    mesh(g, cyl(0.62, 0.62, 0.28, 9), C.ink, -1.1, 0.62, 0.4, { rz: Math.PI / 2 });
    mesh(g, cyl(0.62, 0.62, 0.28, 9), C.ink, 1.1, 0.62, 0.4, { rz: Math.PI / 2 });
    mesh(g, box(0.16, 0.16, 1.3), C.woodDark, 0, 0.7, 2.4);
    // 车斗里的粮食单独成组，运粮时按高度慢慢长满（基准点在斗底，直接拉 y 缩放）
    var heap = new THREE.Group();
    heap.position.set(0, 1.12, -1.0);
    mesh(heap, box(1.5, 0.5, 1.1), C.wheat, 0, 0.24, 0);
    mesh(heap, box(0.9, 0.24, 0.8), C.wheatDeep, -0.12, 0.56, 0.05);
    g.add(heap);
    g.userData.heap = heap;
    return g;
  }

  function makePlow() {
    var g = new THREE.Group();
    mesh(g, box(0.18, 0.18, 2.6), C.gray, 0, 0.7, 0);
    mesh(g, box(2.0, 0.14, 0.2), C.gray, 0, 0.7, -0.7);
    mesh(g, box(0.14, 0.14, 1.1), C.wood, 0, 0.9, 1.5, { rx: 0.3 });
    for (var i = -1; i <= 1; i++) {
      mesh(g, box(0.55, 0.5, 0.1), C.gray, i * 0.68, 0.4, -0.7, { rx: 0.55 });
    }
    return g;
  }

  function makeHarvester() {
    var g = new THREE.Group();
    mesh(g, box(2.3, 1.3, 3.4), C.barn, 0, 1.15, 0);
    mesh(g, box(1.5, 1.1, 1.2), C.cream, 0, 2.15, -0.9);
    mesh(g, box(1.52, 0.5, 0.44), 0x9EC8E0, 0, 2.25, -0.62);
    mesh(g, box(3.0, 0.4, 0.7), C.gray, 0, 1.5, 1.95);
    mesh(g, box(3.0, 0.9, 0.14), C.wheatDeep, 0, 2.0, 2.2);
    mesh(g, cyl(0.82, 0.82, 0.4, 10), C.ink, -1.15, 0.82, -1.0, { rz: Math.PI / 2 });
    mesh(g, cyl(0.82, 0.82, 0.4, 10), C.ink, 1.15, 0.82, -1.0, { rz: Math.PI / 2 });
    mesh(g, cyl(0.5, 0.5, 0.32, 10), C.ink, -1.1, 0.52, 1.0, { rz: Math.PI / 2 });
    mesh(g, cyl(0.5, 0.5, 0.32, 10), C.ink, 1.1, 0.52, 1.0, { rz: Math.PI / 2 });
    return g;
  }

  function makeWheelbarrow(withGrain) {
    var g = new THREE.Group();
    mesh(g, box(1.0, 0.4, 0.7), C.gray, 0, 0.55, 0);
    mesh(g, box(0.9, 0.45, 0.12), C.gray, 0, 0.85, 0.34, { rx: -0.25 });
    mesh(g, box(0.9, 0.45, 0.12), C.gray, 0, 0.85, -0.34, { rx: 0.25 });
    mesh(g, cyl(0.26, 0.26, 0.14, 8), C.ink, 0, 0.28, 0.55, { rz: Math.PI / 2 });
    mesh(g, cyl(0.05, 0.05, 1.2, 5), C.wood, 0, 0.7, -0.7, { rx: 0.4 });
    if (withGrain) {
      var heap = new THREE.Group();
      heap.position.set(0, 0.74, 0);
      mesh(heap, box(0.72, 0.3, 0.5), C.wheat, 0, 0.12, 0, { cast: false });
      mesh(heap, box(0.44, 0.2, 0.34), C.wheatDeep, 0.05, 0.32, -0.04, { cast: false });
      g.add(heap);
      g.userData.heap = heap;
    }
    return g;
  }

  function makeWateringCan() {
    var g = new THREE.Group();
    mesh(g, cyl(0.34, 0.4, 0.6, 8), C.teal, 0, 0.35, 0);
    mesh(g, cyl(0.05, 0.05, 0.6, 5), C.teal, 0.42, 0.55, 0, { rz: -0.85 });
    mesh(g, cyl(0.1, 0.06, 0.14, 6), C.teal, 0.7, 0.78, 0, { rz: -0.85 });
    mesh(g, cyl(0.03, 0.03, 0.34, 4), C.teal, -0.3, 0.72, 0, { rz: 0.4 });
    return g;
  }

  function makeShovel() {
    var g = new THREE.Group();
    mesh(g, cyl(0.04, 0.04, 1.4, 5), C.wood, 0, 0.8, 0, { rz: 0.3 });
    mesh(g, box(0.34, 0.42, 0.08), C.gray, 0.4, 0.2, 0);
    return g;
  }

  function makePitchfork() {
    var g = new THREE.Group();
    mesh(g, cyl(0.04, 0.04, 1.6, 5), C.wood, 0, 0.85, 0);
    mesh(g, box(0.6, 0.08, 0.08), C.gray, 0, 1.6, 0);
    for (var i = -1; i <= 1; i++) {
      mesh(g, cyl(0.025, 0.025, 0.4, 4), C.gray, i * 0.26, 1.78, 0);
    }
    return g;
  }

  function makeHay() {
    var g = new THREE.Group();
    for (var i = 0; i < 3; i++) {
      mesh(g, cyl(0.85, 0.85, 1.5, 9), C.wheat, -2.4 + i * 2.3, 0.85, (i % 2) * 0.6, { rz: Math.PI / 2 });
    }
    mesh(g, box(1.2, 0.8, 1.2), C.wheatDeep, 3.4, 0.4, -0.4);
    return g;
  }

  function makeAppleTree() {
    var g = new THREE.Group();
    mesh(g, cyl(0.35, 0.5, 2.6, 6), C.trunk, 0, 1.3, 0);
    mesh(g, sph(1.7, 8, 6), C.leaf, 0, 3.5, 0);
    mesh(g, sph(1.2, 7, 5), C.leafDark, -1.0, 3.0, 0.5);
    mesh(g, sph(1.1, 7, 5), C.leaf, 1.0, 3.1, -0.4);
    mesh(g, sph(0.18, 6, 4), C.red, 0.6, 3.4, 0.9, { cast: false });
    mesh(g, sph(0.18, 6, 4), C.red, -0.7, 3.2, 0.8, { cast: false });
    mesh(g, sph(0.18, 6, 4), C.red, 0.2, 4.2, -0.6, { cast: false });
    return g;
  }

  function makeTree(s) {
    s = s || 1;
    var g = new THREE.Group();
    mesh(g, cyl(0.42 * s, 0.62 * s, 3.0 * s, 6), C.trunk, 0, 1.5 * s, 0);
    mesh(g, sph(1.9 * s, 8, 6), C.leaf, 0, 4.0 * s, 0);
    mesh(g, sph(1.35 * s, 7, 5), C.leafDark, -1.15 * s, 3.2 * s, 0.55 * s);
    mesh(g, sph(1.25 * s, 7, 5), C.leaf, 1.1 * s, 3.4 * s, -0.5 * s);
    return g;
  }

  function makePond() {
    var g = new THREE.Group();
    var water = new THREE.Mesh(
      new THREE.CircleGeometry(10.6, 30),
      new THREE.MeshPhongMaterial({
        color: C.water,
        flatShading: true,
        shininess: 30,
        specular: 0x2F6F86,
        transparent: true,
        opacity: 0.9
      })
    );
    water.rotation.x = -Math.PI / 2;
    water.position.y = 0.14;
    water.receiveShadow = true;
    water.userData.wordId = 'pond';
    g.add(water);
    for (var i = 0; i < 20; i++) {
      var a = i / 20 * Math.PI * 2;
      mesh(g, sph(0.3 + (i % 3) * 0.08, 6, 4), C.stone, Math.cos(a) * 10.8, 0.18, Math.sin(a) * 10.8, { cast: false });
    }
    for (var j = 0; j < 14; j++) {
      var b = j / 14 * Math.PI * 2 + 0.2;
      mesh(g, cyl(0.04, 0.04, 1.1, 4), C.leafDark, Math.cos(b) * 9.6, 0.65, Math.sin(b) * 9.6, { cast: false });
    }
    g.userData.water = water;
    return g;
  }

  function makeBridge() {
    var g = new THREE.Group();
    for (var i = 0; i < 7; i++) {
      mesh(g, box(3.0, 0.1, 0.34), C.wood, 0, 0.3 + Math.sin(i / 6 * Math.PI) * 0.16, -2.1 + i * 0.7, { rx: 0.06 });
    }
    for (var s = -1; s <= 1; s += 2) {
      mesh(g, box(0.1, 0.9, 0.1), C.woodDark, s * 1.5, 0.75, -2.0);
      mesh(g, box(0.1, 0.9, 0.1), C.woodDark, s * 1.5, 0.75, 2.0);
      mesh(g, box(0.08, 0.08, 4.2), C.woodDark, s * 1.5, 1.15, 0);
    }
    return g;
  }

  function makeHill(r, h) {
    var geo = new THREE.SphereGeometry(r, 12, 7, 0, Math.PI * 2, 0, Math.PI / 2);
    var m = new THREE.Mesh(geo, material(C.sage));
    m.scale.y = h / r;
    m.castShadow = false;
    m.receiveShadow = true;
    return m;
  }

  function makeCloud(scale) {
    var g = new THREE.Group();
    var mat = material(C.white, { opacity: 0.92 });
    mesh(g, sph(3.2 * scale, 7, 5), mat, 0, 0, 0, { cast: false, receive: false });
    mesh(g, sph(2.2 * scale, 7, 5), mat, 3.2 * scale, -0.4 * scale, 0.4 * scale, { cast: false, receive: false });
    mesh(g, sph(2.4 * scale, 7, 5), mat, -3.0 * scale, -0.3 * scale, -0.3 * scale, { cast: false, receive: false });
    return g;
  }

  function makeLamp() {
    var g = new THREE.Group();
    mesh(g, cyl(0.08, 0.11, 3.4, 6), C.woodDark, 0, 1.7, 0);
    mesh(g, box(0.7, 0.08, 0.08), C.woodDark, 0.3, 3.35, 0);
    mesh(g, sph(0.22, 8, 6), lampMaterial(), 0.62, 3.2, 0, { cast: false });
    return g;
  }

  function makeCow() {
    var g = new THREE.Group();
    var white = C.white;
    var dark = 0x2E2A26;
    // 白底身体 + 环绕两圈的黑花斑（斑块略宽于身体，包住两侧）+ 背脊黑条
    mesh(g, box(1.35, 1.1, 2.1), white, 0, 1.2, 0);
    mesh(g, box(1.38, 0.6, 0.82), dark, 0, 1.34, -0.52);
    mesh(g, box(1.38, 0.44, 0.56), dark, 0, 1.0, 0.46);
    mesh(g, box(0.56, 0.1, 2.12), dark, -0.26, 1.75, 0);
    // 头 + 粉色口鼻 + 眼睛（统一挂到 head 轴，便于低头吃草）
    var head = new THREE.Group();
    head.position.set(0, 1.55, 0.72);
    g.add(head);
    var headParts = [];
    // 头 + 粉色口鼻 + 眼睛
    headParts.push(mesh(g, box(0.8, 0.74, 0.68), white, 0, 1.76, 1.08));
    headParts.push(mesh(g, box(0.5, 0.3, 0.2), C.pink, 0, 1.56, 1.46));
    headParts.push(mesh(g, box(0.12, 0.08, 0.06), dark, -0.13, 1.58, 1.58));
    headParts.push(mesh(g, box(0.12, 0.08, 0.06), dark, 0.13, 1.58, 1.58));
    headParts.push(mesh(g, box(0.16, 0.16, 0.1), dark, -0.21, 1.9, 1.43));
    headParts.push(mesh(g, box(0.16, 0.16, 0.1), dark, 0.21, 1.9, 1.43));
    // 牛角 + 耳朵（内耳粉色）
    headParts.push(mesh(g, cone(0.09, 0.3, 5), 0xE4D7BB, -0.27, 2.14, 1.02, { rz: 0.4 }));
    headParts.push(mesh(g, cone(0.09, 0.3, 5), 0xE4D7BB, 0.27, 2.14, 1.02, { rz: -0.4 }));
    var earL = mesh(g, box(0.3, 0.12, 0.2), white, -0.5, 1.88, 1.0, { rz: 0.25 });
    var earR = mesh(g, box(0.3, 0.12, 0.2), white, 0.5, 1.88, 1.0, { rz: -0.25 });
    headParts.push(earL);
    headParts.push(earR);
    mesh(earL, box(0.16, 0.05, 0.12), C.pink, 0, 0, 0.06);
    mesh(earR, box(0.16, 0.05, 0.12), C.pink, 0, 0, 0.06);
    for (var hp = 0; hp < headParts.length; hp++) head.attach(headParts[hp]);
    // 腿 + 深色蹄
    for (var i = 0; i < 4; i++) {
      var xs = i % 2 === 0 ? -0.46 : 0.46;
      var zs = i < 2 ? 0.72 : -0.72;
      mesh(g, cyl(0.12, 0.12, 1.2, 5), white, xs, 0.6, zs);
      mesh(g, cyl(0.13, 0.13, 0.16, 5), dark, xs, 0.08, zs);
    }
    // 粉色乳房（奶牛标志）
    mesh(g, sph(0.24, 6, 5), C.pink, 0, 0.62, -0.42);
    mesh(g, cyl(0.04, 0.05, 0.16, 4), C.pink, -0.1, 0.46, -0.42);
    mesh(g, cyl(0.04, 0.05, 0.16, 4), C.pink, 0.1, 0.46, -0.42);
    // 尾巴 + 尾端黑毛
    var tail = mesh(g, cyl(0.05, 0.05, 0.8, 4), white, 0, 1.5, -1.08, { rx: 0.5 });
    mesh(tail, sph(0.1, 5, 4), dark, 0, -0.45, 0);
    g.userData.idle = { kind: 'cow', tail: tail, head: head, phase: 0.4 };
    return g;
  }

  function makePig() {
    var g = new THREE.Group();
    var skin = 0xF4AEBC;
    var skinDeep = 0xE58DA3;
    var hoofCol = 0xA8645F;
    // 圆滚滚的躯干
    var body = mesh(g, sph(0.7, 12, 9), skin, 0, 0.82, -0.05);
    body.scale.set(1.0, 0.88, 1.28);
    // 头 + 猪鼻 + 眼睛 + 耳朵 + 腮红
    var head = new THREE.Group();
    head.position.set(0, 1.04, 0.76);
    g.add(head);
    var skull = mesh(head, sph(0.42, 12, 9), skin, 0, 0, 0);
    skull.scale.set(1, 0.92, 0.95);
    mesh(head, cyl(0.2, 0.22, 0.2, 10), skinDeep, 0, -0.06, 0.4, { rx: Math.PI / 2 });
    for (var pn = -1; pn <= 1; pn += 2) {
      var nostril = mesh(head, sph(0.03, 8, 6), hoofCol, pn * 0.075, -0.06, 0.505, { cast: false });
      nostril.scale.set(1, 1.25, 0.4);
    }
    var mouth = mesh(head, new THREE.TorusGeometry(0.045, 0.007, 5, 12, Math.PI), C.ink, 0, -0.18, 0.512, { cast: false });
    mouth.rotation.z = Math.PI;
    for (var es = -1; es <= 1; es += 2) {
      var eye = mesh(head, sph(0.052, 10, 8), C.ink, es * 0.17, 0.12, 0.35);
      eye.scale.set(1, 1.06, 0.6);
      mesh(head, sph(0.016, 8, 6), C.white, es * 0.15, 0.145, 0.39, { cast: false });
      var ear = mesh(head, cone(0.17, 0.26, 4), skin, es * 0.27, 0.34, 0.02, { rz: es * -0.28 });
      ear.scale.z = 0.6;
      var innerEar = mesh(head, cone(0.1, 0.16, 4), skinDeep, es * 0.28, 0.36, 0.08, { rz: es * -0.28 });
      innerEar.scale.z = 0.4;
    }
    // 四条短腿 + 深色蹄
    for (var i = 0; i < 4; i++) {
      var px = i % 2 === 0 ? -0.34 : 0.34;
      var pz = i < 2 ? 0.52 : -0.56;
      mesh(g, cyl(0.13, 0.14, 0.42, 6), skin, px, 0.24, pz);
      mesh(g, cyl(0.135, 0.135, 0.1, 6), hoofCol, px, 0.05, pz);
    }
    // 卷卷的小尾巴
    var tail = new THREE.Group();
    tail.position.set(0, 1.0, -1.0);
    g.add(tail);
    var curl = mesh(tail, new THREE.TorusGeometry(0.1, 0.027, 4, 10, Math.PI * 1.6), skin, 0, 0, 0);
    curl.rotation.y = Math.PI / 2;
    g.userData.idle = { kind: 'pig', phase: 1.2, body: g, head: head, tail: tail };
    return g;
  }

  function makeSheep() {
    var g = new THREE.Group();
    var wool = C.white;
    var face = 0x4A4238;
    // 羊毛：主体 + 一圈鼓包，轮廓毛茸茸
    mesh(g, sph(0.84, 8, 6), wool, 0, 1.02, 0);
    mesh(g, sph(0.56, 7, 5), wool, 0.64, 1.02, 0.34);
    mesh(g, sph(0.54, 7, 5), wool, -0.6, 1.04, -0.3);
    mesh(g, sph(0.42, 6, 5), wool, 0.3, 1.56, -0.08);
    mesh(g, sph(0.4, 6, 5), wool, -0.32, 1.55, 0.3);
    mesh(g, sph(0.4, 6, 5), wool, -0.05, 1.6, 0.5);
    mesh(g, sph(0.38, 6, 5), wool, 0.06, 1.56, -0.58);
    mesh(g, sph(0.36, 6, 5), wool, -0.5, 1.3, 0.36);
    mesh(g, sph(0.34, 6, 5), wool, 0.52, 1.3, -0.3);
    // 深色脸 + 口鼻 + 眼睛 + 垂耳（挂到 head 轴，便于低头吃草）
    var head = new THREE.Group();
    head.position.set(0, 1.14, 0.68);
    g.add(head);
    var headParts = [];
    headParts.push(mesh(g, box(0.46, 0.52, 0.56), face, 0, 1.22, 0.92));
    headParts.push(mesh(g, box(0.34, 0.26, 0.18), 0x6E6456, 0, 1.06, 1.22));
    headParts.push(mesh(g, box(0.1, 0.1, 0.08), C.ink, -0.13, 1.28, 1.22));
    headParts.push(mesh(g, box(0.1, 0.1, 0.08), C.ink, 0.13, 1.28, 1.22));
    headParts.push(mesh(g, box(0.34, 0.14, 0.18), face, -0.36, 1.3, 0.94, { rz: 0.35 }));
    headParts.push(mesh(g, box(0.34, 0.14, 0.18), face, 0.36, 1.3, 0.94, { rz: -0.35 }));
    for (var hp = 0; hp < headParts.length; hp++) head.attach(headParts[hp]);
    // 腿 + 深色蹄
    for (var i = 0; i < 4; i++) {
      var xs = i % 2 === 0 ? -0.4 : 0.4;
      var zs = i < 2 ? 0.45 : -0.45;
      mesh(g, cyl(0.08, 0.08, 0.7, 4), face, xs, 0.35, zs);
      mesh(g, cyl(0.09, 0.09, 0.12, 4), 0x2E2A24, xs, 0.06, zs);
    }
    // 小尾巴
    mesh(g, sph(0.14, 5, 4), wool, 0, 1.14, -0.9);
    g.userData.idle = { kind: 'sheep', phase: 2.1, body: g, head: head };
    return g;
  }

  function makeHorse() {
    var g = new THREE.Group();
    var coat = 0x9A6B42;
    var mane = 0x46301F;
    var hoof = 0x3A2F26;
    // 身体
    mesh(g, box(1.05, 1.05, 2.25), coat, 0, 1.55, 0);
    // 高脖子 + 沿颈背的一排鬃毛
    mesh(g, box(0.52, 1.4, 0.6), coat, 0, 2.2, 0.95, { rx: 0.3 });
    for (var mi = 0; mi < 6; mi++) {
      mesh(g, box(0.14, 0.28, 0.2), mane, 0, 2.82 - mi * 0.24, 0.8 - mi * 0.055);
    }
    // 头 + 白鼻梁 + 深色口鼻 + 眼睛 + 耳朵（挂到 head 轴，便于低头吃草）
    var head = new THREE.Group();
    head.position.set(0, 2.45, 0.95);
    g.add(head);
    var headParts = [];
    headParts.push(mesh(g, box(0.52, 0.5, 0.86), coat, 0, 2.88, 1.42));
    headParts.push(mesh(g, box(0.14, 0.36, 0.09), C.cream, 0, 2.94, 1.85));
    headParts.push(mesh(g, box(0.4, 0.32, 0.24), 0x5F4A33, 0, 2.74, 1.86));
    headParts.push(mesh(g, box(0.12, 0.1, 0.06), C.ink, -0.2, 2.96, 1.86));
    headParts.push(mesh(g, box(0.12, 0.1, 0.06), C.ink, 0.2, 2.96, 1.86));
    headParts.push(mesh(g, cone(0.09, 0.28, 4), coat, -0.19, 3.22, 1.42));
    headParts.push(mesh(g, cone(0.09, 0.28, 4), coat, 0.19, 3.22, 1.42));
    for (var hp = 0; hp < headParts.length; hp++) head.attach(headParts[hp]);
    // 长腿 + 深色蹄 + 前腿白袜
    for (var i = 0; i < 4; i++) {
      var xs = i % 2 === 0 ? -0.42 : 0.42;
      var zs = i < 2 ? 0.82 : -0.82;
      mesh(g, cyl(0.1, 0.1, 1.7, 5), coat, xs, 0.85, zs);
      mesh(g, cyl(0.12, 0.12, 0.14, 5), hoof, xs, 0.07, zs);
    }
    mesh(g, cyl(0.11, 0.11, 0.4, 5), C.cream, -0.42, 0.35, 0.82);
    mesh(g, cyl(0.11, 0.11, 0.4, 5), C.cream, 0.42, 0.35, 0.82);
    // 深色长尾
    var tail = mesh(g, cyl(0.07, 0.11, 1.15, 5), mane, 0, 1.75, -1.18, { rx: 0.4 });
    mesh(tail, sph(0.13, 5, 4), mane, 0, -0.6, 0);
    g.userData.idle = { kind: 'horse', tail: tail, head: head, phase: 3.0, body: g };
    return g;
  }

  function makeGoat() {
    var g = new THREE.Group();
    var coat = 0xE6DDCC;
    var patch = 0x9C7A52;
    var hornCol = 0xC9B68F;
    // 身体 + 棕色斑块
    mesh(g, box(0.82, 0.74, 1.45), coat, 0, 1.02, 0);
    mesh(g, box(0.84, 0.3, 0.52), patch, 0, 1.3, -0.36);
    mesh(g, box(0.86, 0.36, 0.4), patch, 0, 0.98, 0.3);
    // 头 + 口鼻 + 山羊胡子 + 弯角 + 耳朵 + 眼睛（挂到 head 轴，便于低头吃草）
    var head = new THREE.Group();
    head.position.set(0, 1.08, 0.58);
    g.add(head);
    var headParts = [];
    headParts.push(mesh(g, box(0.46, 0.46, 0.52), coat, 0, 1.26, 0.82));
    headParts.push(mesh(g, box(0.32, 0.2, 0.16), 0xCFC4AC, 0, 1.14, 1.14));
    headParts.push(mesh(g, cone(0.07, 0.34, 4), 0xB7A98E, 0, 0.96, 1.12, { rx: Math.PI }));
    // 弯角（每边两段）
    headParts.push(mesh(g, cone(0.07, 0.3, 4), hornCol, -0.13, 1.6, 0.72, { rz: 0.5 }));
    headParts.push(mesh(g, cone(0.05, 0.24, 4), hornCol, -0.26, 1.7, 0.66, { rz: 1.1 }));
    headParts.push(mesh(g, cone(0.07, 0.3, 4), hornCol, 0.13, 1.6, 0.72, { rz: -0.5 }));
    headParts.push(mesh(g, cone(0.05, 0.24, 4), hornCol, 0.26, 1.7, 0.66, { rz: -1.1 }));
    // 横耳朵 + 眼睛
    headParts.push(mesh(g, box(0.32, 0.1, 0.16), coat, -0.36, 1.3, 0.84, { rz: 0.4 }));
    headParts.push(mesh(g, box(0.32, 0.1, 0.16), coat, 0.36, 1.3, 0.84, { rz: -0.4 }));
    headParts.push(mesh(g, box(0.08, 0.08, 0.06), C.ink, -0.14, 1.3, 1.08));
    headParts.push(mesh(g, box(0.08, 0.08, 0.06), C.ink, 0.14, 1.3, 1.08));
    for (var hp = 0; hp < headParts.length; hp++) head.attach(headParts[hp]);
    // 腿 + 深色蹄
    for (var i = 0; i < 4; i++) {
      var xs = i % 2 === 0 ? -0.3 : 0.3;
      var zs = i < 2 ? 0.5 : -0.5;
      mesh(g, cyl(0.07, 0.07, 0.85, 4), coat, xs, 0.42, zs);
      mesh(g, cyl(0.08, 0.08, 0.12, 4), 0x3A2F26, xs, 0.06, zs);
    }
    // 上翘短尾
    mesh(g, cone(0.09, 0.3, 4), coat, 0, 1.2, -0.78, { rx: -0.7 });
    g.userData.idle = { kind: 'goat', phase: 4.2, body: g, head: head };
    return g;
  }

  function makeChicken(rooster) {
    var g = new THREE.Group();
    var bodyColor = rooster ? 0xE7A24B : 0xFFFDF6;
    var body = mesh(g, sph(0.36, 7, 5), bodyColor, 0, 0.52, 0);
    body.scale.set(1, 0.9, 1.15);
    mesh(g, sph(0.24, 7, 5), bodyColor, 0, 0.9, 0.24);
    mesh(g, box(0.1, 0.16, 0.1), C.red, 0, 1.12, 0.24);
    mesh(g, box(0.1, 0.14, 0.1), C.red, 0, 1.14, 0.12);
    mesh(g, cone(0.08, 0.18, 4), C.orange, 0, 0.9, 0.48, { rx: Math.PI / 2 });
    mesh(g, box(0.08, 0.12, 0.06), C.red, 0, 0.78, 0.44);
    mesh(g, cyl(0.03, 0.03, 0.4, 4), C.orange, -0.12, 0.2, 0);
    mesh(g, cyl(0.03, 0.03, 0.4, 4), C.orange, 0.12, 0.2, 0);
    if (rooster) {
      mesh(g, box(0.12, 0.5, 0.4), 0x5E8FB8, 0, 0.72, -0.36, { rx: -0.5 });
      mesh(g, box(0.12, 0.42, 0.34), 0xC8553D, 0, 0.8, -0.5, { rx: -0.7 });
      mesh(g, box(0.12, 0.34, 0.28), 0xF2C14E, 0, 0.62, -0.34, { rx: -0.4 });
    } else {
      mesh(g, box(0.3, 0.26, 0.1), C.creamDeep, 0, 0.6, -0.34, { rx: -0.6 });
    }
    g.userData.idle = { kind: rooster ? 'rooster' : 'chicken', phase: rooster ? 5.1 : 1.7, body: g };
    return g;
  }

  function makeDuck(goose) {
    var g = new THREE.Group();
    var col = goose ? C.white : 0xF6D06B;
    var body = mesh(g, sph(0.42, 8, 6), col, 0, 0.45, 0);
    body.scale.set(1, 0.68, 1.35);
    if (goose) {
      mesh(g, cyl(0.12, 0.14, 0.9, 6), col, 0, 1.0, 0.42, { rx: 0.18 });
      mesh(g, sph(0.22, 7, 5), col, 0, 1.45, 0.55);
      mesh(g, cone(0.09, 0.28, 4), C.orange, 0, 1.45, 0.78, { rx: Math.PI / 2 });
    } else {
      mesh(g, sph(0.26, 7, 5), col, 0, 0.72, 0.4);
      mesh(g, box(0.22, 0.1, 0.26), C.orange, 0, 0.68, 0.62);
    }
    mesh(g, box(0.34, 0.1, 0.24), col, 0, 0.5, -0.52, { rx: 0.4 });
    g.userData.idle = { kind: goose ? 'goose' : 'duck', phase: goose ? 2.6 : 0.8, body: g };
    return g;
  }

  // 小兔子：参考《小兔子的午后农场》的圆润造型重做——
  // 椭球身体 + 后腿肉垫 + 四只脚 + 圆尾巴，头部有腮帮子、口鼻、粉鼻头、
  // 亮晶晶的眼睛（带高光）、腮红、粉内耳长耳朵、胡须和一朵小雏菊。
  // 段数控制在 10-14，保持农场整体低多边形风格。
  var RABBIT = {
    fur: 0xF6F0E4,
    furLight: 0xFDF9F1,
    furBright: 0xFFFDF8,
    pink: 0xE795A3,
    blush: 0xF4C3C9,
    innerEar: 0xEFA6B3,
    eye: 0x2A241F,
    whisker: 0x8B7A66
  };

  function addRabbitFace(head, s) {
    // s = 头部整体缩放（1 = 站姿主角兔，略小用于蹦跳兔）
    // 腮帮子
    var cheekL = mesh(head, sph(0.13 * s, 10, 8), RABBIT.furLight, -0.13 * s, -0.07 * s, 0.15 * s);
    cheekL.scale.set(1, 0.92, 0.92);
    var cheekR = mesh(head, sph(0.13 * s, 10, 8), RABBIT.furLight, 0.13 * s, -0.07 * s, 0.15 * s);
    cheekR.scale.set(1, 0.92, 0.92);
    // 口鼻
    var muzzle = mesh(head, sph(0.12 * s, 10, 8), RABBIT.furLight, 0, -0.1 * s, 0.22 * s);
    muzzle.scale.set(1.12, 0.8, 0.95);
    // 粉鼻头 + 小嘴
    var nose = mesh(head, sph(0.045 * s, 8, 6), RABBIT.pink, 0, -0.045 * s, 0.335 * s, { cast: false });
    nose.scale.set(1.25, 0.9, 0.8);
    mesh(head, box(0.055 * s, 0.012 * s, 0.012 * s), 0x6B4A42, 0, -0.13 * s, 0.328 * s, { cast: false });
    // 腮红
    var blushL = mesh(head, sph(0.055 * s, 8, 6), RABBIT.blush, -0.18 * s, -0.08 * s, 0.19 * s, { cast: false });
    blushL.scale.set(1, 0.7, 0.18);
    var blushR = mesh(head, sph(0.055 * s, 8, 6), RABBIT.blush, 0.18 * s, -0.08 * s, 0.19 * s, { cast: false });
    blushR.scale.set(1, 0.7, 0.18);
    // 眼睛 + 高光
    mesh(head, sph(0.065 * s, 10, 8), RABBIT.eye, -0.145 * s, 0.03 * s, 0.215 * s);
    mesh(head, sph(0.065 * s, 10, 8), RABBIT.eye, 0.145 * s, 0.03 * s, 0.215 * s);
    mesh(head, sph(0.019 * s, 8, 6), C.white, -0.125 * s, 0.052 * s, 0.262 * s, { cast: false });
    mesh(head, sph(0.019 * s, 8, 6), C.white, 0.125 * s, 0.052 * s, 0.262 * s, { cast: false });
    // 胡须：每侧 3 根细枝，呈扇形张开
    for (var side = -1; side <= 1; side += 2) {
      for (var wi = 0; wi < 3; wi++) {
        mesh(head, box(0.22 * s, 0.006 * s, 0.006 * s), RABBIT.whisker,
          side * 0.2 * s, (-0.09 - wi * 0.022) * s, 0.26 * s,
          { rz: side * (0.22 - wi * 0.2), cast: false });
      }
    }
  }

  function addRabbitEar(head, side, s) {
    var e = new THREE.Group();
    e.position.set(side * 0.105 * s, 0.2 * s, -0.01 * s);
    e.rotation.z = side * -0.12;
    e.rotation.x = -0.08;
    head.add(e);
    var outer = mesh(e, sph(0.1 * s, 10, 8), RABBIT.fur, 0, 0.24 * s, 0);
    outer.scale.set(1, 2.5, 0.55);
    var inner = mesh(e, sph(0.06 * s, 8, 6), RABBIT.innerEar, 0, 0.245 * s, 0.04 * s, { cast: false });
    inner.scale.set(1, 2.3, 0.3);
    return e;
  }

  function makeRabbit() {
    var g = new THREE.Group();
    // 身体 + 浅色胸腹 + 后腿肉垫
    var body = mesh(g, sph(0.36, 14, 10), RABBIT.fur, 0, 0.44, -0.02);
    body.scale.set(1.0, 1.0, 1.2);
    var chest = mesh(g, sph(0.29, 12, 9), RABBIT.furLight, 0, 0.43, 0.19);
    chest.scale.set(0.9, 0.9, 0.86);
    var haunchL = mesh(g, sph(0.25, 10, 8), RABBIT.fur, -0.27, 0.32, -0.09);
    haunchL.scale.set(0.9, 1.0, 1.05);
    var haunchR = mesh(g, sph(0.25, 10, 8), RABBIT.fur, 0.27, 0.32, -0.09);
    haunchR.scale.set(0.9, 1.0, 1.05);
    // 后脚掌 + 收在胸前的前爪
    var footL = mesh(g, sph(0.14, 10, 8), RABBIT.fur, -0.2, 0.12, 0.16);
    footL.scale.set(1.0, 0.78, 1.35);
    var footR = mesh(g, sph(0.14, 10, 8), RABBIT.fur, 0.2, 0.12, 0.16);
    footR.scale.set(1.0, 0.78, 1.35);
    var pawL = mesh(g, sph(0.09, 8, 6), RABBIT.furLight, -0.13, 0.16, 0.36);
    pawL.scale.set(1, 0.92, 1.25);
    var pawR = mesh(g, sph(0.09, 8, 6), RABBIT.furLight, 0.13, 0.16, 0.36);
    pawR.scale.set(1, 0.92, 1.25);
    // 圆尾巴
    mesh(g, sph(0.12, 10, 8), RABBIT.furBright, 0, 0.46, -0.44);
    // 头
    var head = new THREE.Group();
    head.position.set(0, 0.86, 0.24);
    g.add(head);
    var skull = mesh(head, sph(0.28, 14, 10), RABBIT.fur, 0, 0, 0);
    skull.scale.set(1, 0.96, 0.98);
    addRabbitFace(head, 1);
    var earL = addRabbitEar(head, -1, 1);
    var earR = addRabbitEar(head, 1, 1);
    // 耳边的小雏菊（贴着右耳根部）
    var flower = new THREE.Group();
    flower.position.set(0.19, 0.16, 0.11);
    flower.rotation.set(0.2, 0.5, 0.3);
    head.add(flower);
    mesh(flower, sph(0.032, 8, 6), C.wheat, 0, 0, 0, { cast: false });
    for (var p = 0; p < 6; p++) {
      var pa = p / 6 * Math.PI * 2;
      var petal = mesh(flower, sph(0.028, 6, 5), RABBIT.furBright,
        Math.cos(pa) * 0.06, Math.sin(pa) * 0.06, 0, { cast: false });
      petal.scale.set(1, 1, 0.5);
    }
    g.userData.idle = { kind: 'rabbit', phase: 0.3, body: g, head: head, earL: earL, earR: earR };
    return g;
  }

  // 小猫：参考《打盹的橘猫》的造型重做——
  // 圆臀坐姿 + 橘色虎斑 + 奶油色口鼻/围兜/脚掌 + 粉鼻头和肉垫 +
  // 亮晶晶的眼睛 + 三角耳（粉内耳）+ 胡须 + 青绿项圈金铃铛 + 深色尾尖。
  function makeCat() {
    var g = new THREE.Group();
    var fur = 0xE9A05C;
    var cream = 0xFFE7CE;
    var pink = 0xDE9A93;
    var stripe = 0xA95F2C;
    var gold = 0xD6A84F;
    var collarCol = C.teal;

    // 圆臀 + 胸脯 + 奶油色围兜
    var hips = mesh(g, sph(0.3, 12, 9), fur, 0, 0.32, -0.04);
    hips.scale.set(1.08, 1.05, 1.15);
    var chest = mesh(g, sph(0.24, 12, 9), fur, 0, 0.52, 0.06);
    chest.scale.set(0.92, 1.05, 0.95);
    var bib = mesh(g, sph(0.17, 10, 8), cream, 0, 0.5, 0.2);
    bib.scale.set(0.9, 1.0, 0.55);
    // 前腿 + 奶油色脚掌（三颗粉色肉垫）+ 后脚掌
    for (var side = -1; side <= 1; side += 2) {
      mesh(g, cyl(0.055, 0.06, 0.36, 6), fur, side * 0.13, 0.2, 0.28);
      var paw = mesh(g, sph(0.075, 10, 8), cream, side * 0.13, 0.06, 0.33);
      paw.scale.set(1, 0.7, 1.2);
      for (var tb = -1; tb <= 1; tb++) {
        mesh(g, sph(0.014, 6, 5), pink, side * 0.13 + tb * 0.026, 0.036, 0.4, { cast: false });
      }
      var hind = mesh(g, sph(0.09, 10, 8), cream, side * 0.24, 0.08, 0.1);
      hind.scale.set(0.9, 0.55, 1.2);
    }
    // 头
    var head = new THREE.Group();
    head.position.set(0, 0.84, 0.16);
    g.add(head);
    var skull = mesh(head, sph(0.26, 14, 10), fur, 0, 0, 0);
    skull.scale.set(1, 0.95, 0.97);
    // 奶油色口鼻 + 粉鼻头 + 微笑
    var muzzle = mesh(head, sph(0.13, 10, 8), cream, 0, -0.06, 0.19);
    muzzle.scale.set(1.15, 0.72, 0.72);
    var nose = mesh(head, sph(0.032, 8, 6), pink, 0, -0.02, 0.3, { cast: false });
    nose.scale.set(1.2, 0.8, 0.7);
    var mouth = mesh(head, new THREE.TorusGeometry(0.048, 0.007, 5, 12, Math.PI), C.ink,
      0, -0.105, 0.31, { cast: false });
    mouth.rotation.z = Math.PI;
    // 脸颊
    var cheekL = mesh(head, sph(0.08, 8, 6), cream, -0.16, -0.07, 0.19, { cast: false });
    cheekL.scale.set(1, 1, 0.7);
    var cheekR = mesh(head, sph(0.08, 8, 6), cream, 0.16, -0.07, 0.19, { cast: false });
    cheekR.scale.set(1, 1, 0.7);
    // 眼睛 + 高光
    var eyeL = mesh(head, sph(0.055, 10, 8), C.ink, -0.11, 0.05, 0.205);
    eyeL.scale.set(1, 1.05, 0.6);
    var eyeR = mesh(head, sph(0.055, 10, 8), C.ink, 0.11, 0.05, 0.205);
    eyeR.scale.set(1, 1.05, 0.6);
    mesh(head, sph(0.016, 8, 6), C.white, -0.09, 0.076, 0.254, { cast: false });
    mesh(head, sph(0.016, 8, 6), C.white, 0.09, 0.076, 0.254, { cast: false });
    // 三角耳（粉内耳）
    function makeCatEar(s) {
      var e = new THREE.Group();
      e.position.set(s * 0.16, 0.2, -0.01);
      e.rotation.z = s * -0.22;
      e.rotation.x = -0.05;
      head.add(e);
      var outer = mesh(e, cone(0.13, 0.26, 3), fur, 0, 0.13, 0, { ry: Math.PI / 6 });
      outer.scale.z = 0.5;
      var inner = mesh(e, cone(0.075, 0.16, 3), pink, 0, 0.12, 0.045, { ry: Math.PI / 6, cast: false });
      inner.scale.z = 0.35;
      return e;
    }
    var earL = makeCatEar(-1);
    var earR = makeCatEar(1);
    // 额头虎斑（M 形三道）
    for (var si = -1; si <= 1; si++) {
      var mark = mesh(head, sph(0.04, 6, 5), stripe, si * 0.085, 0.155, 0.17, { cast: false });
      mark.scale.set(0.42, 1.35, 0.25);
      mark.rotation.x = -0.5;
      mark.rotation.z = si * -0.35;
    }
    // 胡须
    for (var ws = -1; ws <= 1; ws += 2) {
      for (var wi = 0; wi < 3; wi++) {
        mesh(head, box(0.2, 0.006, 0.006), C.cream,
          ws * 0.18, -0.06 - wi * 0.02, 0.24,
          { rz: ws * (0.2 - wi * 0.18), cast: false });
      }
    }
    // 青绿项圈 + 金铃铛
    var collar = mesh(g, new THREE.TorusGeometry(0.185, 0.022, 6, 18), collarCol, 0, 0.7, 0.13);
    collar.rotation.x = Math.PI / 2 - 0.18;
    var bell = mesh(g, sph(0.038, 10, 8), gold, 0, 0.62, 0.3);
    bell.scale.set(1, 1, 0.9);
    mesh(g, box(0.018, 0.018, 0.012), C.ink, 0, 0.62, 0.335, { cast: false });
    // 尾巴：从身后绕到身侧，深色尾尖
    var tailGroup = new THREE.Group();
    tailGroup.position.set(-0.05, 0.14, -0.3);
    g.add(tailGroup);
    var tailCurve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(-0.3, -0.03, 0.14),
      new THREE.Vector3(-0.39, -0.06, 0.38),
      new THREE.Vector3(-0.31, -0.07, 0.58),
      new THREE.Vector3(-0.23, -0.07, 0.64)
    ]);
    var tail = new THREE.Mesh(new THREE.TubeGeometry(tailCurve, 16, 0.05, 5, false), material(fur));
    tail.castShadow = true;
    tail.receiveShadow = true;
    tailGroup.add(tail);
    mesh(tailGroup, sph(0.055, 8, 6), stripe, -0.23, -0.07, 0.64);

    g.userData.idle = { kind: 'cat', phase: 1.1, body: g, head: head, tail: tailGroup, earL: earL, earR: earR };
    return g;
  }

  function makeLazyCat() {
    var g = new THREE.Group();
    var fur = 0xE9A05C;
    var stripe = 0xB97A3F;
    var belly = 0xFFE7CE;
    // 侧躺贴地的身体 + 浅色肚皮 + 背上的虎斑条纹
    var body = mesh(g, sph(0.5, 9, 7), fur, 0, 0.34, 0);
    body.scale.set(1.25, 0.62, 0.92);
    var tummy = mesh(g, sph(0.34, 7, 5), belly, 0, 0.2, 0.14);
    tummy.scale.set(1.3, 0.42, 1.0);
    // 虎斑条：用椭圆环贴住被压扁的身体，正/侧/背三个角度看都是贴合的条纹
    var stripeRing = function (z, rx, ry) {
      var ring = mesh(g, new THREE.TorusGeometry(1, 0.032, 5, 18), stripe, 0, 0.34, z);
      ring.scale.set(rx, ry, 0.62);
    };
    stripeRing(-0.18, 0.575, 0.285);
    stripeRing(0, 0.625, 0.31);
    stripeRing(0.18, 0.575, 0.285);
    // 头枕在前爪上：眯眼弧线 + 奶油色口鼻 + 粉鼻头 + 胡须
    mesh(g, sph(0.27, 10, 8), fur, 0, 0.42, 0.5);
    var pawL = mesh(g, sph(0.12, 8, 6), belly, -0.1, 0.14, 0.62);
    pawL.scale.set(1.05, 0.7, 1.35);
    var pawR = mesh(g, sph(0.12, 8, 6), belly, 0.1, 0.14, 0.62);
    pawR.scale.set(1.05, 0.7, 1.35);
    mesh(g, cone(0.1, 0.2, 4), fur, -0.16, 0.64, 0.48);
    mesh(g, cone(0.1, 0.2, 4), fur, 0.16, 0.64, 0.48);
    mesh(g, cone(0.055, 0.12, 4), 0xE79A9C, -0.16, 0.66, 0.5);
    mesh(g, cone(0.055, 0.12, 4), 0xE79A9C, 0.16, 0.66, 0.5);
    var muzzle = mesh(g, sph(0.09, 8, 6), belly, 0, 0.37, 0.7);
    muzzle.scale.set(1.25, 0.72, 0.65);
    var lazyEyeL = mesh(g, new THREE.TorusGeometry(0.05, 0.008, 5, 12, Math.PI), C.ink, -0.11, 0.45, 0.752, { cast: false });
    lazyEyeL.rotation.y = -0.25;
    var lazyEyeR = mesh(g, new THREE.TorusGeometry(0.05, 0.008, 5, 12, Math.PI), C.ink, 0.11, 0.45, 0.752, { cast: false });
    lazyEyeR.rotation.y = 0.25;
    var lazyNose = mesh(g, sph(0.032, 8, 6), C.pink, 0, 0.38, 0.79, { cast: false });
    lazyNose.scale.set(1.15, 0.8, 0.7);
    mesh(g, box(0.045, 0.012, 0.012), C.ink, 0, 0.345, 0.765, { cast: false });
    for (var lws = -1; lws <= 1; lws += 2) {
      for (var lwi = 0; lwi < 3; lwi++) {
        mesh(g, box(0.2, 0.007, 0.007), C.cream,
          lws * 0.19, 0.36 - lwi * 0.02, 0.72,
          { rz: lws * (0.2 - lwi * 0.18), cast: false });
      }
    }
    // 尾巴单独成组，idle 时轻轻摆动；贴地绕到身侧，锥形收尖 + 深色尾尖
    var tail = new THREE.Group();
    tail.position.set(0.34, 0.12, -0.34);
    g.add(tail);
    var tailCurve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(0.3, -0.05, -0.12),
      new THREE.Vector3(0.54, -0.07, 0.04),
      new THREE.Vector3(0.58, -0.07, 0.32),
      new THREE.Vector3(0.44, -0.07, 0.52)
    ]);
    mesh(tail, new THREE.TubeGeometry(tailCurve, 20, 0.068, 6, false), fur, 0, 0, 0);
    mesh(tail, sph(0.07, 8, 6), stripe, 0.44, -0.07, 0.52);
    g.userData.idle = { kind: 'lazy_cat', tail: tail, phase: 0.8, body: g };
    return g;
  }

  function makeHopRabbit() {
    var g = new THREE.Group();
    var fur = 0xF3EDE2;
    var furLight = 0xFDF9F1;
    var shade = 0xD9D0C2;
    // 前倾的身体 + 浅色肚皮 + 大后腿 + 收在胸前的前爪（像正要蹦起来）
    var body = mesh(g, sph(0.36, 12, 9), fur, 0, 0.46, 0.0);
    body.scale.set(1.0, 1.02, 1.12);
    body.rotation.x = -0.2;
    var belly = mesh(g, sph(0.26, 10, 8), furLight, 0, 0.4, 0.22);
    belly.scale.set(0.86, 0.82, 0.7);
    var thighL = mesh(g, sph(0.2, 8, 6), shade, -0.22, 0.3, -0.15);
    thighL.scale.set(0.95, 1.0, 1.1);
    var thighR = mesh(g, sph(0.2, 8, 6), shade, 0.22, 0.3, -0.15);
    thighR.scale.set(0.95, 1.0, 1.1);
    var footL = mesh(g, sph(0.17, 10, 8), fur, -0.2, 0.1, -0.02);
    footL.scale.set(1.05, 0.6, 1.5);
    var footR = mesh(g, sph(0.17, 10, 8), fur, 0.2, 0.1, -0.02);
    footR.scale.set(1.05, 0.6, 1.5);
    var pawL = mesh(g, sph(0.075, 8, 6), furLight, -0.12, 0.52, 0.33);
    pawL.scale.set(1, 1.1, 1.2);
    var pawR = mesh(g, sph(0.075, 8, 6), furLight, 0.12, 0.52, 0.33);
    pawR.scale.set(1, 1.1, 1.2);
    // 圆尾巴
    mesh(g, sph(0.115, 10, 8), 0xFFFDF8, 0, 0.46, -0.42);
    // 头 + 同一套五官（略小一号）
    var head = new THREE.Group();
    head.position.set(0, 0.84, 0.16);
    g.add(head);
    var skull = mesh(head, sph(0.27, 12, 9), fur, 0, 0, 0);
    skull.scale.set(1, 0.98, 0.98);
    addRabbitFace(head, 0.95);
    // 竖起的长耳朵（粉内耳）
    var earL = addRabbitEar(head, -1, 0.95);
    var earR = addRabbitEar(head, 1, 0.95);
    // 牧场里的装饰兔不蹦跳，改成低头在草坡上闻闻草、偶尔抬头（kind = rabbit_graze）
    g.userData.idle = { kind: 'rabbit_graze', phase: 0.9, body: g, head: head, earL: earL, earR: earR };
    return g;
  }

  function makeDog() {
    var g = new THREE.Group();
    var fur = 0xC9905A;
    var furDark = 0x8B5E3C;
    var cream = 0xF7E6C8;
    // 圆润的躯干 + 奶油色胸口
    var body = mesh(g, sph(0.42, 12, 9), fur, 0, 0.66, -0.08);
    body.scale.set(1.0, 0.95, 1.45);
    var chest = mesh(g, sph(0.3, 10, 8), cream, 0, 0.62, 0.42);
    chest.scale.set(0.9, 0.95, 0.7);
    mesh(g, sph(0.26, 10, 8), fur, 0, 0.86, 0.36);
    // 头：口鼻 + 黑鼻头 + 笑嘴 + 眼睛高光 + 腮红 + 垂耳
    var head = new THREE.Group();
    head.position.set(0, 1.08, 0.5);
    g.add(head);
    var skull = mesh(head, sph(0.32, 12, 9), fur, 0, 0, 0);
    skull.scale.set(1, 0.95, 1);
    var muzzle = mesh(head, sph(0.18, 10, 8), cream, 0, -0.1, 0.26);
    muzzle.scale.set(1.05, 0.8, 1.0);
    var nose = mesh(head, sph(0.052, 8, 6), C.ink, 0, -0.03, 0.42);
    nose.scale.set(1.2, 0.85, 0.8);
    var mouth = mesh(head, new THREE.TorusGeometry(0.06, 0.008, 5, 12, Math.PI), C.ink, 0, -0.155, 0.43, { cast: false });
    mouth.rotation.z = Math.PI;
    var earL = new THREE.Group();
    earL.position.set(-0.27, 0.08, -0.03);
    earL.rotation.z = -0.35;
    head.add(earL);
    var earLon = mesh(earL, sph(0.15, 8, 6), furDark, 0, -0.12, 0);
    earLon.scale.set(0.55, 1.2, 0.8);
    var earR = new THREE.Group();
    earR.position.set(0.27, 0.08, -0.03);
    earR.rotation.z = 0.35;
    head.add(earR);
    var earRon = mesh(earR, sph(0.15, 8, 6), furDark, 0, -0.12, 0);
    earRon.scale.set(0.55, 1.2, 0.8);
    for (var es = -1; es <= 1; es += 2) {
      var eye = mesh(head, sph(0.06, 10, 8), C.ink, es * 0.14, 0.05, 0.27);
      eye.scale.set(1, 1.08, 0.62);
      mesh(head, sph(0.017, 8, 6), C.white, es * 0.122, 0.075, 0.315, { cast: false });
      var blush = mesh(head, sph(0.07, 8, 6), 0xF4C3C9, es * 0.18, -0.07, 0.25, { cast: false });
      blush.scale.set(1.0, 0.45, 0.3);
    }
    // 红色项圈（前半圈贴合胸口）+ 金色小牌
    var collar = mesh(g, new THREE.TorusGeometry(0.24, 0.03, 6, 16, Math.PI), C.red, 0, 0.8, 0.36, { rx: Math.PI / 2 });
    mesh(g, sph(0.045, 8, 6), 0xE8C15A, 0, 0.72, 0.62);
    // 四条腿 + 奶油色爪子
    for (var i = 0; i < 4; i++) {
      var lx = i % 2 === 0 ? -0.23 : 0.23;
      var lz = i < 2 ? 0.38 : -0.45;
      mesh(g, cyl(0.085, 0.075, 0.5, 6), fur, lx, 0.28, lz);
      var paw = mesh(g, sph(0.1, 8, 6), cream, lx, 0.07, lz + 0.04);
      paw.scale.set(1, 0.7, 1.25);
    }
    // 翘起来的尾巴，idle 时快速摇摆
    var tail = new THREE.Group();
    tail.position.set(0, 0.84, -0.66);
    g.add(tail);
    var tailCurve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(0.02, 0.22, -0.14),
      new THREE.Vector3(0.03, 0.42, -0.16),
      new THREE.Vector3(0.02, 0.55, -0.06)
    ]);
    mesh(tail, new THREE.TubeGeometry(tailCurve, 14, 0.05, 5, false), fur, 0, 0, 0);
    mesh(tail, sph(0.05, 8, 6), cream, 0.02, 0.55, -0.06);
    g.userData.idle = { kind: 'dog', tail: tail, head: head, earL: earL, earR: earR, phase: 2.4, body: g };
    return g;
  }

  function makeBee() {
    var g = new THREE.Group();
    mesh(g, sph(0.2, 6, 4), C.yellow, 0, 0, 0);
    mesh(g, cyl(0.205, 0.205, 0.08, 6), C.ink, 0, 0.02, 0, { rx: Math.PI / 2 });
    mesh(g, cyl(0.205, 0.205, 0.08, 6), C.ink, 0, -0.02, 0, { rx: Math.PI / 2 });
    var wingMat = new THREE.MeshPhongMaterial({ color: 0xE8F6FF, transparent: true, opacity: 0.6, flatShading: true, side: THREE.DoubleSide, depthWrite: false });
    mesh(g, new THREE.CircleGeometry(0.26, 6), wingMat, -0.14, 0.2, 0, { rx: -0.7, rz: 0.3, cast: false });
    mesh(g, new THREE.CircleGeometry(0.26, 6), wingMat, 0.14, 0.2, 0, { rx: -0.7, rz: -0.3, cast: false });
    g.userData.idle = { kind: 'bee', phase: 0.5, body: g };
    return g;
  }

  function makeBird() {
    var g = new THREE.Group();
    mesh(g, sph(0.22, 6, 4), C.blue, 0, 0, 0);
    mesh(g, sph(0.15, 6, 4), C.blue, 0, 0.14, 0.18);
    mesh(g, cone(0.06, 0.16, 4), C.orange, 0, 0.13, 0.34, { rx: Math.PI / 2 });
    mesh(g, box(0.26, 0.04, 0.16), C.blue, -0.22, 0.06, 0, { rz: 0.4 });
    mesh(g, box(0.26, 0.04, 0.16), C.blue, 0.22, 0.06, 0, { rz: -0.4 });
    mesh(g, box(0.12, 0.04, 0.18), 0x4A80B0, 0, 0.02, -0.24);
    g.userData.idle = { kind: 'bird', phase: 3.4, body: g };
    return g;
  }

  function makePerson(opts) {
    var g = new THREE.Group();
    var coat = opts.coat;
    var pants = opts.pants;
    var skin = opts.skin || 0xF0C9A0;
    mesh(g, cyl(0.3, 0.4, 1.0, 7), coat, 0, 1.1, 0);
    mesh(g, sph(0.32, 8, 6), skin, 0, 1.82, 0);
    mesh(g, cyl(0.13, 0.13, 0.7, 5), pants, -0.17, 0.38, 0);
    mesh(g, cyl(0.13, 0.13, 0.7, 5), pants, 0.17, 0.38, 0);
    mesh(g, cyl(0.09, 0.09, 0.8, 5), coat, -0.4, 1.1, 0, { rz: 0.18 });
    mesh(g, cyl(0.09, 0.09, 0.8, 5), coat, 0.4, 1.1, 0, { rz: -0.18 });
    if (opts.hat) {
      mesh(g, cyl(0.48, 0.48, 0.08, 8), opts.hat, 0, 2.02, 0);
      mesh(g, cyl(0.26, 0.3, 0.3, 8), opts.hat, 0, 2.18, 0);
    } else if (opts.hair) {
      mesh(g, sph(0.33, 8, 5), opts.hair, 0, 1.9, -0.04);
      if (opts.bun) mesh(g, sph(0.16, 6, 4), opts.hair, 0, 2.06, -0.3);
    }
    if (opts.apron) {
      mesh(g, box(0.5, 0.7, 0.06), opts.apron, 0, 1.0, 0.34);
    }
    g.scale.setScalar(opts.scale || 1);
    return g;
  }

  function makeFarmer() {
    var g = makePerson({ coat: 0x6FA8DC, pants: 0x4A6B8A, hat: C.wheat, skin: 0xE8B98A });
    g.userData.idle = { kind: 'walk', phase: 0.6, body: g };
    return g;
  }

  // 推着独轮车运粮的农夫：独轮车挂在一个以轮轴为支点的组里，方便倒粮时整车前倾。
  // 默认隐藏，farm-scene.js 的运粮小剧场开始后放到谷仓门口并显示。
  function makeGrainFarmer() {
    var g = makePerson({ coat: 0x6FA8DC, pants: 0x4A6B8A, hat: C.wheat, skin: 0xE8B98A });
    var pivot = new THREE.Group();
    pivot.position.set(0, 0.28, 1.60);   // 轮轴位置（独轮车中心在农夫身前 1.05m，轮子在车前 0.55m）
    var barrow = makeWheelbarrow(true);
    barrow.position.set(0, -0.28, -0.55);
    pivot.add(barrow);
    g.add(pivot);
    g.userData.barrowPivot = pivot;
    g.userData.barrow = barrow;
    return g;
  }

  function makeChild() {
    var g = makePerson({ coat: 0xE7A24B, pants: 0x5E8FB8, hair: 0x4A3426, scale: 0.74 });
    g.userData.idle = { kind: 'walk', phase: 1.9, body: g };
    return g;
  }

  function makeGrandma() {
    var g = makePerson({ coat: 0x8FC7B0, pants: 0x6E9E8A, hair: 0xD8D2C4, bun: true, apron: 0xFFFDF6, skin: 0xE8B98A });
    g.userData.idle = { kind: 'grandma', phase: 2.2, body: g };
    return g;
  }

  // 谷仓旁的胡萝卜小菜园：翻松的土床 + 两道土垄 + 三面小木栅栏 + 8 棵胡萝卜。
  // 正向（局部 +z）留空不设栅栏，方便兔子跑进来啃萝卜；胡萝卜单独成组，便于被吃掉后缩小隐藏、过一会儿再长回来。
  function makeCarrotGarden() {
    var g = new THREE.Group();
    var bedW = 3.4;
    var bedD = 2.3;
    var halfW = bedW / 2 + 0.22;
    var halfD = bedD / 2 + 0.22;

    // 土床 + 两道隆起的土垄
    mesh(g, box(bedW, 0.16, bedD), 0xA8794F, 0, 0.08, 0);
    mesh(g, box(bedW - 0.3, 0.12, 0.56), 0xB4895E, 0, 0.22, -0.5);
    mesh(g, box(bedW - 0.3, 0.12, 0.56), 0xB4895E, 0, 0.22, 0.5);

    // 三面小木栅栏：后侧一整道、左右两侧各半道，正面敞开
    var postGeo = box(0.09, 0.5, 0.09);
    for (var px = -2; px <= 2; px++) {
      mesh(g, postGeo, C.wood, px * (halfW / 2), 0.25, -halfD);
    }
    for (var sz = -1; sz <= 1; sz++) {
      mesh(g, postGeo, C.wood, -halfW, 0.25, sz * 0.62 * halfD);
      mesh(g, postGeo, C.wood, halfW, 0.25, sz * 0.62 * halfD);
    }
    mesh(g, box(halfW * 2, 0.07, 0.06), C.woodDark, 0, 0.33, -halfD);
    mesh(g, box(halfW * 2, 0.07, 0.06), C.woodDark, 0, 0.44, -halfD);
    for (var rs = -1; rs <= 1; rs += 2) {
      mesh(g, box(0.06, 0.07, halfD * 1.45), C.woodDark, rs * halfW, 0.33, -0.26 * halfD);
      mesh(g, box(0.06, 0.07, halfD * 1.45), C.woodDark, rs * halfW, 0.44, -0.26 * halfD);
    }

    // 胡萝卜：2 行 × 4 列，每棵一个 Group
    var carrots = [];
    var cols = [-1.15, -0.38, 0.38, 1.15];
    var rows = [-0.5, 0.5];
    var grnd = makeRng(6613);
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < cols.length; c++) {
        var plant = new THREE.Group();
        plant.position.set(cols[c] + (grnd() - 0.5) * 0.14, 0.28, rows[r] + (grnd() - 0.5) * 0.12);
        plant.rotation.y = grnd() * Math.PI * 2;
        g.add(plant);
        // 露出土面的橙色萝卜肩（锥尖朝下埋进土里）
        mesh(plant, cone(0.15, 0.26, 6), C.orange, 0, 0.06, 0, { rx: Math.PI });
        // 6 片窄叶向外斜张（叶尖朝外，不用竖直的"小树"造型）
        for (var lf = 0; lf < 6; lf++) {
          var a = (lf / 6) * Math.PI * 2 + 0.35;
          mesh(plant, cone(0.045, 0.3, 4), lf % 2 ? C.leaf : C.leafDark,
            Math.cos(a) * 0.07, 0.15, Math.sin(a) * 0.07,
            { rx: Math.sin(a) * 0.6, rz: -Math.cos(a) * 0.6 });
        }
        carrots.push({ group: plant });
      }
    }
    return { group: g, carrots: carrots };
  }

  function buildAll(scene) {
    var root = new THREE.Group();
    scene.add(root);

    var objectsMap = {};
    var labelList = [];

    function register(id, obj, labelOffset, opts) {
      opts = opts || {};
      obj.userData.wordId = id;
      if (!objectsMap[id]) {
        objectsMap[id] = { root: obj, instanced: !!opts.instanced };
        labelList.push({ id: id, root: obj, offset: labelOffset || 2, anchor: opts.anchor || null });
      }
    }

    function placeFromLayout(id, obj) {
      var L = D.layout[id];
      if (L) {
        obj.position.x = L.x || 0;
        obj.position.z = L.z || 0;
        obj.rotation.y = L.ry || 0;
      }
      return obj;
    }

    var ground = new THREE.Mesh(new THREE.PlaneGeometry(140, 110), material(C.grass));
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    root.add(ground);

    var patches = [
      { x: -26, z: 30, r: 18, c: C.sage },
      { x: 30, z: -30, r: 16, c: C.sage },
      { x: 42, z: 34, r: 12, c: 0x9CC77C },
      { x: 0, z: 0, r: 14, c: 0x9CC77C }
    ];
    for (var pi = 0; pi < patches.length; pi++) {
      var patch = new THREE.Mesh(new THREE.CircleGeometry(patches[pi].r, 18), material(patches[pi].c));
      patch.rotation.x = -Math.PI / 2;
      patch.position.set(patches[pi].x, 0.01, patches[pi].z);
      patch.receiveShadow = true;
      root.add(patch);
    }

    var ring = new THREE.Mesh(new THREE.RingGeometry(0.84, 1, 64), material(C.soil));
    ring.rotation.x = -Math.PI / 2;
    ring.scale.set(27, 20, 1);
    ring.position.y = 0.03;
    ring.receiveShadow = true;
    root.add(ring);

    function spur(x1, z1, x2, z2) {
      var dx = x2 - x1, dz = z2 - z1;
      var len = Math.sqrt(dx * dx + dz * dz);
      var m = new THREE.Mesh(new THREE.BoxGeometry(4.6, 0.05, len), material(C.soil));
      m.position.set((x1 + x2) / 2, 0.025, (z1 + z2) / 2);
      m.rotation.y = Math.atan2(dx, dz);
      m.receiveShadow = true;
      root.add(m);
    }
    spur(-19, -14, -34, -24);
    spur(19, -14, 34, -24);
    spur(-19, 14, -30, 24);
    spur(19, 14, 34, 26);
    spur(-66, -8, -26, -8);

    var barn = placeFromLayout('barn', makeBarn());
    root.add(barn);
    register('barn', barn, 11);

    var farmhouse = placeFromLayout('farmhouse', makeFarmhouse());
    root.add(farmhouse);
    register('farmhouse', farmhouse, 9.5);

    var silo = placeFromLayout('silo', makeSilo());
    root.add(silo);
    register('silo', silo, 13.5);

    var windmill = placeFromLayout('windmill', makeWindmill());
    root.add(windmill);
    register('windmill', windmill, 14.5);

    var well = placeFromLayout('well', makeWell());
    root.add(well);
    register('well', well, 4.6);

    var coop = placeFromLayout('chicken_coop', makeCoop());
    root.add(coop);
    register('chicken_coop', coop, 4.2);

    var stable = placeFromLayout('stable', makeStable());
    root.add(stable);
    register('stable', stable, 6.6);

    var greenhouse = placeFromLayout('greenhouse', makeGreenhouse());
    root.add(greenhouse);
    register('greenhouse', greenhouse, 6.4);

    var gate = placeFromLayout('gate', makeGate());
    root.add(gate);
    register('gate', gate, 3.6);

    var shed = makeToolShed();
    shed.position.set(-58, 0, -26);
    shed.rotation.y = 0.2;
    root.add(shed);

    var barnTrees = new THREE.Group();

    var treeSpots = [
      { x: -62, z: 20, s: 1.25 },
      { x: -8, z: 38, s: 1.05 },
      { x: -18, z: -46, s: 0.95 },
      { x: 62, z: -46, s: 1.0 },
      { x: 60, z: 46, s: 1.1 },
      { x: 4, z: -46, s: 0.9 }
    ];
    for (var ti = 0; ti < treeSpots.length; ti++) {
      var tree = makeTree(treeSpots[ti].s);
      tree.position.set(treeSpots[ti].x, 0, treeSpots[ti].z);
      root.add(tree);
      register('tree', tree, 6.4 * treeSpots[ti].s);
    }

    var hill = makeHill(11, 6);
    hill.position.set(D.layout.hill.x, 0, D.layout.hill.z);
    root.add(hill);
    register('hill', hill, 7.2);

    var hill2 = makeHill(7, 3.4);
    hill2.position.set(-20, 0, 42);
    root.add(hill2);

    var pondGroup = placeFromLayout('pond', makePond());
    root.add(pondGroup);
    register('pond', pondGroup, 2.6);

    var bridge = makeBridge();
    bridge.position.set(38, 0, 15.5);
    root.add(bridge);

    var grassGroup = new THREE.Group();
    grassGroup.position.set(0, 0, 0);
    root.add(grassGroup);
    var tuftGeo = cone(0.22, 0.7, 4);
    var tuftMat = material(C.grassDark);
    var tuftMat2 = material(C.leaf);
    var tuftsA = new THREE.InstancedMesh(tuftGeo, tuftMat, 70);
    var tuftsB = new THREE.InstancedMesh(tuftGeo, tuftMat2, 70);
    tuftsA.castShadow = false;
    tuftsB.castShadow = false;
    tuftsA.frustumCulled = false;
    tuftsB.frustumCulled = false;
    var tuftDummy = new THREE.Object3D();
    var tuftRnd = makeRng(4021);
    for (var gi = 0; gi < 70; gi++) {
      var ga = tuftRnd() * Math.PI * 2;
      var gr = 2 + tuftRnd() * 7;
      var gx = Math.cos(ga) * gr;
      var gz = Math.sin(ga) * gr;
      var gs = 0.6 + tuftRnd() * 0.8;
      tuftDummy.position.set(gx, 0.35 * gs, gz);
      tuftDummy.rotation.set(0, tuftRnd() * Math.PI, 0);
      tuftDummy.scale.set(gs, gs, gs);
      tuftDummy.updateMatrix();
      tuftsA.setMatrixAt(gi, tuftDummy.matrix);
      tuftDummy.position.set(gx + 0.5, 0.3 * gs, gz - 0.4);
      tuftDummy.updateMatrix();
      tuftsB.setMatrixAt(gi, tuftDummy.matrix);
    }
    tuftsA.instanceMatrix.needsUpdate = true;
    tuftsB.instanceMatrix.needsUpdate = true;
    grassGroup.add(tuftsA);
    grassGroup.add(tuftsB);
    register('grass', grassGroup, 1.4, { anchor: new THREE.Vector3(0, 1.2, 0), instanced: true });

    function scatterField(id, parts, count, cx, cz, sx, sz, seed, opts) {
      opts = opts || {};
      var group = new THREE.Group();
      group.position.set(cx, 0, cz);
      root.add(group);
      var rnd = makeRng(seed);
      var meshes = [];
      for (var p = 0; p < parts.length; p++) {
        var im = new THREE.InstancedMesh(parts[p].geo, material(parts[p].color), count);
        im.castShadow = false;
        im.receiveShadow = false;
        im.frustumCulled = false;
        group.add(im);
        meshes.push(im);
      }
      var dummy = new THREE.Object3D();
      for (var i = 0; i < count; i++) {
        var x = (rnd() - 0.5) * sx;
        var z = (rnd() - 0.5) * sz;
        var ry = rnd() * Math.PI * 2;
        var sc = 0.82 + rnd() * 0.38;
        for (var q = 0; q < parts.length; q++) {
          var part = parts[q];
          dummy.position.set(x + (part.ox || 0) * sc, part.y || 0, z + (part.oz || 0) * sc);
          dummy.rotation.set(0, ry, part.tilt || 0);
          dummy.scale.set(sc * (part.sx || 1), sc * (part.sy || 1), sc * (part.sz || 1));
          dummy.updateMatrix();
          meshes[q].setMatrixAt(i, dummy.matrix);
        }
      }
      for (var k = 0; k < meshes.length; k++) meshes[k].instanceMatrix.needsUpdate = true;
      register(id, group, opts.label || 2.2, { instanced: true, anchor: new THREE.Vector3(cx, opts.label || 2.2, cz) });
      if (opts.sway) swayers.push({ obj: group, phase: (seed % 100) / 16, amp: opts.sway });
      return group;
    }

    var swayers = [];

    scatterField('wheat', [{ geo: cone(0.16, 1.7, 4), color: C.wheat, y: 0.85 }], 150, 44, -22, 15, 9, 911);
    scatterField('corn', [
      { geo: cyl(0.1, 0.14, 1.9, 5), color: C.leafDark, y: 0.95 },
      { geo: cyl(0.15, 0.15, 0.55, 5), color: C.wheat, y: 1.25, ox: 0.1 }
    ], 56, 27, -24, 8, 7, 917, { sway: 0.012 });
    scatterField('potato', [{ geo: sph(0.38, 6, 4), color: C.leaf, y: 0.34, sy: 0.8 }], 30, 54, -34, 8, 6, 923);
    scatterField('carrot', [
      { geo: cone(0.22, 0.6, 4), color: C.leaf, y: 0.35 },
      { geo: cone(0.14, 0.4, 4), color: C.orange, y: 0.1, ox: 0.05 }
    ], 28, 54, -16, 8, 5, 929);
    scatterField('tomato', [
      { geo: sph(0.36, 6, 4), color: C.leaf, y: 0.4, sy: 0.85 },
      { geo: sph(0.14, 6, 4), color: C.red, y: 0.52, ox: 0.18, oz: 0.1 }
    ], 24, 58, -28, 7, 6, 937);
    scatterField('pumpkin', [
      { geo: sph(0.55, 7, 5), color: C.orange, y: 0.42, sy: 0.78 },
      { geo: cyl(0.06, 0.06, 0.28, 5), color: C.leafDark, y: 0.8 }
    ], 8, 46, -42, 6, 3, 941);
    scatterField('sunflower', [
      { geo: cyl(0.07, 0.1, 2.0, 5), color: C.leafDark, y: 1.0 },
      { geo: sph(0.42, 8, 5), color: C.yellow, y: 2.05, sy: 0.5 },
      { geo: sph(0.2, 6, 4), color: 0x7A5230, y: 2.1, oz: 0.16, sx: 1.1, sy: 0.4 }
    ], 16, 32, -16, 7, 4, 947, { sway: 0.02, label: 3.1 });
    scatterField('strawberry', [
      { geo: sph(0.3, 6, 4), color: C.leaf, y: 0.24, sy: 0.55 },
      { geo: sph(0.13, 6, 4), color: C.red, y: 0.24, ox: 0.16, oz: 0.08 }
    ], 40, 24, 40, 9, 6, 953);
    scatterField('flower', [
      { geo: cyl(0.04, 0.04, 0.5, 4), color: C.leafDark, y: 0.25 },
      { geo: sph(0.15, 6, 4), color: C.pink, y: 0.55 }
    ], 30, 26, 16, 8, 5, 959);
    scatterField('flower', [
      { geo: cyl(0.04, 0.04, 0.5, 4), color: C.leafDark, y: 0.25 },
      { geo: sph(0.15, 6, 4), color: C.purple, y: 0.55 }
    ], 24, 52, 36, 7, 5, 967);

    var hayGroup = placeFromLayout('hay', makeHay());
    root.add(hayGroup);
    register('hay', hayGroup, 2.4);

    var appleSpots = [
      { x: 20, z: 12 }, { x: 28, z: 10 }, { x: 48, z: 12 }, { x: 58, z: 18 },
      { x: 58, z: 36 }, { x: 48, z: 43 }, { x: 34, z: 43 }, { x: 20, z: 30 }
    ];
    for (var ai = 0; ai < appleSpots.length; ai++) {
      var at = makeAppleTree();
      at.position.set(appleSpots[ai].x, 0, appleSpots[ai].z);
      at.rotation.y = ai * 1.3;
      root.add(at);
      register('apple', at, 6.4);
    }

    var plow = placeFromLayout('plow', makePlow());
    root.add(plow);
    register('plow', plow, 1.8);

    var harvester = placeFromLayout('harvester', makeHarvester());
    root.add(harvester);
    register('harvester', harvester, 3.6);

    var wheelbarrow = placeFromLayout('wheelbarrow', makeWheelbarrow());
    root.add(wheelbarrow);
    register('wheelbarrow', wheelbarrow, 1.6);

    var wateringCan = placeFromLayout('watering_can', makeWateringCan());
    root.add(wateringCan);
    register('watering_can', wateringCan, 1.4);

    var shovel = placeFromLayout('shovel', makeShovel());
    root.add(shovel);
    register('shovel', shovel, 1.6);

    var pitchfork = placeFromLayout('pitchfork', makePitchfork());
    root.add(pitchfork);
    register('pitchfork', pitchfork, 2.0);

    var cow = placeFromLayout('cow', makeCow());
    root.add(cow);
    register('cow', cow, 2.8);

    var pig = placeFromLayout('pig', makePig());
    root.add(pig);
    register('pig', pig, 1.8);

    var sheep = placeFromLayout('sheep', makeSheep());
    root.add(sheep);
    register('sheep', sheep, 2.2);

    var horse = placeFromLayout('horse', makeHorse());
    root.add(horse);
    register('horse', horse, 3.6);

    var goat = placeFromLayout('goat', makeGoat());
    root.add(goat);
    register('goat', goat, 2.1);

    // 牧场动物群：同种动物的多个实例共享一个 wordId —— 点任意一只都打开同一张单词卡；
    // 这里只设 userData.wordId（不调 register，避免重复标签），拾取与 idle 动画按实例各自生效。
    var pastureHerd = [
      { id: 'cow', make: makeCow, x: -23, z: 21, ry: 2.0, s: 1.0 },
      { id: 'cow', make: makeCow, x: -33, z: 11.5, ry: -2.2, s: 0.58 },
      { id: 'sheep', make: makeSheep, x: -36.5, z: 28.5, ry: 0.6, s: 1.0 },
      { id: 'sheep', make: makeSheep, x: -31, z: 32.5, ry: 2.4, s: 0.9 },
      { id: 'sheep', make: makeSheep, x: -45, z: 18.5, ry: -1.3, s: 1.05 },
      { id: 'sheep', make: makeSheep, x: -39, z: 15, ry: 3.1, s: 0.76 },
      { id: 'horse', make: makeHorse, x: -12, z: 32, ry: 2.7, s: 0.7 },
      { id: 'goat', make: makeGoat, x: -60, z: 9.5, ry: 1.4, s: 0.95 },
      { id: 'goat', make: makeGoat, x: -50, z: 9, ry: -2.1, s: 1.0 }
    ];
    for (var hi = 0; hi < pastureHerd.length; hi++) {
      var herd = pastureHerd[hi];
      var herdAnimal = herd.make();
      herdAnimal.position.set(herd.x, 0, herd.z);
      herdAnimal.rotation.y = herd.ry;
      herdAnimal.scale.setScalar(herd.s);
      herdAnimal.userData.wordId = herd.id;
      root.add(herdAnimal);
    }

    // 牧场里的两个小活宝：树荫下打盹的慵懒小猫 + 围着羊群蹦蹦跳跳的小兔子
    var lazyCat = makeLazyCat();
    lazyCat.position.set(-59.5, 0, 17.5);
    lazyCat.rotation.y = 2.4;
    lazyCat.userData.wordId = 'cat';
    root.add(lazyCat);

    var hopRabbit = makeHopRabbit();
    hopRabbit.position.set(-28.5, 0, 29);
    hopRabbit.rotation.y = -0.9;
    hopRabbit.scale.setScalar(0.92);
    hopRabbit.userData.wordId = 'rabbit';
    root.add(hopRabbit);

    var chicken = placeFromLayout('chicken', makeChicken(false));
    root.add(chicken);
    register('chicken', chicken, 1.3);

    var rooster = placeFromLayout('rooster', makeChicken(true));
    root.add(rooster);
    register('rooster', rooster, 1.4);

    var rabbit = placeFromLayout('rabbit', makeRabbit());
    root.add(rabbit);
    register('rabbit', rabbit, 1.7);

    // 谷仓前的胡萝卜小菜园：位置在兔子家门口西侧，敞口朝向兔子（farm-scene.js 里的兔子会定时跑过来啃一根）
    var carrotGarden = makeCarrotGarden();
    carrotGarden.group.position.set(-38.6, 0, -15.6);
    carrotGarden.group.rotation.y = Math.atan2(rabbit.position.x - carrotGarden.group.position.x,
      rabbit.position.z - carrotGarden.group.position.z);
    carrotGarden.group.userData.wordId = 'carrot';
    root.add(carrotGarden.group);

    var cat = placeFromLayout('cat', makeCat());
    root.add(cat);
    register('cat', cat, 1.45);

    var grandma = placeFromLayout('grandma', makeGrandma());
    root.add(grandma);
    register('grandma', grandma, 2.3);

    var duck = makeDuck(false);
    duck.position.set(D.layout.duck.x, 0.16, D.layout.duck.z);
    duck.rotation.y = D.layout.duck.ry;
    root.add(duck);
    register('duck', duck, 1.1);

    var goose = makeDuck(true);
    goose.position.set(D.layout.goose.x, 0.16, D.layout.goose.z);
    goose.rotation.y = D.layout.goose.ry;
    root.add(goose);
    register('goose', goose, 1.5);

    var bee = makeBee();
    bee.position.set(D.layout.bee.x, 2.6, D.layout.bee.z);
    root.add(bee);
    register('bee', bee, 0.8);

    var bird = makeBird();
    bird.position.set(D.layout.bird.x, 4.6, D.layout.bird.z);
    root.add(bird);
    register('bird', bird, 0.6);

    var tractor = makeTractor();
    root.add(tractor);
    register('tractor', tractor, 3.2);

    var trailer = makeTrailer();
    root.add(trailer);
    register('trailer', trailer, 2.4);

    var farmer = makeFarmer();
    root.add(farmer);
    register('farmer', farmer, 2.4);

    // 谷仓运粮专用农夫（不进单词表，也不参与路上的散步）
    var grainFarmer = makeGrainFarmer();
    grainFarmer.visible = false;
    root.add(grainFarmer);

    var child = makeChild();
    root.add(child);
    register('child', child, 2.1);

    var dog = makeDog();
    root.add(dog);
    register('dog', dog, 1.55);

    var fence = buildFence(root);
    register('fence', fence.posts, 2.2, { anchor: new THREE.Vector3(0, 2.2, -52), instanced: true });
    register('fence', fence.rails, 2.2, { anchor: new THREE.Vector3(0, 2.2, -52), instanced: true });

    var beehiveGroup = new THREE.Group();
    beehiveGroup.position.set(44, 0, -12);
    for (var bi = 0; bi < 3; bi++) {
      mesh(beehiveGroup, box(1.0, 1.1, 1.0), C.wheat, bi * 1.4 - 1.4, 0.55, 0);
      mesh(beehiveGroup, box(1.1, 0.12, 1.1), C.woodDark, bi * 1.4 - 1.4, 1.12, 0);
    }
    root.add(beehiveGroup);

    var lampSpots = [
      { x: 0, z: 21 }, { x: 0, z: -21 }, { x: 27, z: 0 }, { x: -27, z: 0 }
    ];
    for (var li = 0; li < lampSpots.length; li++) {
      var lamp = makeLamp();
      lamp.position.set(lampSpots[li].x, 0, lampSpots[li].z);
      lamp.rotation.y = Math.atan2(-lampSpots[li].x, -lampSpots[li].z);
      root.add(lamp);
    }

    var clouds = [];
    for (var ci = 0; ci < 7; ci++) {
      var cloud = makeCloud(0.8 + (ci % 3) * 0.3);
      cloud.position.set(-80 + ci * 26, 42 + (ci % 3) * 6, -50 + (ci % 4) * 30);
      root.add(cloud);
      clouds.push({ obj: cloud, speed: 0.35 + (ci % 3) * 0.12, baseZ: cloud.position.z });
    }

    var fireflyGroup = new THREE.Group();
    var fireflyMat = new THREE.MeshBasicMaterial({ color: 0xFFD782, transparent: true, opacity: 0 });
    var fireflyList = [];
    var fRnd = makeRng(7771);
    for (var fi = 0; fi < 26; fi++) {
      var fly = new THREE.Mesh(new THREE.SphereGeometry(0.16, 5, 4), fireflyMat);
      var fx = (fRnd() - 0.5) * 60;
      var fz = (fRnd() - 0.5) * 44;
      fly.position.set(fx, 1.2 + fRnd() * 3.2, fz);
      fireflyGroup.add(fly);
      fireflyList.push({ obj: fly, baseY: fly.position.y, phase: fRnd() * 6.28, x0: fx, z0: fz, r: 1.2 + fRnd() * 2 });
    }
    root.add(fireflyGroup);

    var idles = [];
    root.traverse(function (o) {
      if (o.userData && o.userData.idle) idles.push({ root: o, cfg: o.userData.idle });
    });

    root.traverse(function (o) {
      if (o.isMesh && !o.isInstancedMesh) {
        if (o.geometry && !o.geometry.boundingSphere) o.geometry.computeBoundingSphere();
        var rr = o.geometry && o.geometry.boundingSphere ? o.geometry.boundingSphere.radius : 0;
        if (rr < 1.3) o.castShadow = false;
      }
    });

    var actors = [
      { id: 'tractor', obj: tractor, angle: 0.45, speed: 0.052 },
      { id: 'trailer', obj: trailer, angle: 0.30, speed: 0.052 },
      { id: 'farmer', obj: farmer, angle: 2.20, speed: 0.085 },
      { id: 'child', obj: child, angle: 2.34, speed: 0.085 },
      { id: 'dog', obj: dog, angle: 2.50, speed: 0.10 }
    ];

    return {
      root: root,
      objects: objectsMap,
      labels: labelList,
      swayers: swayers,
      idles: idles,
      actors: actors,
      clouds: clouds,
      bee: bee,
      fireflyGroup: fireflyGroup,
      fireflyMat: fireflyMat,
      fireflies: fireflyList,
      pondWater: pondGroup.userData.water,
      windowMats: windowMats,
      lampMats: lampMats,
      carrotGarden: carrotGarden,
      grainFarmer: grainFarmer
    };
  }

  function buildFence(root) {
    var postGeo = new THREE.BoxGeometry(0.16, 1.35, 0.16);
    var railGeo = new THREE.BoxGeometry(1, 0.14, 0.12);
    var postList = [];
    var railList = [];

    function edge(x1, z1, x2, z2, skipGate) {
      var len = Math.sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1));
      var steps = Math.max(1, Math.round(len / 3.4));
      var prev = null;
      for (var i = 0; i <= steps; i++) {
        var t = i / steps;
        var x = x1 + (x2 - x1) * t;
        var z = z1 + (z2 - z1) * t;
        if (skipGate && Math.abs(z + 8) < 4.2) { prev = null; continue; }
        postList.push([x, z]);
        if (prev) {
          var mx = (x + prev[0]) / 2;
          var mz = (z + prev[1]) / 2;
          var dx = x - prev[0];
          var dz = z - prev[1];
          var d = Math.sqrt(dx * dx + dz * dz);
          railList.push([mx, mz, d, Math.atan2(-dz, dx)]);
        }
        prev = [x, z];
      }
    }

    edge(-68, -52, 68, -52, false);
    edge(-68, 52, 68, 52, false);
    edge(-68, -52, -68, 52, true);
    edge(68, -52, 68, 52, false);

    var posts = new THREE.InstancedMesh(postGeo, material(C.woodDark), postList.length);
    var rails = new THREE.InstancedMesh(railGeo, material(C.wood), railList.length * 2);
    posts.castShadow = true;
    posts.receiveShadow = true;
    rails.castShadow = true;
    rails.receiveShadow = true;
    posts.frustumCulled = false;
    rails.frustumCulled = false;
    posts.userData.wordId = 'fence';
    rails.userData.wordId = 'fence';
    var dummy = new THREE.Object3D();
    for (var i = 0; i < postList.length; i++) {
      dummy.position.set(postList[i][0], 0.68, postList[i][1]);
      dummy.rotation.set(0, 0, 0);
      dummy.scale.set(1, 1, 1);
      dummy.updateMatrix();
      posts.setMatrixAt(i, dummy.matrix);
    }
    for (var r = 0; r < railList.length; r++) {
      var item = railList[r];
      dummy.position.set(item[0], 0.55, item[1]);
      dummy.rotation.set(0, item[3], 0);
      dummy.scale.set(item[2], 1, 1);
      dummy.updateMatrix();
      rails.setMatrixAt(r * 2, dummy.matrix);
      dummy.position.set(item[0], 1.05, item[1]);
      dummy.updateMatrix();
      rails.setMatrixAt(r * 2 + 1, dummy.matrix);
    }
    posts.instanceMatrix.needsUpdate = true;
    rails.instanceMatrix.needsUpdate = true;
    root.add(posts);
    root.add(rails);
    return { posts: posts, rails: rails };
  }

  global.FarmModels = { buildAll: buildAll, colors: C };
})(window);
