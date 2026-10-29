/* 低多边形客餐厅模型。所有可点击物品都是独立 Group，并保留 OBJ_* 命名。 */
(function () {
  'use strict';

  const THREE = window.THREE;
  const FLOOR_Y = 0.03;
  const TABLE_TOP = FLOOR_Y + 0.805;

  const RGB = {
    floorA: [77, 0.071, 76],
    floorB: [74, 0.068, 71],
    floorC: [80, 0.06, 84],
    wall: [94, 0.019, 88],
    wallCool: [93, 0.025, 166],
    trim: [88, 0.025, 80],
    cream: [96, 0.014, 82],
    white: [99, 0.003, 80],
    ink: [25, 0.018, 240],
    wood: [69, 0.083, 64],
    woodLight: [78, 0.069, 73],
    woodDark: [57, 0.076, 57],
    sofa: [70, 0.105, 43],
    sofaDark: [60, 0.105, 38],
    sofaLight: [82, 0.064, 52],
    teal: [58, 0.092, 171],
    tealDark: [45, 0.08, 171],
    mint: [84, 0.055, 168],
    rug: [91, 0.028, 80],
    rugInner: [95, 0.023, 78],
    coral: [69, 0.125, 33],
    mustard: [81, 0.115, 83],
    green: [57, 0.105, 143],
    greenDark: [45, 0.09, 145],
    sky: [88, 0.045, 220],
    metal: [76, 0.008, 230],
    glass: [85, 0.045, 220],
    stone: [90, 0.006, 210],
    stoneDeep: [82, 0.007, 215],
    steel: [74, 0.006, 250],
    appliance: [88, 0.004, 235],
    glassDark: [24, 0.012, 250],
    tile: [92, 0.007, 195],
    brass: [72, 0.09, 78],
    sageGrey: [59, 0.028, 158],
    sageGreyDark: [48, 0.026, 158],
    linen: [96, 0.013, 84],
    linenDust: [91, 0.017, 82]
  };

  // 房间从 8m × 6m 的客餐厅向东扩出 3.5m 的开放厨房。
  const ROOM = { minX: -4.19, maxX: 7.65, minZ: -3.19, maxZ: 3.19, centerX: 1.73 };
  const KITCHEN = {
    counterZ: -2.68,
    counterTop: 0.92,
    islandX: 5.95,
    islandZ: -0.86,
    islandTop: 0.9
  };

  const dataById = new Map(window.WordRoomData.objects.map((item) => [item.id, item]));
  // 户型级纯数据（客餐厅分区取景中心 + 卧室门洞），见 room-layout.js
  const LAYOUT = window.WordRoomLayout || { areas: {}, doors: {} };
  const hitMaterial = new THREE.MeshBasicMaterial({
    transparent: true,
    opacity: 0,
    colorWrite: false,
    depthWrite: false
  });

  // 调色板里的 L 是 OKLCH 的百分比（0-100），线性 sRGB 计算要 0-1，先归一化。
  function linearSrgb([L, C, H]) {
    const lightness = L / 100;
    const h = (H * Math.PI) / 180;
    const a = C * Math.cos(h);
    const b = C * Math.sin(h);
    const l_ = lightness + 0.3963377774 * a + 0.2158037573 * b;
    const m_ = lightness - 0.1055613458 * a - 0.0638541728 * b;
    const s_ = lightness - 0.0894841775 * a - 1.291485548 * b;
    const l = l_ * l_ * l_;
    const m = m_ * m_ * m_;
    const s = s_ * s_ * s_;
    return [
      Math.max(0, Math.min(1, 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
      Math.max(0, Math.min(1, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
      Math.max(0, Math.min(1, -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s))
    ];
  }

  // 原始配色是给网页大屏调的柔和低彩度；手机上缩到一半后几乎读不出颜色，
  // 这里统一放大彩度（上限 0.4 防止超出 sRGB 色域）。
  const CHROMA_GAIN = 1.4;

  function color(token) {
    const [r, g, b] = linearSrgb([token[0], Math.min(0.4, token[1] * CHROMA_GAIN), token[2]]);
    return new THREE.Color().setRGB(r, g, b, THREE.LinearSRGBColorSpace);
  }

  const materialCache = new Map();

  function material(token, options) {
    const opts = options || {};
    const key = token.join(',') + JSON.stringify(opts);
    if (materialCache.has(key)) return materialCache.get(key);
    const mat = new THREE.MeshStandardMaterial({
      color: color(token),
      roughness: opts.roughness ?? 0.78,
      metalness: opts.metalness ?? 0.02,
      flatShading: opts.flatShading ?? true,
      transparent: opts.transparent ?? false,
      opacity: opts.opacity ?? 1,
      side: opts.side ?? THREE.FrontSide,
      emissive: opts.emissive ? color(opts.emissive) : new THREE.Color(0x000000),
      emissiveIntensity: opts.emissiveIntensity ?? 0
    });
    mat.userData.token = token;
    materialCache.set(key, mat);
    return mat;
  }

  function canvasTexture(width, height, draw) {
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d');
    draw(ctx, width, height);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.minFilter = THREE.LinearFilter;
    texture.magFilter = THREE.LinearFilter;
    texture.anisotropy = 4;
    return texture;
  }

  function roundRect(ctx, x, y, w, h, r) {
    const radius = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.arcTo(x + w, y, x + w, y + h, radius);
    ctx.arcTo(x + w, y + h, x, y + h, radius);
    ctx.arcTo(x, y + h, x, y, radius);
    ctx.arcTo(x, y, x + w, y, radius);
    ctx.closePath();
  }

  function makeScreenTexture() {
    return canvasTexture(900, 520, (ctx, w, h) => {
      const grad = ctx.createLinearGradient(0, 0, w, h);
      grad.addColorStop(0, '#dff6ec');
      grad.addColorStop(0.55, '#eff3d7');
      grad.addColorStop(1, '#f7dfc0');
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, w, h);

      ctx.fillStyle = 'rgba(255,255,255,0.68)';
      ctx.beginPath();
      ctx.arc(758, 102, 78, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = '#2b6858';
      ctx.font = '800 178px "Assistant Local", Arial, sans-serif';
      ctx.textBaseline = 'middle';
      ctx.letterSpacing = '-8px';
      ctx.fillText('ABC', 72, 244);
      ctx.letterSpacing = '0px';

      ctx.fillStyle = '#1c5f50';
      ctx.font = '700 42px "Assistant Local", Arial, sans-serif';
      ctx.fillText("Let's learn together!", 78, 370);

      const colors = ['#e4a06f', '#76b9a3', '#eac464'];
      for (let i = 0; i < 3; i += 1) {
        ctx.fillStyle = colors[i];
        roundRect(ctx, 78 + i * 94, 408, 72, 26, 13);
        ctx.fill();
      }

      ctx.strokeStyle = 'rgba(43,104,88,0.28)';
      ctx.lineWidth = 5;
      ctx.beginPath();
      ctx.arc(730, 386, 90, Math.PI * 1.05, Math.PI * 1.78);
      ctx.stroke();
    });
  }

  function makePictureTexture() {
    return canvasTexture(700, 460, (ctx, w, h) => {
      ctx.fillStyle = '#f6eddb';
      ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = '#dfa06d';
      ctx.beginPath();
      ctx.arc(512, 156, 106, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#5e9d8a';
      ctx.beginPath();
      ctx.moveTo(90, 372);
      ctx.lineTo(90, 242);
      ctx.arc(225, 242, 135, Math.PI, 0, true);
      ctx.lineTo(360, 372);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = '#eac464';
      ctx.beginPath();
      ctx.arc(480, 336, 48, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = '#1f594d';
      ctx.lineWidth = 7;
      ctx.beginPath();
      ctx.moveTo(92, 398);
      ctx.bezierCurveTo(245, 306, 396, 442, 610, 350);
      ctx.stroke();
    });
  }

  function makeClockTexture() {
    return canvasTexture(512, 512, (ctx, w, h) => {
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = '#fbf6ea';
      ctx.beginPath();
      ctx.arc(256, 256, 248, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = '#2c6658';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.font = '700 58px "Assistant Local", Arial, sans-serif';
      ctx.fillText('12', 256, 84);
      ctx.fillText('3', 428, 256);
      ctx.fillText('6', 256, 428);
      ctx.fillText('9', 84, 256);

      for (let i = 0; i < 60; i += 1) {
        const angle = (i / 60) * Math.PI * 2;
        const major = i % 5 === 0;
        const r1 = major ? 196 : 207;
        const r2 = 218;
        ctx.strokeStyle = major ? '#2c6658' : '#d7cbb8';
        ctx.lineWidth = major ? 4 : 2;
        ctx.beginPath();
        ctx.moveTo(256 + Math.sin(angle) * r1, 256 - Math.cos(angle) * r1);
        ctx.lineTo(256 + Math.sin(angle) * r2, 256 - Math.cos(angle) * r2);
        ctx.stroke();
      }
    });
  }

  function makeWindowTexture() {
    return canvasTexture(600, 700, (ctx, w, h) => {
      const grad = ctx.createLinearGradient(0, 0, 0, h);
      grad.addColorStop(0, '#dfeff5');
      grad.addColorStop(0.55, '#cfe8dc');
      grad.addColorStop(1, '#b8d6b8');
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = 'rgba(255,250,220,0.78)';
      ctx.beginPath();
      ctx.arc(418, 148, 92, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = 'rgba(128,174,147,0.32)';
      ctx.beginPath();
      ctx.arc(180, 640, 260, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.42)';
      ctx.beginPath();
      ctx.ellipse(420, 310, 110, 32, -0.1, 0, Math.PI * 2);
      ctx.fill();
    });
  }

  function roundedRectShape(w, h, r) {
    const radius = Math.max(0.002, Math.min(r, w / 2 - 0.001, h / 2 - 0.001));
    const s = new THREE.Shape();
    s.moveTo(-w / 2 + radius, -h / 2);
    s.lineTo(w / 2 - radius, -h / 2);
    s.quadraticCurveTo(w / 2, -h / 2, w / 2, -h / 2 + radius);
    s.lineTo(w / 2, h / 2 - radius);
    s.quadraticCurveTo(w / 2, h / 2, w / 2 - radius, h / 2);
    s.lineTo(-w / 2 + radius, h / 2);
    s.quadraticCurveTo(-w / 2, h / 2, -w / 2, h / 2 - radius);
    s.lineTo(-w / 2, -h / 2 + radius);
    s.quadraticCurveTo(-w / 2, -h / 2, -w / 2 + radius, -h / 2);
    s.closePath();
    return s;
  }

  function roundedBoxGeometry(w, h, d, r) {
    const radius = Math.max(0.002, Math.min(r, w / 2 - 0.002, h / 2 - 0.002));
    const bevel = Math.min(0.018, d * 0.18, radius * 0.32);
    const shape = roundedRectShape(w, h, radius);
    const geo = new THREE.ExtrudeGeometry(shape, {
      depth: Math.max(0.002, d - bevel * 2),
      bevelEnabled: bevel > 0.001,
      bevelSegments: 2,
      steps: 1,
      bevelSize: bevel,
      bevelThickness: bevel,
      curveSegments: 4
    });
    geo.center();
    geo.computeVertexNormals();
    return geo;
  }

  function roundedPlaneGeometry(w, d, r) {
    const shape = roundedRectShape(w, d, r);
    const geo = new THREE.ShapeGeometry(shape, 5);
    geo.rotateX(-Math.PI / 2);
    geo.center();
    return geo;
  }

  function roundedRingGeometry(w, d, r, thickness) {
    const shape = roundedRectShape(w, d, r);
    const hole = roundedRectShape(w - thickness * 2, d - thickness * 2, Math.max(0.01, r - thickness));
    shape.holes.push(hole);
    const geo = new THREE.ShapeGeometry(shape, 5);
    geo.rotateX(-Math.PI / 2);
    geo.center();
    return geo;
  }

  function addMesh(parent, geometry, mat, position, cast, receive) {
    const mesh = new THREE.Mesh(geometry, mat);
    if (position) mesh.position.set(position[0] || 0, position[1] || 0, position[2] || 0);
    mesh.castShadow = cast !== false;
    mesh.receiveShadow = receive !== false;
    parent.add(mesh);
    return mesh;
  }

  function box(parent, w, h, d, r, mat, x, y, z, cast) {
    return addMesh(parent, roundedBoxGeometry(w, h, d, r), mat, [x, y, z], cast);
  }

  function cylinder(parent, rt, rb, h, seg, mat, x, y, z, cast) {
    return addMesh(parent, new THREE.CylinderGeometry(rt, rb, h, seg), mat, [x, y, z], cast);
  }

  // 给实体墙/挂墙件打上朝向标记，room-scene 每帧按相机方位整组隐藏。
  function wallSide(mesh, side) {
    mesh.userData.wallSide = side;
    return mesh;
  }

  function buildRoomShell(root) {
    const base = box(root, 11.9, 0.28, 6.38, 0.09, material(RGB.trim), ROOM.centerX, -0.14, 0, false);
    base.receiveShadow = true;

    // 15 条地板等距铺满 -3.995 .. 7.63：原来固定 0.8 步距会伸到 x≈8.00，和东翼地板共面。
    const floorStart = -3.995;
    const floorEnd = ROOM.maxX - 0.02;
    const plankStep = (floorEnd - floorStart) / 15;
    for (let i = 0; i < 15; i += 1) {
      const x = floorStart + plankStep / 2 + i * plankStep;
      const token = i % 3 === 0 ? RGB.floorA : i % 3 === 1 ? RGB.floorB : RGB.floorC;
      const plank = addMesh(
        root,
        new THREE.BoxGeometry(plankStep - 0.005, 0.036, 5.92),
        material(token, { roughness: 0.86 }),
        [x, FLOOR_Y - 0.018, 0],
        false
      );
      plank.receiveShadow = true;
    }

    const wallMat = material(RGB.wall, { roughness: 0.9 });
    const trimMat = material(RGB.trim, { roughness: 0.82 });
    const plankMat = material(RGB.woodLight, { roughness: 0.82 });

    wallSide(box(root, 2.29, 3, 0.16, 0.04, wallMat, -2.855, 1.5, -3.06, false), 'north');
    wallSide(box(root, 4.04, 3, 0.16, 0.04, wallMat, 1.94, 1.5, -3.06, false), 'north');
    // 北墙向东延长，作为开放厨房的背景墙
    wallSide(box(root, 3.7, 3, 0.16, 0.04, wallMat, 5.85, 1.5, -3.06, false), 'north');
    wallSide(box(root, 1.64, 0.92, 0.16, 0.035, wallMat, -0.9, 0.46, -3.06, false), 'north');
    wallSide(box(root, 1.64, 0.62, 0.16, 0.035, wallMat, -0.9, 2.69, -3.06, false), 'north');
    wallSide(box(root, 0.16, 3, 6, 0.04, wallMat, -4.06, 1.5, 0, false), 'west');

    wallSide(box(root, 11.56, 0.09, 0.07, 0.025, plankMat, ROOM.centerX, 0.095, -2.94, false), 'north');
    wallSide(box(root, 0.07, 0.09, 5.9, 0.025, plankMat, -3.94, 0.095, 0, false), 'west');
    wallSide(box(root, 11.56, 0.025, 0.03, 0.012, trimMat, ROOM.centerX, 0.9, -2.955, false), 'north');

    const wainscot = material(RGB.wallCool, { roughness: 0.9 });
    wallSide(box(root, 3.82, 0.74, 0.035, 0.03, wainscot, 1.96, 0.47, -2.955, false), 'north');
    wallSide(box(root, 3.86, 0.035, 0.055, 0.012, plankMat, 1.96, 0.855, -2.94, false), 'north');
    for (let i = 0; i < 4; i += 1) {
      wallSide(box(root, 0.022, 0.63, 0.025, 0.008, material(RGB.trim, { roughness: 0.9 }), 0.55 + i * 0.94, 0.43, -2.932, false), 'north');
    }

    const doorTrim = material(RGB.trim, { roughness: 0.82 });
    wallSide(box(root, 11.6, 0.06, 0.05, 0.018, doorTrim, ROOM.centerX, 2.96, -2.98, false), 'north');
  }

  function buildWindowAndCurtain(objects, hitboxes, root) {
    const windowGroup = new THREE.Group();
    windowGroup.name = 'OBJ_window';
    windowGroup.position.set(-0.9, FLOOR_Y, -2.9);
    windowGroup.userData = objectMeta('window');
    windowGroup.userData.wallSide = 'north';
    root.add(windowGroup);
    objects.push(windowGroup);

    const frameMat = material(RGB.cream, { roughness: 0.72 });
    const innerFrame = material(RGB.trim, { roughness: 0.7 });
    box(windowGroup, 1.82, 0.08, 0.12, 0.025, frameMat, 0, 2.38, 0);
    box(windowGroup, 1.82, 0.08, 0.12, 0.025, frameMat, 0, 0.92, 0);
    box(windowGroup, 0.08, 1.5, 0.12, 0.025, frameMat, -0.85, 1.65, 0);
    box(windowGroup, 0.08, 1.5, 0.12, 0.025, frameMat, 0.85, 1.65, 0);
    box(windowGroup, 0.045, 1.5, 0.075, 0.015, innerFrame, 0, 1.65, 0.03);
    box(windowGroup, 1.62, 0.04, 0.075, 0.015, innerFrame, 0, 1.66, 0.03);
    box(windowGroup, 1.94, 0.08, 0.26, 0.025, frameMat, 0, 0.87, 0.08);

    const exteriorMat = new THREE.MeshBasicMaterial({ map: makeWindowTexture() });
    addMesh(windowGroup, new THREE.PlaneGeometry(1.58, 1.48), exteriorMat, [0, 1.65, -0.09], false, false);
    const glassMat = material(RGB.glass, {
      transparent: true,
      opacity: 0.2,
      roughness: 0.08,
      metalness: 0.05,
      flatShading: false,
      side: THREE.DoubleSide
    });
    addMesh(windowGroup, new THREE.PlaneGeometry(1.57, 1.47), glassMat, [0, 1.65, 0.075], false, false);
    addMesh(windowGroup, new THREE.BoxGeometry(0.2, 0.03, 0.04), material(RGB.metal), [0.6, 1.08, 0.15], false, false);

    hit(windowGroup, 'window', 1.9, 1.72, 0.3, 0, 1.66, 0, hitboxes);

    const curtainGroup = new THREE.Group();
    curtainGroup.name = 'OBJ_curtain';
    curtainGroup.position.set(-0.9, FLOOR_Y, -2.72);
    curtainGroup.userData = objectMeta('curtain');
    curtainGroup.userData.wallSide = 'north';
    root.add(curtainGroup);
    objects.push(curtainGroup);

    const rodMat = material(RGB.woodDark, { roughness: 0.5, metalness: 0.12 });
    const rod = addMesh(curtainGroup, new THREE.CylinderGeometry(0.027, 0.027, 2.36, 16), rodMat, [0, 2.53, 0], true);
    rod.rotation.z = Math.PI / 2;
    cylinder(curtainGroup, 0.06, 0.06, 0.07, 14, rodMat, -1.18, 2.53, 0);
    cylinder(curtainGroup, 0.06, 0.06, 0.07, 14, rodMat, 1.18, 2.53, 0);

    const curtainMat = material(RGB.coral, {
      roughness: 0.9,
      flatShading: true,
      side: THREE.DoubleSide
    });
    const panels = [-1, 1];
    panels.forEach((side) => {
      const geo = new THREE.PlaneGeometry(0.5, 2.44, 14, 1);
      const pos = geo.attributes.position;
      for (let i = 0; i < pos.count; i += 1) {
        const x = pos.getX(i);
        pos.setZ(i, Math.sin((x / 0.5 + 0.5) * Math.PI * 3.2) * 0.05 + 0.02);
      }
      geo.computeVertexNormals();
      const panel = addMesh(curtainGroup, geo, curtainMat, [side * 0.83, 1.27, 0], true, false);
      panel.rotation.y = side * 0.06;
      hit(curtainGroup, 'curtain', 0.62, 2.44, 0.24, side * 0.83, 1.27, 0.02, hitboxes);
    });
  }

  function buildSofa(objects, hitboxes, root) {
    const g = objectGroup('sofa', -1.56, FLOOR_Y, -0.1, root);
    objects.push(g);
    const body = material(RGB.sofa);
    const bodyDark = material(RGB.sofaDark);
    const bodyLight = material(RGB.sofaLight);
    const wood = material(RGB.woodDark);

    [-0.33, 0.33].forEach((x) => {
      [-0.96, 0.96].forEach((z) => {
        cylinder(g, 0.045, 0.05, 0.2, 10, wood, x, 0.1, z);
      });
    });
    box(g, 0.96, 0.28, 2.3, 0.1, bodyDark, 0, 0.28, 0);
    box(g, 0.9, 0.2, 1.06, 0.09, bodyLight, -0.02, 0.5, -0.55);
    box(g, 0.9, 0.2, 1.06, 0.09, bodyLight, -0.02, 0.5, 0.55);
    box(g, 0.24, 0.83, 2.3, 0.1, bodyDark, 0.37, 0.73, 0);
    const topRoll = addMesh(g, new THREE.CylinderGeometry(0.12, 0.12, 2.3, 18), body, [0.37, 1.15, 0], true);
    topRoll.rotation.x = Math.PI / 2;
    [-1.14, 1.14].forEach((z) => {
      box(g, 0.99, 0.36, 0.2, 0.08, bodyDark, 0, 0.57, z);
      const armRoll = addMesh(g, new THREE.CylinderGeometry(0.1, 0.1, 0.86, 16), body, [0, 0.75, z], true);
      armRoll.rotation.z = Math.PI / 2;
    });
    [-0.56, 0.56].forEach((z) => {
      const backCushion = box(g, 0.16, 0.5, 1.02, 0.07, bodyLight, 0.23, 0.83, z);
      backCushion.rotation.z = -0.05;
    });
    box(g, 0.015, 0.06, 2.2, 0.007, material(RGB.cream), -0.47, 0.42, 0, false);
    hit(g, 'sofa', 1.04, 0.6, 2.5, 0, 0.32, 0, hitboxes);
    hit(g, 'sofa', 0.3, 1.14, 2.4, 0.36, 0.68, 0, hitboxes);
    hit(g, 'sofa', 0.96, 0.78, 0.2, 0, 0.62, -1.15, hitboxes);
    hit(g, 'sofa', 0.96, 0.78, 0.2, 0, 0.62, 1.15, hitboxes);
  }

  function buildCushion(objects, hitboxes, root) {
    const g = objectGroup('cushion', -1.46, FLOOR_Y, -1.05, root);
    objects.push(g);
    g.rotation.y = 0.16;
    const mat = material(RGB.mustard);
    const pillow = box(g, 0.16, 0.58, 0.56, 0.1, mat, 0, 1.16, 0);
    pillow.rotation.z = -0.1;
    const patch = box(g, 0.012, 0.3, 0.31, 0.035, material(RGB.cream), -0.087, 1.18, 0, false);
    patch.rotation.z = -0.1;
    const button = cylinder(g, 0.023, 0.023, 0.01, 12, material(RGB.woodDark), -0.096, 1.18, 0, false);
    button.rotation.z = Math.PI / 2;
    hit(g, 'cushion', 0.34, 0.66, 0.64, 0, 1.16, 0, hitboxes);
  }

  function buildCoffeeTable(objects, hitboxes, root) {
    const g = objectGroup('coffee_table', -2.71, FLOOR_Y, 0.02, root);
    objects.push(g);
    const wood = material(RGB.woodLight);
    const woodDark = material(RGB.wood);
    box(g, 1.24, 0.11, 0.78, 0.12, wood, 0, 0.44, 0);
    box(g, 1.04, 0.055, 0.6, 0.06, woodDark, 0, 0.19, 0);
    [-0.49, 0.49].forEach((x) => {
      [-0.27, 0.27].forEach((z) => {
        box(g, 0.07, 0.39, 0.07, 0.025, woodDark, x, 0.205, z);
      });
    });
    hit(g, 'coffee_table', 1.32, 0.52, 0.86, 0, 0.25, 0, hitboxes);
  }

  function buildRemote(objects, hitboxes, root) {
    const g = objectGroup('remote_control', -3.02, FLOOR_Y + 0.505, 0.18, root);
    objects.push(g);
    g.rotation.y = -0.34;
    const shell = material(RGB.ink, { roughness: 0.55, metalness: 0.08 });
    box(g, 0.17, 0.04, 0.4, 0.04, shell, 0, 0.025, 0);
    const buttonMat = material(RGB.cream, { roughness: 0.65 });
    const accentMat = material(RGB.coral, { roughness: 0.6 });
    [
      [-0.035, -0.1, 0.035, 0.035, buttonMat],
      [0.035, -0.1, 0.035, 0.035, buttonMat],
      [0, -0.035, 0.085, 0.025, buttonMat],
      [-0.035, 0.035, 0.035, 0.035, buttonMat],
      [0.035, 0.035, 0.035, 0.035, buttonMat],
      [0, 0.11, 0.04, 0.04, accentMat]
    ].forEach(([x, z, w, d, mat]) => {
      box(g, w, 0.012, d, 0.008, mat, x, 0.049, z, false);
    });
    hit(g, 'remote_control', 0.28, 0.18, 0.46, 0, 0.13, 0, hitboxes);
  }

  function buildRug(objects, hitboxes, root) {
    const g = objectGroup('rug', -2.23, FLOOR_Y, 0.1, root);
    objects.push(g);
    box(g, 3.36, 0.024, 2.65, 0.18, material(RGB.rug), 0, 0.012, 0, false);
    addMesh(g, roundedPlaneGeometry(3.06, 2.35, 0.14), material(RGB.rugInner), [0, 0.028, 0], false);
    addMesh(g, roundedRingGeometry(3.14, 2.43, 0.16, 0.022), material(RGB.teal, { roughness: 0.82 }), [0, 0.031, 0], false);
    hit(g, 'rug', 3.42, 0.12, 2.7, 0, 0.05, 0, hitboxes);
  }

  function buildFloorLamp(objects, hitboxes, root) {
    const g = objectGroup('floor_lamp', -3.47, FLOOR_Y, 1.56, root);
    objects.push(g);
    const stand = material(RGB.metal, { roughness: 0.45, metalness: 0.28 });
    cylinder(g, 0.23, 0.26, 0.055, 24, stand, 0, 0.03, 0);
    cylinder(g, 0.023, 0.023, 1.42, 12, stand, 0, 0.77, 0);
    const shadeMat = material(RGB.cream, {
      roughness: 0.82,
      emissive: [92, 0.08, 78],
      emissiveIntensity: 0.22,
      side: THREE.DoubleSide
    });
    const shade = addMesh(g, new THREE.CylinderGeometry(0.19, 0.31, 0.35, 22, 1, true), shadeMat, [0, 1.55, 0], true);
    shade.rotation.y = 0.3;
    cylinder(g, 0.19, 0.19, 0.012, 22, shadeMat, 0, 1.73, 0, false);
    addMesh(g, new THREE.SphereGeometry(0.105, 14, 10), material(RGB.cream, { emissive: [95, 0.1, 82], emissiveIntensity: 1.6 }), [0, 1.44, 0], false);
    const glow = new THREE.PointLight(color(RGB.cream), 7, 4.4, 2);
    glow.position.set(0, 1.47, 0);
    g.add(glow);
    hit(g, 'floor_lamp', 0.64, 1.86, 0.64, 0, 0.94, 0, hitboxes);
  }

  function buildBookshelf(objects, hitboxes, root) {
    const g = objectGroup('bookshelf', -2.58, FLOOR_Y, -2.72, root);
    objects.push(g);
    const frame = material(RGB.woodLight);
    const back = material(RGB.woodDark);
    box(g, 1.42, 2.06, 0.07, 0.02, back, 0, 1.03, -0.16);
    box(g, 0.07, 2.08, 0.36, 0.02, frame, -0.69, 1.04, 0);
    box(g, 0.07, 2.08, 0.36, 0.02, frame, 0.69, 1.04, 0);
    box(g, 1.45, 0.07, 0.38, 0.02, frame, 0, 0.045, 0);
    box(g, 1.45, 0.07, 0.38, 0.02, frame, 0, 2.055, 0);
    [0.71, 1.38].forEach((y) => {
      box(g, 1.38, 0.055, 0.34, 0.015, frame, 0, y, 0);
    });

    const bookColors = [RGB.coral, RGB.teal, RGB.mustard, RGB.green, RGB.cream, RGB.sofaDark];
    const spinePositions = [
      [-0.5, 0.28], [-0.35, 0.32], [-0.19, 0.26], [0.01, 0.34], [0.17, 0.29],
      [-0.48, 0.25], [-0.33, 0.3], [-0.17, 0.28], [0.0, 0.32], [0.18, 0.25], [0.34, 0.3]
    ];
    spinePositions.forEach(([x, h], i) => {
      const shelfY = i < 5 ? 0.75 : 1.42;
      const mat = material(bookColors[i % bookColors.length], { roughness: 0.85 });
      const book = box(g, 0.11, h, 0.24, 0.012, mat, x, shelfY + h / 2, 0.045, false);
      book.rotation.z = i % 4 === 0 ? 0.04 : 0;
    });
    const bowl = addMesh(g, new THREE.CylinderGeometry(0.11, 0.08, 0.07, 16), material(RGB.cream), [0.4, 1.77, 0.04], false);
    bowl.rotation.y = 0.4;
    hit(g, 'bookshelf', 1.58, 2.18, 0.55, 0, 1.08, 0, hitboxes);
  }

  function buildOpenBook(objects, hitboxes, root) {
    const g = objectGroup('book', -2.53, FLOOR_Y + 0.505, 0.08, root);
    objects.push(g);
    g.rotation.y = 0.3;
    const cover = material(RGB.coral);
    const pages = material(RGB.cream, { roughness: 0.95 });
    const leftCover = box(g, 0.32, 0.018, 0.42, 0.015, cover, -0.17, 0.018, 0, false);
    leftCover.rotation.z = 0.13;
    const rightCover = box(g, 0.32, 0.018, 0.42, 0.015, cover, 0.17, 0.018, 0, false);
    rightCover.rotation.z = -0.13;
    const leftPage = box(g, 0.29, 0.03, 0.38, 0.01, pages, -0.16, 0.04, 0, false);
    leftPage.rotation.z = 0.13;
    const rightPage = box(g, 0.29, 0.03, 0.38, 0.01, pages, 0.16, 0.04, 0, false);
    rightPage.rotation.z = -0.13;
    box(g, 0.025, 0.05, 0.4, 0.008, material(RGB.woodDark), 0, 0.035, 0, false);
    for (let i = 0; i < 3; i += 1) {
      box(g, 0.23, 0.004, 0.008, 0.002, material(RGB.trim), -0.16, 0.058 + i * 0.007, -0.08 + i * 0.09, false);
      box(g, 0.23, 0.004, 0.008, 0.002, material(RGB.trim), 0.16, 0.058 + i * 0.007, -0.08 + i * 0.09, false);
    }
    hit(g, 'book', 0.66, 0.2, 0.54, 0, 0.13, 0, hitboxes);
  }

  function buildPlant(objects, hitboxes, root) {
    const g = objectGroup('plant', -3.43, FLOOR_Y, 2.38, root);
    objects.push(g);
    const pot = material(RGB.coral, { roughness: 0.9 });
    cylinder(g, 0.27, 0.2, 0.42, 18, pot, 0, 0.21, 0);
    cylinder(g, 0.29, 0.29, 0.06, 18, pot, 0, 0.44, 0);
    cylinder(g, 0.245, 0.245, 0.025, 18, material(RGB.woodDark), 0, 0.405, 0, false);
    const stemMat = material(RGB.greenDark);
    for (let i = 0; i < 7; i += 1) {
      const angle = (i / 7) * Math.PI * 2;
      const height = 0.55 + (i % 3) * 0.2;
      const stem = addMesh(g, new THREE.CylinderGeometry(0.012, 0.017, height, 7), stemMat, [
        Math.cos(angle) * 0.05,
        0.42 + height / 2,
        Math.sin(angle) * 0.05
      ], true);
      stem.rotation.z = Math.cos(angle) * 0.2;
      stem.rotation.x = Math.sin(angle) * 0.2;

      const leafMat = material(i % 2 === 0 ? RGB.green : RGB.greenDark);
      const leaf = addMesh(g, new THREE.SphereGeometry(0.18, 9, 6), leafMat, [
        Math.cos(angle) * (0.17 + (i % 3) * 0.03),
        0.63 + (i % 3) * 0.21,
        Math.sin(angle) * (0.17 + (i % 3) * 0.03)
      ], true);
      leaf.scale.set(1.46, 0.32, 0.7);
      leaf.rotation.y = -angle;
      leaf.rotation.z = 0.35 + (i % 2) * 0.12;
    }
    hit(g, 'plant', 0.86, 1.6, 0.86, 0, 0.8, 0, hitboxes);
  }

  function buildTVStand(objects, hitboxes, root) {
    const g = objectGroup('tv_stand', -3.58, FLOOR_Y, -0.15, root);
    objects.push(g);
    const wood = material(RGB.woodLight);
    const dark = material(RGB.woodDark);
    box(g, 0.4, 0.5, 1.92, 0.07, wood, 0, 0.29, 0);
    box(g, 0.45, 0.06, 1.98, 0.025, material(RGB.cream), 0, 0.555, 0);
    [-0.46, 0.46].forEach((z) => {
      box(g, 0.015, 0.36, 0.78, 0.015, material(RGB.cream, { roughness: 0.8 }), 0.208, 0.29, z, false);
      const handle = addMesh(g, new THREE.CylinderGeometry(0.012, 0.012, 0.18, 8), dark, [0.226, 0.31, z], false);
      handle.rotation.x = Math.PI / 2;
    });
    [-0.75, 0.75].forEach((z) => {
      box(g, 0.1, 0.07, 0.1, 0.02, dark, -0.1, 0.035, z);
    });
    hit(g, 'tv_stand', 0.58, 0.66, 2.08, 0, 0.32, 0, hitboxes);
  }

  function buildTV(objects, hitboxes, root) {
    const g = new THREE.Group();
    g.name = 'OBJ_tv';
    g.position.set(-3.73, FLOOR_Y + 1.13, -0.15);
    g.rotation.y = Math.PI / 2;
    g.userData = objectMeta('tv');
    root.add(g);
    objects.push(g);

    const bezel = material(RGB.ink, { roughness: 0.58, metalness: 0.15 });
    box(g, 1.83, 1.03, 0.075, 0.035, bezel, 0, 0, 0);
    const screenMat = new THREE.MeshBasicMaterial({ map: makeScreenTexture() });
    addMesh(g, new THREE.PlaneGeometry(1.68, 0.89), screenMat, [0, 0, 0.044], false, false);
    const shine = new THREE.MeshBasicMaterial({
      color: color(RGB.cream),
      transparent: true,
      opacity: 0.1,
      depthWrite: false
    });
    addMesh(g, new THREE.PlaneGeometry(0.52, 0.9), shine, [-0.53, 0, 0.047], false, false);
    box(g, 0.08, 0.1, 0.035, 0.01, bezel, 0, -0.56, 0);
    box(g, 0.48, 0.035, 0.26, 0.015, bezel, 0, -0.57, 0);
    hit(g, 'tv', 1.98, 1.16, 0.28, 0, 0, 0.01, hitboxes);
  }

  function buildPicture(objects, hitboxes, root) {
    const g = new THREE.Group();
    g.name = 'OBJ_picture';
    g.position.set(-3.94, 2.3, -0.15);
    g.rotation.y = Math.PI / 2;
    g.userData = objectMeta('picture');
    root.add(g);
    objects.push(g);

    const frame = material(RGB.woodLight);
    box(g, 1.08, 0.08, 0.085, 0.025, frame, 0, 0.35, 0);
    box(g, 1.08, 0.08, 0.085, 0.025, frame, 0, -0.35, 0);
    box(g, 0.08, 0.78, 0.085, 0.025, frame, -0.5, 0, 0);
    box(g, 0.08, 0.78, 0.085, 0.025, frame, 0.5, 0, 0);
    box(g, 0.96, 0.68, 0.02, 0.01, material(RGB.cream), 0, 0, 0.035, false);
    const art = new THREE.MeshBasicMaterial({ map: makePictureTexture() });
    addMesh(g, new THREE.PlaneGeometry(0.9, 0.62), art, [0, 0, 0.049], false, false);
    hit(g, 'picture', 1.2, 0.9, 0.22, 0, 0, 0, hitboxes);
  }

  function buildClock(objects, hitboxes, root) {
    const g = new THREE.Group();
    g.name = 'OBJ_clock';
    g.position.set(1.0, 2.3, -2.9);
    g.userData = objectMeta('clock');
    root.add(g);
    objects.push(g);

    const body = addMesh(g, new THREE.CylinderGeometry(0.33, 0.33, 0.085, 32), material(RGB.cream), [0, 0, 0], true);
    body.rotation.x = Math.PI / 2;
    const rim = addMesh(g, new THREE.TorusGeometry(0.3, 0.025, 10, 32), material(RGB.tealDark), [0, 0, 0.052], true);
    const faceMat = new THREE.MeshBasicMaterial({ map: makeClockTexture(), transparent: true });
    addMesh(g, new THREE.CircleGeometry(0.292, 36), faceMat, [0, 0, 0.056], false, false);
    const handMat = material(RGB.ink, { roughness: 0.5 });
    const hour = new THREE.Group();
    hour.position.z = 0.069;
    const hourStick = box(hour, 0.024, 0.17, 0.014, 0.006, handMat, 0, 0.075, 0, false);
    hour.rotation.z = 2.54;
    g.add(hour);
    const minute = new THREE.Group();
    minute.position.z = 0.076;
    box(minute, 0.018, 0.235, 0.012, 0.005, handMat, 0, 0.105, 0, false);
    minute.rotation.z = 0.42;
    g.add(minute);
    const second = new THREE.Group();
    second.position.z = 0.083;
    box(second, 0.012, 0.25, 0.008, 0.003, material(RGB.coral), 0, 0.11, 0, false);
    second.rotation.z = -1.2;
    g.add(second);
    const cap = addMesh(g, new THREE.CylinderGeometry(0.035, 0.035, 0.02, 16), material(RGB.coral), [0, 0, 0.085], false);
    cap.rotation.x = Math.PI / 2;
    hit(g, 'clock', 0.76, 0.76, 0.2, 0, 0, 0, hitboxes);
  }

  function buildAirConditioner(objects, hitboxes, root) {
    const g = objectGroup('air_conditioner', 3.12, 2.55, -2.9, root);
    objects.push(g);
    const shell = material(RGB.white, { roughness: 0.55 });
    box(g, 1.14, 0.35, 0.25, 0.09, shell, 0, 0, 0);
    box(g, 1.0, 0.24, 0.035, 0.06, material(RGB.cream, { roughness: 0.7 }), 0, 0, 0.135);
    for (let i = 0; i < 6; i += 1) {
      box(g, 0.68, 0.012, 0.012, 0.005, material(RGB.trim), -0.08, -0.08 + i * 0.026, 0.158, false);
    }
    const led = addMesh(g, new THREE.SphereGeometry(0.016, 10, 8), material(RGB.teal, { emissive: RGB.teal, emissiveIntensity: 1.2 }), [0.39, -0.1, 0.15], false);
    box(g, 1.02, 0.028, 0.14, 0.012, shell, 0, -0.15, 0.045).rotation.x = 0.2;
    hit(g, 'air_conditioner', 1.34, 0.56, 0.42, 0, 0, 0, hitboxes);
  }

  function buildTrashCan(objects, hitboxes, root) {
    const g = objectGroup('trash_can', 3.55, FLOOR_Y, 2.35, root);
    objects.push(g);
    cylinder(g, 0.25, 0.21, 0.52, 20, material(RGB.white), 0, 0.26, 0);
    cylinder(g, 0.265, 0.265, 0.07, 20, material(RGB.teal), 0, 0.56, 0);
    cylinder(g, 0.2, 0.2, 0.012, 20, material(RGB.ink, { roughness: 0.7 }), 0, 0.6, 0, false);
    box(g, 0.16, 0.035, 0.08, 0.015, material(RGB.woodDark), 0, 0.08, 0.25);
    box(g, 0.32, 0.035, 0.025, 0.01, material(RGB.tealDark), 0, 0.13, 0.24);
    hit(g, 'trash_can', 0.64, 0.78, 0.64, 0, 0.4, 0, hitboxes);
  }

  function buildDiningTable(objects, hitboxes, root) {
    const g = objectGroup('dining_table', 2.15, FLOOR_Y, -0.4, root);
    objects.push(g);
    const lightWood = material(RGB.woodLight);
    const darkWood = material(RGB.wood);
    const cream = material(RGB.cream);
    box(g, 1.94, 0.1, 1.12, 0.13, lightWood, 0, 0.75, 0);
    box(g, 1.72, 0.12, 0.9, 0.05, darkWood, 0, 0.67, 0);
    [-0.78, 0.78].forEach((x) => {
      [-0.41, 0.41].forEach((z) => {
        box(g, 0.105, 0.67, 0.105, 0.03, darkWood, x, 0.335, z);
      });
    });
    box(g, 1.5, 0.008, 0.3, 0.02, cream, 0, 0.805, 0, false);
    hit(g, 'dining_table', 2.04, 0.86, 1.24, 0, 0.43, 0, hitboxes);
  }

  function chair(parent, x, z, rotation) {
    const g = new THREE.Group();
    g.position.set(x, 0, z);
    g.rotation.y = rotation;
    parent.add(g);
    const seatMat = material(RGB.teal);
    const frame = material(RGB.woodLight);
    const pad = material(RGB.cream);
    box(g, 0.48, 0.08, 0.46, 0.07, seatMat, 0, 0.45, 0);
    box(g, 0.42, 0.035, 0.4, 0.05, pad, 0, 0.493, -0.01, false);
    box(g, 0.48, 0.54, 0.07, 0.06, seatMat, 0, 0.75, 0.215);
    box(g, 0.42, 0.08, 0.05, 0.03, pad, 0, 0.9, 0.22, false);
    [-0.18, 0.18].forEach((lx) => {
      [-0.16, 0.16].forEach((lz) => {
        box(g, 0.055, 0.43, 0.055, 0.018, frame, lx, 0.215, lz);
      });
    });
    box(g, 0.36, 0.04, 0.04, 0.012, frame, 0, 0.16, 0, false);
    return g;
  }

  function buildDiningChairs(objects, hitboxes, root) {
    const g = objectGroup('dining_chair', 2.15, FLOOR_Y, -0.4, root);
    objects.push(g);
    chair(g, -0.48, 0.98, 0);
    chair(g, 0.48, 0.98, 0);
    chair(g, -0.48, -0.98, Math.PI);
    chair(g, 0.48, -0.98, Math.PI);
    [[-0.48, 0.98], [0.48, 0.98], [-0.48, -0.98], [0.48, -0.98]].forEach(([x, z]) => {
      hit(g, 'dining_chair', 0.58, 0.46, 0.62, x, 0.24, z, hitboxes);
      hit(g, 'dining_chair', 0.54, 0.58, 0.2, x, 0.76, z + 0.2, hitboxes);
    });
    g.userData.labelAnchorLocal = new THREE.Vector3(0.48, 1.18, 0.98);
  }

  function buildPlate(objects, hitboxes, root) {
    const g = objectGroup('plate', 1.63, TABLE_TOP + 0.012, -0.5, root);
    objects.push(g);
    const ceramic = material(RGB.cream, { roughness: 0.48 });
    cylinder(g, 0.16, 0.15, 0.018, 26, ceramic, 0, 0, 0, false);
    const rim = addMesh(g, new THREE.TorusGeometry(0.145, 0.012, 8, 26), material(RGB.teal, { roughness: 0.55 }), [0, 0.015, 0], false);
    rim.rotation.x = Math.PI / 2;
    cylinder(g, 0.105, 0.105, 0.006, 24, material(RGB.white), 0, 0.016, 0, false);
    hit(g, 'plate', 0.42, 0.18, 0.42, 0, 0.07, 0, hitboxes);
  }

  function buildBowl(objects, hitboxes, root) {
    const g = objectGroup('bowl', 2.47, TABLE_TOP + 0.02, -0.62, root);
    objects.push(g);
    const mat = material(RGB.coral, { roughness: 0.5 });
    const bowl = addMesh(g, new THREE.CylinderGeometry(0.14, 0.075, 0.1, 22, 1, true), mat, [0, 0.06, 0], false);
    bowl.material.side = THREE.DoubleSide;
    cylinder(g, 0.08, 0.08, 0.018, 20, material(RGB.cream), 0, 0.012, 0, false);
    const rim = addMesh(g, new THREE.TorusGeometry(0.138, 0.009, 7, 22), material(RGB.cream), [0, 0.11, 0], false);
    rim.rotation.x = Math.PI / 2;
    hit(g, 'bowl', 0.38, 0.25, 0.38, 0, 0.12, 0, hitboxes);
  }

  function buildCup(objects, hitboxes, root) {
    const g = objectGroup('cup', 2.8, TABLE_TOP + 0.012, -0.33, root);
    objects.push(g);
    const mat = material(RGB.mustard, { roughness: 0.5 });
    cylinder(g, 0.07, 0.062, 0.12, 20, mat, 0, 0.06, 0, false);
    cylinder(g, 0.061, 0.061, 0.01, 20, material(RGB.woodDark, { roughness: 0.8 }), 0, 0.122, 0, false);
    const handle = addMesh(g, new THREE.TorusGeometry(0.05, 0.012, 7, 16), mat, [0.075, 0.07, 0], false);
    handle.rotation.y = 0;
    hit(g, 'cup', 0.28, 0.27, 0.28, 0, 0.12, 0, hitboxes);
  }

  function buildSpoon(objects, hitboxes, root) {
    const g = objectGroup('spoon', 1.94, TABLE_TOP + 0.015, -0.26, root);
    objects.push(g);
    g.rotation.y = -0.28;
    const metal = material(RGB.metal, { roughness: 0.32, metalness: 0.5 });
    box(g, 0.037, 0.012, 0.3, 0.014, metal, 0, 0.012, 0.05, false);
    const head = addMesh(g, new THREE.SphereGeometry(0.062, 16, 10), metal, [0, 0.022, -0.145], false);
    head.scale.set(1, 0.3, 1.45);
    hit(g, 'spoon', 0.22, 0.13, 0.48, 0, 0.05, 0, hitboxes);
  }

  function buildFork(objects, hitboxes, root) {
    const g = objectGroup('fork', 1.3, TABLE_TOP + 0.015, -0.27, root);
    objects.push(g);
    g.rotation.y = 0.26;
    const metal = material(RGB.metal, { roughness: 0.32, metalness: 0.5 });
    box(g, 0.034, 0.012, 0.29, 0.014, metal, 0, 0.012, 0.06, false);
    box(g, 0.075, 0.012, 0.055, 0.015, metal, 0, 0.015, -0.11, false);
    [-0.026, 0, 0.026].forEach((x) => {
      box(g, 0.012, 0.01, 0.09, 0.004, metal, x, 0.015, -0.17, false);
    });
    hit(g, 'fork', 0.23, 0.13, 0.48, 0, 0.05, 0, hitboxes);
  }

  function buildKettle(objects, hitboxes, root) {
    const g = objectGroup('kettle', 2.88, TABLE_TOP + 0.018, -0.80, root);
    objects.push(g);
    const shell = material(RGB.white, { roughness: 0.36, metalness: 0.1 });
    const accent = material(RGB.teal);
    const body = addMesh(g, new THREE.SphereGeometry(0.15, 20, 12), shell, [0, 0.14, 0], false);
    body.scale.set(1, 0.86, 1);
    cylinder(g, 0.105, 0.105, 0.025, 20, material(RGB.cream), 0, 0.018, 0, false);
    cylinder(g, 0.09, 0.1, 0.035, 18, accent, 0, 0.268, 0, false);
    addMesh(g, new THREE.SphereGeometry(0.034, 12, 8), accent, [0, 0.302, 0], false);
    const spout = addMesh(g, new THREE.CylinderGeometry(0.016, 0.036, 0.23, 10), shell, [0.18, 0.2, 0], false);
    spout.rotation.z = -0.95;
    const handle = addMesh(g, new THREE.TorusGeometry(0.095, 0.015, 7, 18, Math.PI * 1.38), accent, [-0.135, 0.19, 0], false);
    handle.rotation.z = -0.1;
    hit(g, 'kettle', 0.48, 0.44, 0.48, 0, 0.2, 0, hitboxes);
  }


  // ---------- 开放式厨房：北墙一字型操作台 + 中岛（参考 open-design 厨房方案） ----------

  function buildKitchenShell(root) {
    const tileMat = material(RGB.tile, { roughness: 0.58 });
    const tile = addMesh(root, new THREE.BoxGeometry(3.42, 0.016, 4.2), tileMat, [5.95, FLOOR_Y + 0.006, -0.9], false);
    tile.receiveShadow = true;

    const grout = material(RGB.trim, { roughness: 0.9 });
    for (let i = 0; i < 5; i += 1) {
      box(root, 3.42, 0.005, 0.014, 0.004, grout, 5.95, FLOOR_Y + 0.016, -2.94 + i * 0.82, false);
    }
    for (let i = 0; i < 4; i += 1) {
      box(root, 0.014, 0.005, 4.2, 0.004, grout, 4.4 + i * 0.88, FLOOR_Y + 0.016, -0.9, false);
    }

    // 台面后挡墙：石材压条 + 浅色墙砖
    wallSide(box(root, 3.5, 0.06, 0.06, 0.015, material(RGB.stone, { roughness: 0.45 }), 5.9, 0.95, -2.95, false), 'north');
    wallSide(box(root, 3.5, 0.56, 0.03, 0.01, material(RGB.tile, { roughness: 0.5 }), 5.9, 1.25, -2.97, false), 'north');
    for (let i = 0; i < 7; i += 1) {
      wallSide(box(root, 0.012, 0.56, 0.012, 0.004, material(RGB.trim, { roughness: 0.85 }), 4.3 + i * 0.5, 1.25, -2.955, false), 'north');
    }

    // 微波炉小搁板
    wallSide(box(root, 0.72, 0.05, 0.44, 0.02, material(RGB.woodLight, { roughness: 0.7 }), 7.04, 0.99, -2.62, false), 'north');
  }


  // 台面：柜体 + 石材台面，灶台/烤箱/洗碗机都嵌在这条橱柜上
  function buildKitchenRun(root) {
    const body = material(RGB.woodLight, { roughness: 0.7 });
    const stone = material(RGB.stoneDeep, { roughness: 0.42 });
    const dark = material(RGB.woodDark, { roughness: 0.85 });
    const brass = material(RGB.brass, { roughness: 0.32, metalness: 0.5 });

    box(root, 1.96, 0.1, 0.54, 0.03, dark, 6.31, 0.06, -2.73, false);
    box(root, 2.0, 0.78, 0.6, 0.03, body, 6.31, 0.48, -2.7, false);
    const top = box(root, 2.14, 0.055, 0.72, 0.03, stone, 6.31, 0.897, -2.68, false);
    top.receiveShadow = true;
    box(root, 2.0, 0.02, 0.02, 0.008, stone, 6.31, 0.875, -2.36, false);

    // 左侧柜门（烤箱和洗碗机占了右边两格）
    const door = box(root, 0.56, 0.62, 0.03, 0.02, material(RGB.cream, { roughness: 0.64 }), 5.62, 0.5, -2.385, false);
    door.receiveShadow = true;
    box(root, 0.44, 0.02, 0.03, 0.01, brass, 5.62, 0.74, -2.36, false);
    box(root, 0.03, 0.62, 0.03, 0.01, material(RGB.trim, { roughness: 0.8 }), 5.93, 0.5, -2.38, false);
  }

  function buildIsland(root) {
    const g = new THREE.Group();
    g.position.set(KITCHEN.islandX, FLOOR_Y, KITCHEN.islandZ);
    root.add(g);
    const body = material(RGB.woodLight, { roughness: 0.7 });
    const panel = material(RGB.cream, { roughness: 0.68 });
    const stone = material(RGB.stone, { roughness: 0.42 });
    box(g, 2.4, 0.86, 1.02, 0.06, body, 0, 0.43, 0);
    box(g, 2.48, 0.06, 1.1, 0.03, stone, 0, 0.89, 0);
    [-0.6, 0.6].forEach((x) => {
      box(g, 0.52, 0.66, 0.03, 0.02, panel, x, 0.46, 0.515, false);
    });
    box(g, 2.2, 0.06, 0.9, 0.02, material(RGB.woodDark, { roughness: 0.82 }), 0, 0.03, 0, false);
    box(g, 0.32, 0.02, 0.16, 0.01, material(RGB.metal), 0.86, 0.79, 0.28, false);
  }

  function buildHood(root) {
    const g = new THREE.Group();
    g.position.set(5.7, 1.56, -2.86);
    root.add(g);
    const steel = material(RGB.steel, { roughness: 0.3, metalness: 0.55 });
    box(g, 0.86, 0.12, 0.4, 0.035, steel, 0, 0, 0.03, false);
    box(g, 0.62, 0.09, 0.32, 0.025, material(RGB.metal, { roughness: 0.35, metalness: 0.5 }), 0, -0.09, 0.03, false);
    box(g, 0.3, 0.72, 0.24, 0.025, steel, 0, 0.44, -0.05, false);
    box(g, 0.18, 0.02, 0.12, 0.008, material(RGB.cream, { emissive: RGB.cream, emissiveIntensity: 0.9 }), 0, -0.068, 0.08, false);
  }

  function buildFridge(objects, hitboxes, root) {
    const g = objectGroup('fridge', 4.75, FLOOR_Y, -2.58, root);
    objects.push(g);
    const shell = material(RGB.appliance, { roughness: 0.44, metalness: 0.25 });
    const doorMat = material(RGB.appliance, { roughness: 0.38, metalness: 0.3 });
    const handle = material(RGB.metal, { roughness: 0.3, metalness: 0.6 });
    box(g, 0.92, 1.94, 0.7, 0.07, shell, 0, 0.97, 0);
    box(g, 0.87, 0.62, 0.04, 0.02, doorMat, 0, 1.56, 0.345, false);
    box(g, 0.87, 1.16, 0.04, 0.02, doorMat, 0, 0.63, 0.345, false);
    box(g, 0.87, 0.012, 0.02, 0.006, material(RGB.ink, { roughness: 0.7 }), 0, 1.245, 0.355, false);
    box(g, 0.03, 0.34, 0.03, 0.01, handle, 0.34, 1.56, 0.38, false);
    box(g, 0.03, 0.5, 0.03, 0.01, handle, 0.34, 0.66, 0.38, false);
    [-0.24, 0.02].forEach((x, i) => {
      box(g, 0.11, 0.09, 0.006, 0.01, material([78, 0.1, 40 + i * 30], { roughness: 0.6 }), x, 0.95 + i * 0.16, 0.368, false);
    });
    hit(g, 'fridge', 0.98, 2.0, 0.82, 0, 1.0, 0, hitboxes);
  }

  function buildStove(objects, hitboxes, root) {
    const g = objectGroup('stove', 5.7, KITCHEN.counterTop, KITCHEN.counterZ, root);
    objects.push(g);
    const glassMat = material(RGB.glassDark, { roughness: 0.22, metalness: 0.25 });
    const steel = material(RGB.metal, { roughness: 0.35, metalness: 0.55 });
    box(g, 0.8, 0.026, 0.48, 0.03, glassMat, 0, 0.013, 0, false);
    [-0.19, 0.19].forEach((dx) => {
      const outer = addMesh(g, new THREE.TorusGeometry(0.082, 0.013, 6, 22), steel, [dx, 0.03, 0.02], false);
      outer.rotation.x = Math.PI / 2;
      const inner = addMesh(g, new THREE.TorusGeometry(0.042, 0.009, 6, 18), material(RGB.ink, { roughness: 0.5 }), [dx, 0.032, 0.02], false);
      inner.rotation.x = Math.PI / 2;
    });
    for (let i = 0; i < 3; i += 1) {
      const knob = cylinder(g, 0.022, 0.022, 0.028, 12, steel, -0.24 + i * 0.24, 0.03, -0.2, false);
      knob.rotation.x = Math.PI / 2;
    }
    hit(g, 'stove', 1.0, 0.2, 0.62, 0, 0.05, 0, hitboxes);
  }

  function buildOven(objects, hitboxes, root) {
    const g = objectGroup('oven', 6.34, FLOOR_Y, -2.36, root);
    objects.push(g);
    const frame = material(RGB.glassDark, { roughness: 0.3, metalness: 0.25 });
    const steel = material(RGB.metal, { roughness: 0.3, metalness: 0.6 });
    box(g, 0.64, 0.64, 0.07, 0.03, frame, 0, 0.54, 0);
    box(g, 0.54, 0.36, 0.02, 0.02, material(RGB.ink, { roughness: 0.32 }), 0, 0.49, 0.045, false);
    box(g, 0.5, 0.035, 0.06, 0.014, steel, 0, 0.79, 0.055, false);
    box(g, 0.42, 0.012, 0.03, 0.006, material(RGB.coral, { emissive: RGB.coral, emissiveIntensity: 0.35 }), 0, 0.87, 0.045, false);
    hit(g, 'oven', 0.7, 0.72, 0.24, 0, 0.54, 0, hitboxes);
  }

  function buildDishwasher(objects, hitboxes, root) {
    const g = objectGroup('dishwasher', 6.98, FLOOR_Y, -2.36, root);
    objects.push(g);
    const panel = material(RGB.appliance, { roughness: 0.37, metalness: 0.3 });
    box(g, 0.6, 0.76, 0.05, 0.02, panel, 0, 0.42, 0);
    box(g, 0.52, 0.04, 0.045, 0.012, material(RGB.metal), 0, 0.75, 0.035, false);
    box(g, 0.36, 0.02, 0.02, 0.008, material(RGB.teal, { emissive: RGB.teal, emissiveIntensity: 0.7 }), 0, 0.67, 0.03, false);
    hit(g, 'dishwasher', 0.68, 0.82, 0.24, 0, 0.42, 0, hitboxes);
  }

  function buildCabinet(objects, hitboxes, root) {
    const g = objectGroup('cabinet', 6.6, 1.68, -2.8, root);
    objects.push(g);
    const door = material(RGB.cream, { roughness: 0.66 });
    const line = material(RGB.trim, { roughness: 0.82 });
    const brass = material(RGB.brass, { roughness: 0.32, metalness: 0.5 });
    box(g, 1.2, 0.72, 0.36, 0.03, door, 0, 0, 0);
    box(g, 0.02, 0.66, 0.02, 0.008, line, 0, 0, 0.19, false);
    [-0.3, 0.3].forEach((x) => {
      box(g, 0.15, 0.028, 0.03, 0.01, brass, x, -0.07, 0.2, false);
    });
    box(g, 1.12, 0.02, 0.07, 0.008, material(RGB.cream, { emissive: RGB.cream, emissiveIntensity: 0.85 }), 0, -0.38, 0.16, false);
    hit(g, 'cabinet', 1.3, 0.82, 0.4, 0, 0, 0, hitboxes);
  }

  function buildMicrowave(objects, hitboxes, root) {
    const g = objectGroup('microwave', 7.04, 1.14, -2.62, root);
    objects.push(g);
    const shell = material(RGB.appliance, { roughness: 0.42, metalness: 0.28 });
    box(g, 0.54, 0.32, 0.38, 0.03, shell, 0, 0.16, 0);
    box(g, 0.3, 0.22, 0.02, 0.012, material(RGB.glassDark, { roughness: 0.28 }), -0.08, 0.16, 0.2, false);
    box(g, 0.14, 0.26, 0.03, 0.012, material(RGB.cream, { roughness: 0.6 }), 0.19, 0.16, 0.19, false);
    box(g, 0.022, 0.2, 0.025, 0.008, material(RGB.metal), 0.12, 0.16, 0.21, false);
    hit(g, 'microwave', 0.72, 0.5, 0.52, 0, 0.16, 0, hitboxes);
  }

  function buildToaster(objects, hitboxes, root) {
    const g = objectGroup('toaster', 6.95, KITCHEN.islandTop, -0.88, root);
    objects.push(g);
    const body = material(RGB.coral, { roughness: 0.52 });
    box(g, 0.3, 0.19, 0.19, 0.05, body, 0, 0.095, 0);
    box(g, 0.24, 0.03, 0.13, 0.02, material(RGB.ink, { roughness: 0.65 }), 0, 0.19, 0, false);
    box(g, 0.05, 0.03, 0.045, 0.012, material(RGB.metal), 0.17, 0.12, 0, false);
    hit(g, 'toaster', 0.52, 0.36, 0.4, 0, 0.12, 0, hitboxes);
  }

  function buildPot(objects, hitboxes, root) {
    const g = objectGroup('pot', 5.5, KITCHEN.counterTop + 0.026, -2.72, root);
    objects.push(g);
    const steel = material(RGB.steel, { roughness: 0.3, metalness: 0.6 });
    cylinder(g, 0.145, 0.13, 0.2, 22, steel, 0, 0.1, 0);
    cylinder(g, 0.15, 0.15, 0.025, 22, material(RGB.steel, { roughness: 0.28, metalness: 0.62 }), 0, 0.21, 0, false);
    cylinder(g, 0.03, 0.03, 0.035, 12, material(RGB.ink, { roughness: 0.5 }), 0, 0.24, 0, false);
    [-1, 1].forEach((side) => {
      const ear = addMesh(g, new THREE.TorusGeometry(0.045, 0.012, 6, 14, Math.PI), material(RGB.ink, { roughness: 0.6 }), [side * 0.16, 0.14, 0], false);
      ear.rotation.z = side > 0 ? -Math.PI / 2 : Math.PI / 2;
    });
    hit(g, 'pot', 0.5, 0.38, 0.48, 0, 0.14, 0, hitboxes);
  }

  function buildPan(objects, hitboxes, root) {
    const g = objectGroup('pan', 5.98, KITCHEN.counterTop + 0.026, -2.66, root);
    objects.push(g);
    const dark = material(RGB.glassDark, { roughness: 0.42, metalness: 0.3 });
    cylinder(g, 0.16, 0.14, 0.07, 22, dark, 0, 0.035, 0);
    const rim = addMesh(g, new THREE.TorusGeometry(0.16, 0.012, 6, 22), dark, [0, 0.07, 0], false);
    rim.rotation.x = Math.PI / 2;
    const stem = box(g, 0.26, 0.03, 0.05, 0.015, material(RGB.ink, { roughness: 0.5 }), 0.25, 0.09, 0, false);
    stem.rotation.z = 0.1;
    hit(g, 'pan', 0.56, 0.24, 0.5, 0.06, 0.09, 0, hitboxes);
  }

  function buildKnife(objects, hitboxes, root) {
    const g = objectGroup('knife', 6.45, KITCHEN.islandTop, -0.54, root);
    objects.push(g);
    box(g, 0.16, 0.2, 0.1, 0.03, material(RGB.woodLight, { roughness: 0.72 }), 0, 0.1, 0);
    [-0.04, 0, 0.04].forEach((x, i) => {
      const blade = box(g, 0.012, 0.24, 0.022, 0.005, material(RGB.metal, { roughness: 0.24, metalness: 0.62 }), x, 0.19, 0.02 + i * 0.008, false);
      blade.rotation.z = (i - 1) * 0.1;
    });
    hit(g, 'knife', 0.44, 0.42, 0.38, 0, 0.17, 0, hitboxes);
  }

  function barStool(parent, x, z) {
    const g = new THREE.Group();
    g.position.set(x, 0, z);
    parent.add(g);
    const legMat = material(RGB.ink, { roughness: 0.34, metalness: 0.5 });
    cylinder(g, 0.2, 0.2, 0.075, 20, material(RGB.sofa, { roughness: 0.62 }), 0, 0.63, 0);
    cylinder(g, 0.21, 0.21, 0.02, 20, material(RGB.sofaDark, { roughness: 0.6 }), 0, 0.585, 0, false);
    [[-0.13, -0.13], [0.13, -0.13], [-0.13, 0.13], [0.13, 0.13]].forEach(([lx, lz]) => {
      box(g, 0.032, 0.6, 0.032, 0.01, legMat, lx, 0.29, lz);
    });
    const ring = addMesh(g, new THREE.TorusGeometry(0.15, 0.012, 6, 20), legMat, [0, 0.2, 0], false);
    ring.rotation.x = Math.PI / 2;
    return g;
  }

  function buildBarStools(objects, hitboxes, root) {
    const g = objectGroup('stool', 5.95, FLOOR_Y, 0.18, root);
    objects.push(g);
    barStool(g, -0.62, 0);
    barStool(g, 0.62, 0);
    [-0.62, 0.62].forEach((x) => {
      hit(g, 'stool', 0.5, 0.72, 0.5, x, 0.36, 0, hitboxes);
    });
    g.userData.labelAnchorLocal = new THREE.Vector3(0.62, 0.78, 0);
  }

  function buildSink(objects, hitboxes, root) {
    const g = objectGroup('sink', 5.4, KITCHEN.islandTop + 0.02, -0.88, root);
    objects.push(g);
    const steel = material(RGB.steel, { roughness: 0.26, metalness: 0.62 });
    box(g, 0.64, 0.025, 0.48, 0.03, steel, 0, 0.013, 0, false);
    box(g, 0.52, 0.02, 0.36, 0.02, material(RGB.ink, { roughness: 0.38 }), 0, 0.028, 0, false);
    box(g, 0.44, 0.016, 0.28, 0.015, material(RGB.steel, { roughness: 0.5, metalness: 0.4 }), 0, 0.036, 0, false);
    cylinder(g, 0.022, 0.022, 0.28, 12, steel, -0.24, 0.18, -0.16, false);
    box(g, 0.26, 0.03, 0.03, 0.012, steel, -0.12, 0.31, -0.16, false);
    box(g, 0.03, 0.07, 0.03, 0.01, steel, -0.01, 0.28, -0.16, false);
    hit(g, 'sink', 0.7, 0.4, 0.54, 0, 0.16, 0, hitboxes);
  }

  // ==================== 东翼扩建：儿童房 + 主卧 ====================
  // 两间房各自建在自己的局部坐标里：房间中心 = (0, 0)，北墙在 z = -hd，东墙 +hw，西墙 -hw，南侧剖开。
  // 场景层按房间切换显示，所以两间房都可以放在原点，取景各自独立，不会被 19m 外的大房间拖小。
  const BEDROOM_CEIL = 2.8;

  function bedroomShell(root, hw, hd, win, door) {
    const base = box(root, hw * 2 + 0.34, 0.28, hd * 2 + 0.38, 0.09, material(RGB.trim), 0, -0.14, 0.02, false);
    base.receiveShadow = true;

    const planks = Math.max(4, Math.round((hw * 2) / 0.56));
    const pw = (hw * 2) / planks;
    for (let i = 0; i < planks; i += 1) {
      const token = i % 3 === 0 ? RGB.floorA : i % 3 === 1 ? RGB.floorB : RGB.floorC;
      const plank = addMesh(
        root,
        new THREE.BoxGeometry(pw - 0.012, 0.036, hd * 2 - 0.04),
        material(token, { roughness: 0.86 }),
        [-hw + pw / 2 + i * pw, FLOOR_Y - 0.018, 0],
        false
      );
      plank.receiveShadow = true;
    }

    const wallMat = material(RGB.wall, { roughness: 0.9 });
    const trimMat = material(RGB.trim, { roughness: 0.82 });
    const plankMat = material(RGB.woodLight, { roughness: 0.82 });
    const h = BEDROOM_CEIL;
    const zWall = -hd - 0.08;
    const outer = hw + 0.16;

    // 北墙在窗洞处断开：左侧、右侧、窗下、窗上四块
    wallSide(box(root, win.x0 + outer, h, 0.16, 0.04, wallMat, (-outer + win.x0) / 2, h / 2, zWall, false), 'north');
    wallSide(box(root, outer - win.x1, h, 0.16, 0.04, wallMat, (win.x1 + outer) / 2, h / 2, zWall, false), 'north');
    // 窗下墙比窗台矮 6cm：两块顶面同高会 z-fighting
    wallSide(box(root, win.x1 - win.x0, win.y0 - 0.06, 0.16, 0.035, wallMat, (win.x0 + win.x1) / 2, (win.y0 - 0.06) / 2, zWall, false), 'north');
    wallSide(box(root, win.x1 - win.x0, h - win.y1, 0.16, 0.035, wallMat, (win.x0 + win.x1) / 2, (win.y1 + h) / 2, zWall, false), 'north');

    // 窗台、玻璃、竖梃
    wallSide(box(root, win.x1 - win.x0 + 0.1, 0.05, 0.2, 0.02, trimMat, (win.x0 + win.x1) / 2, win.y0 - 0.02, zWall + 0.03, false), 'north');
    wallSide(box(root, win.x1 - win.x0 - 0.03, win.y1 - win.y0 - 0.03, 0.02, 0.01,
      material(RGB.glass, { roughness: 0.25, transparent: true, opacity: 0.5 }),
      (win.x0 + win.x1) / 2, (win.y0 + win.y1) / 2, zWall + 0.05, false), 'north');
    wallSide(box(root, 0.05, win.y1 - win.y0, 0.06, 0.015, trimMat, (win.x0 + win.x1) / 2, (win.y0 + win.y1) / 2, zWall + 0.06, false), 'north');

    // 只砌北墙和西墙：东侧和南侧剖开（相机就在 +x/+z 一侧，砌东墙会把整间房挡掉）
    // 西墙是通往客餐厅的共享墙：按 door 数据留门洞（门套 + 打开约 80° 的门扇），门扇随西墙一起显隐。
    const westX = -hw - 0.08;
    const wallH = h - 0.02;
    if (!door) {
      wallSide(box(root, 0.16, wallH, hd * 2 + 0.16, 0.04, wallMat, westX, wallH / 2, 0, false), 'west');
    } else {
      const zMin = -hd - 0.08;
      const zMax = hd + 0.08;
      const opening = door.z1 - door.z0;
      wallSide(box(root, 0.16, wallH, door.z0 - zMin, 0.04, wallMat, westX, wallH / 2, (zMin + door.z0) / 2, false), 'west');
      wallSide(box(root, 0.16, wallH, zMax - door.z1, 0.04, wallMat, westX, wallH / 2, (door.z1 + zMax) / 2, false), 'west');
      // 门洞上方的过梁
      wallSide(box(root, 0.16, wallH - door.height, opening, 0.04, wallMat,
        westX, door.height + (wallH - door.height) / 2, (door.z0 + door.z1) / 2, false), 'west');

      // 门套：两侧竖框 + 上槛，稍微凸出墙面盖住接缝
      wallSide(box(root, 0.2, door.height, 0.06, 0.012, trimMat, westX, door.height / 2, door.z0, false), 'west');
      wallSide(box(root, 0.2, door.height, 0.06, 0.012, trimMat, westX, door.height / 2, door.z1, false), 'west');
      wallSide(box(root, 0.2, 0.07, opening + 0.11, 0.012, trimMat, westX, door.height + 0.035, (door.z0 + door.z1) / 2, false), 'west');

      // 门扇：铰链在北侧门套，朝房间里侧（+x）打开
      const leaf = new THREE.Group();
      leaf.position.set(-hw + 0.045, FLOOR_Y, door.z0 + 0.02);
      leaf.rotation.y = door.open;
      root.add(leaf);
      const leafH = door.height - 0.05;
      const leafW = opening - 0.04;
      const leafMat = material(RGB.woodLight, { roughness: 0.68 });
      const panelMat = material(RGB.cream, { roughness: 0.74 });
      wallSide(box(leaf, 0.045, leafH, leafW, 0.008, leafMat, 0, leafH / 2, leafW / 2, true), 'west');
      [0.45, 1.28].forEach((cy, i) => {
        const ph = i === 0 ? 0.5 : 0.8;
        wallSide(box(leaf, 0.012, ph, leafW * 0.58, 0.004, panelMat, 0.026, cy, leafW / 2, false), 'west');
        wallSide(box(leaf, 0.012, ph, leafW * 0.58, 0.004, panelMat, -0.026, cy, leafW / 2, false), 'west');
      });
      [0.055, -0.055].forEach((hx) => {
        const grip = cylinder(leaf, 0.012, 0.012, 0.11, 8,
          material(RGB.brass, { metalness: 0.45, roughness: 0.35 }), hx, 1.02, leafW - 0.11, false);
        grip.rotation.z = Math.PI / 2;
        wallSide(grip, 'west');
      });
    }

    // 踢脚线（北 / 西）：西侧在门洞处断开
    wallSide(box(root, hw * 2, 0.09, 0.07, 0.025, plankMat, 0, 0.095, -hd + 0.04, false), 'north');
    if (!door) {
      wallSide(box(root, 0.07, 0.09, hd * 2, 0.025, plankMat, -hw + 0.04, 0.095, 0, false), 'west');
    } else {
      wallSide(box(root, 0.07, 0.09, door.z0 + hd, 0.025, plankMat, -hw + 0.04, 0.095, (door.z0 - hd) / 2, false), 'west');
      wallSide(box(root, 0.07, 0.09, hd - door.z1, 0.025, plankMat, -hw + 0.04, 0.095, (door.z1 + hd) / 2, false), 'west');
    }

    // 窗帘杆 + 两片布（装饰件，不参与点击）
    const rodMat = material(RGB.woodDark, { roughness: 0.7 });
    const rod = addMesh(root, new THREE.CylinderGeometry(0.018, 0.018, win.x1 - win.x0 + 0.62, 10), rodMat,
      [(win.x0 + win.x1) / 2, win.y1 + 0.16, zWall + 0.11], false);
    rod.rotation.z = Math.PI / 2;
    wallSide(rod, 'north');
    const cloth = material(RGB.linen, { roughness: 0.92 });
    [win.x0 - 0.18, win.x1 + 0.18].forEach((x, i) => {
      const panel = box(root, 0.3, win.y1 - win.y0 + 0.34, 0.055, 0.02, cloth, x, (win.y0 + win.y1) / 2 + 0.06, zWall + 0.1, false);
      panel.rotation.y = i === 0 ? -0.06 : 0.06;
      wallSide(panel, 'north');
    });
  }

  // —— 通用件：柜体、抽屉、台面 ——
  function cabinetBody(g, w, h, d, colorToken, doorColorToken, doors) {
    const body = material(colorToken);
    const doorMat = material(doorColorToken);
    box(g, w, h, d, 0.03, body, 0, h / 2, 0);
    box(g, w - 0.04, 0.05, d - 0.05, 0.015, material(RGB.cream), 0, 0.03, 0, false);
    const n = doors || 2;
    const seg = w / n;
    for (let i = 0; i < n; i += 1) {
      const cx = -w / 2 + seg / 2 + i * seg;
      box(g, seg - 0.05, h - 0.1, 0.02, 0.012, doorMat, cx, h / 2, d / 2 + 0.01, false);
      const handle = cylinder(g, 0.013, 0.013, 0.2, 8, material(RGB.brass, { metalness: 0.3, roughness: 0.4 }),
        cx + (i === 0 ? seg * 0.32 : -seg * 0.32), h / 2, d / 2 + 0.035, false);
      handle.rotation.x = 0;
    }
  }

  function drawerFront(g, w, h, x, y, z) {
    box(g, w, h, 0.025, 0.012, material(RGB.woodLight), x, y, z, false);
    const knob = cylinder(g, 0.022, 0.022, 0.05, 10, material(RGB.brass, { metalness: 0.35, roughness: 0.38 }), x, y, z + 0.03, false);
    knob.rotation.x = Math.PI / 2;
  }

  // —— 儿童房 12 件 ——
  function buildChildRoom(root) {
    const hw = 2.2;
    const hd = 1.8;
    const objects = [];
    const hitboxes = [];
    bedroomShell(root, hw, hd, { x0: -0.86, x1: -0.08, y0: 0.95, y1: 2.15 }, LAYOUT.doors.child);

    // 1 床：床头靠北墙，床尾朝南
    (function childBed() {
      const g = objectGroup('bed', 0.5, FLOOR_Y, -0.85, root);
      objects.push(g);
      const frame = material(RGB.wood);
      const quilt = material(RGB.teal);
      const sheet = material(RGB.cream);
      const legMat = material(RGB.woodDark);
      [-0.42, 0.42].forEach((x) => {
        [-0.82, 0.82].forEach((z) => {
          cylinder(g, 0.038, 0.042, 0.2, 8, legMat, x, 0.1, z);
        });
      });
      box(g, 1.0, 0.2, 1.9, 0.05, frame, 0, 0.24, 0);
      box(g, 0.94, 0.3, 1.8, 0.09, sheet, 0, 0.49, 0);
      box(g, 0.98, 0.07, 1.02, 0.05, quilt, 0, 0.665, 0.34);
      box(g, 0.98, 0.16, 0.1, 0.035, quilt, 0, 0.6, 0.83, false);
      box(g, 1.0, 0.66, 0.07, 0.03, frame, 0, 0.5, -0.915);
      const pillow = box(g, 0.54, 0.16, 0.34, 0.08, material(RGB.sky), 0, 0.7, -0.7);
      pillow.rotation.x = -0.06;
      hit(g, 'bed', 1.02, 0.42, 1.94, 0, 0.4, 0, hitboxes);
      hit(g, 'bed', 1.0, 0.68, 0.12, 0, 0.5, -0.92, hitboxes);
    }());

    // 2 书桌：靠北墙东段，桌面朝南
    (function childDesk() {
      const g = objectGroup('desk', 1.6, FLOOR_Y, -1.15, root);
      objects.push(g);
      const wood = material(RGB.wood);
      const woodDark = material(RGB.woodDark);
      box(g, 1.2, 0.055, 0.5, 0.02, wood, 0, 0.72, 0);
      [-0.56, 0.56].forEach((x) => {
        box(g, 0.05, 0.7, 0.46, 0.015, woodDark, x, 0.35, 0);
      });
      box(g, 1.1, 0.06, 0.42, 0.015, woodDark, 0, 0.14, 0, false);
      box(g, 0.46, 0.16, 0.44, 0.02, wood, 0.3, 0.6, 0);
      drawerFront(g, 0.4, 0.12, 0.3, 0.6, 0.235);
      // 桌上的书和笔筒
      box(g, 0.26, 0.035, 0.2, 0.012, material(RGB.coral), -0.3, 0.765, 0.02, false);
      box(g, 0.24, 0.03, 0.18, 0.01, material(RGB.mustard), -0.29, 0.797, 0.01, false);
      cylinder(g, 0.045, 0.045, 0.12, 12, material(RGB.sky), 0.06, 0.81, -0.1, false);
      hit(g, 'desk', 1.24, 0.78, 0.54, 0, 0.38, 0, hitboxes);
    }());

    // 3 椅子：面朝书桌
    (function childChair() {
      const g = objectGroup('chair', 1.725, FLOOR_Y, -0.6, root);
      objects.push(g);
      const body = material(RGB.mustard);
      const legMat = material(RGB.woodDark);
      box(g, 0.45, 0.055, 0.42, 0.04, body, 0, 0.44, 0);
      const back = box(g, 0.42, 0.4, 0.05, 0.03, body, 0, 0.66, 0.185);
      back.rotation.x = -0.08;
      [-0.18, 0.18].forEach((x) => {
        [-0.16, 0.16].forEach((z) => {
          cylinder(g, 0.018, 0.02, 0.43, 8, legMat, x, 0.215, z);
        });
      });
      hit(g, 'chair', 0.52, 0.9, 0.5, 0, 0.45, 0.02, hitboxes);
    }());

    // 4 衣柜：北墙西段，2m 高
    (function childWardrobe() {
      const g = objectGroup('wardrobe', -1.5, FLOOR_Y, -1.45, root);
      objects.push(g);
      cabinetBody(g, 1.2, 2.0, 0.55, RGB.woodDark, RGB.woodLight, 2);
      box(g, 1.26, 0.05, 0.6, 0.02, material(RGB.woodDark), 0, 2.02, 0, false);
      hit(g, 'wardrobe', 1.26, 2.02, 0.62, 0, 1.01, 0, hitboxes);
    }());

    // 5 玩具箱：箱体 + 掀盖
    (function childToyBox() {
      const g = objectGroup('toy_box', -0.61, FLOOR_Y, 0.34, root);
      objects.push(g);
      const body = material(RGB.coral);
      const bodyDark = material(RGB.woodDark);
      box(g, 0.5, 0.4, 0.35, 0.04, body, 0, 0.2, 0);
      box(g, 0.44, 0.03, 0.29, 0.012, material(RGB.coral), 0, 0.05, 0, false);
      const lid = box(g, 0.54, 0.05, 0.39, 0.03, bodyDark, 0, 0.44, -0.02);
      lid.rotation.x = -0.16;
      box(g, 0.07, 0.09, 0.02, 0.01, material(RGB.brass, { metalness: 0.3 }), 0, 0.36, 0.18, false);
      // 露在外面的两个玩具
      box(g, 0.1, 0.1, 0.1, 0.02, material(RGB.mustard), -0.12, 0.42, 0.02, false).rotation.y = 0.4;
      box(g, 0.09, 0.09, 0.09, 0.02, material(RGB.sky), 0.1, 0.42, 0.0, false).rotation.y = -0.3;
      hit(g, 'toy_box', 0.56, 0.52, 0.42, 0, 0.26, 0, hitboxes);
    }());

    // 6 圆地毯
    (function childRoundRug() {
      const g = objectGroup('round_rug', -1.35, FLOOR_Y, -0.35, root);
      objects.push(g);
      addMesh(g, new THREE.CylinderGeometry(0.75, 0.75, 0.024, 36), material(RGB.mustard), [0, 0.012, 0], false);
      addMesh(g, new THREE.CylinderGeometry(0.62, 0.62, 0.026, 36), material(RGB.cream), [0, 0.014, 0], false);
      addMesh(g, new THREE.CylinderGeometry(0.5, 0.5, 0.028, 36), material(RGB.mustard), [0, 0.016, 0], false);
      hit(g, 'round_rug', 1.5, 0.16, 1.5, 0, 0.06, 0, hitboxes);
    }());

    // 7 书柜：西墙，开口朝东
    (function childBookcase() {
      const g = objectGroup('bookcase', -1.94, FLOOR_Y, 0.95, root);
      objects.push(g);
      const body = material(RGB.sky);
      const bodyDark = material(RGB.sky, { roughness: 0.9 });
      g.rotation.y = Math.PI / 2;
      [-0.675, 0.675].forEach((x) => {
        box(g, 0.05, 1.1, 0.45, 0.02, bodyDark, x, 0.55, 0);
      });
      // 顶板 / 底板 / 背板都比侧板内缩 2cm：端面与侧面共面会 z-fighting
      box(g, 1.32, 0.045, 0.43, 0.015, bodyDark, 0, 1.07, 0);
      box(g, 1.32, 0.045, 0.43, 0.015, bodyDark, 0, 0.026, 0);
      box(g, 1.32, 1.06, 0.03, 0.01, material(RGB.sky, { roughness: 0.92 }), 0, 0.55, -0.2, false);
      // 两层可用的层板
      [0.39, 0.72].forEach((y) => {
        box(g, 1.26, 0.04, 0.4, 0.012, body, 0, y, 0.01, false);
      });
      const bookTokens = [RGB.coral, RGB.mustard, RGB.teal, RGB.green, RGB.sky, RGB.wood];
      let seed = 0;
      [0.115, 0.445, 0.775].forEach((y, row) => {
        for (let i = 0; i < 5; i += 1) {
          seed += 1;
          const w = 0.04 + ((seed * 7) % 5) * 0.008;
          box(g, w, 0.24 - (row === 2 ? 0.06 : 0), 0.3, 0.006,
            material(bookTokens[(seed + row) % bookTokens.length]),
            -0.42 + i * 0.17, y + 0.145, 0.06, false);
        }
      });
      hit(g, 'bookcase', 1.46, 1.14, 0.52, 0, 0.57, 0, hitboxes);
    }());

    // 8 搁板：矮架子，上面放小车
    (function childShelf() {
      const g = objectGroup('shelf', 1.28, FLOOR_Y, 1.34, root);
      objects.push(g);
      const body = material(RGB.cream);
      box(g, 0.7, 0.05, 0.26, 0.02, body, 0, 0.175, 0);
      [-0.33, 0.33].forEach((x) => {
        box(g, 0.04, 0.15, 0.26, 0.012, body, x, 0.075, 0, false);
      });
      box(g, 0.62, 0.03, 0.22, 0.01, material(RGB.woodLight), 0, 0.02, 0, false);
      // 架子上的小车和积木
      box(g, 0.16, 0.06, 0.09, 0.02, material(RGB.coral), -0.16, 0.225, 0, false);
      cylinder(g, 0.026, 0.026, 0.018, 10, material(RGB.ink), -0.22, 0.215, 0.04, false).rotation.z = Math.PI / 2;
      box(g, 0.09, 0.09, 0.09, 0.015, material(RGB.mustard), 0.14, 0.24, 0, false);
      box(g, 0.07, 0.07, 0.07, 0.012, material(RGB.teal), 0.24, 0.23, 0.01, false);
      hit(g, 'shelf', 0.74, 0.28, 0.32, 0, 0.14, 0, hitboxes);
    }());

    // 9 篮子
    (function childBasket() {
      const g = objectGroup('basket', 1.86, FLOOR_Y, 0.34, root);
      objects.push(g);
      const weave = material(RGB.woodLight);
      addMesh(g, new THREE.CylinderGeometry(0.17, 0.14, 0.28, 16), weave, [0, 0.14, 0], true);
      addMesh(g, new THREE.CylinderGeometry(0.15, 0.15, 0.03, 16), material(RGB.linen), [0, 0.285, 0], false);
      [-1, 1].forEach((dir) => {
        const handle = addMesh(g, new THREE.TorusGeometry(0.09, 0.012, 6, 12, Math.PI), material(RGB.woodDark),
          [dir * 0.15, 0.27, 0], false);
        handle.rotation.y = Math.PI / 2;
      });
      hit(g, 'basket', 0.4, 0.36, 0.4, 0, 0.18, 0, hitboxes);
    }());

    // 10 海报：书桌上方的北墙
    (function childPoster() {
      const g = objectGroup('poster', 1.62, 1.62, -1.72, root);
      objects.push(g);
      box(g, 0.62, 0.92, 0.03, 0.012, material(RGB.coral), 0, 0, 0);
      const art = addMesh(g, new THREE.PlaneGeometry(0.52, 0.82), new THREE.MeshStandardMaterial({
        map: makePictureTexture(),
        roughness: 0.92,
        metalness: 0
      }), [0, 0, 0.02], false);
      art.receiveShadow = false;
      hit(g, 'poster', 0.7, 1.0, 0.14, 0, 0, 0, hitboxes);
    }());

    // 11 毯子：叠好放在床尾
    (function childBlanket() {
      const g = objectGroup('blanket', 0.5, FLOOR_Y + 0.66, -0.25, root);
      objects.push(g);
      const cloth = material(RGB.mustard);
      box(g, 0.45, 0.09, 0.35, 0.04, cloth, 0, 0.045, 0);
      box(g, 0.44, 0.03, 0.11, 0.015, material(RGB.cream), 0, 0.1, -0.1, false);
      hit(g, 'blanket', 0.5, 0.18, 0.4, 0, 0.09, 0, hitboxes);
    }());

    // 12 玩具车：地板上
    (function childToyCar() {
      const g = objectGroup('toy_car', 0.62, FLOOR_Y, 1.05, root);
      objects.push(g);
      g.rotation.y = -0.5;
      const body = material(RGB.coral);
      box(g, 0.12, 0.06, 0.22, 0.03, body, 0, 0.06, 0);
      box(g, 0.1, 0.045, 0.1, 0.02, material(RGB.sky), 0, 0.1, -0.02);
      const wheel = material(RGB.ink, { roughness: 0.6 });
      [-0.065, 0.065].forEach((x) => {
        [-0.07, 0.07].forEach((z) => {
          const w = cylinder(g, 0.028, 0.028, 0.022, 10, wheel, x, 0.028, z, false);
          w.rotation.z = Math.PI / 2;
        });
      });
      hit(g, 'toy_car', 0.26, 0.2, 0.3, 0, 0.08, 0, hitboxes);
    }());

    if (objects.length !== 12) {
      throw new Error('儿童房应该有 12 件可点物品，实际 ' + objects.length);
    }
    return { objects, hitboxes };
  }

  // —— 主卧 12 件 ——
  // 相机从 +x/+z 方向看，所以靠东墙的家具只会露背面；衣柜、斗柜、镜子统一放在北墙和西墙。
  function buildMasterRoom(root) {
    const hw = 2.3;
    const hd = 1.8;
    const objects = [];
    const hitboxes = [];
    bedroomShell(root, hw, hd, { x0: -1.55, x1: -0.45, y0: 0.95, y1: 2.15 }, LAYOUT.doors.master);

    // 1 双人床
    (function masterBed() {
      const g = objectGroup('double_bed', 0.55, FLOOR_Y, -0.75, root);
      objects.push(g);
      const frame = material(RGB.wood);
      const quilt = material(RGB.sageGrey);
      const quiltDark = material(RGB.sageGreyDark);
      const sheet = material(RGB.cream);
      [-0.72, 0.72].forEach((x) => {
        [-0.88, 0.88].forEach((z) => {
          cylinder(g, 0.042, 0.046, 0.22, 8, material(RGB.woodDark), x, 0.11, z);
        });
      });
      box(g, 1.7, 0.22, 2.0, 0.05, frame, 0, 0.22, 0);
      box(g, 1.62, 0.32, 1.92, 0.1, sheet, 0, 0.5, 0);
      box(g, 1.66, 0.08, 1.24, 0.06, quilt, 0, 0.7, 0.32);
      // 折边要落在床垫和被子里面，端面一旦和床垫端面共面就会 z-fighting（真机表现为一直在闪）
      box(g, 1.66, 0.16, 0.12, 0.04, quiltDark, 0, 0.7, 0.85, false);
      const head = box(g, 1.7, 0.72, 0.08, 0.035, frame, 0, 0.5, -0.96);
      head.rotation.x = -0.04;
      // 靠床头的一只枕头是装饰件，可点的那只在东半边
      const deco = box(g, 0.66, 0.17, 0.36, 0.09, material(RGB.linen), -0.4, 0.74, -0.72);
      deco.rotation.x = -0.07;
      hit(g, 'double_bed', 1.72, 0.46, 2.04, 0, 0.42, 0, hitboxes);
      hit(g, 'double_bed', 1.7, 0.74, 0.14, 0, 0.5, -0.97, hitboxes);
    }());

    // 2 床头柜
    (function masterNightstand() {
      const g = objectGroup('nightstand', 1.48, FLOOR_Y, -1.5, root);
      objects.push(g);
      const wood = material(RGB.wood);
      box(g, 0.5, 0.5, 0.45, 0.03, wood, 0, 0.29, 0);
      [-0.19, 0.19].forEach((x) => {
        [-0.16, 0.16].forEach((z) => {
          cylinder(g, 0.018, 0.02, 0.08, 8, material(RGB.woodDark), x, 0.04, z);
        });
      });
      drawerFront(g, 0.4, 0.16, 0, 0.34, 0.235);
      box(g, 0.54, 0.03, 0.48, 0.012, material(RGB.woodDark), 0, 0.555, 0, false);
      hit(g, 'nightstand', 0.56, 0.6, 0.5, 0, 0.3, 0, hitboxes);
    }());

    // 3 台灯：坐在床头柜上
    (function masterLamp() {
      const g = objectGroup('lamp', 1.48, FLOOR_Y + 0.57, -1.38, root);
      objects.push(g);
      const brass = material(RGB.brass, { metalness: 0.3, roughness: 0.42 });
      cylinder(g, 0.085, 0.095, 0.03, 16, brass, 0, 0.015, 0);
      cylinder(g, 0.013, 0.013, 0.22, 10, brass, 0, 0.13, 0);
      const shade = addMesh(g, new THREE.CylinderGeometry(0.075, 0.135, 0.17, 8),
        material(RGB.mustard, { roughness: 0.85, emissive: RGB.mustard, emissiveIntensity: 0.12 }), [0, 0.3, 0], true);
      shade.rotation.y = 0.3;
      hit(g, 'lamp', 0.32, 0.44, 0.32, 0, 0.22, 0, hitboxes);
    }());

    // 4 枕头：床上的另一只
    (function masterPillow() {
      const g = objectGroup('pillow', 0.9, FLOOR_Y + 0.66, -1.4, root);
      objects.push(g);
      const cloth = material(RGB.linen);
      const p = box(g, 0.62, 0.17, 0.36, 0.09, cloth, 0, 0.085, 0);
      p.rotation.x = -0.07;
      box(g, 0.6, 0.02, 0.3, 0.03, material(RGB.linenDust), 0, 0.175, 0, false);
      hit(g, 'pillow', 0.68, 0.26, 0.42, 0, 0.1, 0, hitboxes);
    }());

    // 5 衣帽柜：西墙，门朝东
    (function masterCloset() {
      const g = objectGroup('closet', -2.02, FLOOR_Y, -1.1, root);
      objects.push(g);
      g.rotation.y = Math.PI / 2;
      cabinetBody(g, 1.2, 2.0, 0.55, RGB.wood, RGB.woodLight, 2);
      box(g, 1.26, 0.05, 0.6, 0.02, material(RGB.woodDark), 0, 2.02, 0, false);
      hit(g, 'closet', 1.26, 2.02, 0.6, 0, 1.01, 0, hitboxes);
    }());

    // 6 斗柜：西墙，三只抽屉朝东（梳妆台的位置）
    (function masterDresser() {
      const g = objectGroup('dresser', -2.05, FLOOR_Y, 0.8, root);
      objects.push(g);
      g.rotation.y = Math.PI / 2;
      const wood = material(RGB.woodDark);
      box(g, 0.7, 0.9, 0.5, 0.03, wood, 0, 0.5, 0);
      box(g, 0.74, 0.04, 0.54, 0.015, material(RGB.wood), 0, 0.97, 0, false);
      [0.2, 0.45, 0.7].forEach((y) => {
        drawerFront(g, 0.62, 0.19, 0, y, 0.255);
      });
      [-0.3, 0.3].forEach((x) => {
        [-0.2, 0.2].forEach((z) => {
          cylinder(g, 0.02, 0.022, 0.1, 8, material(RGB.woodDark), x, 0.05, z);
        });
      });
      hit(g, 'dresser', 0.76, 1.0, 0.56, 0, 0.5, 0, hitboxes);
    }());

    // 7 镜子：斗柜上方，镜面朝东
    (function masterMirror() {
      const g = objectGroup('mirror', -2.22, 1.55, 0.8, root);
      objects.push(g);
      g.rotation.y = Math.PI / 2;
      box(g, 0.62, 0.82, 0.05, 0.09, material(RGB.woodLight), 0, 0, 0);
      addMesh(g, new THREE.PlaneGeometry(0.5, 0.7),
        new THREE.MeshStandardMaterial({
          color: color(RGB.glass),
          roughness: 0.12,
          metalness: 0.62,
          emissive: color(RGB.sky),
          emissiveIntensity: 0.07
        }), [0, 0, 0.028], false);
      hit(g, 'mirror', 0.68, 0.9, 0.16, 0, 0, 0, hitboxes);
    }());

    // 8 凳子：镜子前面
    (function masterStool() {
      const g = objectGroup('stool_master', -1.42, FLOOR_Y, 0.8, root);
      objects.push(g);
      const seat = material(RGB.coral);
      addMesh(g, new THREE.CylinderGeometry(0.18, 0.18, 0.06, 8), seat, [0, 0.42, 0], true);
      addMesh(g, new THREE.CylinderGeometry(0.15, 0.15, 0.03, 8), material(RGB.coral, { roughness: 0.9 }), [0, 0.375, 0], false);
      for (let i = 0; i < 3; i += 1) {
        const angle = (i / 3) * Math.PI * 2 + 0.4;
        const leg = cylinder(g, 0.016, 0.02, 0.4, 8, material(RGB.woodDark),
          Math.sin(angle) * 0.11, 0.2, Math.cos(angle) * 0.11);
        leg.rotation.x = Math.cos(angle) * -0.08;
        leg.rotation.z = Math.sin(angle) * 0.08;
      }
      hit(g, 'stool_master', 0.4, 0.5, 0.4, 0, 0.25, 0, hitboxes);
    }());

    // 9 长凳：横在床尾
    (function masterBench() {
      const g = objectGroup('bench', 0.55, FLOOR_Y, 0.62, root);
      objects.push(g);
      const wood = material(RGB.woodDark);
      box(g, 1.2, 0.07, 0.35, 0.03, wood, 0, 0.42, 0);
      [-0.5, 0.5].forEach((x) => {
        [-0.13, 0.13].forEach((z) => {
          box(g, 0.055, 0.39, 0.055, 0.02, wood, x, 0.195, z);
        });
      });
      box(g, 1.04, 0.04, 0.04, 0.015, wood, 0, 0.2, 0, false);
      // 凳子上叠着一条薄毯
      box(g, 0.34, 0.06, 0.28, 0.02, material(RGB.linen), -0.3, 0.485, 0, false);
      hit(g, 'bench', 1.24, 0.5, 0.4, 0, 0.25, 0, hitboxes);
    }());

    // 10 地毯：床边
    (function masterRug() {
      const g = objectGroup('rug_master', 0.55, FLOOR_Y, 1.35, root);
      objects.push(g);
      addMesh(g, roundedPlaneGeometry(2.0, 0.75, 0.1), material(RGB.rug), [0, 0.014, 0], false);
      addMesh(g, roundedRingGeometry(1.86, 0.62, 0.09, 0.03), material(RGB.sageGrey, { roughness: 0.88 }), [0, 0.019, 0], false);
      hit(g, 'rug_master', 2.04, 0.14, 0.8, 0, 0.05, 0, hitboxes);
    }());

    // 11 暖气片：北墙东端
    (function masterHeater() {
      const g = objectGroup('heater', 2.02, FLOOR_Y, -1.68, root);
      objects.push(g);
      const metal = material(RGB.cream, { roughness: 0.55, metalness: 0.12 });
      for (let i = 0; i < 9; i += 1) {
        box(g, 0.035, 0.56, 0.15, 0.012, metal, -0.24 + i * 0.06, 0.34, 0, false);
      }
      box(g, 0.54, 0.045, 0.11, 0.015, metal, 0, 0.6, 0, false);
      box(g, 0.54, 0.045, 0.11, 0.015, metal, 0, 0.09, 0, false);
      [-0.16, 0.16].forEach((x) => {
        cylinder(g, 0.022, 0.022, 0.06, 8, material(RGB.metal), x, 0.06, 0, false);
      });
      hit(g, 'heater', 0.62, 0.66, 0.24, 0, 0.33, 0, hitboxes);
    }());

    // 12 相框：立在斗柜台面上
    (function masterPhotoFrame() {
      const g = objectGroup('photo_frame', -2.0, FLOOR_Y + 0.99, 0.67, root);
      objects.push(g);
      g.rotation.y = Math.PI / 2 - 0.22;
      box(g, 0.34, 0.27, 0.03, 0.015, material(RGB.wood), 0, 0.135, 0);
      addMesh(g, new THREE.PlaneGeometry(0.26, 0.19), new THREE.MeshStandardMaterial({
        map: makePictureTexture(),
        roughness: 0.94,
        metalness: 0
      }), [0, 0.135, 0.018], false);
      const stand = box(g, 0.1, 0.12, 0.015, 0.008, material(RGB.woodDark), 0, 0.07, -0.06, false);
      stand.rotation.x = 0.5;
      hit(g, 'photo_frame', 0.4, 0.34, 0.16, 0, 0.14, 0, hitboxes);
    }());

    if (objects.length !== 12) {
      throw new Error('主卧应该有 12 件可点物品，实际 ' + objects.length);
    }
    return { objects, hitboxes };
  }

  // 生活阳台：6.6m × 2.4m，北侧玻璃推拉门，南/东/西三侧栏杆，东端洗烘 + 收纳。
  function buildBalcony(root) {
    const objects = [];
    const hitboxes = [];

    const base = box(root, 6.9, 0.28, 2.58, 0.09, material(RGB.trim), 0, -0.142, 0.06, false);
    base.receiveShadow = true;

    const tileTexture = canvasTexture(512, 512, (ctx, w, h) => {
      ctx.fillStyle = '#d9d6cd';
      ctx.fillRect(0, 0, w, h);
      ctx.strokeStyle = '#b9b5aa';
      ctx.lineWidth = 4;
      const cells = 4;
      for (let i = 0; i <= cells; i += 1) {
        const p = (i * w) / cells;
        ctx.beginPath();
        ctx.moveTo(p, 0);
        ctx.lineTo(p, h);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(0, p);
        ctx.lineTo(w, p);
        ctx.stroke();
      }
      for (let i = 0; i < 260; i += 1) {
        ctx.fillStyle = i % 3 === 0 ? 'rgba(120,116,104,0.08)' : 'rgba(255,255,255,0.06)';
        ctx.fillRect(Math.random() * w, Math.random() * h, 3, 3);
      }
    });
    tileTexture.wrapS = THREE.RepeatWrapping;
    tileTexture.wrapT = THREE.RepeatWrapping;
    tileTexture.repeat.set(3, 1.5);
    const tileMat = new THREE.MeshStandardMaterial({ map: tileTexture, roughness: 0.86 });
    const floor = addMesh(root, new THREE.BoxGeometry(6.6, 0.036, 2.4), tileMat, [0, FLOOR_Y - 0.018, 0], false);
    floor.receiveShadow = true;

    // 北侧玻璃推拉门：两扇大玻璃 + 细金属框，不参与点击/藏墙。
    const frameMat = material(RGB.metal, { roughness: 0.35, metalness: 0.5 });
    box(root, 6.66, 0.09, 0.12, 0.02, frameMat, 0, 2.22, -1.2, false);
    box(root, 6.66, 0.07, 0.12, 0.02, frameMat, 0, 0.045, -1.2, false);
    [-3.26, -1.63, 0, 1.63, 3.26].forEach((x) => {
      box(root, 0.06, 2.2, 0.1, 0.02, frameMat, x, 1.1, -1.2, false);
    });
    const doorGlass = material(RGB.glass, {
      transparent: true,
      opacity: 0.22,
      roughness: 0.08,
      metalness: 0.05,
      side: THREE.DoubleSide
    });
    box(root, 3.08, 2.06, 0.03, 0.01, doorGlass, -1.63, 1.12, -1.19, false);
    box(root, 3.08, 2.06, 0.03, 0.01, doorGlass, 1.63, 1.12, -1.19, false);

    // 南/东/西栏杆 + 东端矮墙
    const railingGroup = objectGroup('railing', 0, FLOOR_Y, 0, root);
    objects.push(railingGroup);
    const rail = material(RGB.steel, { roughness: 0.32, metalness: 0.55 });
    const postXs = [-3.2, -2.1, -1.0, 0.1, 1.2, 2.3, 3.2];
    postXs.forEach((x) => {
      box(railingGroup, 0.05, 1.08, 0.05, 0.015, rail, x, 0.54, 1.18, false);
    });
    box(railingGroup, 6.44, 0.06, 0.08, 0.02, rail, 0, 1.1, 1.18, false);
    box(railingGroup, 6.44, 0.04, 0.05, 0.015, rail, 0, 0.16, 1.18, false);
    [-1.14, -0.4, 0.4, 1.14].forEach((z) => {
      box(railingGroup, 0.05, 1.08, 0.05, 0.015, rail, -3.2, 0.54, z, false);
      box(railingGroup, 0.05, 1.08, 0.05, 0.015, rail, 3.2, 0.54, z, false);
    });
    box(railingGroup, 0.08, 0.06, 2.36, 0.02, rail, -3.2, 1.1, 0, false);
    box(railingGroup, 0.08, 0.06, 2.36, 0.02, rail, 3.2, 1.1, 0, false);
    box(railingGroup, 0.05, 0.04, 2.36, 0.015, rail, -3.2, 0.16, 0, false);
    box(railingGroup, 0.05, 0.04, 2.36, 0.015, rail, 3.2, 0.16, 0, false);
    // 东端 1.2m 矮墙，给洗烘叠放做背景（不参与 north/west 藏墙）
    const lowWall = box(railingGroup, 0.12, 1.2, 1.8, 0.03, material(RGB.wall, { roughness: 0.9 }), 3.14, 0.6, -0.3, false);
    lowWall.receiveShadow = true;
    hit(railingGroup, 'railing', 6.5, 1.05, 0.16, 0, 0.55, 1.18, hitboxes);

    // 东端洗涤区
    const white = material(RGB.white, { roughness: 0.5 });
    const darkGlass = material(RGB.glassDark, { roughness: 0.22, metalness: 0.2 });

    const washer = objectGroup('washing_machine', 2.72, FLOOR_Y, -0.72, root);
    objects.push(washer);
    box(washer, 0.62, 0.9, 0.62, 0.05, white, 0, 0.45, 0, true);
    const washerDoor = addMesh(washer, new THREE.CylinderGeometry(0.21, 0.21, 0.03, 24), darkGlass, [0, 0.5, 0.315], false);
    washerDoor.rotation.x = Math.PI / 2;
    cylinder(washer, 0.245, 0.245, 0.02, 24, material(RGB.steel, { roughness: 0.3, metalness: 0.6 }), 0, 0.5, 0.33);
    cylinder(washer, 0.04, 0.04, 0.025, 12, material(RGB.ink), 0, 0.86, 0.31);
    hit(washer, 'washing_machine', 0.72, 1.0, 0.72, 0, 0.5, 0, hitboxes);

    const dryer = objectGroup('dryer', 2.72, FLOOR_Y + 0.98, -0.72, root);
    objects.push(dryer);
    box(dryer, 0.62, 0.86, 0.62, 0.05, white, 0, 0.43, 0, true);
    const dryerDoor = addMesh(dryer, new THREE.CylinderGeometry(0.2, 0.2, 0.03, 24), darkGlass, [0, 0.45, 0.315], false);
    dryerDoor.rotation.x = Math.PI / 2;
    cylinder(dryer, 0.05, 0.05, 0.02, 12, material(RGB.steel, { roughness: 0.3, metalness: 0.6 }), 0, 0.78, 0.31);
    hit(dryer, 'dryer', 0.72, 0.95, 0.72, 0, 0.45, 0, hitboxes);

    const cabinet = objectGroup('storage_cabinet', -2.88, FLOOR_Y, -0.2, root);
    objects.push(cabinet);
    // 收纳柜挪到西端清洁区，柜门转向东侧（+x），不再挡住东端洗衣机/烘干机
    cabinet.rotation.y = Math.PI;
    const cabBody = material(RGB.cream, { roughness: 0.6 });
    const cabDoor = material(RGB.sageGrey, { roughness: 0.62 });
    box(cabinet, 0.52, 1.7, 0.5, 0.03, cabBody, 0, 0.85, 0, true);
    box(cabinet, 0.03, 0.78, 0.44, 0.012, cabDoor, -0.27, 1.24, 0, false);
    box(cabinet, 0.03, 0.78, 0.44, 0.012, cabDoor, -0.27, 0.42, 0, false);
    cylinder(cabinet, 0.015, 0.015, 0.16, 8, material(RGB.brass, { roughness: 0.3, metalness: 0.5 }), -0.3, 1.24, 0.14);
    hit(cabinet, 'storage_cabinet', 0.62, 1.8, 0.6, 0, 0.85, 0, hitboxes);

    const sink = objectGroup('laundry_sink', 2.55, FLOOR_Y, 0.62, root);
    objects.push(sink);
    cylinder(sink, 0.12, 0.14, 0.62, 12, material(RGB.white, { roughness: 0.45 }), 0, 0.31, 0);
    box(sink, 0.55, 0.2, 0.5, 0.05, material(RGB.white, { roughness: 0.4 }), 0, 0.8, 0, true);
    box(sink, 0.44, 0.03, 0.38, 0.012, material(RGB.stoneDeep, { roughness: 0.5 }), 0, 0.9, 0, false);
    const faucet = addMesh(sink, new THREE.CylinderGeometry(0.018, 0.018, 0.24, 10), material(RGB.metal), [0, 1.02, -0.16], false);
    faucet.rotation.x = 0.35;
    hit(sink, 'laundry_sink', 0.65, 0.95, 0.6, 0, 0.5, 0, hitboxes);

    // 中段晾晒区
    const rack = objectGroup('drying_rack', 0.55, FLOOR_Y, 0.25, root);
    objects.push(rack);
    const rackMetal = material(RGB.steel, { roughness: 0.35, metalness: 0.45 });
    [-0.62, 0.62].forEach((x) => {
      [-0.26, 0.26].forEach((z) => {
        const leg = box(rack, 0.05, 1.4, 0.05, 0.015, rackMetal, x, 0.7, z, true);
        leg.rotation.x = z > 0 ? -0.16 : 0.16;
      });
    });
    [-0.26, 0.26].forEach((z) => {
      box(rack, 1.3, 0.045, 0.045, 0.015, rackMetal, 0, 1.32, z, false);
    });
    [-0.5, -0.25, 0, 0.25, 0.5].forEach((x) => {
      box(rack, 0.03, 0.03, 0.62, 0.012, rackMetal, x, 1.27, 0, false);
    });
    hit(rack, 'drying_rack', 1.45, 1.45, 0.7, 0, 0.72, 0, hitboxes);

    const basket = objectGroup('laundry_basket', 1.65, FLOOR_Y, 0.75, root);
    objects.push(basket);
    cylinder(basket, 0.21, 0.17, 0.45, 16, material(RGB.linenDust, { roughness: 0.92 }), 0, 0.225, 0, true);
    cylinder(basket, 0.19, 0.19, 0.03, 16, material(RGB.sageGrey, { roughness: 0.9 }), 0, 0.45, 0);
    [-0.21, 0.21].forEach((x) => {
      box(basket, 0.03, 0.12, 0.05, 0.01, material(RGB.sageGrey, { roughness: 0.9 }), x, 0.5, 0, false);
    });
    hit(basket, 'laundry_basket', 0.55, 0.55, 0.55, 0, 0.28, 0, hitboxes);

    const pin = objectGroup('clothespin', 1.62, FLOOR_Y + 0.68, 0.55, root);
    objects.push(pin);
    box(pin, 0.05, 0.17, 0.028, 0.01, material(RGB.woodLight, { roughness: 0.7 }), -0.02, 0, 0, true);
    box(pin, 0.05, 0.17, 0.028, 0.01, material(RGB.woodLight, { roughness: 0.7 }), 0.02, 0, 0, true);
    box(pin, 0.06, 0.025, 0.035, 0.008, material(RGB.metal), 0, 0.01, 0, false);
    hit(pin, 'clothespin', 0.22, 0.22, 0.22, 0, 0, 0, hitboxes);

    const stool = objectGroup('folding_stool', 0.95, FLOOR_Y, 0.85, root);
    objects.push(stool);
    box(stool, 0.38, 0.05, 0.38, 0.02, material(RGB.woodLight, { roughness: 0.66 }), 0, 0.42, 0, true);
    [-0.14, 0.14].forEach((x) => {
      [-0.14, 0.14].forEach((z) => {
        const leg = box(stool, 0.035, 0.42, 0.035, 0.01, material(RGB.woodDark), x, 0.21, z, false);
        leg.rotation.x = z > 0 ? -0.12 : 0.12;
      });
    });
    hit(stool, 'folding_stool', 0.45, 0.52, 0.45, 0, 0.26, 0, hitboxes);

    // 西端清洁/园艺区
    const broom = objectGroup('broom', -3.15, FLOOR_Y, 0.4, root);
    objects.push(broom);
    const broomHandle = addMesh(broom, new THREE.CylinderGeometry(0.018, 0.018, 1.32, 10), material(RGB.woodDark), [0, 0.72, 0], true);
    broomHandle.rotation.z = 0.08;
    const broomHead = box(broom, 0.3, 0.1, 0.13, 0.02, material(RGB.mustard, { roughness: 0.85 }), 0.05, 0.06, 0.05, true);
    broomHead.rotation.y = 0.2;
    box(broom, 0.26, 0.08, 0.1, 0.01, material(RGB.mustard, { roughness: 0.95 }), 0.05, 0.0, 0.08, false);
    hit(broom, 'broom', 0.4, 1.45, 0.4, 0, 0.72, 0, hitboxes);

    const mop = objectGroup('mop', -2.65, FLOOR_Y, 0.5, root);
    objects.push(mop);
    const mopHandle = addMesh(mop, new THREE.CylinderGeometry(0.018, 0.018, 1.28, 10), material(RGB.teal), [0, 0.7, 0], true);
    mopHandle.rotation.z = -0.06;
    cylinder(mop, 0.16, 0.12, 0.07, 14, material(RGB.linenDust, { roughness: 0.95 }), 0, 0.06, 0);
    hit(mop, 'mop', 0.36, 1.4, 0.36, 0, 0.7, 0, hitboxes);

    const bucket = objectGroup('bucket', -2.25, FLOOR_Y, 0.8, root);
    objects.push(bucket);
    cylinder(bucket, 0.18, 0.15, 0.4, 16, material(RGB.teal, { roughness: 0.55 }), 0, 0.2, 0, true);
    cylinder(bucket, 0.16, 0.16, 0.02, 16, material(RGB.tealDark), 0, 0.4, 0);
    [-0.16, 0.16].forEach((x) => {
      box(bucket, 0.02, 0.14, 0.02, 0.008, material(RGB.metal), x, 0.46, 0, false);
    });
    box(bucket, 0.32, 0.02, 0.02, 0.008, material(RGB.metal), 0, 0.53, 0, false);
    hit(bucket, 'bucket', 0.42, 0.58, 0.42, 0, 0.28, 0, hitboxes);

    const plant = objectGroup('balcony_plant', -2.7, FLOOR_Y, -0.75, root);
    objects.push(plant);
    cylinder(plant, 0.17, 0.12, 0.26, 14, material(RGB.coral, { roughness: 0.85 }), 0, 0.13, 0, true);
    cylinder(plant, 0.15, 0.15, 0.02, 14, material(RGB.woodDark), 0, 0.27, 0);
    for (let i = 0; i < 7; i += 1) {
      const angle = (i / 7) * Math.PI * 2;
      const leaf = addMesh(
        plant,
        new THREE.ConeGeometry(0.075, 0.5, 5),
        material(RGB.green, { roughness: 0.8, flatShading: true }),
        [Math.cos(angle) * 0.1, 0.5 + (i % 3) * 0.06, Math.sin(angle) * 0.1],
        true
      );
      leaf.rotation.z = Math.cos(angle) * 0.45;
      leaf.rotation.x = -Math.sin(angle) * 0.45;
    }
    hit(plant, 'balcony_plant', 0.48, 0.85, 0.48, 0, 0.4, 0, hitboxes);

    const flowerPot = objectGroup('flower_pot', -1.7, FLOOR_Y, -0.8, root);
    objects.push(flowerPot);
    cylinder(flowerPot, 0.14, 0.11, 0.22, 14, material(RGB.coral, { roughness: 0.88 }), 0, 0.11, 0, true);
    cylinder(flowerPot, 0.12, 0.12, 0.02, 14, material(RGB.woodDark), 0, 0.22, 0);
    cylinder(flowerPot, 0.012, 0.012, 0.24, 8, material(RGB.greenDark), 0, 0.33, 0);
    addMesh(flowerPot, new THREE.IcosahedronGeometry(0.07, 0), material(RGB.mustard, { roughness: 0.7 }), [0, 0.47, 0], true);
    hit(flowerPot, 'flower_pot', 0.32, 0.6, 0.32, 0, 0.3, 0, hitboxes);

    const wateringCan = objectGroup('watering_can', -1.55, FLOOR_Y, 0.65, root);
    objects.push(wateringCan);
    cylinder(wateringCan, 0.12, 0.12, 0.22, 14, material(RGB.teal, { roughness: 0.5 }), 0, 0.13, 0, true);
    const spout = addMesh(wateringCan, new THREE.CylinderGeometry(0.025, 0.04, 0.34, 10), material(RGB.teal), [0.18, 0.22, 0], true);
    spout.rotation.z = -0.9;
    box(wateringCan, 0.04, 0.14, 0.03, 0.01, material(RGB.teal), -0.06, 0.3, 0, false);
    box(wateringCan, 0.14, 0.03, 0.03, 0.01, material(RGB.teal), -0.13, 0.37, 0, false);
    hit(wateringCan, 'watering_can', 0.42, 0.38, 0.3, 0, 0.2, 0, hitboxes);

    if (objects.length !== 15) throw new Error('阳台应该有 15 件可点物品，实际 ' + objects.length);
    return { objects, hitboxes };
  }

  function buildBedrooms(childRoot, masterRoot) {
    const child = buildChildRoom(childRoot);
    const master = buildMasterRoom(masterRoot);
    return {
      objects: child.objects.concat(master.objects),
      hitboxes: child.hitboxes.concat(master.hitboxes)
    };
  }

  // 四间房共用一套世界坐标；各房间模型仍按本地原点建模，装配时再整体平移。
  const ROOM_OFFSETS = {
    main: { x: 0, z: 0 },
    child: { x: 10.01, z: -1.19 },
    master: { x: 10.11, z: 2.81 },
    balcony: { x: -0.89, z: 4.39 }
  };

  // 每间房一份取景参数：bounds 供相机平移到边上时留内缩量，fit 系列供 fitRadius 用。
  // 这里全部是世界坐标，room-scene 直接把相机 target 放进去。
  const ROOM_FRAMES = {
    main: {
      bounds: {
        minX: ROOM.minX,
        maxX: ROOM.maxX,
        minZ: ROOM.minZ,
        maxZ: ROOM.maxZ,
        centerX: ROOM.centerX,
        halfWidth: (ROOM.maxX - ROOM.minX) / 2,
        halfDepth: (ROOM.maxZ - ROOM.minZ) / 2
      },
      target: { x: ROOM.centerX + 0.12, y: 0.86, z: 0.05 },
      fitMin: 12.3,
      fitMax: 34,
      zoomMin: 5.4,
      // 内缩量收窄（原 1.7 / 1.3 会把镜头锁在客餐厅中部，放大后到不了东侧厨房）
      panInsetX: 0.6,
      panInsetZ: 0.5,
      fitScale: 1,
      // 客厅 / 餐厅 / 厨房三个取景中心（room-layout.js），供页面 chip 与原生 focus 使用
      areas: LAYOUT.areas
    },
    child: {
      bounds: { minX: 7.81, maxX: 12.21, minZ: -2.99, maxZ: 0.61, centerX: 10.01, halfWidth: 2.2, halfDepth: 1.8 },
      target: { x: 10.06, y: 0.78, z: -1.17 },
      fitMin: 7.6,
      fitMax: 11,
      fitScale: 0.92,
      zoomMin: 2.9,
      panInsetX: 0.55,
      panInsetZ: 0.45
    },
    master: {
      bounds: { minX: 7.81, maxX: 12.41, minZ: 1.01, maxZ: 4.61, centerX: 10.11, halfWidth: 2.3, halfDepth: 1.8 },
      target: { x: 10.16, y: 0.78, z: 2.83 },
      fitMin: 7.6,
      fitMax: 11,
      fitScale: 0.92,
      zoomMin: 2.9,
      panInsetX: 0.58,
      panInsetZ: 0.45
    },
    balcony: {
      bounds: { minX: -4.19, maxX: 2.41, minZ: 3.19, maxZ: 5.59, centerX: -0.89, centerZ: 4.39, halfWidth: 3.3, halfDepth: 1.2 },
      target: { x: -0.89, y: 0.8, z: 4.39 },
      fitMin: 4.5,
      fitMax: 13.5,
      zoomMin: 2.4,
      panInsetX: 0.9,
      panInsetZ: 0.45,
      fitScale: 1
    },
    overview: {
      bounds: { minX: -4.36, maxX: 12.58, minZ: -3.19, maxZ: 5.76, centerX: 4.11, centerZ: 1.285, halfWidth: 8.47, halfDepth: 4.475 },
      target: { x: 4.1, y: 0.7, z: 1.3 },
      fitMin: 16,
      fitMax: 48,
      zoomMin: 8,
      panInsetX: 1.2,
      panInsetZ: 0.8,
      fitScale: 1
    }
  };

  function objectMeta(id) {
    const meta = dataById.get(id);
    if (!meta) throw new Error('Unknown object: ' + id);
    return {
      id,
      objectId: id,
      objectName: meta.objectName,
      word: meta.word,
      phonetic: meta.phonetic,
      zh: meta.zh,
      kidDefinition: meta.kidDefinition,
      example: meta.example,
      category: meta.category,
      room: meta.room,
      labelBias: meta.labelBias,
      interactive: true
    };
  }

  function objectGroup(id, x, y, z, root) {
    const g = new THREE.Group();
    g.name = 'OBJ_' + id;
    g.position.set(x, y, z);
    g.userData = objectMeta(id);
    root.add(g);
    return g;
  }

  function hit(group, id, w, h, d, x, y, z, hitboxes) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), hitMaterial);
    mesh.position.set(x, y, z);
    mesh.userData = { isHitbox: true, objectId: id };
    mesh.renderOrder = -1;
    mesh.castShadow = false;
    mesh.receiveShadow = false;
    group.add(mesh);
    hitboxes.push(mesh);
    return mesh;
  }

  function buildRoom(root) {
    materialCache.clear();
    const hitboxes = [];
    const objects = [];
    buildRoomShell(root);    buildKitchenShell(root);
    buildKitchenRun(root);
    buildIsland(root);
    buildHood(root);
    buildWindowAndCurtain(objects, hitboxes, root);
    buildSofa(objects, hitboxes, root);
    buildCushion(objects, hitboxes, root);
    buildCoffeeTable(objects, hitboxes, root);
    buildRemote(objects, hitboxes, root);
    buildRug(objects, hitboxes, root);
    buildFloorLamp(objects, hitboxes, root);
    buildBookshelf(objects, hitboxes, root);
    buildOpenBook(objects, hitboxes, root);
    buildPlant(objects, hitboxes, root);
    buildTVStand(objects, hitboxes, root);
    buildTV(objects, hitboxes, root);
    buildPicture(objects, hitboxes, root);
    buildClock(objects, hitboxes, root);
    buildAirConditioner(objects, hitboxes, root);
    buildTrashCan(objects, hitboxes, root);
    buildDiningTable(objects, hitboxes, root);
    buildDiningChairs(objects, hitboxes, root);
    buildPlate(objects, hitboxes, root);
    buildBowl(objects, hitboxes, root);
    buildCup(objects, hitboxes, root);
    buildSpoon(objects, hitboxes, root);
    buildFork(objects, hitboxes, root);
    buildKettle(objects, hitboxes, root);
    buildFridge(objects, hitboxes, root);
    buildStove(objects, hitboxes, root);
    buildOven(objects, hitboxes, root);
    buildDishwasher(objects, hitboxes, root);
    buildCabinet(objects, hitboxes, root);
    buildMicrowave(objects, hitboxes, root);
    buildToaster(objects, hitboxes, root);
    buildPot(objects, hitboxes, root);
    buildPan(objects, hitboxes, root);
    buildKnife(objects, hitboxes, root);
    buildBarStools(objects, hitboxes, root);
    buildSink(objects, hitboxes, root);

    if (objects.length !== 37) {
      throw new Error('Expected 37 interactive objects, built ' + objects.length);
    }

    return { objects, hitboxes };
  }

  window.WordRoomModels = {
    buildRoom,
    buildBedrooms,
    buildBalcony,
    FLOOR_Y,
    rooms: ROOM_FRAMES,
    offsets: ROOM_OFFSETS,
    bounds: ROOM_FRAMES.main.bounds
  };
})();
