/* 小星英语 · 3D 身体课：Three.js 小星与舞台。
 * 模型照 open-design 原型 xiaoxing-body-class 的 createXiaoxing 移植：
 * 程序化低多边形 + 可点击部位 + 柔和高亮光环 + 部位指示环。
 * 不依赖任何网络资源，three.min.js 与页面同目录。 */
(function () {
  'use strict';

  const THREE = window.THREE;
  const DATA = window.BodyClassData;
  if (!THREE || !DATA) {
    return;
  }

  const PAL = {
    skin: 0xf7c3a0, skinDeep: 0xe9a07c, hair: 0x3d2a23, shirt: 0x2f9c7e, shirtDeep: 0x237a62,
    pants: 0x34405e, shoes: 0xee6b4d, sole: 0xf6f4ef, eye: 0x241d1b, white: 0xffffff,
    mouth: 0x7c2a33, tongue: 0xe8818a, scarf: 0xf18b3e, cheek: 0xea8a7a, accent: 0x008a6a
  };

  function mat(color, opt) {
    return new THREE.MeshStandardMaterial(Object.assign({ color: color, roughness: 0.8, metalness: 0 }, opt || {}));
  }

  function add(parent, geo, mtl, pos, scale, name) {
    const m = new THREE.Mesh(geo, mtl);
    if (name) m.name = name;
    if (pos) m.position.set(pos[0], pos[1], pos[2]);
    if (scale) m.scale.set(scale[0], scale[1], scale[2]);
    m.castShadow = true;
    m.receiveShadow = true;
    parent.add(m);
    return m;
  }

  /* 外套背面：一片自己画出来的布，纬线绕成朝后的一道弧，最凸处在背后正中。 */
  function addBackCoat(body, M) {
    const g = new THREE.Group();
    g.name = 'backCoat';
    const R = 0.58, HALF = 0.5, ROWS = 12, COLS = 15;
    const at = function (s, y) {
      return new THREE.Vector3(Math.sin(s) * R * 1.004, y, -Math.abs(Math.cos(s)) * R * 1.004);
    };
    const pos = [], idx = [];
    const top = 2.0, bottom = 0.82;
    for (let r = 0; r <= ROWS; r++) {
      const y = top + (bottom - top) * (r / ROWS);
      for (let c = 0; c <= COLS; c++) {
        const s = -HALF + (HALF * 2) * (c / COLS);
        const v = at(s, y);
        v.z = -Math.abs(v.z) - 0.004;
        pos.push(v.x, v.y, v.z);
      }
    }
    for (let r = 0; r < ROWS; r++) {
      for (let c = 0; c < COLS; c++) {
        const a = r * (COLS + 1) + c, b = a + 1, d = a + COLS + 1, e = d + 1;
        idx.push(a, d, b, b, d, e);
      }
    }
    const cloth = new THREE.BufferGeometry();
    cloth.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    cloth.setIndex(idx);
    cloth.computeVertexNormals();
    const coat = new THREE.Mesh(cloth, M.back);
    coat.geometry.name = 'coatPanel';
    coat.name = 'backPanel';
    coat.userData.part = 'back';
    coat.castShadow = true;
    coat.receiveShadow = true;
    g.add(coat);

    const collarPts = [];
    for (let i = 0; i <= 12; i++) {
      const s = -HALF + (HALF * 2) * (i / 12);
      collarPts.push(at(s, top + 0.012));
    }
    const collar = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(collarPts), 24, 0.03, 8, false), M.backTrim);
    collar.geometry.name = 'coatCollar';
    collar.name = 'backCollar';
    collar.userData.part = 'back';
    collar.castShadow = true;
    g.add(collar);

    const seamPts = [];
    for (let i = 0; i <= 10; i++) {
      const t = i / 10;
      seamPts.push(at(0, top - 0.05 + (bottom + 0.12 - top + 0.05) * t));
    }
    const seam = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(seamPts), 20, 0.014, 6, false), M.backTrim);
    seam.geometry.name = 'coatSeam';
    seam.name = 'backSeam';
    seam.userData.part = 'back';
    seam.castShadow = true;
    g.add(seam);
    body.add(g);
    return g;
  }

  function createXiaoxing() {
    const root = new THREE.Group();
    const body = new THREE.Group();
    root.add(body);
    const M = {
      skin: mat(PAL.skin, { roughness: 0.68 }), skinDeep: mat(PAL.skinDeep, { roughness: 0.7 }),
      hair: mat(PAL.hair, { roughness: 0.5 }), shirt: mat(PAL.shirt, { roughness: 0.75 }),
      shirtDeep: mat(PAL.shirtDeep, { roughness: 0.75 }), pants: mat(PAL.pants, { roughness: 0.8 }),
      shoe: mat(PAL.shoes, { roughness: 0.55 }), sole: mat(PAL.sole, { roughness: 0.9 }),
      eye: mat(PAL.eye, { roughness: 0.2 }), white: mat(PAL.white, { roughness: 0.25 }),
      mouth: mat(PAL.mouth, { roughness: 0.6 }), tongue: mat(PAL.tongue, { roughness: 0.6 }),
      scarf: mat(PAL.scarf, { roughness: 0.65 }),
      back: mat(PAL.shirt, { roughness: 0.8, side: THREE.DoubleSide, emissive: PAL.shirt, emissiveIntensity: 0.04 }),
      backTrim: mat(PAL.shirtDeep, { roughness: 0.8, side: THREE.DoubleSide })
    };

    const headG = new THREE.Group();
    headG.position.set(0, 3.28, 0);
    body.add(headG);
    add(headG, new THREE.SphereGeometry(0.78, 40, 30), M.skin, [0, 0.1, 0], [1, 0.97, 0.95], 'head');
    add(headG, new THREE.SphereGeometry(0.805, 40, 24, 0, Math.PI * 2, 0, Math.PI * 0.42), M.hair, [0, 0.11, -0.03], [1.01, 1, 0.99], 'hair');
    [[-0.16, 0.88, 0.02, 0.19, 0.5, 0.3], [0.12, 0.93, -0.1, 0.16, -0.4, 1.1], [0.34, 0.78, -0.18, 0.12, 0.2, 2.1]].forEach(function (c) {
      const curl = add(headG, new THREE.TorusGeometry(c[3], c[3] * 0.45, 10, 22, Math.PI * 1.55), M.hair, [c[0], c[1], c[2]], null, 'hairCurl');
      curl.rotation.set(c[4], 0.3, c[5]);
    });

    [-1, 1].forEach(function (sx) {
      const outer = add(headG, new THREE.TorusGeometry(0.17, 0.075, 12, 26), M.skin, [0.74 * sx, 0.02, -0.02], null, 'earO' + sx);
      outer.rotation.y = Math.PI / 2;
      outer.scale.set(1, 1.35, 1);
      const inner = new THREE.Mesh(new THREE.CircleGeometry(0.115, 22), M.skinDeep);
      inner.position.set(0.768 * sx, 0.02, -0.02);
      inner.rotation.y = Math.PI / 2 * sx;
      inner.scale.set(1, 1.3, 1);
      inner.name = 'earI' + sx;
      headG.add(inner);
    });

    const eyes = [];
    const eyeMat = new THREE.MeshStandardMaterial({ color: 0x1d1a1b, roughness: 0.18, metalness: 0.05 });
    const glintMat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.95 });
    const glintMat2 = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.7 });
    [-1, 1].forEach(function (sx) {
      const g = new THREE.Group();
      g.position.set(0.25 * sx, 0.15, 0.66);
      g.name = 'eyeG' + sx;
      headG.add(g);
      add(g, new THREE.SphereGeometry(0.118, 28, 22), eyeMat, [0, 0, 0], [1, 1.16, 0.62]);
      const glint = new THREE.Mesh(new THREE.SphereGeometry(0.034, 14, 12), glintMat);
      glint.name = 'glint';
      glint.position.set(0.035 * sx, 0.045, 0.07);
      glint.scale.set(1, 1, 0.6);
      g.add(glint);
      const glint2 = new THREE.Mesh(new THREE.SphereGeometry(0.017, 12, 10), glintMat2);
      glint2.name = 'glint2';
      glint2.position.set(-0.035 * sx, -0.04, 0.072);
      glint2.scale.set(1, 1, 0.6);
      g.add(glint2);
      eyes.push({ g: g });
      const brow = add(headG, new THREE.TorusGeometry(0.125, 0.019, 8, 18, Math.PI), M.hair, [0.25 * sx, 0.34, 0.64]);
      brow.rotation.z = sx * 0.1;
      brow.rotation.x = -0.25;
    });

    add(headG, new THREE.SphereGeometry(0.085, 24, 18), M.skinDeep, [0, 0.0, 0.76], [1, 0.85, 0.9], 'nose');

    const mouthG = new THREE.Group();
    mouthG.position.set(0, -0.19, 0.65);
    headG.add(mouthG);
    const mouth = new THREE.Mesh(new THREE.SphereGeometry(0.15, 28, 16, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), M.mouth);
    mouth.name = 'mouth';
    mouth.scale.set(1.25, 0.66, 0.5);
    mouthG.add(mouth);
    const teeth = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.05, 0.05), M.white);
    teeth.name = 'teeth';
    teeth.position.set(0, -0.006, 0.055);
    mouthG.add(teeth);
    const tongue = new THREE.Mesh(new THREE.SphereGeometry(0.07, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), M.tongue);
    tongue.name = 'tongue';
    tongue.rotation.x = Math.PI;
    tongue.position.set(0, -0.055, 0.03);
    tongue.scale.set(1.15, 0.7, 0.55);
    mouthG.add(tongue);

    [-1, 1].forEach(function (sx) {
      const c = new THREE.Mesh(new THREE.CircleGeometry(0.095, 24), new THREE.MeshBasicMaterial({ color: PAL.cheek, transparent: true, opacity: 0.42 }));
      c.name = 'cheek';
      c.position.set(0.43 * sx, -0.12, 0.55);
      c.lookAt(c.position.x * 2.4, c.position.y, 3);
      headG.add(c);
    });

    add(body, new THREE.CylinderGeometry(0.19, 0.235, 0.36, 24), M.skin, [0, 2.62, 0], null, 'neck');
    const scarf = add(body, new THREE.TorusGeometry(0.235, 0.085, 14, 40), M.scarf, [0, 2.47, 0], [1.05, 1, 1]);
    scarf.rotation.x = Math.PI / 2;
    const t1 = add(body, new THREE.BoxGeometry(0.12, 0.3, 0.055), M.scarf, [-0.26, 2.27, 0.24], [1, 1, 1]);
    t1.rotation.set(0.2, 0, 0.3);
    const t2 = add(body, new THREE.BoxGeometry(0.1, 0.22, 0.055), M.scarf, [-0.11, 2.3, 0.28]);
    t2.rotation.set(0.2, 0, -0.15);
    add(body, new THREE.SphereGeometry(0.5, 36, 26), M.shirt, [0, 1.86, 0], [1.06, 0.92, 0.78], 'chest');
    add(body, new THREE.SphereGeometry(0.46, 36, 26), M.shirt, [0, 1.4, 0.02], [1.0, 0.8, 0.86], 'tummy');
    add(body, new THREE.CylinderGeometry(0.44, 0.39, 0.3, 32), M.pants, [0, 1.0, 0], null, 'hips');

    const star = new THREE.Shape();
    for (let i = 0; i < 10; i++) {
      const a = -Math.PI / 2 + i * Math.PI / 5, r = i % 2 === 0 ? 0.115 : 0.05;
      if (i === 0) star.moveTo(Math.cos(a) * r, Math.sin(a) * r);
      else star.lineTo(Math.cos(a) * r, Math.sin(a) * r);
    }
    star.closePath();
    const badge = add(body, new THREE.ExtrudeGeometry(star, { depth: 0.03, bevelEnabled: true, bevelSize: 0.01, bevelThickness: 0.012, bevelSegments: 2 }), M.scarf, [0.27, 1.95, 0.37], null, 'badge');
    badge.rotation.set(-0.3, 0.1, 0);

    const nav = new THREE.Mesh(new THREE.CircleGeometry(0.034, 18), M.skinDeep);
    nav.name = 'tummy';
    nav.position.set(0, 1.32, 0.408);
    nav.rotation.x = -0.12;
    body.add(nav);

    const pad = function (name, part, r, pos) {
      const m = new THREE.Mesh(new THREE.SphereGeometry(1, 8, 6), new THREE.MeshBasicMaterial({ visible: false }));
      m.name = name;
      m.userData.part = part;
      m.scale.set(r[0], r[1], r[2]);
      m.position.set(pos[0], pos[1], pos[2]);
      body.add(m);
      return m;
    };
    const backCoat = addBackCoat(body, M);
    pad('padShoulderL', 'shoulder', [0.22, 0.2, 0.24], [-0.5, 2.22, 0]);
    pad('padShoulderR', 'shoulder', [0.22, 0.2, 0.24], [0.5, 2.22, 0]);
    pad('padTummy', 'tummy', [0.09, 0.09, 0.06], [0, 1.32, 0.4]);
    pad('padBelly', 'belly', [0.2, 0.11, 0.05], [0, 1.62, 0.36]);
    pad('padChestF', 'chest', [0.26, 0.16, 0.06], [0, 2.02, 0.38]);
    pad('padChest', 'chest', [0.14, 0.14, 0.08], [0, 1.95, 0.36]);

    const arms = [];
    [-1, 1].forEach(function (sx) {
      const shoulder = new THREE.Group();
      shoulder.position.set(0.5 * sx, 2.2, 0);
      body.add(shoulder);
      add(shoulder, new THREE.SphereGeometry(0.17, 24, 18), M.shirt, [0.03 * sx, 0, 0], null, 'armUpper' + sx);
      add(shoulder, new THREE.CapsuleGeometry(0.122, 0.34, 10, 18), M.shirt, [0.05 * sx, -0.27, 0], null, 'armUp' + sx);
      add(shoulder, new THREE.CylinderGeometry(0.128, 0.128, 0.08, 20), M.shirtDeep, [0.05 * sx, -0.45, 0], null, 'armCuff' + sx);
      const elbow = new THREE.Group();
      elbow.position.set(0.05 * sx, -0.5, 0);
      shoulder.add(elbow);
      add(elbow, new THREE.SphereGeometry(0.104, 16, 12), M.skin, [0, 0, 0], null, 'armElbow' + sx);
      add(elbow, new THREE.CapsuleGeometry(0.102, 0.28, 10, 18), M.skin, [0, -0.21, 0], null, 'armFore' + sx);
      const hand = new THREE.Group();
      hand.position.set(0, -0.44, 0);
      elbow.add(hand);
      add(hand, new THREE.SphereGeometry(0.13, 24, 18), M.skin, [0, 0, 0], [1, 1.08, 0.82], 'handPalm' + sx);
      for (let i = 0; i < 4; i++) {
        add(hand, new THREE.CapsuleGeometry(0.033, 0.085, 6, 10), M.skin, [(i - 1.5) * 0.056, -0.135, 0.015], null, 'fi' + i + sx);
      }
      const thumb = add(hand, new THREE.CapsuleGeometry(0.04, 0.07, 6, 10), M.skin, [-0.115 * sx, -0.02, 0.05], null, 'thumb' + sx);
      thumb.rotation.z = sx * 0.95;
      arms.push({ sx: sx, shoulder: shoulder, elbow: elbow, hand: hand });
    });

    [-1, 1].forEach(function (sx) {
      add(body, new THREE.SphereGeometry(0.14, 14, 10), M.pants, [0.21 * sx, 0.8, 0.02], null, 'legKnee' + sx);
      add(body, new THREE.CapsuleGeometry(0.147, 0.26, 10, 18), M.pants, [0.21 * sx, 0.7, 0], null, 'legUp' + sx);
      add(body, new THREE.CapsuleGeometry(0.12, 0.22, 10, 18), M.skin, [0.22 * sx, 0.33, 0.01], null, 'legLow' + sx);
      const shoe = new THREE.Group();
      shoe.position.set(0.22 * sx, 0.12, 0.07);
      body.add(shoe);
      add(shoe, new THREE.SphereGeometry(0.165, 28, 20), M.shoe, [0, 0, 0.02], [1, 0.76, 1.42], 'shoeBody' + sx);
      const sole = add(shoe, new THREE.CapsuleGeometry(0.055, 0.3, 6, 14), M.sole, [0, -0.075, 0.03]);
      sole.rotation.x = Math.PI / 2;
      sole.scale.set(2.7, 1, 1.25);
      add(shoe, new THREE.SphereGeometry(0.05, 14, 10), M.sole, [0, 0.03, 0.255]);
    });

    return { root: root, body: body, headG: headG, eyes: eyes, mouthG: mouthG, mouth: mouth, arms: arms, backCoat: backCoat };
  }

  const MESH_PART = [
    ['glint', 'eye'], ['brow', 'eye'], ['eye', 'eye'],
    ['armElbow', 'elbow'], ['armUpper', 'arm'], ['armTop', 'arm'], ['armUp', 'arm'], ['armCuff', 'arm'], ['arm', 'arm'],
    ['handPalm', 'hand'], ['hand', 'hand'],
    ['thumb', 'thumb'],
    ['fi', 'finger'],
    ['ear', 'ear'],
    ['nose', 'nose'], ['mouth', 'mouth'], ['tongue', 'mouth'], ['teeth', 'teeth'],
    ['hairCurl', 'hair'], ['hair', 'hair'],
    ['head', 'head'], ['neck', 'neck'],
    ['backPanel', 'back'], ['backCollar', 'back'], ['backSeam', 'back'],
    ['padShoulder', 'shoulder'], ['padBelly', 'belly'],
    ['padChest', 'chest'], ['padSkin', 'skin'],
    ['padTummy', 'tummy'], ['tummy', 'tummy'], ['cheek', 'face'],
    ['chest', 'chest'], ['badge', 'chest'],
    ['hips', 'body'],
    ['legKnee', 'knee'], ['legUp', 'leg'], ['legLow', 'leg'],
    ['shoeBody', 'foot']
  ];

  function meshPart(name) {
    for (let i = 0; i < MESH_PART.length; i++) {
      if (name.indexOf(MESH_PART[i][0]) === 0) return MESH_PART[i][1];
    }
    return null;
  }

  /* 光环贴在部位朝镜头的一侧：z 取部位表面附近，避免埋进身体或横成一条线。 */
  const HALO_Z = {
    head: 0.84, hair: 0.8, face: 1.15, ear: 0.34, eye: 1.0, nose: 1.14, mouth: 1.04,
    teeth: 1.14, neck: 0.4, shoulder: 0.48, arm: 0.42, elbow: 0.4, hand: 0.36,
    finger: 0.34, thumb: 0.42, chest: 0.86, belly: 0.8, tummy: 0.76, back: -0.8,
    skin: 1.0, body: 1.0, leg: 0.38, knee: 0.52, foot: 0.56, toe: 0.58
  };
  const HALO_R = {
    head: 0.82, hair: 0.56, face: 0.5, ear: 0.3, eye: 0.34, nose: 0.24, mouth: 0.3,
    teeth: 0.2, neck: 0.33, shoulder: 0.3, arm: 0.35, elbow: 0.22, hand: 0.3,
    finger: 0.22, thumb: 0.16, chest: 0.4, belly: 0.36, tummy: 0.18, back: 0.55,
    skin: 0.22, body: 1.05, leg: 0.3, knee: 0.22, foot: 0.28, toe: 0.26
  };

  function haloTarget(id) {
    const h = DATA.hit[id] || DATA.hit.head;
    const focus = id === 'body' ? [0, 1.86, 0.6] : id === 'skin' ? [0, 3.28, 1.02] : h.c;
    const z = HALO_Z[id] !== undefined ? HALO_Z[id] : Math.min(0.78, Math.max(0.35, focus[2] * 0.72));
    const r = HALO_R[id] !== undefined ? HALO_R[id] : Math.max(0.22, h.r * 0.95);
    return { x: focus[0], y: focus[1], z: z, r: r };
  }

  function BodyStage(canvas, callbacks) {
    this.canvas = canvas;
    this.callbacks = callbacks || {};
    this.selected = null;
    this.playing = false;
    this.destroyed = false;
    this.drag = null;
    this.hoverId = null;
    this.waveTimer = 0;
    this.blink = 0;
    this.blinkT = 2.4;
    this.t = 0;
    this.readySent = false;
    this.pointer = new THREE.Vector2();
    this.raycaster = new THREE.Raycaster();
    this.yaw = 0;
    this.targetYaw = 0;
    this.lastHoverCheck = 0;
    this.init();
  }

  BodyStage.prototype.init = function () {
    const self = this;
    const canvas = this.canvas;
    const mount = canvas.parentNode;
    const W = function () { return mount.clientWidth || 360; };
    const H = function () { return mount.clientHeight || 420; };

    let renderer;
    try {
      renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
    } catch (err) {
      if (self.callbacks.onError) self.callbacks.onError('webgl');
      return;
    }
    this.renderer = renderer;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(W(), H(), false);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.NeutralToneMapping;
    renderer.toneMappingExposure = 1.0;
    canvas.style.cssText = 'display:block;width:100%;height:100%;touch-action:none';
    canvas.setAttribute('aria-label', '可以拖动旋转的 3D 小星，点身上的部位就能听发音、看单词卡');

    const scene = new THREE.Scene();
    this.scene = scene;
    const camera = new THREE.PerspectiveCamera(26, W() / H(), 0.1, 100);
    this.camera = camera;

    scene.add(new THREE.HemisphereLight(0xffffff, 0xd8e2df, 0.95));
    scene.add(new THREE.AmbientLight(0xffffff, 0.28));
    const key = new THREE.DirectionalLight(0xffffff, 1.9);
    key.position.set(4.5, 7.5, 7);
    key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024);
    key.shadow.camera.left = -4;
    key.shadow.camera.right = 4;
    key.shadow.camera.top = 7;
    key.shadow.camera.bottom = -2;
    key.shadow.camera.near = 1;
    key.shadow.camera.far = 25;
    key.shadow.bias = -0.0012;
    key.shadow.radius = 4;
    scene.add(key);
    const fill = new THREE.DirectionalLight(0xffffff, 0.5);
    fill.position.set(-6, 3.5, 4.5);
    scene.add(fill);
    const rim = new THREE.DirectionalLight(0xfff0e0, 0.65);
    rim.position.set(-1.5, 4.5, -6.5);
    scene.add(rim);

    const platform = new THREE.Mesh(new THREE.CylinderGeometry(1.62, 1.68, 0.14, 72), mat(0xffffff, { roughness: 0.95 }));
    platform.position.y = -0.07;
    platform.receiveShadow = true;
    scene.add(platform);
    const track = new THREE.Mesh(new THREE.TorusGeometry(1.63, 0.028, 10, 90), new THREE.MeshBasicMaterial({ color: 0xdfe9e6 }));
    track.rotation.x = Math.PI / 2;
    track.position.y = 0.004;
    scene.add(track);
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(14, 14), new THREE.ShadowMaterial({ opacity: 0.12 }));
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = 0.001;
    floor.receiveShadow = true;
    scene.add(floor);

    const lang = createXiaoxing();
    scene.add(lang.root);
    this.lang = lang;

    lang.root.traverse(function (o) {
      if (!o.isMesh || o.userData.part) return;
      const part = meshPart(o.name || '');
      if (part) o.userData.part = part;
    });
    const solids = [];
    lang.root.traverse(function (o) {
      if (o.isMesh && o.userData.part !== undefined) solids.push(o);
    });
    this.solids = solids;

    const loose = [];
    const looseGeo = new THREE.SphereGeometry(1, 12, 10);
    const NO_FALLBACK = ['back', 'skin'];
    Object.keys(DATA.hit).forEach(function (id) {
      if (NO_FALLBACK.indexOf(id) >= 0) return;
      const h = DATA.hit[id];
      const s = new THREE.Mesh(looseGeo, new THREE.MeshBasicMaterial({ visible: false }));
      s.scale.set(h.r * 0.6, h.r * 0.6, h.r * 0.6 * 0.42);
      s.position.set(h.c[0], h.c[1], h.c[2]);
      s.userData.id = id;
      lang.root.add(s);
      loose.push(s);
    });
    this.loose = loose;

    /* 高亮光环：贴在身体表面上的光圈 + 光盘 + 脉冲环。 */
    const halo = new THREE.Group();
    lang.root.add(halo);
    const ringMat = new THREE.MeshBasicMaterial({ color: PAL.scarf, transparent: true, opacity: 0, depthWrite: false });
    const pingMat = new THREE.MeshBasicMaterial({ color: PAL.scarf, transparent: true, opacity: 0, depthWrite: false });
    const discMat = new THREE.MeshBasicMaterial({ color: PAL.scarf, transparent: true, opacity: 0, depthWrite: false });
    const ring = new THREE.Mesh(new THREE.TorusGeometry(1, 0.042, 10, 72), ringMat);
    const ping = new THREE.Mesh(new THREE.TorusGeometry(1, 0.02, 10, 72), pingMat);
    const disc = new THREE.Mesh(new THREE.CircleGeometry(1, 64), discMat);
    ring.rotation.x = Math.PI / 2;
    ping.rotation.x = Math.PI / 2;
    halo.add(disc, ring, ping);
    halo.position.set(0, 3.4, 0.5);
    halo.scale.setScalar(0.0001);
    this.halo = { group: halo, ring: ring, ping: ping, disc: disc, ringMat: ringMat, pingMat: pingMat, discMat: discMat };

    const glowCanvas = document.createElement('canvas');
    glowCanvas.width = glowCanvas.height = 128;
    const gctx = glowCanvas.getContext('2d');
    const grd = gctx.createRadialGradient(64, 64, 2, 64, 64, 64);
    grd.addColorStop(0, 'rgba(219,112,59,0.95)');
    grd.addColorStop(0.45, 'rgba(219,112,59,0.32)');
    grd.addColorStop(1, 'rgba(219,112,59,0)');
    gctx.fillStyle = grd;
    gctx.fillRect(0, 0, 128, 128);
    const glowTex = new THREE.CanvasTexture(glowCanvas);
    glowTex.colorSpace = THREE.SRGBColorSpace;
    const glowMat = new THREE.SpriteMaterial({ map: glowTex, transparent: true, opacity: 0, depthWrite: false, depthTest: false });
    const glow = new THREE.Sprite(glowMat);
    glow.renderOrder = 5;
    glow.scale.setScalar(0.001);
    lang.root.add(glow);
    this.glow = { sprite: glow, mat: glowMat };

    /* 部位指示点：贴在身体上的小圆环，选中哪个部位就指到哪。 */
    const dotGeo = new THREE.RingGeometry(0.7, 1, 28);
    const dots = [];
    for (let i = 0; i < 3; i++) {
      const m = new THREE.MeshBasicMaterial({ color: PAL.accent, transparent: true, opacity: 0, side: THREE.DoubleSide, depthTest: false });
      const d = new THREE.Mesh(dotGeo, m);
      d.scale.setScalar(0.05);
      d.visible = false;
      d.renderOrder = 6;
      lang.root.add(d);
      dots.push(d);
    }
    this.dots = dots;

    const EVEN = 4.56, LOOK = EVEN / 2, HALF_TAN = Math.tan(13 * Math.PI / 180);
    this.fitZ = function () {
      const aspect = Math.max(0.45, W() / H());
      const zH = (EVEN / 2 * 1.04) / HALF_TAN;
      const zW = (2.5 / 2 * 1.04) / (HALF_TAN * aspect);
      return Math.max(zH, zW, 9.8);
    };
    this.camZ = this.camZTarget = this.fitZ();

    this.resize = function () {
      const w = W(), h = H();
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      self.camZ = self.camZTarget = self.fitZ();
    };
    this.resizeObserver = new ResizeObserver(this.resize);
    this.resizeObserver.observe(mount);
    this.resize();

    function pointAt(clientX, clientY) {
      const r = canvas.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) return null;
      self.pointer.x = ((clientX - r.left) / r.width) * 2 - 1;
      self.pointer.y = -((clientY - r.top) / r.height) * 2 + 1;
      self.raycaster.setFromCamera(self.pointer, camera);
      const main = self.raycaster.intersectObjects(solids, false)[0];
      if (main) return main.object.userData.part;
      const backup = self.raycaster.intersectObjects(loose, false)[0];
      return backup ? backup.object.userData.id : null;
    }

    function onDown(e) {
      self.drag = { x: e.clientX, yaw: self.targetYaw, moved: 0 };
      if (canvas.setPointerCapture) canvas.setPointerCapture(e.pointerId);
    }
    function onMove(e) {
      if (self.drag) {
        const dx = e.clientX - self.drag.x;
        self.drag.moved = Math.max(self.drag.moved, Math.abs(dx));
        if (self.drag.moved > 5) self.targetYaw = self.drag.yaw + dx * 0.012;
        return;
      }
      const now = performance.now();
      if (now - self.lastHoverCheck < 60) return;
      self.lastHoverCheck = now;
      const id = pointAt(e.clientX, e.clientY);
      if (id !== self.hoverId) {
        self.hoverId = id;
        canvas.style.cursor = id ? 'pointer' : 'grab';
      }
    }
    function onUp(e) {
      const d = self.drag;
      if (d && d.moved <= 5 && e && e.clientX !== undefined) {
        const id = pointAt(e.clientX, e.clientY);
        if (id && self.callbacks.onPick) self.callbacks.onPick(id);
      }
      self.drag = null;
    }
    function onLeave() {
      self.hoverId = null;
      canvas.style.cursor = 'grab';
    }
    this.handlers = { down: onDown, move: onMove, up: onUp, leave: onLeave };
    canvas.style.cursor = 'grab';
    canvas.addEventListener('pointerdown', onDown);
    canvas.addEventListener('pointermove', onMove);
    canvas.addEventListener('pointerup', onUp);
    canvas.addEventListener('pointerleave', onLeave);
    window.addEventListener('pointerup', onUp);

    this.last = performance.now();
    let raf = 0;
    const frame = function (now) {
      if (self.destroyed) return;
      raf = requestAnimationFrame(frame);
      const dt = Math.min((now - self.last) / 1000, 0.05);
      self.last = now;
      self.t += dt;
      const t = self.t;
      const breathe = Math.sin(t * 1.6) * 0.011;
      lang.body.scale.set(1 + breathe, 1 + breathe * 1.4, 1 + breathe);
      lang.body.position.y = Math.abs(Math.sin(t * 1.9)) * 0.026;

      self.yaw += (self.targetYaw - self.yaw) * Math.min(1, dt * 5.5);
      lang.root.rotation.y = self.yaw;

      const headSpeed = Math.min(1, dt * 3);
      lang.headG.rotation.y += (Math.sin(t * 0.55) * 0.1 - lang.headG.rotation.y) * headSpeed;
      lang.headG.rotation.z += (Math.sin(t * 0.8) * 0.03 - lang.headG.rotation.z) * headSpeed;

      self.blinkT -= dt;
      if (self.blinkT <= 0) {
        self.blink = 1;
        self.blinkT = 2.6 + Math.random() * 3.2;
      }
      self.blink = Math.max(0, self.blink - dt * 5.5);
      const open = Math.max(0.06, 1 - Math.sin(self.blink * Math.PI) * 0.94);
      lang.eyes.forEach(function (e) { e.g.scale.y = open; });

      const talk = self.playing ? 0.55 + Math.abs(Math.sin(t * 9.5)) * 0.85 : 0.55;
      lang.mouth.scale.y += (0.66 * talk - lang.mouth.scale.y) * Math.min(1, dt * 14);

      self.waveTimer = Math.max(0, self.waveTimer - dt);
      lang.arms.forEach(function (a) {
        let gs = 0.16 + Math.sin(t * 1.5 + (a.sx > 0 ? 0 : 1.4)) * 0.025;
        let ge = 0.1;
        if (self.waveTimer > 0 && a.sx > 0) {
          gs = -2.35;
          ge = 0.5 + Math.sin(t * 12) * 0.5;
        } else if (self.waveTimer > 0 && a.sx < 0) {
          gs = -1.15;
          ge = 0.95;
        }
        a.shoulder.rotation.z += (a.sx * gs - a.shoulder.rotation.z) * Math.min(1, dt * 8);
        a.elbow.rotation.z += (a.sx * ge - a.elbow.rotation.z) * Math.min(1, dt * 8);
      });

      self.camZ += (self.camZTarget - self.camZ) * Math.min(1, dt * 6);
      camera.position.set(0, LOOK + Math.sin(t * 0.3) * 0.025, self.camZ);
      camera.lookAt(0, LOOK, 0);
      camera.updateMatrixWorld();

      self.updateDots(dt, t);
      self.updateHalo(dt, t);
      renderer.render(scene, camera);

      if (!self.readySent) {
        self.readySent = true;
        if (self.callbacks.onReady) self.callbacks.onReady();
      }
    };
    raf = requestAnimationFrame(frame);
    this.raf = raf;
  };

  BodyStage.prototype.updateHalo = function (dt, t) {
    const h = this.halo;
    if (!h) return;
    const lang = this.lang;
    if (this.selected) {
      const ht = haloTarget(this.selected);
      h.group.position.x += (ht.x - h.group.position.x) * Math.min(1, dt * 9);
      h.group.position.y += (ht.y - h.group.position.y) * Math.min(1, dt * 9);
      h.group.position.z += (ht.z - h.group.position.z) * Math.min(1, dt * 9);
      h.group.scale.setScalar(ht.r * (1 + Math.sin(t * 2.6) * 0.05));
      h.ringMat.opacity += (0.55 - h.ringMat.opacity) * Math.min(1, dt * 6);
      h.pingMat.opacity += (0.24 - h.pingMat.opacity) * Math.min(1, dt * 6);
      h.discMat.opacity += (0.04 - h.discMat.opacity) * Math.min(1, dt * 6);
      h.ring.lookAt(this.camera.position);
      h.ping.lookAt(this.camera.position);
      h.disc.lookAt(this.camera.position);
      h.ring.rotation.z += t * 0.5;
      h.ping.rotation.z += t * 0.5;
      const pulse = 0.18 + ht.r * 0.25;
      this.glow.sprite.position.set(ht.x, ht.y, ht.z + 0.28);
      this.glow.sprite.scale.setScalar(pulse * (1 + Math.sin(t * 2.6) * 0.08));
      this.glow.mat.opacity += (0.12 - this.glow.mat.opacity) * Math.min(1, dt * 7);
    } else {
      h.ringMat.opacity *= 1 - Math.min(1, dt * 6);
      h.pingMat.opacity *= 1 - Math.min(1, dt * 6);
      h.discMat.opacity *= 1 - Math.min(1, dt * 6);
      this.glow.mat.opacity *= 1 - Math.min(1, dt * 6);
      h.group.scale.setScalar(Math.max(0.0001, h.group.scale.x * (1 - Math.min(1, dt * 6))));
    }
  };

  BodyStage.prototype.updateDots = function (dt, t) {
    const self = this;
    const pts = (this.selected && DATA.guide[this.selected]) || [];
    this.dots.forEach(function (d, i) {
      const p = pts[i];
      if (!p) {
        d.visible = false;
        d.material.opacity = 0;
        return;
      }
      d.visible = true;
      d.position.set(p[0], p[1], p[2]);
      d.position.z += 0.1;
      d.scale.setScalar(0.062 + Math.sin(t * 2.4 + i) * 0.009);
      d.lookAt(self.camera.position);
      const want = 0.42 + Math.sin(t * 2.4 + i) * 0.1;
      d.material.opacity += (want - d.material.opacity) * Math.min(1, dt * 7);
    });
  };

  BodyStage.prototype.setSelected = function (id, face) {
    this.selected = id || null;
    if (face && id) this.targetYaw = id === 'back' ? Math.PI : 0;
  };

  BodyStage.prototype.setSpeaking = function (playing) {
    this.playing = !!playing;
  };

  BodyStage.prototype.nudge = function (dir) {
    this.targetYaw += dir * Math.PI / 2;
  };

  BodyStage.prototype.wave = function () {
    this.waveTimer = 2.0;
  };

  BodyStage.prototype.reset = function () {
    this.targetYaw = 0;
  };

  BodyStage.prototype.dispose = function () {
    this.destroyed = true;
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.resizeObserver) this.resizeObserver.disconnect();
    const h = this.handlers;
    if (h) {
      this.canvas.removeEventListener('pointerdown', h.down);
      this.canvas.removeEventListener('pointermove', h.move);
      this.canvas.removeEventListener('pointerup', h.up);
      this.canvas.removeEventListener('pointerleave', h.leave);
      window.removeEventListener('pointerup', h.up);
    }
    if (this.scene) {
      this.scene.traverse(function (o) {
        if (o.geometry) o.geometry.dispose();
        if (o.material) {
          const list = Array.isArray(o.material) ? o.material : [o.material];
          list.forEach(function (m) { m.dispose(); });
        }
      });
    }
    if (this.renderer) this.renderer.dispose();
  };

  window.BodyStage = BodyStage;
})();
