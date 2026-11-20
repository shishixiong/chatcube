(function (global) {
  'use strict';

  var T = global.THREE;
  var doc = global.document;
  var MANIFEST = global.AirportModelManifest || [];
  var DATA = global.AirportData || { objects: [], byId: {} };

  var canvas = null;
  var renderer = null;
  var scene = null;
  var camera = null;
  var clock = null;
  var loader = null;

  var models = {};        // assetId -> THREE.Group
  var wordRoots = {};     // wordId -> THREE.Object3D (primary instance)
  var wordById = DATA.byId || {};
  var ready = false;
  var mixers = [];
  var mixerByAsset = {};
  var clipsByAsset = {};
  var moving = [];
  var rafId = 0;
  var mode = { failReason: '' };

  var raycaster = new T.Raycaster();
  var pointer = new T.Vector2();
  var tmpVec = new T.Vector3();

  var camTween = null;
  var selectedId = null;
  var selectionRing = null;
  var orbit = { target: new T.Vector3(20, 0, -45), radius: 300, theta: 0.8, phi: 0.9 };
  var pointers = {};
  var pinchDist = 0;
  var labelsOn = false;
  var labelEls = {};
  var labelLayer = null;

  var VIEWS = {
    overview: { target: [20, 0, -45], position: [190, 135, 195] },
    terminal_zone: { target: [10, 4, 12], position: [10, 34, 82] },
    apron_zone: { target: [50, 6, -52], position: [125, 30, -8] },
    runway_zone: { target: [-10, 2, -145], position: [-90, 62, -42] },
    hangar_zone: { target: [-165, 5, -12], position: [-55, 44, 72] }
  };

  function $(id) { return doc.getElementById(id); }

  function base64ToArrayBuffer(b64) {
    var bin = global.atob(b64);
    var len = bin.length;
    var bytes = new Uint8Array(len);
    for (var i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
    return bytes.buffer;
  }

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var s = doc.createElement('script');
      s.src = src;
      s.async = true;
      s.onload = function () { resolve(); };
      s.onerror = function () { reject(new Error('script ' + src)); };
      doc.head.appendChild(s);
    });
  }

  function createMaterial(skinned) {
    var mat = new T.MeshPhongMaterial({
      vertexColors: true,
      flatShading: true,
      shininess: 0,
      specular: 0x000000,
      side: T.FrontSide
    });
    if (skinned) mat.skinning = true;
    return mat;
  }

  function patchMaterial(mesh, mat) {
    mesh.material = mat;
    mesh.frustumCulled = true;
    mesh.castShadow = false;
    mesh.receiveShadow = false;
  }

  /** Collapse a static model's sub-meshes into one draw call. */
  function mergeStaticMeshes(root, mat) {
    root.updateMatrixWorld(true);
    var meshes = [];
    root.traverse(function (n) { if (n.isMesh && !n.isSkinnedMesh) meshes.push(n); });
    if (meshes.length < 2) return;

    var totalV = 0;
    var totalI = 0;
    var i;
    for (i = 0; i < meshes.length; i++) {
      var g0 = meshes[i].geometry;
      if (!g0 || !g0.attributes.position || !g0.attributes.color) return;
      totalV += g0.attributes.position.count;
      totalI += g0.index ? g0.index.count : g0.attributes.position.count;
    }

    var P = new Float32Array(totalV * 3);
    var C = new Float32Array(totalV * 3);
    var I = new Uint32Array(totalI);
    var vOff = 0;
    var iOff = 0;
    var v = new T.Vector3();
    for (i = 0; i < meshes.length; i++) {
      var mesh = meshes[i];
      var geo = mesh.geometry;
      var pos = geo.attributes.position;
      var col = geo.attributes.color;
      var m = mesh.matrixWorld;
      for (var k = 0; k < pos.count; k++) {
        v.set(pos.getX(k), pos.getY(k), pos.getZ(k)).applyMatrix4(m);
        P[(vOff + k) * 3] = v.x;
        P[(vOff + k) * 3 + 1] = v.y;
        P[(vOff + k) * 3 + 2] = v.z;
        C[(vOff + k) * 3] = col.getX(k);
        C[(vOff + k) * 3 + 1] = col.getY(k);
        C[(vOff + k) * 3 + 2] = col.getZ(k);
      }
      if (geo.index) {
        var idx = geo.index;
        for (var j = 0; j < idx.count; j++) I[iOff + j] = idx.getX(j) + vOff;
        iOff += idx.count;
      } else {
        for (var q = 0; q < pos.count; q++) I[iOff + q] = q + vOff;
        iOff += pos.count;
      }
      vOff += pos.count;
    }

    var merged = new T.BufferGeometry();
    merged.setAttribute('position', new T.BufferAttribute(P, 3));
    merged.setAttribute('color', new T.BufferAttribute(C, 3));
    merged.setIndex(new T.BufferAttribute(I, 1));
    merged.computeBoundingSphere();

    for (i = 0; i < meshes.length; i++) {
      var parent = meshes[i].parent;
      if (parent) parent.remove(meshes[i]);
    }
    var single = new T.Mesh(merged, mat);
    single.userData.merged = true;
    root.add(single);
  }

  function tagWord(root, wordId) {
    if (!wordId) return;
    root.userData.wordId = wordId;
    root.traverse(function (node) {
      node.userData.wordId = wordId;
    });
    if (!wordRoots[wordId]) wordRoots[wordId] = root;
  }

  function prepare(gltf, entry) {
    var root = gltf.scene;
    root.name = entry.id;
    root.updateMatrixWorld(true);
    var hasSkin = false;
    root.traverse(function (node) { if (node.isSkinnedMesh) hasSkin = true; });
    var mat = createMaterial(hasSkin);
    root.traverse(function (node) {
      if (node.isMesh) patchMaterial(node, mat);
    });
    if (!hasSkin && (!gltf.animations || gltf.animations.length === 0)) {
      mergeStaticMeshes(root, mat);
    }
    if (entry.wordId) tagWord(root, entry.wordId);
    if (gltf.animations && gltf.animations.length > 0) {
      var mixer = new T.AnimationMixer(root);
      var clip = T.AnimationClip.findByName(gltf.animations, 'Idle') || gltf.animations[0];
      if (clip) mixer.clipAction(clip).play();
      mixers.push({ mixer: mixer, root: root });
      mixerByAsset[entry.id] = mixer;
      clipsByAsset[entry.id] = gltf.animations;
      root.userData.hasAnim = true;
    }
    models[entry.id] = root;
    return root;
  }

  function loadAll(onProgress, onReady, onError) {
    var total = MANIFEST.length;
    var done = 0;
    var failed = [];
    var queue = MANIFEST.slice();
    var active = 0;
    var CONCURRENCY = 6;

    if (total === 0) { onError('manifest-empty'); return; }

    function finish(e, err) {
      done += 1;
      onProgress(done, total);
      if (err) failed.push(e.id + ': ' + err);
      if (done >= total) {
        ready = true;
        if (failed.length > 0) {
          mode.failReason = failed.join('; ');
          console.error('AirportScene load failures: ' + mode.failReason);
          onError(mode.failReason);
        } else {
          onReady();
        }
      } else {
        pump();
      }
    }

    var FAILTEST = /[?&]failtest=1/.test(global.location.search);

    function parseOne(entry, cb) {
      if (FAILTEST && entry.id === MANIFEST[0].id) {
        cb('failtest: injected parse failure');
        return;
      }
      try {
        loader.parse(
          base64ToArrayBuffer(global.AIRPORT_MODELS[entry.id]),
          '',
          function (gltf) { prepare(gltf, entry); cb(null); },
          function (err) { cb(err && err.message ? err.message : String(err)); }
        );
      } catch (e) {
        cb(e.message);
      }
    }

    function pump() {
      while (active < CONCURRENCY && queue.length > 0) {
        (function (entry) {
          active += 1;
          loadScript(entry.file).then(function () {
            active -= 1;
            if (!global.AIRPORT_MODELS || !global.AIRPORT_MODELS[entry.id]) {
              finish(entry, 'missing base64 data');
              return;
            }
            parseOne(entry, function (err) { finish(entry, err); });
          }, function () {
            active -= 1;
            finish(entry, 'script load failed');
          });
        })(queue.shift());
      }
    }

    pump();
  }

  // ---------------- world helpers ----------------

  function groundPlane(w, d, x, z, y, color) {
    var geo = new T.PlaneGeometry(w, d);
    var mat = new T.MeshLambertMaterial({ color: color });
    var mesh = new T.Mesh(geo, mat);
    mesh.rotation.x = -Math.PI / 2;
    mesh.position.set(x, y, z);
    scene.add(mesh);
    return mesh;
  }

  function box(w, h, d, x, y, z, color, opacity) {
    var geo = new T.BoxGeometry(w, h, d);
    var mat = new T.MeshLambertMaterial({ color: color, transparent: !!opacity, opacity: opacity || 1 });
    var mesh = new T.Mesh(geo, mat);
    mesh.position.set(x, y, z);
    scene.add(mesh);
    return mesh;
  }

  /** One merged mesh of flat quads: each quad = [x, z, w, d]. */
  function quadMesh(quads, y, color) {
    var verts = new Float32Array(quads.length * 4 * 3);
    var idx = new Uint32Array(quads.length * 6);
    var vo = 0;
    var io = 0;
    for (var i = 0; i < quads.length; i++) {
      var q = quads[i];
      var x0 = q[0] - q[2] / 2;
      var x1 = q[0] + q[2] / 2;
      var z0 = q[1] - q[3] / 2;
      var z1 = q[1] + q[3] / 2;
      verts[vo * 3] = x0; verts[vo * 3 + 1] = y; verts[vo * 3 + 2] = z0;
      verts[vo * 3 + 3] = x1; verts[vo * 3 + 4] = y; verts[vo * 3 + 5] = z0;
      verts[vo * 3 + 6] = x1; verts[vo * 3 + 7] = y; verts[vo * 3 + 8] = z1;
      verts[vo * 3 + 9] = x0; verts[vo * 3 + 10] = y; verts[vo * 3 + 11] = z1;
      idx[io] = vo; idx[io + 1] = vo + 2; idx[io + 2] = vo + 1;
      idx[io + 3] = vo; idx[io + 4] = vo + 3; idx[io + 5] = vo + 2;
      vo += 4;
      io += 6;
    }
    var geo = new T.BufferGeometry();
    geo.setAttribute('position', new T.BufferAttribute(verts, 3));
    geo.setIndex(new T.BufferAttribute(idx, 1));
    var mat = new T.MeshBasicMaterial({ color: color });
    var mesh = new T.Mesh(geo, mat);
    scene.add(mesh);
    return mesh;
  }

  function addDashedLine(x0, z0, x1, z1, y, color, dash, gap, width) {
    var quads = [];
    var dx = x1 - x0;
    var dz = z1 - z0;
    var len = Math.sqrt(dx * dx + dz * dz);
    var ux = dx / len;
    var uz = dz / len;
    var step = dash + gap;
    for (var d = 0; d < len; d += step) {
      var mid = d + Math.min(dash, len - d) / 2;
      var half = Math.min(dash, len - d) / 2;
      quads.push([x0 + ux * mid, z0 + uz * mid, Math.abs(ux) * half * 2 + Math.abs(uz) * width,
        Math.abs(uz) * half * 2 + Math.abs(ux) * width]);
    }
    return quadMesh(quads, y, color);
  }

  function addModel(assetId, x, y, z, rotY, scale, wordId) {
    var root = models[assetId];
    if (!root) return null;
    root.position.set(x, y, z);
    root.rotation.y = rotY || 0;
    if (scale) root.scale.setScalar(scale);
    if (wordId) tagWord(root, wordId);
    scene.add(root);
    return root;
  }

  function place(assetId, x, y, z, rotY, scale, wordId) {
    var root = models[assetId];
    if (!root) return null;
    var obj = root.clone(true);
    obj.position.set(x, y, z);
    obj.rotation.y = rotY || 0;
    if (scale) obj.scale.setScalar(scale);
    if (wordId) tagWord(obj, wordId);
    scene.add(obj);
    return obj;
  }

  function setClip(assetId, name) {
    var mixer = mixerByAsset[assetId];
    var clips = clipsByAsset[assetId];
    if (!mixer || !clips) return;
    mixer.stopAllAction();
    var clip = T.AnimationClip.findByName(clips, name);
    if (clip) mixer.clipAction(clip).play();
  }

  // ---------------- world ----------------

  function buildWorld() {
    // Ground
    groundPlane(520, 420, 0, -40, 0, 0x8fbf6a);
    var runwayMesh = groundPlane(400, 44, 0, -160, 0.01, 0x5e6469);
    tagWord(runwayMesh, 'runway');
    var taxiwayMesh = groundPlane(400, 16, 0, -112, 0.012, 0x6c7278);
    tagWord(taxiwayMesh, 'taxiway');
    var apronMesh = groundPlane(220, 84, 45, -58, 0.013, 0x7a8084);
    tagWord(apronMesh, 'apron');
    groundPlane(300, 14, 0, 48, 0.012, 0x63696e);        // landside road
    groundPlane(104, 44, 8, 12, 0.014, 0xd9d6ce);        // terminal floor

    // Markings
    addDashedLine(-198, -160, 198, -160, 0.02, 0xffffff, 6, 6, 0.6);
    quadMesh([[-160, -182, 8, 1], [-140, -182, 8, 1], [-120, -182, 8, 1],
      [-160, -138, 8, 1], [-140, -138, 8, 1], [-120, -138, 8, 1]], 0.02, 0xffffff);
    quadMesh([[0, -112, 396, 0.5]], 0.02, 0xe5c84a);
    // apron stand lead-in lines
    quadMesh([[20, -60, 0.6, 60], [65, -58, 0.6, 60], [105, -55, 0.6, 60]], 0.02, 0xffffff);
    quadMesh([[0, -30, 180, 0.4], [-40, 48, 300, 0.4]], 0.02, 0xe5c84a);

    // Terminal: back wall of bays + open south columns
    var i;
    for (i = 0; i < 12; i++) {
      var bx = -40 + i * 8;
      if (i === 0) addModel('terminal-structure-bay-ea2467', bx, 0.05, -8, 0, 1, 'terminal');
      else place('terminal-structure-bay-ea2467', bx, 0.05, -8, 0, 1, 'terminal');
    }
    for (i = 0; i < 3; i++) {
      place('terminal-structure-bay-ea2467', -44, 0.05, 0 + i * 8, Math.PI / 2, 1, 'terminal');
      place('terminal-structure-bay-ea2467', 60, 0.05, 0 + i * 8, -Math.PI / 2, 1, 'terminal');
    }
    // Cutaway roof: covers the back half only, so the hall reads from the south.
    var roof = box(108, 1.2, 14, 8, 8.6, -1, 0xcfd3d6);
    tagWord(roof, 'terminal');
    wordRoots['terminal'] = roof;
    box(110, 0.6, 16, 8, 9.2, -1, 0x9fc4d8, 0.35);
    for (i = 0; i < 12; i++) {
      place('terminal-facade-module-5574b6', -36 + i * 8, 0.05, 24, Math.PI, 1, null);
    }
    addModel('gate-lounge-module-5ebc23', 10, 0.05, 0, 0, 1, 'gate');
    place('gate-lounge-module-5ebc23', 68, 0.05, 0, 0, 1, null);
    place('gate-seating-row-cc0ff3', 12, 0.05, 6, 0, 1, null);
    place('gate-seating-row-cc0ff3', 70, 0.05, 6, 0, 1, null);

    addModel('check-in-desk-run-b96c12', -22, 0.05, 18, 0, 1, 'check_in');
    addModel('baggage-reclaim-carousel-7ceef0', -8, 0.05, 25, 0, 1, 'baggage_carousel');
    addModel('passport-control-booth-7724c6', -2, 0.05, 4, Math.PI, 1, 'passport_control');
    addModel('x-ray-baggage-conveyor-b3d1cc', 8, 0.05, 10, 0, 1, 'x_ray');
    place('security-body-scanner-ef6fcd', 14, 0.05, 10, 0, 1, null);
    place('queue-barrier-stanchion-run-1836c8', 2, 0.05, 7, 0, 1, null);
    addModel('departures-board-7b85c8', 26, 0.05, 4, 0, 1, 'departures_board');
    addModel('overhead-wayfinding-sign-64d4e8', 44, 0.05, 4, 0, 1, 'sign');
    addModel('moving-walkway-run-9f078a', 46, 0.05, 16, Math.PI / 2, 1, 'moving_walkway');
    addModel('terminal-escalator-b80f37', 34, 0.05, 26, 0, 1, 'escalator');

    // Landside
    addModel('airport-hotel-1a1e0a', 205, 0.05, 78, 0, 1, 'airport_hotel');
    addModel('multi-storey-car-park-021465', -86, 0.05, 88, 0, 1, 'car_park');
    place('departures-kerb-canopy-run-d1ed9e', 20, 0.05, 42, 0, 1, null);
    place('taxi-rank-sign-f5f39d', 34, 0.05, 52, 0, 1, null);
    place('crew-minivan-2ed5f1', -30, 0.05, 52, Math.PI / 2, 1, null);

    // Tower + facilities
    addModel('control-tower-c95a65', 122, 0.05, -28, 0, 1, 'control_tower');
    addModel('air-traffic-radar-mast-3e5642', 136, 0.05, -86, 0, 1, 'radar');
    addModel('rotating-airport-beacon-e1ea5a', 64, 0.05, -136, 0, 1, 'beacon');
    addModel('windsock-d5df79', -84, 0.05, -138, 0, 1, 'windsock');
    addModel('papi-unit-adc7c4', -122, 0.05, -138, 0, 1, 'papi');
    addModel('apron-floodlight-mast-e0d04a', 96, 0.05, -96, 0, 1, 'floodlight');
    addModel('runway-edge-light-run-ebe7e1', -20, 0.05, -138, 0, 1, 'runway_lights');
    place('runway-edge-light-run-ebe7e1', 60, 0.05, -138, 0, 1, 'runway_lights');
    place('runway-guard-light-5a6541', 150, 0.05, -136, 0, 1, null);
    place('lit-taxiway-sign-206955', 10, 0.05, -100, 0, 1, null);

    // Hangar zone
    addModel('maintenance-hangar-6fab99', -168, 0.05, -34, 0, 1, 'hangar');
    addModel('cargo-shed-bcb2a8', -164, 0.05, 16, 0, 1, 'cargo_shed');
    addModel('airport-fire-station-92c6b7', -118, 0.05, 42, 0, 1, 'fire_station');
    addModel('fuel-farm-tank-ed67f0', -104, 0.05, -70, 0, 1, 'fuel_tank');
    addModel('regional-turboprop-097f26', -240, 0.05, -40, 0, 1, 'turboprop');
    addModel('cargo-freighter-b4377e', -215, 0.05, 10, Math.PI / 2, 1, 'cargo_plane');
    addModel('airport-crash-tender-2422ba', -108, 0.05, 26, 0, 1, 'fire_truck');
    place('cargo-forklift-91f591', -150, 0.05, 34, 0, 1, null);
    place('uld-container-a055c6', -144, 0.05, 34, 0, 1, null);

    // Apron aircraft + jet bridges
    addModel('widebody-airliner-ae0a5a', 20, 0.05, -60, 0, 1, 'airplane');
    addModel('narrow-body-airliner-619183', 65, 0.05, -58, 0, 1, 'jet');
    addModel('business-jet-684611', 105, 0.05, -55, 0, 1, 'private_jet');
    addModel('helicopter-9d1986', 142, 0.05, -12, Math.PI / 2, 1, 'helicopter');
    addModel('jet-bridge-4f39c0', 20, 0.05, -24, Math.PI / 2, 1, 'jet_bridge');
    place('jet-bridge-4f39c0', 65, 0.05, -24, Math.PI / 2, 1, null);

    // Apron vehicles
    addModel('pushback-tug-8eab46', 8, 0.05, -38, 0.3, 1, 'pushback_tug');
    addModel('baggage-tug-fb69f7', 32, 0.05, -30, 0, 1, 'baggage_tug');
    addModel('baggage-cart-b1bb82', 37, 0.05, -30, 0, 1, 'baggage_cart');
    place('baggage-cart-b1bb82', 42, 0.05, -30, 0, 1, 'baggage_cart');
    addModel('container-loader-254a74', 58, 0.05, -42, 0, 1, 'container_loader');
    addModel('belt-loader-3d84fd', 76, 0.05, -44, 0, 1, 'belt_loader');
    addModel('aviation-fuel-tanker-truck-37ed29', 10, 0.05, -76, 0, 1, 'fuel_truck');
    addModel('catering-truck-496150', 70, 0.05, -72, 0, 1, 'catering_truck');
    addModel('airstairs-truck-de0f4b', 100, 0.05, -72, 0, 1, 'airstairs_truck');
    addModel('apron-passenger-bus-c46aef', 128, 0.05, -46, 0, 1, 'airport_bus');
    addModel('follow-me-car-b3c6a5', 140, 0.05, -88, 0, 1, 'follow_me_car');
    addModel('apron-sweeper-truck-937ca0', 90, 0.05, -30, 0, 1, 'sweeper');

    // People
    addModel('airline-pilot-63226a', 26, 0.05, -36, 0, 1, 'pilot');
    addModel('flight-attendant-befaf4', 32, 0.05, -4, 0, 1, 'flight_attendant');
    addModel('traveller-92f20c', 0, 0.05, 20, Math.PI / 2, 1, 'traveller');
    setClip('traveller-92f20c', 'Walk');
    addModel('airport-security-officer-8fd38a', 6, 0.05, 12, 0, 1, 'security_officer');
    addModel('baggage-handler-0823f5', 36, 0.05, -36, 0, 1, 'baggage_handler');

    buildMotions();
    buildSelectionRing();
    buildLabels();
  }

  function buildMotions() {
    // Taxiing jet (decoration, not a word)
    var taxi = place('narrow-body-airliner-619183', -190, 0.05, -116, Math.PI / 2, 1, null);
    if (taxi) {
      var taxiDir = 1;
      moving.push(function (dt) {
        taxi.position.x += dt * 7 * taxiDir;
        if (taxi.position.x > 196) { taxiDir = -1; taxi.rotation.y = -Math.PI / 2; }
        if (taxi.position.x < -196) { taxiDir = 1; taxi.rotation.y = Math.PI / 2; }
      });
    }

    // Baggage train (word roots are static; this is an extra decoration train)
    var tug = place('baggage-tug-fb69f7', -10, 0.05, -94, Math.PI / 2, 1, null);
    var cartA = place('baggage-cart-b1bb82', -16, 0.05, -94, Math.PI / 2, 1, null);
    var cartB = place('baggage-cart-b1bb82', -22, 0.05, -94, Math.PI / 2, 1, null);
    if (tug && cartA && cartB) {
      var train = [tug, cartA, cartB];
      var tDir = 1;
      moving.push(function (dt) {
        var move = dt * 5 * tDir;
        for (var i = 0; i < train.length; i++) train[i].position.x += move;
        if (tug.position.x > 120) { tDir = -1; for (var a = 0; a < train.length; a++) train[a].rotation.y = -Math.PI / 2; }
        if (tug.position.x < -40) { tDir = 1; for (var b = 0; b < train.length; b++) train[b].rotation.y = Math.PI / 2; }
      });
    }

    // Follow-me car
    var follow = place('follow-me-car-b3c6a5', -30, 0.05, -20, Math.PI / 2, 1, null);
    if (follow) {
      var fDir = 1;
      moving.push(function (dt) {
        follow.position.x += dt * 9 * fDir;
        if (follow.position.x > 130) { fDir = -1; follow.rotation.y = -Math.PI / 2; }
        if (follow.position.x < -30) { fDir = 1; follow.rotation.y = Math.PI / 2; }
      });
    }

    // Walking traveller (a word target that moves — must stay clickable)
    var walker = wordRoots['traveller'];
    if (walker) {
      var wDir = 1;
      moving.push(function (dt) {
        walker.position.x += dt * 1.2 * wDir;
        walker.rotation.y = wDir > 0 ? Math.PI / 2 : -Math.PI / 2;
        if (walker.position.x > 46) wDir = -1;
        if (walker.position.x < -34) wDir = 1;
      });
    }
  }

  function buildSelectionRing() {
    var geo = new T.RingGeometry(2.2, 3.0, 40);
    var mat = new T.MeshBasicMaterial({ color: 0xe5c84a, transparent: true, opacity: 0.85, side: T.DoubleSide, depthWrite: false });
    selectionRing = new T.Mesh(geo, mat);
    selectionRing.rotation.x = -Math.PI / 2;
    selectionRing.visible = false;
    scene.add(selectionRing);
  }

  function buildLabels() {
    labelLayer = $('labelLayer');
    if (!labelLayer) return;
    for (var i = 0; i < DATA.objects.length; i++) {
      var o = DATA.objects[i];
      var el = doc.createElement('div');
      el.className = 'airport-label';
      el.textContent = o.word;
      el.hidden = true;
      labelLayer.appendChild(el);
      labelEls[o.id] = el;
    }
  }

  function setLabels(on) {
    labelsOn = !!on;
    if (labelLayer) labelLayer.hidden = !labelsOn;
    if (!labelsOn) {
      for (var id in labelEls) if (labelEls[id]) labelEls[id].hidden = true;
    }
  }

  function updateLabels() {
    if (!labelsOn || !labelLayer) return;
    var rect = canvas.getBoundingClientRect();
    for (var i = 0; i < DATA.objects.length; i++) {
      var o = DATA.objects[i];
      var root = wordRoots[o.id];
      var el = labelEls[o.id];
      if (!root || !el) continue;
      root.getWorldPosition(tmpVec);
      tmpVec.y += 8;
      tmpVec.project(camera);
      if (tmpVec.z > 1 || tmpVec.z < -1) { el.hidden = true; continue; }
      var x = (tmpVec.x * 0.5 + 0.5) * rect.width;
      var y = (-tmpVec.y * 0.5 + 0.5) * rect.height;
      if (x < -40 || x > rect.width + 40 || y < -20 || y > rect.height + 20) { el.hidden = true; continue; }
      el.hidden = false;
      el.style.transform = 'translate(' + x + 'px,' + y + 'px) translate(-50%,-100%)';
    }
  }

  function setView(focus) {
    var v = VIEWS[focus] || VIEWS.overview;
    var t = new T.Vector3(v.target[0], v.target[1], v.target[2]);
    var p = new T.Vector3(v.position[0], v.position[1], v.position[2]);
    var off = p.sub(t);
    if (camera.aspect < 1) off.multiplyScalar(1.7);
    tweenCamera([t.x + off.x, t.y + off.y, t.z + off.z], v.target);
  }

  function focusParams(root) {
    var box = new T.Box3().setFromObject(root);
    var center = box.getCenter(new T.Vector3());
    var size = box.getSize(new T.Vector3());
    var radius = Math.max(size.x, size.z) * 0.5;
    var dist = Math.min(170, Math.max(16, radius * 1.9));
    var height = Math.max(9, Math.min(70, radius * 1.1));
    var targetY = center.y + size.y * 0.2;
    if (camera.aspect < 1) {
      dist *= 1.45;
      height *= 1.15;
      targetY -= dist * 0.18;
    }
    return {
      target: [center.x, targetY, center.z],
      pos: [center.x + dist * 0.75, center.y + height, center.z + dist * 0.75],
      center: center
    };
  }

  function focusWord(wordId) {
    var root = wordRoots[wordId];
    if (!root) return;
    selectedId = wordId;
    var f = focusParams(root);
    tweenCamera(f.pos, f.target);
    if (selectionRing) {
      selectionRing.visible = true;
      selectionRing.position.set(f.center.x, 0.06, f.center.z);
    }
  }

  function applyCameraNow(pos, target) {
    camTween = null;
    camera.position.set(pos[0], pos[1], pos[2]);
    camera.userData.target = new T.Vector3(target[0], target[1], target[2]);
    camera.lookAt(camera.userData.target);
    syncOrbitFromCamera();
    if (renderer && scene) renderer.render(scene, camera);
  }

  function syncOrbitFromCamera() {
    var t = camera.userData.target || new T.Vector3(0, 0, 0);
    var d = camera.position.clone().sub(t);
    var r = d.length();
    if (r < 0.001) return;
    orbit.target.copy(t);
    orbit.radius = r;
    orbit.phi = Math.acos(Math.max(-1, Math.min(1, d.y / r)));
    orbit.theta = Math.atan2(d.x, d.z);
  }

  function applyOrbit() {
    var sp = Math.sin(orbit.phi);
    var cp = Math.cos(orbit.phi);
    camera.position.set(
      orbit.target.x + orbit.radius * sp * Math.sin(orbit.theta),
      orbit.target.y + orbit.radius * cp,
      orbit.target.z + orbit.radius * sp * Math.cos(orbit.theta)
    );
    camera.lookAt(orbit.target);
    camera.userData.target = orbit.target.clone();
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

  function pointerCount() {
    var n = 0;
    for (var k in pointers) if (pointers[k]) n += 1;
    return n;
  }

  function wireOrbit() {
    if (!canvas) return;
    canvas.addEventListener('pointerdown', function (e) {
      if (canvas.setPointerCapture) {
        try { canvas.setPointerCapture(e.pointerId); } catch (_e) { /* ignore */ }
      }
      pointers[e.pointerId] = { x: e.clientX, y: e.clientY };
      camTween = null;
      syncOrbitFromCamera();
      if (pointerCount() === 2) pinchDist = pinchDistance();
    });
    canvas.addEventListener('pointermove', function (e) {
      var p = pointers[e.pointerId];
      if (!p) return;
      var dx = e.clientX - p.x;
      var dy = e.clientY - p.y;
      p.x = e.clientX;
      p.y = e.clientY;
      var count = pointerCount();
      if (count === 1) {
        orbit.theta -= dx * 0.006;
        orbit.phi = clamp(orbit.phi - dy * 0.005, 0.12, 1.5);
        applyOrbit();
      } else if (count === 2) {
        var d = pinchDistance();
        if (pinchDist > 0 && d > 0) {
          orbit.radius = clamp(orbit.radius * (pinchDist / d), 25, 800);
          applyOrbit();
        }
        pinchDist = d;
      }
    });
    function release(e) {
      delete pointers[e.pointerId];
      if (pointerCount() < 2) pinchDist = 0;
    }
    canvas.addEventListener('pointerup', release);
    canvas.addEventListener('pointercancel', release);
    canvas.addEventListener('wheel', function (e) {
      e.preventDefault();
      camTween = null;
      syncOrbitFromCamera();
      orbit.radius = clamp(orbit.radius * Math.exp(e.deltaY * 0.0012), 25, 800);
      applyOrbit();
    }, { passive: false });
  }

  function pinchDistance() {
    var ids = [];
    for (var k in pointers) if (pointers[k]) ids.push(pointers[k]);
    if (ids.length < 2) return 0;
    var dx = ids[0].x - ids[1].x;
    var dy = ids[0].y - ids[1].y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function setViewInstant(focus) {
    var v = VIEWS[focus] || VIEWS.overview;
    var t = new T.Vector3(v.target[0], v.target[1], v.target[2]);
    var p = new T.Vector3(v.position[0], v.position[1], v.position[2]);
    var off = p.sub(t);
    if (camera.aspect < 1) off.multiplyScalar(1.7);
    applyCameraNow([t.x + off.x, t.y + off.y, t.z + off.z], v.target);
  }

  function focusWordInstant(wordId) {
    var root = wordRoots[wordId];
    if (!root) return;
    var f = focusParams(root);
    applyCameraNow(f.pos, f.target);
    if (selectionRing) {
      selectionRing.visible = true;
      selectionRing.position.set(f.center.x, 0.06, f.center.z);
    }
  }

  function tweenCamera(pos, target) {
    camTween = {
      t: 0,
      fromPos: camera.position.clone(),
      fromTarget: currentTarget(),
      toPos: new T.Vector3(pos[0], pos[1], pos[2]),
      toTarget: new T.Vector3(target[0], target[1], target[2])
    };
  }

  function currentTarget() {
    return camera.userData.target ? camera.userData.target.clone() : new T.Vector3(0, 0, 0);
  }

  function updateCamera(dt) {
    if (!camTween) return;
    camTween.t = Math.min(1, camTween.t + dt / 0.7);
    var e = camTween.t < 0.5
      ? 2 * camTween.t * camTween.t
      : 1 - Math.pow(-2 * camTween.t + 2, 2) / 2;
    camera.position.lerpVectors(camTween.fromPos, camTween.toPos, e);
    var tgt = new T.Vector3().lerpVectors(camTween.fromTarget, camTween.toTarget, e);
    camera.lookAt(tgt);
    camera.userData.target = tgt;
    if (camTween.t >= 1) {
      camTween = null;
      syncOrbitFromCamera();
    }
  }

  function init() {
    canvas = $('stageCanvas');
    renderer = new T.WebGLRenderer({ canvas: canvas, antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(global.devicePixelRatio || 1, 2));
    renderer.setSize(canvas.clientWidth || 1, canvas.clientHeight || 1, false);
    renderer.outputEncoding = T.sRGBEncoding;
    scene = new T.Scene();
    scene.background = new T.Color(0xbfe3f5);
    scene.fog = new T.Fog(0xd8ecf6, 360, 950);
    camera = new T.PerspectiveCamera(45, 1, 0.5, 5000);
    camera.position.set(190, 135, 195);
    camera.userData.target = new T.Vector3(20, 0, -45);
    camera.lookAt(camera.userData.target);
    clock = new T.Clock();
    loader = new T.GLTFLoader();
    createLights();
    global.addEventListener('resize', resize);
    resize();
    wireOrbit();
    syncOrbitFromCamera();
  }

  function createLights() {
    var hemi = new T.HemisphereLight(0xffffff, 0x9a8f7a, 0.95);
    hemi.position.set(0, 200, 0);
    scene.add(hemi);
    var sun = new T.DirectionalLight(0xfff2dd, 0.85);
    sun.position.set(-120, 160, 90);
    scene.add(sun);
    var fill = new T.DirectionalLight(0xbfd8ea, 0.35);
    fill.position.set(140, 80, -120);
    scene.add(fill);
  }

  function resize() {
    if (!renderer || !canvas) return;
    var w = canvas.clientWidth || 1;
    var h = canvas.clientHeight || 1;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }

  function loop() {
    rafId = global.requestAnimationFrame(loop);
    var dt = Math.min(clock.getDelta(), 0.1);
    if (!(dt > 0)) dt = 0.016;
    for (var i = 0; i < mixers.length; i++) mixers[i].mixer.update(dt);
    for (var j = 0; j < moving.length; j++) moving[j](dt);
    updateCamera(dt);
    if (selectedId && selectionRing && wordRoots[selectedId]) {
      wordRoots[selectedId].getWorldPosition(tmpVec);
      selectionRing.position.set(tmpVec.x, 0.06, tmpVec.z);
    }
    updateLabels();
    renderer.render(scene, camera);
  }

  function start() {
    if (rafId === 0) loop();
  }

  function getWordRoot(wordId) { return wordRoots[wordId] || null; }

  function pick(clientX, clientY) {
    if (!canvas) return null;
    var rect = canvas.getBoundingClientRect();
    pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    var hits = raycaster.intersectObjects(scene.children, true);
    for (var i = 0; i < hits.length; i++) {
      var node = hits[i].object;
      while (node) {
        if (node.userData && node.userData.wordId) return node.userData.wordId;
        node = node.parent;
      }
    }
    return null;
  }

  function stats() {
    var meshes = 0;
    var tris = 0;
    scene.traverse(function (o) {
      if (o.isMesh) {
        meshes += 1;
        var g = o.geometry;
        tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
      }
    });
    return {
      meshes: meshes,
      triangles: Math.round(tris),
      drawCalls: renderer ? renderer.info.render.calls : 0
    };
  }

  global.AirportScene = {
    init: init,
    start: start,
    loadAll: loadAll,
    buildWorld: buildWorld,
    setView: setView,
    focusWord: focusWord,
    setLabels: setLabels,
    setViewInstant: setViewInstant,
    focusWordInstant: focusWordInstant,
    addModel: addModel,
    place: place,
    getWordRoot: getWordRoot,
    pick: pick,
    stats: stats,
    scene: function () { return scene; },
    camera: function () { return camera; },
    wordById: function () { return wordById; }
  };
})(typeof window !== 'undefined' ? window : globalThis);
