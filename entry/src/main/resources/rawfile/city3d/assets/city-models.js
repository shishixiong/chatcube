/* ============================================================
   小词城 Word City · 低多边形建模工厂
   所有几何体共享缓存，材质按颜色共享，控制移动端开销。
   导出 window.WordCityModels = { buildWorld, buildVehicle, buildPerson, palette }
   ============================================================ */
(function () {
  'use strict';

  var THREE = window.THREE;
  var M = (window.WordCityModels = window.WordCityModels || {});
  if (!THREE) {
    console.error('[WordCity] 未找到 THREE，请确认 assets/vendor/three.min.js 已加载。');
    return;
  }

  var FONT = '"PingFang SC","HarmonyOS Sans SC","Noto Sans SC",-apple-system,sans-serif';

  var P = {
    grass: '#7ECB6A', grassDeep: '#5FAE54', soil: '#B7A88E',
    road: '#4B5563', line: '#F8F5EA', bike: '#8FD3A8',
    sidewalk: '#E4DCCB', curb: '#C9BFAE',
    coral: '#F2826A', mustard: '#F2C14E', mint: '#6FCF97',
    skyBlue: '#6FA8DC', lavender: '#A78BFA', cream: '#FFF3D6',
    red: '#E5484D', yellow: '#F5A524', green: '#30A46C',
    brand: '#FF9F43', window: '#58707F', frame: '#FFF9EC',
    trunk: '#8B6A48', leaf: '#6FCF97', leafDeep: '#4FA06A',
    water: '#77BFD9', sand: '#E7D6AD', dark: '#33302C'
  };
  M.palette = P;

  var geos = {};
  var mats = {};

  function mat(color, opts) {
    var key = color + '|' + (opts ? JSON.stringify(opts) : '');
    if (!mats[key]) {
      var cfg = { color: color, flatShading: true };
      if (opts) { for (var k in opts) { cfg[k] = opts[k]; } }
      mats[key] = new THREE.MeshLambertMaterial(cfg);
    }
    return mats[key];
  }

  function matA(color, opacity) {
    var key = 'A' + color + '|' + opacity;
    if (!mats[key]) {
      mats[key] = new THREE.MeshLambertMaterial({
        color: color, transparent: true, opacity: opacity,
        flatShading: true, depthWrite: false
      });
    }
    return mats[key];
  }

  function geoBox(w, h, d) {
    var k = 'b' + w.toFixed(3) + '_' + h.toFixed(3) + '_' + d.toFixed(3);
    if (!geos[k]) { geos[k] = new THREE.BoxGeometry(w, h, d); }
    return geos[k];
  }

  function geoCyl(rt, rb, h, seg) {
    var k = 'c' + rt.toFixed(3) + '_' + rb.toFixed(3) + '_' + h.toFixed(3) + '_' + seg;
    if (!geos[k]) { geos[k] = new THREE.CylinderGeometry(rt, rb, h, seg); }
    return geos[k];
  }

  function box(parent, w, h, d, color, x, y, z, opts) {
    var m = new THREE.Mesh(geoBox(w, h, d), opts && opts.material ? opts.material : mat(color));
    m.position.set(x || 0, y || 0, z || 0);
    if (opts) {
      if (opts.ry) { m.rotation.y = opts.ry; }
      if (opts.rx) { m.rotation.x = opts.rx; }
      if (opts.rz) { m.rotation.z = opts.rz; }
      if (opts.cast) { m.castShadow = true; }
      if (opts.receive) { m.receiveShadow = true; }
    }
    if (parent) { parent.add(m); }
    return m;
  }

  function cyl(parent, rt, rb, h, seg, color, x, y, z, opts) {
    var m = new THREE.Mesh(geoCyl(rt, rb, h, seg), opts && opts.material ? opts.material : mat(color));
    m.position.set(x || 0, y || 0, z || 0);
    if (opts) {
      if (opts.rx) { m.rotation.x = opts.rx; }
      if (opts.rz) { m.rotation.z = opts.rz; }
      if (opts.ry) { m.rotation.y = opts.ry; }
      if (opts.cast) { m.castShadow = true; }
    }
    if (parent) { parent.add(m); }
    return m;
  }

  function cone(parent, r, h, seg, color, x, y, z, opts) {
    var k = 'k' + r.toFixed(2) + '_' + h.toFixed(2) + '_' + seg;
    if (!geos[k]) { geos[k] = new THREE.ConeGeometry(r, h, seg); }
    var m = new THREE.Mesh(geos[k], mat(color));
    m.position.set(x || 0, y || 0, z || 0);
    if (opts) {
      if (opts.rx) { m.rotation.x = opts.rx; }
      if (opts.rz) { m.rotation.z = opts.rz; }
      if (opts.ry) { m.rotation.y = opts.ry; }
      if (opts.cast) { m.castShadow = true; }
    }
    if (parent) { parent.add(m); }
    return m;
  }

  function flatPlane(parent, w, d, color, x, y, z, opts) {
    var k = 'p' + w.toFixed(3) + '_' + d.toFixed(3);
    if (!geos[k]) { geos[k] = new THREE.PlaneGeometry(w, d); }
    var m = new THREE.Mesh(geos[k], opts && opts.material ? opts.material : mat(color));
    m.rotation.x = -Math.PI / 2;
    m.position.set(x || 0, y || 0, z || 0);
    m.receiveShadow = true;
    if (parent) { parent.add(m); }
    return m;
  }

  function shade(hex, amt) {
    var n = parseInt(String(hex).replace('#', ''), 16);
    var r = (n >> 16) & 255;
    var g = (n >> 8) & 255;
    var b = n & 255;
    if (amt < 0) {
      r = Math.round(r * (1 + amt));
      g = Math.round(g * (1 + amt));
      b = Math.round(b * (1 + amt));
    } else {
      r = Math.round(r + (255 - r) * amt);
      g = Math.round(g + (255 - g) * amt);
      b = Math.round(b + (255 - b) * amt);
    }
    return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
  }

  function canvas2d(w, h) {
    var c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    return [c, c.getContext('2d')];
  }

  function toTex(c, repeatX, repeatY) {
    var t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 4;
    if (repeatX || repeatY) {
      t.wrapS = THREE.RepeatWrapping;
      t.wrapT = THREE.RepeatWrapping;
      t.repeat.set(repeatX || 1, repeatY || 1);
    }
    return t;
  }

  function roundRect(g, x, y, w, h, r) {
    var rr = Math.min(r, w / 2, h / 2);
    g.beginPath();
    g.moveTo(x + rr, y);
    g.arcTo(x + w, y, x + w, y + h, rr);
    g.arcTo(x + w, y + h, x, y + h, rr);
    g.arcTo(x, y + h, x, y, rr);
    g.arcTo(x, y, x + w, y, rr);
    g.closePath();
  }

  /* 立面贴图同时产出两张图：白天墙面 + 夜间亮灯窗户（emissiveMap）。
     窗格亮灯用固定种子伪随机，保证每次打开的亮窗位置一致。 */
  function facadeTexture(base, cols, rows, opts) {
    opts = opts || {};
    var pair = canvas2d(256, 256);
    var c = pair[0];
    var g = pair[1];
    var glowPair = canvas2d(256, 256);
    var gcv = glowPair[0];
    var gg = glowPair[1];
    gg.fillStyle = '#000000';
    gg.fillRect(0, 0, 256, 256);

    g.fillStyle = base;
    g.fillRect(0, 0, 256, 256);
    g.fillStyle = shade(base, -0.1);
    g.fillRect(0, 216, 256, 40);
    g.fillStyle = shade(base, 0.4);
    g.fillRect(0, 0, 256, 12);

    var padX = 24;
    var top = 42;
    var bottom = 208;
    var cw = (256 - padX * 2) / cols;
    var ch = (bottom - top) / rows;
    var seed = 0;
    var baseStr = String(base);
    for (var si = 0; si < baseStr.length; si++) { seed = (seed * 31 + baseStr.charCodeAt(si)) % 99991; }

    for (var r = 0; r < rows; r++) {
      for (var i = 0; i < cols; i++) {
        var x = padX + i * cw + 8;
        var y = top + r * ch + 7;
        var w = cw - 16;
        var h = ch - 16;
        if (w < 6 || h < 6) { continue; }
        g.fillStyle = P.frame;
        roundRect(g, x - 3, y - 3, w + 6, h + 6, 4);
        g.fill();
        var glass = g.createLinearGradient(x, y, x + w, y + h);
        glass.addColorStop(0, '#7E94A2');
        glass.addColorStop(0.55, P.window);
        glass.addColorStop(1, '#455B69');
        g.fillStyle = glass;
        g.fillRect(x, y, w, h);
        g.fillStyle = 'rgba(255,255,255,0.28)';
        g.fillRect(x + 2, y + 2, Math.max(3, w * 0.28), h - 4);
        g.fillStyle = shade(base, 0.24);
        g.fillRect(x - 4, y + h + 2, w + 8, 3);

        seed = (seed * 1103515245 + 12345) % 2147483648;
        var lit = (seed / 2147483648) > 0.34;
        if (lit) {
          var warm = (seed % 7 === 0) ? '#FFD79A' : '#FFE9BC';
          gg.save();
          gg.shadowColor = 'rgba(255,214,150,0.9)';
          gg.shadowBlur = 7;
          gg.fillStyle = warm;
          gg.fillRect(x, y, w, h);
          gg.restore();
          if (h > 12) {
            gg.fillStyle = 'rgba(255,255,255,0.45)';
            gg.fillRect(x + 1, y + 1, w - 2, 2);
          }
        }
      }
    }

    if (opts.bricks) {
      g.globalAlpha = 0.14;
      g.strokeStyle = '#6B3A2E';
      g.lineWidth = 1;
      for (var yy = 12; yy < 256; yy += 12) {
        g.beginPath();
        g.moveTo(0, yy);
        g.lineTo(256, yy);
        g.stroke();
      }
      g.globalAlpha = 1;
    }
    return { map: toTex(c), glow: toTex(gcv) };
  }

  /* 远景楼立面：只有窗格点阵，远看就是「有窗的楼」，成本极低 */
  function distantFacade(base) {
    var pair = canvas2d(64, 128);
    var g = pair[1];
    g.fillStyle = base;
    g.fillRect(0, 0, 64, 128);
    g.fillStyle = shade(base, -0.14);
    g.fillRect(0, 0, 64, 6);
    g.fillStyle = 'rgba(90,110,125,0.62)';
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 4; c++) {
        g.fillRect(6 + c * 14, 12 + r * 12, 8, 6);
      }
    }
    return toTex(pair[0]);
  }

  /* 细颗粒噪点贴图：给草地 / 沥青 / 沙地加质感，避免大面积纯色发平 */
  function noiseTexture(base, opts) {
    opts = opts || {};
    var size = opts.size || 128;
    var amount = opts.amount === undefined ? 0.1 : opts.amount;
    var pair = canvas2d(size, size);
    var c = pair[0];
    var g = pair[1];
    g.fillStyle = base;
    g.fillRect(0, 0, size, size);
    var n = opts.dots || 900;
    var seed = 1234567;
    for (var i = 0; i < n; i++) {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      var rnd = seed / 2147483648;
      var x = rnd * size;
      seed = (seed * 1103515245 + 12345) % 2147483648;
      var y = (seed / 2147483648) * size;
      seed = (seed * 1103515245 + 12345) % 2147483648;
      var k = (seed / 2147483648 - 0.5) * 2;
      g.fillStyle = k > 0 ? 'rgba(255,255,255,' + (amount * k).toFixed(3) + ')'
        : 'rgba(60,50,40,' + (amount * -k).toFixed(3) + ')';
      var s = opts.dotSize || 2;
      g.fillRect(x, y, s, s);
    }
    if (opts.streaks) {
      g.globalAlpha = 0.06;
      g.strokeStyle = '#000000';
      for (var st = 0; st < 26; st++) {
        g.beginPath();
        g.moveTo(0, st * 5 + 2);
        g.lineTo(size, st * 5 + 2);
        g.stroke();
      }
      g.globalAlpha = 1;
    }
    return toTex(c, opts.repeatX, opts.repeatY);
  }

  /* 柔和圆形阴影贴图：给静态物体补一层接触阴影，让它们「坐」在地上 */
  var softShadowTex = null;
  function shadowTexture() {
    if (softShadowTex) { return softShadowTex; }
    var pair = canvas2d(128, 128);
    var g = pair[1];
    var grad = g.createRadialGradient(64, 64, 4, 64, 64, 62);
    grad.addColorStop(0, 'rgba(52,44,34,0.55)');
    grad.addColorStop(0.55, 'rgba(52,44,34,0.26)');
    grad.addColorStop(1, 'rgba(52,44,34,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 128, 128);
    softShadowTex = toTex(pair[0]);
    return softShadowTex;
  }

  /* 夜间光斑 / 光晕贴图 */
  var glowTex = null;
  function glowTexture() {
    if (glowTex) { return glowTex; }
    var pair = canvas2d(96, 96);
    var g = pair[1];
    var grad = g.createRadialGradient(48, 48, 1, 48, 48, 46);
    grad.addColorStop(0, 'rgba(255,246,214,0.95)');
    grad.addColorStop(0.28, 'rgba(255,214,140,0.55)');
    grad.addColorStop(0.62, 'rgba(255,186,96,0.18)');
    grad.addColorStop(1, 'rgba(255,170,70,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 96, 96);
    glowTex = toTex(pair[0]);
    return glowTex;
  }
  M.glowTexture = glowTexture;
  M.shadowTexture = shadowTexture;
  M.noiseTexture = noiseTexture;

  /* 静态装饰合批：把若干「永不动画、永不被点击」的组按材质合并成一个大网格。
     几何体共享缓存的场景里，这一步能显著压低 draw call（移动端 WebView 的瓶颈）。 */
  function mergeStatic(groups, allowTransparent) {
    var buckets = new Map();
    var drop = [];
    groups.forEach(function (g) {
      if (!g) { return; }
      g.updateMatrixWorld(true);
      g.traverse(function (o) {
        if (!o.isMesh || o.isInstancedMesh) { return; }
        var m = o.material;
        if (!m || Array.isArray(m) || !o.geometry) { return; }
        if (m.transparent && !allowTransparent) { return; }
        if (!o.geometry.attributes.position) { return; }
        if (!buckets.has(m.uuid)) { buckets.set(m.uuid, { mat: m, parts: [] }); }
        buckets.get(m.uuid).parts.push(o);
        drop.push(o);
      });
    });

    var mergedGroups = [];
    buckets.forEach(function (bucket) {
      var parts = bucket.parts;
      if (parts.length < 2) { return; }
      var totalVerts = 0;
      var totalIdx = 0;
      var prepared = [];
      for (var i = 0; i < parts.length; i++) {
        var src = parts[i];
        var geo = src.geometry;
        var posCount = geo.attributes.position.count;
        var idxCount = geo.index ? geo.index.count : posCount;
        prepared.push({ geo: geo, posCount: posCount, idxCount: idxCount, matrix: src.matrixWorld });
        totalVerts += posCount;
        totalIdx += idxCount;
      }
      var pos = new Float32Array(totalVerts * 3);
      var nrm = new Float32Array(totalVerts * 3);
      var uv = new Float32Array(totalVerts * 2);
      var index = totalVerts > 65535 ? new Uint32Array(totalIdx) : new Uint16Array(totalIdx);
      var vOff = 0;
      var iOff = 0;
      var v = new THREE.Vector3();
      var nm = new THREE.Matrix3();
      for (var p = 0; p < prepared.length; p++) {
        var item = prepared[p];
        var g2 = item.geo;
        var srcPos = g2.attributes.position.array;
        var srcNrm = g2.attributes.normal ? g2.attributes.normal.array : null;
        var srcUv = g2.attributes.uv ? g2.attributes.uv.array : null;
        nm.getNormalMatrix(item.matrix);
        for (var vi = 0; vi < item.posCount; vi++) {
          v.set(srcPos[vi * 3], srcPos[vi * 3 + 1], srcPos[vi * 3 + 2]).applyMatrix4(item.matrix);
          pos[(vOff + vi) * 3] = v.x;
          pos[(vOff + vi) * 3 + 1] = v.y;
          pos[(vOff + vi) * 3 + 2] = v.z;
          if (srcNrm) {
            v.set(srcNrm[vi * 3], srcNrm[vi * 3 + 1], srcNrm[vi * 3 + 2]).applyMatrix3(nm).normalize();
            nrm[(vOff + vi) * 3] = v.x;
            nrm[(vOff + vi) * 3 + 1] = v.y;
            nrm[(vOff + vi) * 3 + 2] = v.z;
          }
          if (srcUv) {
            uv[(vOff + vi) * 2] = srcUv[vi * 2];
            uv[(vOff + vi) * 2 + 1] = srcUv[vi * 2 + 1];
          }
        }
        if (g2.index) {
          var srcIdx = g2.index.array;
          for (var ii = 0; ii < item.idxCount; ii++) {
            index[iOff + ii] = srcIdx[ii] + vOff;
          }
        } else {
          for (var ni = 0; ni < item.idxCount; ni++) {
            index[iOff + ni] = ni + vOff;
          }
        }
        vOff += item.posCount;
        iOff += item.idxCount;
      }
      var geo2 = new THREE.BufferGeometry();
      geo2.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo2.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
      geo2.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      geo2.setIndex(new THREE.BufferAttribute(index, 1));
      geo2.computeBoundingSphere();
      var mesh = new THREE.Mesh(geo2, bucket.mat);
      mesh.castShadow = false;
      mesh.receiveShadow = false;
      mergedGroups.push(mesh);
    });

    // 合批后把原网格从父节点摘掉（几何体是共享缓存的，不能 dispose）
    for (var d = 0; d < drop.length; d++) {
      if (drop[d].parent) { drop[d].parent.remove(drop[d]); }
    }
    return mergedGroups;
  }
  M.mergeStatic = mergeStatic;

  function stripeTexture(c1, c2) {
    var pair = canvas2d(128, 64);
    var c = pair[0];
    var g = pair[1];
    g.fillStyle = c1;
    g.fillRect(0, 0, 128, 64);
    g.fillStyle = c2;
    for (var i = 0; i < 8; i += 2) {
      g.fillRect(i * 16, 0, 16, 64);
    }
    return toTex(c);
  }

  function signTexture(text, opts) {
    opts = opts || {};
    var cw = opts.cw || 512;
    var ch = opts.ch || 128;
    var pair = canvas2d(cw, ch);
    var c = pair[0];
    var g = pair[1];
    if (opts.bg) {
      g.fillStyle = opts.bg;
      roundRect(g, 2, 2, cw - 4, ch - 4, opts.radius || 18);
      g.fill();
    }
    if (opts.border) {
      g.strokeStyle = opts.border;
      g.lineWidth = 5;
      roundRect(g, 5, 5, cw - 10, ch - 10, opts.radius || 16);
      g.stroke();
    }
    var size = Math.round(ch * 0.46);
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    for (var guard = 0; guard < 24; guard++) {
      g.font = '700 ' + size + 'px ' + FONT;
      if (g.measureText(text).width <= cw * 0.84) { break; }
      size -= 2;
    }
    g.fillStyle = opts.fg || '#3A332B';
    g.fillText(text, cw / 2, ch / 2 + 2);
    return toTex(c);
  }

  function addSign(parent, text, w, h, x, y, z, opts) {
    opts = opts || {};
    var m = new THREE.Mesh(
      new THREE.PlaneGeometry(w, h),
      new THREE.MeshLambertMaterial({ map: signTexture(text, opts), transparent: true })
    );
    m.position.set(x, y, z);
    if (opts.ry) { m.rotation.y = opts.ry; }
    parent.add(m);
    return m;
  }

  function addAwning(parent, w, y, z, c1, c2) {
    var m = new THREE.Mesh(
      geoBox(w, 0.26, 1.7),
      new THREE.MeshLambertMaterial({ map: stripeTexture(c1, c2), flatShading: true })
    );
    m.position.set(0, y, z);
    m.rotation.x = -0.2;
    m.castShadow = true;
    parent.add(m);
    return m;
  }

  function makeBuilding(cfg) {
    var g = new THREE.Group();
    g.position.set(cfg.x, 0, cfg.z);
    if (cfg.rotY) { g.rotation.y = cfg.rotY; }

    var w = cfg.w;
    var d = cfg.d;
    var h = cfg.h;
    var texPair = facadeTexture(cfg.color, cfg.cols || 4, cfg.rows || 3, cfg);
    var bodyMat = new THREE.MeshLambertMaterial({
      map: texPair.map, flatShading: true,
      emissive: new THREE.Color('#FFC97A'), emissiveMap: texPair.glow, emissiveIntensity: 0
    });
    var body = new THREE.Mesh(geoBox(w, h, d), bodyMat);
    body.position.y = h / 2;
    body.castShadow = true;
    body.receiveShadow = true;
    g.add(body);
    if (!M.windowMats) { M.windowMats = []; }
    M.windowMats.push(bodyMat);

    box(g, w + 0.9, 0.4, d + 0.9, shade(cfg.color, 0.3), 0, 0.2, 0, { receive: true });

    // 横向腰线：让大立面有分层，不至于一整块平墙
    if (h > 8) {
      box(g, w + 0.5, 0.22, 0.16, shade(cfg.color, 0.34), 0, h * 0.52, d / 2 + 0.02);
      box(g, w + 0.5, 0.22, 0.16, shade(cfg.color, 0.34), 0, h * 0.52, -d / 2 - 0.02);
      box(g, 0.16, 0.22, d + 0.5, shade(cfg.color, 0.34), w / 2 + 0.02, h * 0.52, 0);
      box(g, 0.16, 0.22, d + 0.5, shade(cfg.color, 0.34), -w / 2 - 0.02, h * 0.52, 0);
    }

    if (cfg.roof === 'pyramid') {
      var rh = cfg.roofH || Math.min(w, d) * 0.3;
      var roof = new THREE.Mesh(
        new THREE.ConeGeometry(Math.max(w, d) * 0.66, rh, 4),
        mat(cfg.roofColor || shade(cfg.color, -0.26))
      );
      roof.rotation.y = Math.PI / 4;
      roof.position.y = h + rh / 2;
      roof.castShadow = true;
      g.add(roof);
      // 落雪盖：只记录参数，buildWorld 末尾统一做成 InstancedMesh（省 draw call）
      if (M.snowMat) {
        M.worldSnowCaps.push({
          kind: 'cone',
          w: Math.max(w, d) * 0.665, h: rh * 0.98,
          x: cfg.x, z: cfg.z, y: h + rh / 2 + 0.06, rotY: (cfg.rotY || 0) + Math.PI / 4
        });
      }
    } else {
      box(g, w + 1.0, 0.36, d + 1.0, cfg.roofColor || shade(cfg.color, -0.24), 0, h + 0.18, 0, { cast: true });
      box(g, w + 1.0, 0.46, 0.3, shade(cfg.color, 0.22), 0, h + 0.55, d / 2 + 0.35);
      box(g, w + 1.0, 0.46, 0.3, shade(cfg.color, 0.22), 0, h + 0.55, -d / 2 - 0.35);
      box(g, 0.3, 0.46, d + 1.0, shade(cfg.color, 0.22), w / 2 + 0.35, h + 0.55, 0);
      box(g, 0.3, 0.46, d + 1.0, shade(cfg.color, 0.22), -w / 2 - 0.35, h + 0.55, 0);
      // 平屋顶积雪：同样只记录参数，末尾统一 InstancedMesh
      if (M.snowMat) {
        M.worldSnowCaps.push({
          kind: 'slab',
          w: w + 0.86, d: d + 0.86,
          x: cfg.x, z: cfg.z, y: h + 0.4, rotY: cfg.rotY || 0
        });
      }
    }

    /* 屋顶小物件：水箱、空调外机、透气帽、天线，让天际线有高低起伏 */
    var roofY = h + 0.4;
    if (cfg.roof !== 'pyramid') {
      if (cfg.waterTank) {
        var tank = new THREE.Group();
        tank.position.set(cfg.waterTank[0], roofY, cfg.waterTank[1]);
        cyl(tank, 1.1, 1.1, 1.8, 10, '#B7A88E', 0, 0.9, 0);
        cone(tank, 1.16, 0.6, 10, '#9C8E76', 0, 2.1, 0);
        box(tank, 0.18, 0.5, 0.18, '#8A8F96', -0.7, 0.25, 0.7);
        box(tank, 0.18, 0.5, 0.18, '#8A8F96', 0.7, 0.25, -0.7);
        g.add(tank);
      }
      if (cfg.acUnit) {
        var ac = new THREE.Group();
        ac.position.set(cfg.acUnit[0], roofY + 0.02, cfg.acUnit[1]);
        box(ac, 1.5, 0.7, 1.0, '#DCD8CE', 0, 0.35, 0, { cast: true });
        box(ac, 0.06, 0.6, 0.9, '#B8B4AA', 0.76, 0.35, 0);
        var fan = new THREE.Mesh(new THREE.TorusGeometry(0.28, 0.04, 5, 12), mat('#8A8F96'));
        fan.position.set(-0.4, 0.36, 0.51);
        ac.add(fan);
        g.add(ac);
      }
      var ventCount = cfg.vents === undefined ? 2 : cfg.vents;
      for (var vi = 0; vi < ventCount; vi++) {
        var vx = -w * 0.28 + vi * (w * 0.28);
        cyl(g, 0.3, 0.34, 0.55, 8, '#A9A296', vx, roofY + 0.28, -d * 0.22);
      }
      if (cfg.antenna) {
        cyl(g, 0.05, 0.07, 3.4, 5, '#8A8F96', w * 0.3, roofY + 1.7, -d * 0.3);
        box(g, 1.1, 0.05, 0.05, '#8A8F96', w * 0.3, roofY + 3.0, -d * 0.3);
        box(g, 0.7, 0.05, 0.05, '#8A8F96', w * 0.3, roofY + 2.5, -d * 0.3);
      }
    }

    /* 墙面附加物：阳台花箱、空调外机、排水管 */
    if (cfg.balconies) {
      for (var bci = 0; bci < cfg.balconies; bci++) {
        var by = h * (0.36 + bci * 0.28);
        var balcony = new THREE.Group();
        balcony.position.set(-w * 0.18 + bci * w * 0.36, by, d / 2 + 0.5);
        box(balcony, Math.min(3.2, w * 0.32), 0.14, 1.0, shade(cfg.color, 0.3), 0, 0, 0, { cast: true });
        box(balcony, Math.min(3.2, w * 0.32), 0.5, 0.1, shade(cfg.color, -0.16), 0, 0.3, 0.46);
        box(balcony, Math.min(3.2, w * 0.32), 0.7, 0.08, '#C9BFAE', 0, 0.42, -0.46);
        // 花箱 + 三朵小花
        box(balcony, 1.0, 0.26, 0.4, '#C08B5C', 0, 0.2, 0.32);
        for (var fli = 0; fli < 3; fli++) {
          var bl = new THREE.Mesh(new THREE.SphereGeometry(0.13, 6, 5), mat(fli % 2 ? '#FFF3D6' : P.coral));
          bl.position.set(-0.3 + fli * 0.3, 0.4, 0.32);
          balcony.add(bl);
        }
        g.add(balcony);
      }
    }
    if (cfg.acWall && cfg.roof !== 'pyramid') {
      var wac = new THREE.Group();
      wac.position.set(w / 2 + 0.35, h * 0.62, d * 0.2);
      box(wac, 0.7, 1.0, 1.5, '#DCD8CE', 0, 0, 0, { cast: true });
      box(wac, 0.06, 0.9, 1.3, '#B8B4AA', 0.36, 0, 0);
      g.add(wac);
    }
    if (cfg.drain) {
      cyl(g, 0.09, 0.09, h, 6, shade(cfg.color, -0.3), w / 2 + 0.12, h / 2, d / 2 - 0.5);
    }

    var doorW = cfg.doorW || 2.2;
    box(g, doorW, 3.1, 0.16, '#6B5B4A', 0, 1.6, d / 2 + 0.08);
    box(g, 0.16, 3.1, 0.16, '#5A4C3E', -doorW * 0.18, 1.6, d / 2 + 0.18);
    box(g, doorW + 0.7, 0.18, 0.7, '#8A6B4A', 0, 3.25, d / 2 + 0.36);
    box(g, doorW + 1.5, 0.18, 0.8, '#D8CDBB', 0, 0.09, d / 2 + 0.62);
    // 门口小花盆与门牌灯
    var pot = new THREE.Group();
    pot.position.set(doorW * 0.72, 0.09, d / 2 + 0.5);
    cyl(pot, 0.24, 0.19, 0.4, 8, '#C08B5C', 0, 0.2, 0);
    var bushS = new THREE.Mesh(new THREE.IcosahedronGeometry(0.26, 0), mat(P.leaf));
    bushS.position.y = 0.55;
    pot.add(bushS);
    g.add(pot);
    box(g, 0.22, 0.14, 0.14, '#FFF3D6', doorW * 0.5 + 0.16, 2.9, d / 2 + 0.12);
    return g;
  }

  /* ---------------- 车辆 ---------------- */

  // 车灯材质登记表：夜间统一提亮（前灯暖白 / 尾灯红）
  M.headlampMats = M.headlampMats || [];
  M.taillampMats = M.taillampMats || [];

  function lampMat(kind) {
    var base = kind === 'head' ? '#FFF3D6' : '#C0392B';
    var m = new THREE.MeshBasicMaterial({ color: base });
    if (kind === 'head') { M.headlampMats.push(m); } else { M.taillampMats.push(m); }
    return m;
  }

  function buildVehicle(type, color) {
    var g = new THREE.Group();
    var wheels = [];
    var beacons = [];
    var door = null;

    function addWheel(x, y, z, r, w) {
      var wg = new THREE.Group();
      wg.position.set(x, y, z);
      var tire = new THREE.Mesh(geoCyl(r, r, w || 0.3, 10), mat('#33302C'));
      tire.rotation.z = Math.PI / 2;
      wg.add(tire);
      var hub = new THREE.Mesh(geoCyl(r * 0.44, r * 0.44, (w || 0.3) + 0.02, 8), mat('#CFC4B2'));
      hub.rotation.z = Math.PI / 2;
      wg.add(hub);
      g.add(wg);
      wheels.push(wg);
    }

    function lightBar(y, z) {
      box(g, 0.9, 0.14, 0.28, '#2A2E33', 0, y, z);
      var red = box(g, 0.36, 0.16, 0.3, '#FF6B6B', -0.24, y + 0.12, z);
      var blue = box(g, 0.36, 0.16, 0.3, '#6C9CFF', 0.24, y + 0.12, z);
      red.material = new THREE.MeshBasicMaterial({ color: '#FF6B6B' });
      blue.material = new THREE.MeshBasicMaterial({ color: '#6C9CFF' });
      beacons.push({ mesh: red, mat: red.material, base: '#FF6B6B' });
      beacons.push({ mesh: blue, mat: blue.material, base: '#6C9CFF' });
    }

    if (type === 'car' || type === 'taxi') {
      var bodyColor = color || P.coral;
      box(g, 1.9, 0.62, 4.1, bodyColor, 0, 0.72, 0, { cast: true });
      box(g, 1.62, 0.55, 2.1, '#3E4E5C', 0, 1.28, -0.15, { cast: true });
      box(g, 1.7, 0.1, 2.2, shade(bodyColor, -0.16), 0, 1.58, -0.15);
      box(g, 1.92, 0.16, 0.5, '#D8D2C6', 0, 0.5, 2.02);
      box(g, 1.92, 0.16, 0.5, '#D8D2C6', 0, 0.5, -2.02);
      box(g, 0.34, 0.2, 0.1, '#FFF3D6', -0.62, 0.78, 2.06, { material: lampMat('head') });
      box(g, 0.34, 0.2, 0.1, '#FFF3D6', 0.62, 0.78, 2.06, { material: lampMat('head') });
      box(g, 0.3, 0.16, 0.1, '#C0392B', -0.64, 0.78, -2.06, { material: lampMat('tail') });
      box(g, 0.3, 0.16, 0.1, '#C0392B', 0.64, 0.78, -2.06, { material: lampMat('tail') });
      addWheel(-0.96, 0.44, 1.32, 0.44, 0.32);
      addWheel(0.96, 0.44, 1.32, 0.44, 0.32);
      addWheel(-0.96, 0.44, -1.32, 0.44, 0.32);
      addWheel(0.96, 0.44, -1.32, 0.44, 0.32);
      if (type === 'taxi') {
        box(g, 0.7, 0.3, 0.4, '#F2C14E', 0, 1.79, -0.15);
        addSign(g, 'TAXI', 0.66, 0.26, 0, 1.79, 0.08, { cw: 256, ch: 96, fg: '#3A2A06' });
      }
    } else if (type === 'bus' || type === 'school_bus') {
      var isSchool = type === 'school_bus';
      var busColor = isSchool ? '#F2C14E' : '#6FA8DC';
      box(g, 2.42, 2.5, 8.4, busColor, 0, 1.55, 0, { cast: true });
      box(g, 2.46, 0.86, 7.2, '#33434F', 0, 2.12, -0.2);
      box(g, 2.5, 0.24, 7.6, shade(busColor, -0.2), 0, 2.8, -0.2);
      if (isSchool) {
        box(g, 2.48, 0.14, 8.0, '#2F2F2F', 0, 1.0, 0);
        box(g, 2.48, 0.14, 8.0, '#2F2F2F', 0, 1.55, 0);
        addSign(g, 'SCHOOL BUS', 3.4, 0.7, 0, 2.42, 4.23, { cw: 512, ch: 112, bg: '#2F2F2F', fg: '#F2C14E' });
      } else {
        addSign(g, 'BUS 12', 2.4, 0.6, 0, 2.45, 4.23, { cw: 384, ch: 112, bg: '#FFF3D6', fg: '#2F5F8A' });
      }
      box(g, 0.5, 2.3, 0.14, '#2A2E33', 0, 1.55, 4.22);
      box(g, 0.24, 0.24, 0.1, '#FFF3D6', -0.72, 1.0, 4.24, { material: lampMat('head') });
      box(g, 0.24, 0.24, 0.1, '#FFF3D6', 0.72, 1.0, 4.24, { material: lampMat('head') });
      box(g, 0.22, 0.2, 0.1, '#C0392B', -0.9, 1.0, -4.24, { material: lampMat('tail') });
      box(g, 0.22, 0.2, 0.1, '#C0392B', 0.9, 1.0, -4.24, { material: lampMat('tail') });
      addWheel(-1.2, 0.46, 2.7, 0.48, 0.34);
      addWheel(1.2, 0.46, 2.7, 0.48, 0.34);
      addWheel(-1.2, 0.46, -2.7, 0.48, 0.34);
      addWheel(1.2, 0.46, -2.7, 0.48, 0.34);
      door = new THREE.Group();
      door.position.set(1.22, 1.55, 1.9);
      box(door, 0.1, 1.9, 1.0, shade(busColor, -0.08), 0, 0, -0.5);
      box(door, 0.12, 0.7, 0.72, '#33434F', 0.01, 0.45, -0.5);
      g.add(door);
    } else if (type === 'ambulance') {
      box(g, 2.2, 1.9, 5.3, '#FBF9F3', 0, 1.18, -0.2, { cast: true });
      box(g, 2.22, 1.0, 1.5, '#FBF9F3', 0, 0.9, 2.6, { cast: true });
      box(g, 2.1, 0.55, 0.9, '#3E4E5C', 0, 1.55, 2.55);
      box(g, 2.24, 0.1, 5.2, '#D8D2C6', 0, 2.16, -0.2);
      box(g, 0.16, 0.8, 0.35, P.red, 1.12, 1.35, -0.4);
      box(g, 0.16, 0.35, 0.8, P.red, 1.12, 1.35, -0.4);
      box(g, 0.16, 0.8, 0.35, P.red, -1.12, 1.35, -0.4);
      box(g, 0.16, 0.35, 0.8, P.red, -1.12, 1.35, -0.4);
      lightBar(2.24, 2.2);
      // 卡车 / 急救车 / 消防车 的车灯
      box(g, 0.3, 0.18, 0.1, '#FFF3D6', 0, 0.9, 2.92, { material: lampMat('head') });
      box(g, 0.26, 0.16, 0.1, '#FFF3D6', -0.8, 0.9, 2.92, { material: lampMat('head') });
      box(g, 0.26, 0.16, 0.1, '#FFF3D6', 0.8, 0.9, 2.92, { material: lampMat('head') });
      box(g, 0.24, 0.16, 0.1, '#C0392B', -0.8, 0.9, -3.02, { material: lampMat('tail') });
      box(g, 0.24, 0.16, 0.1, '#C0392B', 0.8, 0.9, -3.02, { material: lampMat('tail') });
      addWheel(-1.0, 0.44, 1.7, 0.44, 0.3);
      addWheel(1.0, 0.44, 1.7, 0.44, 0.3);
      addWheel(-1.0, 0.44, -1.7, 0.44, 0.3);
      addWheel(1.0, 0.44, -1.7, 0.44, 0.3);
    } else if (type === 'fire_truck') {
      box(g, 2.4, 2.2, 7.8, '#D9483A', 0, 1.38, -0.2, { cast: true });
      box(g, 2.3, 1.5, 1.8, '#C33F33', 0, 1.15, 3.0, { cast: true });
      box(g, 2.1, 0.7, 0.9, '#3E4E5C', 0, 1.75, 3.05);
      box(g, 2.44, 0.24, 7.4, '#B5352B', 0, 2.55, -0.2);
      box(g, 0.18, 0.18, 5.4, '#D8CDBB', -0.7, 2.8, -0.6);
      box(g, 0.18, 0.18, 5.4, '#D8CDBB', 0.7, 2.8, -0.6);
      for (var li = 0; li < 5; li++) {
        box(g, 1.56, 0.1, 0.2, '#D8CDBB', 0, 2.8, -2.6 + li * 1.05);
      }
      lightBar(2.62, 3.1);
      if (beacons[1]) {
        beacons[1].base = '#FF6B6B';
        beacons[1].mat.color.set('#FF6B6B');
      }
      addWheel(-1.16, 0.48, 2.2, 0.48, 0.34);
      addWheel(1.16, 0.48, 2.2, 0.48, 0.34);
      addWheel(-1.16, 0.48, -2.2, 0.48, 0.34);
      addWheel(1.16, 0.48, -2.2, 0.48, 0.34);
    } else if (type === 'truck') {
      box(g, 2.3, 2.3, 4.6, '#8FC7B0', 0, 1.45, -1.0, { cast: true });
      box(g, 2.24, 1.9, 2.3, '#F2C14E', 0, 1.2, 2.4, { cast: true });
      box(g, 2.1, 0.62, 0.9, '#3E4E5C', 0, 1.65, 2.5);
      box(g, 2.34, 0.18, 4.5, '#C9BFAE', 0, 2.65, -1.0);
      box(g, 1.2, 0.8, 0.14, '#FFF9EC', 0, 1.5, 3.56);
      addWheel(-1.0, 0.48, 2.1, 0.48, 0.32);
      addWheel(1.0, 0.48, 2.1, 0.48, 0.32);
      addWheel(-1.0, 0.48, -2.4, 0.48, 0.32);
      addWheel(1.0, 0.48, -2.4, 0.48, 0.32);
    } else if (type === 'bicycle') {
      var wheelGeo = new THREE.TorusGeometry(0.34, 0.055, 6, 14);
      var wm = mat('#33302C');
      var rear = new THREE.Mesh(wheelGeo, wm);
      rear.rotation.y = Math.PI / 2;
      rear.position.set(0, 0.34, -0.55);
      g.add(rear);
      var front = new THREE.Mesh(wheelGeo, wm);
      front.rotation.y = Math.PI / 2;
      front.position.set(0, 0.34, 0.55);
      g.add(front);
      wheels.push(rear, front);
      box(g, 0.08, 0.08, 1.0, '#3D7BFF', 0, 0.6, 0, { rx: 0.12 });
      box(g, 0.08, 0.5, 0.08, '#F2C14E', 0, 0.62, 0.42);
      box(g, 0.08, 0.44, 0.08, '#F2C14E', 0, 0.56, -0.4);
      box(g, 0.5, 0.06, 0.06, '#3D7BFF', 0, 0.9, 0.46);
      box(g, 0.34, 0.1, 0.5, '#5B4B3A', 0, 0.85, -0.16);
      box(g, 0.44, 0.5, 0.3, '#F2826A', 0, 1.13, -0.12);
      var headB = new THREE.Mesh(new THREE.SphereGeometry(0.18, 10, 8), mat('#F2C9A0'));
      headB.position.set(0, 1.48, -0.1);
      g.add(headB);
      box(g, 0.12, 0.4, 0.12, '#8A6B4A', -0.18, 1.1, 0.12, { rx: -0.5 });
      box(g, 0.12, 0.4, 0.12, '#8A6B4A', 0.18, 1.1, 0.12, { rx: -0.5 });
    } else if (type === 'scooter') {
      box(g, 0.28, 0.1, 1.2, '#3D7BFF', 0, 0.22, 0);
      box(g, 0.08, 0.7, 0.08, '#B9C0C9', 0, 0.62, 0.5);
      box(g, 0.52, 0.06, 0.06, '#B9C0C9', 0, 0.96, 0.5);
      cyl(g, 0.16, 0.16, 0.1, 8, '#33302C', 0, 0.16, 0.5, { rz: Math.PI / 2 });
      cyl(g, 0.16, 0.16, 0.1, 8, '#33302C', 0, 0.16, -0.5, { rz: Math.PI / 2 });
    } else if (type === 'boat') {
      box(g, 2.0, 0.7, 4.4, '#8A6B4A', 0, 0.35, 0, { cast: true });
      box(g, 1.7, 0.34, 4.0, '#A9845A', 0, 0.72, 0);
      var prow = new THREE.Mesh(new THREE.ConeGeometry(0.9, 1.0, 4), mat('#8A6B4A'));
      prow.rotation.x = -Math.PI / 2;
      prow.rotation.y = Math.PI / 4;
      prow.position.set(0, 0.35, 2.6);
      g.add(prow);
      box(g, 1.4, 0.8, 1.4, '#FFF3D6', 0, 1.15, -0.7);
      box(g, 1.0, 0.5, 0.9, '#3E4E5C', 0, 1.22, -0.2);
      box(g, 0.08, 1.5, 0.08, '#6B5B4A', 0, 1.8, 0.6);
      var flag = new THREE.Mesh(new THREE.PlaneGeometry(0.8, 0.45), new THREE.MeshLambertMaterial({ color: P.coral, side: THREE.DoubleSide }));
      flag.position.set(0.4, 2.4, 0.6);
      g.add(flag);
    }

    return { group: g, wheels: wheels, beacons: beacons, door: door, type: type };
  }

  /* ---------------- 人物 ---------------- */

  var personShared = null;
  var PERSON_SPEC = {
    office: { shirt: '#6FA8DC', pants: '#3F4A5A', hair: '#3A2E26' },
    student: { shirt: '#F2C14E', pants: '#4A5A78', hair: '#3A2E26', bag: true },
    child: { shirt: '#F2826A', pants: '#6FA8DC', hair: '#4A3520', scale: 0.74 },
    parent: { shirt: '#F5DDD6', pants: '#6B5B4A', hair: '#4A3520' },
    dogwalker: { shirt: '#8FC7B0', pants: '#5B4B3A', hair: '#3A2E26' },
    courier: { shirt: '#FF9F43', pants: '#3F4A5A', hair: '#2F2620', bag: true },
    teacher: { shirt: '#A78BFA', pants: '#4A4458', hair: '#3A2E26' },
    doctor: { shirt: '#FFFFFF', pants: '#7FB8D9', hair: '#2F2620' },
    nurse: { shirt: '#FFFFFF', pants: '#8FD3A8', hair: '#3A2E26', cap: 'nurse' },
    police: { shirt: '#2E5C8A', pants: '#23384F', hair: '#2F2620', cap: 'police' },
    firefighter: { shirt: '#D9483A', pants: '#3A3A3A', hair: '#2F2620', cap: 'fire' },
    driver: { shirt: '#4B5563', pants: '#2F3540', hair: '#2F2620', cap: 'driver' },
    baker: { shirt: '#FFFFFF', pants: '#8A6B4A', hair: '#4A3520', apron: true }
  };

  function sharedPerson() {
    if (!personShared) {
      personShared = {
        headGeo: new THREE.SphereGeometry(0.25, 14, 12),
        headMat: mat('#F2C9A0'),
        hairGeo: new THREE.SphereGeometry(0.26, 12, 10),
        eyeGeo: new THREE.SphereGeometry(0.028, 6, 6),
        eyeMat: mat('#2D2A26'),
        legGeo: geoBox(0.19, 0.7, 0.2),
        armGeo: geoBox(0.14, 0.58, 0.17),
        footGeo: geoBox(0.2, 0.1, 0.3)
      };
    }
    return personShared;
  }

  function buildPerson(type) {
    var spec = PERSON_SPEC[type] || PERSON_SPEC.office;
    var S = sharedPerson();
    var g = new THREE.Group();

    var legL = new THREE.Group();
    legL.position.set(-0.13, 0.74, 0);
    var lm1 = new THREE.Mesh(S.legGeo, mat(spec.pants));
    lm1.position.y = -0.35;
    legL.add(lm1);
    var f1 = new THREE.Mesh(S.footGeo, mat('#4A4038'));
    f1.position.set(0, -0.72, 0.06);
    legL.add(f1);
    g.add(legL);

    var legR = new THREE.Group();
    legR.position.set(0.13, 0.74, 0);
    var lm2 = new THREE.Mesh(S.legGeo, mat(spec.pants));
    lm2.position.y = -0.35;
    legR.add(lm2);
    var f2 = new THREE.Mesh(S.footGeo, mat('#4A4038'));
    f2.position.set(0, -0.72, 0.06);
    legR.add(f2);
    g.add(legR);

    var torso = new THREE.Mesh(geoBox(0.5, 0.64, 0.3), mat(spec.shirt));
    torso.position.y = 1.08;
    torso.castShadow = true;
    g.add(torso);

    if (spec.apron) {
      box(g, 0.42, 0.5, 0.04, '#FFFDF8', 0, 1.0, 0.17);
    }
    if (spec.bag) {
      box(g, 0.16, 0.36, 0.3, '#C0392B', 0.32, 1.05, -0.02);
      box(g, 0.06, 0.5, 0.06, '#8A6B4A', 0.22, 1.18, -0.02);
    }

    var armL = new THREE.Group();
    armL.position.set(-0.31, 1.34, 0);
    var am1 = new THREE.Mesh(S.armGeo, mat(spec.shirt));
    am1.position.y = -0.28;
    armL.add(am1);
    var hand1 = new THREE.Mesh(geoCyl(0.07, 0.07, 0.12, 6), S.headMat);
    hand1.position.y = -0.6;
    armL.add(hand1);
    g.add(armL);

    var armR = new THREE.Group();
    armR.position.set(0.31, 1.34, 0);
    var am2 = new THREE.Mesh(S.armGeo, mat(spec.shirt));
    am2.position.y = -0.28;
    armR.add(am2);
    var hand2 = new THREE.Mesh(geoCyl(0.07, 0.07, 0.12, 6), S.headMat);
    hand2.position.y = -0.6;
    armR.add(hand2);
    g.add(armR);

    var head = new THREE.Mesh(S.headGeo, S.headMat);
    head.position.y = 1.64;
    head.castShadow = true;
    g.add(head);

    var hair = new THREE.Mesh(S.hairGeo, mat(spec.hair));
    hair.scale.set(1.01, 0.72, 0.96);
    hair.position.set(0, 1.76, -0.09);
    g.add(hair);

    var eyeL = new THREE.Mesh(S.eyeGeo, S.eyeMat);
    eyeL.position.set(-0.09, 1.68, 0.225);
    g.add(eyeL);
    var eyeR = new THREE.Mesh(S.eyeGeo, S.eyeMat);
    eyeR.position.set(0.09, 1.68, 0.225);
    g.add(eyeR);

    if (spec.cap === 'police') {
      cyl(g, 0.27, 0.29, 0.16, 10, '#1F3E5C', 0, 1.86, 0);
      box(g, 0.42, 0.05, 0.24, '#12304B', 0, 1.8, 0.2);
      box(g, 0.12, 0.08, 0.02, '#F2C14E', 0, 1.86, 0.29);
    } else if (spec.cap === 'nurse') {
      box(g, 0.34, 0.12, 0.3, '#FFFFFF', 0, 1.88, 0);
      box(g, 0.06, 0.04, 0.06, P.red, 0, 1.94, 0.1);
    } else if (spec.cap === 'fire') {
      var helm = new THREE.Mesh(new THREE.SphereGeometry(0.27, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), mat('#C33F33'));
      helm.position.y = 1.72;
      g.add(helm);
      box(g, 0.58, 0.05, 0.34, '#A93226', 0, 1.73, 0.16);
    } else if (spec.cap === 'driver') {
      cyl(g, 0.26, 0.27, 0.12, 10, '#2F3540', 0, 1.86, 0);
      box(g, 0.36, 0.04, 0.2, '#1F242C', 0, 1.81, 0.18);
    }

    if (spec.scale) { g.scale.setScalar(spec.scale); }
    var parts = { group: g, leftArm: armL, rightArm: armR, leftLeg: legL, rightLeg: legR, head: head };
    // 把部件引用挂到 group 上：场景层需要给人物的手挂雨伞
    g.userData.personParts = parts;
    return parts;
  }

  M.buildPerson = buildPerson;
  M.buildVehicle = buildVehicle;

  /* 室内建模复用这几个基础件，避免再写一套几何/材质辅助。
     都是纯函数式的「往 parent 里加一个盒子/圆柱」。 */
  M.tools = {
    mat: mat,
    matA: matA,
    box: box,
    cyl: cyl,
    flatPlane: flatPlane,
    geoBox: geoBox,
    shade: shade
  };

  /* ---------------- 主世界 ---------------- */

  /* ---------------- 天气道具 ---------------- */

  /* 雨伞工厂：伞面 + 伞骨 + 伞杆 + 弯手柄，整体高约 2 米。
     场景层会把它挂到人物手上（跟随走路摆动），models 里也用它做街边静态伞。 */
  M.makeUmbrella = function (color) {
    var g = new THREE.Group();
    var canopyMat = new THREE.MeshLambertMaterial({
      color: color || '#E5484D', flatShading: true, side: THREE.DoubleSide
    });
    // 伞面：开口朝下的八边形锥，顶点在中心偏下，看起来像撑开的伞
    var canopy = new THREE.Mesh(new THREE.ConeGeometry(0.88, 0.5, 8, 1, true), canopyMat);
    canopy.position.y = 1.6;
    canopy.castShadow = true;
    g.add(canopy);
    // 伞尖
    cyl(g, 0.028, 0.028, 0.3, 5, '#8A8F96', 0, 1.98, 0);
    // 伞杆
    cyl(g, 0.026, 0.026, 1.46, 5, '#8A8F96', 0, 0.86, 0);
    // 弯手柄
    var handle = new THREE.Mesh(new THREE.TorusGeometry(0.085, 0.024, 4, 8, Math.PI), mat('#8A6B4A'));
    handle.position.set(0.085, 0.14, 0);
    handle.rotation.z = Math.PI / 2;
    g.add(handle);
    // 伞骨合并成一个几何体（原先 8 根独立 mesh，现在 1 个），省 7 次 draw call
    var ribGeo = new THREE.BufferGeometry();
    var ribVerts = [];
    for (var ri = 0; ri < 8; ri++) {
      var ang = (ri / 8) * Math.PI * 2;
      var r0 = 0.06, r1 = 0.86;
      var y0 = 1.82, y1 = 1.44;
      ribVerts.push(Math.cos(ang) * r0, y0, Math.sin(ang) * r0);
      ribVerts.push(Math.cos(ang) * r1, y1, Math.sin(ang) * r1);
    }
    ribGeo.setAttribute('position', new THREE.Float32BufferAttribute(ribVerts, 3));
    var ribs = new THREE.LineSegments(ribGeo, mat('#CFC7B6'));
    g.add(ribs);
    return g;
  };

  M.buildWorld = function () {
    var root = new THREE.Group();
    var words = new Map();
    M.windowMats = [];
    // 落雪盖材质：所有屋顶共用一张白板材质，下雪时统一显隐
    M.snowMat = M.snowMat || new THREE.MeshLambertMaterial({
      color: '#F7FBFF', flatShading: true, transparent: true, opacity: 1
    });
    M.worldSnowCaps = [];
    var props = {
      clouds: [], birds: [], ducks: [], trees: [], flags: [], smoke: [],
      signals: [], dog: null, kite: null, guard: null, swingSeat: null,
      seesawBeam: null, fountain: null, fountainPoints: null, river: null,
      busStop: null, lamps: [], lampGlowMat: null, lampPoolMat: null, lampPoolGeo: null,
      stars: null, sunSprite: null, moonSprite: null, pigeons: [], cat: null,
      craneJib: null, craneHook: null, cableGroup: null, windows: M.windowMats,
      headlampMats: [], beaconMats: [], neonMats: [],
      // 天气相关：地面/路面材质（雨天变暗变湿）、屋顶面（积雪）、可摆动的小物件
      groundMats: [], roadMats: [], snowCaps: M.worldSnowCaps,
      umbrellas: [], cloudMats: [], puddleMat: null, puddleGeo: null, puddles: [], rain: null
    };

    function reg(id, node) {
      root.updateMatrixWorld(true);
      var bb = new THREE.Box3().setFromObject(node);
      if (bb.isEmpty() || !isFinite(bb.max.y)) {
        console.warn('[WordCity] 缺少可计算包围盒：' + id);
        words.set(id, { node: node, labelOffset: new THREE.Vector3(0, 4, 0) });
        return;
      }
      var c = bb.getCenter(new THREE.Vector3());
      var local = node.worldToLocal(new THREE.Vector3(c.x, bb.max.y + 1.8, c.z));
      words.set(id, { node: node, labelOffset: local, top: bb.max.y });
    }

    // 纯装饰组：不进 word 体系、不做动画，最后统一合批以压低 draw call
    var staticBag = [];
    function addStatic(g) {
      root.add(g);
      staticBag.push(g);
      return g;
    }

    /* ---------- 地面与基座 ---------- */

    box(root, 140, 6, 112, P.soil, 0, -3.0, 0, { receive: true });

    // 草地：噪点贴图只做明暗，颜色交给 material.color（白色起点 → 着色）
    var grassTex = noiseTexture('#FFFFFF', { amount: 0.1, dots: 1400, dotSize: 2, repeatX: 16, repeatY: 13 });
    var grassMat = new THREE.MeshLambertMaterial({ map: grassTex, flatShading: true });
    grassMat.color.set(P.grass);
    flatPlane(root, 136, 108, P.grass, 0, 0.012, 0, { material: grassMat });
    var grassDeepTex = noiseTexture('#FFFFFF', { amount: 0.11, dots: 1200, repeatX: 5, repeatY: 4 });
    var grassDeepMat = new THREE.MeshLambertMaterial({ map: grassDeepTex, flatShading: true });
    grassDeepMat.color.set(shade(P.grass, -0.06));
    flatPlane(root, 44, 30, shade(P.grass, -0.06), 32, 0.02, 20, { material: grassDeepMat });
    var grassLightTex = noiseTexture('#FFFFFF', { amount: 0.09, dots: 1200, repeatX: 4, repeatY: 3 });
    var grassLightMat = new THREE.MeshLambertMaterial({ map: grassLightTex, flatShading: true });
    grassLightMat.color.set(shade(P.grass, 0.06));
    flatPlane(root, 30, 24, shade(P.grass, 0.06), -34, 0.02, 24, { material: grassLightMat });
    flatPlane(root, 34, 22, shade(P.grass, -0.04), 20, 0.021, -22, { material: grassDeepMat });
    // 草地上色随天气变化：雨天压暗、雪天泛白
    props.groundMats.push(
      { mat: grassMat, base: new THREE.Color(P.grass) },
      { mat: grassDeepMat, base: new THREE.Color(shade(P.grass, -0.06)) },
      { mat: grassLightMat, base: new THREE.Color(shade(P.grass, 0.06)) }
    );

    box(root, 140, 0.7, 1.0, '#C9BFAE', 0, 0.35, 55.5);
    box(root, 140, 0.7, 1.0, '#C9BFAE', 0, 0.35, -55.5);
    box(root, 1.0, 0.7, 112, '#C9BFAE', 69.5, 0.35, 0);
    box(root, 1.0, 0.7, 112, '#C9BFAE', -69.5, 0.35, 0);

    /* ---------- 道路 ---------- */

    var roadTex = noiseTexture(P.road, { amount: 0.14, dots: 1500, dotSize: 2, streaks: true, repeatX: 14, repeatY: 2 });
    var roadMat = new THREE.MeshLambertMaterial({ map: roadTex, flatShading: true });
    var roadTexV = noiseTexture(P.road, { amount: 0.14, dots: 1500, dotSize: 2, streaks: true, repeatX: 2, repeatY: 9 });
    var roadMatV = new THREE.MeshLambertMaterial({ map: roadTexV, flatShading: true });
    var mainRoad = flatPlane(root, 136, 9, P.road, 0, 0.05, 0, { material: roadMat });
    flatPlane(root, 8, 90, P.road, -10, 0.048, 0, { material: roadMatV });
    flatPlane(root, 7, 90, P.road, 35, 0.047, 0, { material: roadMatV });
    flatPlane(root, 136, 6, P.road, 0, 0.046, -32, { material: roadMat });
    // 路面随天气变暗变亮（湿沥青）
    props.roadMats.push(
      { mat: roadMat, base: new THREE.Color(P.road) },
      { mat: roadMatV, base: new THREE.Color(P.road) }
    );

    flatPlane(root, 136, 1.5, P.bike, 0, 0.061, 3.55);
    box(root, 136, 0.02, 0.08, '#F8F5EA', 0, 0.062, 2.78);
    box(root, 136, 0.02, 0.08, '#F8F5EA', 0, 0.062, 4.32);

    var walkMat = mat(P.sidewalk);
    box(root, 136, 0.16, 2.6, P.sidewalk, 0, 0.08, 5.8, { material: walkMat, receive: true });
    box(root, 136, 0.16, 2.6, P.sidewalk, 0, 0.081, -5.8, { material: walkMat, receive: true });
    box(root, 2.6, 0.16, 90, P.sidewalk, -15.3, 0.079, 0, { material: walkMat, receive: true });
    box(root, 2.6, 0.16, 90, P.sidewalk, -4.7, 0.082, 0, { material: walkMat, receive: true });
    box(root, 2.5, 0.16, 90, P.sidewalk, 30.2, 0.079, 0, { material: walkMat, receive: true });
    box(root, 2.5, 0.16, 90, P.sidewalk, 39.8, 0.081, 0, { material: walkMat, receive: true });
    box(root, 136, 0.16, 2.4, P.sidewalk, 0, 0.079, -36.2, { material: walkMat, receive: true });
    box(root, 136, 0.16, 2.4, P.sidewalk, 0, 0.082, -27.8, { material: walkMat, receive: true });

    box(root, 136, 0.18, 0.3, P.curb, 0, 0.09, 4.65);
    box(root, 136, 0.18, 0.3, P.curb, 0, 0.09, -4.65);
    box(root, 0.3, 0.18, 90, P.curb, -14.15, 0.09, 0);
    box(root, 0.3, 0.18, 90, P.curb, -5.85, 0.09, 0);
    box(root, 0.3, 0.18, 90, P.curb, 31.35, 0.09, 0);
    box(root, 0.3, 0.18, 90, P.curb, 38.65, 0.09, 0);
    box(root, 136, 0.18, 0.3, P.curb, 0, 0.09, -29.15);
    box(root, 136, 0.18, 0.3, P.curb, 0, 0.09, -34.85);

    (function laneDashes() {
      var dashGeo = geoBox(2.6, 0.02, 0.16);
      var list = [];
      var x;
      for (x = -64; x <= 64; x += 7) {
        if (Math.abs(x + 10) < 5 || Math.abs(x - 35) < 4.5) { continue; }
        list.push([x, 0.064, 0]);
      }
      for (var z = -42; z <= 42; z += 7) {
        if (Math.abs(z) < 5) { continue; }
        list.push([-10, 0.064, z]);
        list.push([35, 0.064, z]);
      }
      for (x = -64; x <= 64; x += 7) {
        if (Math.abs(x + 10) < 5 || Math.abs(x - 35) < 4.5) { continue; }
        list.push([x, 0.064, -32]);
      }
      var im = new THREE.InstancedMesh(dashGeo, mat(P.line), list.length);
      var m4 = new THREE.Matrix4();
      for (var i = 0; i < list.length; i++) {
        m4.makeTranslation(list[i][0], list[i][1], list[i][2]);
        im.setMatrixAt(i, m4);
      }
      im.instanceMatrix.needsUpdate = true;
      root.add(im);
    })();

    function zebra(x, z) {
      var g = new THREE.Group();
      g.position.set(x, 0, z);
      for (var i = -3; i <= 3; i++) {
        box(g, 3.0, 0.03, 0.52, '#F8F5EA', 0, 0.065, i * 1.08);
      }
      root.add(g);
      return g;
    }
    var crosswalkGroup = zebra(10, 0);
    zebra(-10, 0);
    zebra(35, 0);
    reg('crosswalk', crosswalkGroup);


    (function roadDetails() {
      var manholeMat = mat('#3E3F41');
      var mp = [[-18, 1.5], [8, 3.6], [26, -1.6], [44, 3.4]];
      for (var i = 0; i < mp.length; i++) {
        var m = new THREE.Mesh(new THREE.CircleGeometry(0.5, 12), manholeMat);
        m.rotation.x = -Math.PI / 2;
        m.position.set(mp[i][0], 0.066, mp[i][1]);
        root.add(m);
      }
      var arrowMat = mat('#F8F5EA');
      var ap = [[-28, 2.2], [2, 2.2], [22, 2.2], [-28, -2.2], [2, -2.2], [22, -2.2]];
      ap.forEach(function (p) {
        var g = new THREE.Group();
        g.position.set(p[0], 0.066, p[1]);
        g.rotation.y = p[1] > 0 ? Math.PI / 2 : -Math.PI / 2;
        var shaft = new THREE.Mesh(geoBox(0.16, 0.02, 1.2), arrowMat);
        shaft.position.z = -0.1;
        g.add(shaft);
        var head = new THREE.Mesh(new THREE.ConeGeometry(0.34, 0.7, 3), arrowMat);
        head.rotation.x = Math.PI / 2;
        head.position.z = 0.7;
        g.add(head);
        root.add(g);
      });
    })();

    reg('road', mainRoad);

    /* ---------- 河流与桥 ---------- */

    var riverPair = canvas2d(256, 64);
    var rg = riverPair[1];
    rg.fillStyle = '#77BFD9';
    rg.fillRect(0, 0, 256, 64);
    rg.strokeStyle = 'rgba(255,255,255,0.42)';
    rg.lineWidth = 3;
    for (var wy = 10; wy < 64; wy += 14) {
      rg.beginPath();
      for (var wx = 0; wx <= 256; wx += 16) {
        var yy = wy + Math.sin(wx / 26) * 3;
        if (wx === 0) { rg.moveTo(wx, yy); } else { rg.lineTo(wx, yy); }
      }
      rg.stroke();
    }
    var riverTex = toTex(riverPair[0], 8, 1);
    var riverMat = new THREE.MeshLambertMaterial({ map: riverTex, transparent: true, opacity: 0.94 });
    var river = flatPlane(root, 136, 8.4, P.water, 0, 0.07, 36.6, { material: riverMat });
    river.receiveShadow = false;
    props.river = { mesh: river, tex: riverTex };
    flatPlane(root, 136, 1.0, P.sand, 0, 0.055, 32.0);
    flatPlane(root, 136, 1.0, P.sand, 0, 0.055, 41.2);

    var bridge = new THREE.Group();
    bridge.position.set(35, 0, 36.6);
    for (var bi = 0; bi < 6; bi++) {
      var bz = -6 + bi * 2;
      var by = 0.9 + Math.sin(((bi + 0.5) / 6) * Math.PI) * 1.0;
      box(bridge, 7.0, 0.4, 2.1, '#B98B5E', 0, by, bz, { cast: true });
      box(bridge, 7.2, 0.12, 2.2, '#D0A475', 0, by + 0.24, bz);
    }
    for (var side = -1; side <= 1; side += 2) {
      for (var rp = 0; rp <= 7; rp++) {
        var pz = -7 + rp * 2;
        var py = 1.25 + Math.sin((rp / 7) * Math.PI) * 1.0;
        box(bridge, 0.14, 1.0, 0.14, '#8A6B4A', side * 3.3, py + 0.5, pz);
      }
      box(bridge, 0.18, 0.18, 15, '#A9845A', side * 3.3, 2.45, 0);
    }
    box(bridge, 8.4, 0.2, 1.2, '#D8CDBB', 0, 0.12, -7.3);
    box(bridge, 8.4, 0.2, 1.2, '#D8CDBB', 0, 0.12, 7.3);
    root.add(bridge);
    reg('bridge', bridge);

    /* ---------- 中央广场与喷泉 ---------- */

    var plazaPair = canvas2d(256, 256);
    var pg = plazaPair[1];
    pg.fillStyle = '#EFE7D6';
    pg.fillRect(0, 0, 256, 256);
    pg.strokeStyle = '#DED3BE';
    pg.lineWidth = 2;
    for (var t = 0; t <= 256; t += 32) {
      pg.beginPath(); pg.moveTo(t, 0); pg.lineTo(t, 256); pg.stroke();
      pg.beginPath(); pg.moveTo(0, t); pg.lineTo(256, t); pg.stroke();
    }
    var plazaTex = toTex(plazaPair[0], 2, 2);
    var plaza = box(root, 16, 0.16, 11, '#EFE7D6', 0, 0.08, 10.5, {
      material: new THREE.MeshLambertMaterial({ map: plazaTex, flatShading: true })
    });
    plaza.receiveShadow = true;
    box(root, 16.6, 0.18, 0.3, '#D8CDBB', 0, 0.09, 5.0);
    box(root, 16.6, 0.18, 0.3, '#D8CDBB', 0, 0.09, 16.0);
    box(root, 0.3, 0.18, 11.4, '#D8CDBB', 8.15, 0.09, 10.5);
    box(root, 0.3, 0.18, 11.4, '#D8CDBB', -8.15, 0.09, 10.5);

    var fountain = new THREE.Group();
    fountain.position.set(0, 0, 10);
    cyl(fountain, 3.2, 3.4, 0.55, 20, '#D8CDBB', 0, 0.32, 0);
    var water1 = new THREE.Mesh(new THREE.CircleGeometry(2.95, 24), matA('#8FD3E8', 0.86));
    water1.rotation.x = -Math.PI / 2;
    water1.position.y = 0.61;
    fountain.add(water1);
    cyl(fountain, 1.9, 2.05, 0.5, 18, '#D8CDBB', 0, 0.95, 0);
    var water2 = new THREE.Mesh(new THREE.CircleGeometry(1.75, 22), matA('#A6E1F0', 0.9));
    water2.rotation.x = -Math.PI / 2;
    water2.position.y = 1.21;
    fountain.add(water2);
    cyl(fountain, 0.72, 0.86, 0.45, 14, '#D8CDBB', 0, 1.55, 0);
    var water3 = new THREE.Mesh(new THREE.CircleGeometry(0.62, 16), matA('#C3EDF7', 0.92));
    water3.rotation.x = -Math.PI / 2;
    water3.position.y = 1.79;
    fountain.add(water3);
    cyl(fountain, 0.16, 0.2, 1.2, 8, '#F8F5EA', 0, 2.0, 0);
    root.add(fountain);
    props.fountain = fountain;

    (function fountainParticles() {
      var count = 90;
      var pos = new Float32Array(count * 3);
      var seeds = [];
      for (var i = 0; i < count; i++) {
        seeds.push({
          a: (i * 2.39996) % (Math.PI * 2),
          r: 0.2 + ((i * 37) % 100) / 100 * 1.9,
          p: ((i * 53) % 100) / 100,
          s: 1.4 + ((i * 29) % 100) / 100 * 1.6
        });
      }
      var geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      var pm = new THREE.PointsMaterial({
        color: '#E9F9FF', size: 0.26, transparent: true, opacity: 0.9, depthWrite: false
      });
      var points = new THREE.Points(geo, pm);
      points.position.set(0, 2.45, 10);
      root.add(points);
      props.fountainPoints = { points: points, seeds: seeds, positions: pos, count: count, geo: geo };
    })();

    /* ---------- 公交站 ---------- */

    var busStop = new THREE.Group();
    busStop.position.set(10, 0, 6.4);
    cyl(busStop, 0.1, 0.1, 3.0, 6, '#6B6F76', -2.1, 1.5, 0);
    cyl(busStop, 0.1, 0.1, 3.0, 6, '#6B6F76', 2.1, 1.5, 0);
    box(busStop, 5.0, 0.18, 1.8, '#6FA8DC', 0, 3.0, 0, { cast: true });
    box(busStop, 5.0, 0.06, 1.9, '#A9CFE3', 0, 3.1, 0);
    var glassMat = new THREE.MeshLambertMaterial({
      color: '#CFE7F5', transparent: true, opacity: 0.55, side: THREE.DoubleSide
    });
    box(busStop, 4.6, 1.9, 0.08, '#CFE7F5', 0, 1.6, -0.75, { material: glassMat });
    box(busStop, 3.6, 0.14, 0.6, '#C08B5C', 0, 0.55, -0.3);
    box(busStop, 0.12, 0.55, 0.5, '#8A6B4A', -1.5, 0.28, -0.3);
    box(busStop, 0.12, 0.55, 0.5, '#8A6B4A', 1.5, 0.28, -0.3);
    cyl(busStop, 0.07, 0.07, 3.4, 6, '#6B6F76', 2.7, 1.7, 0.6);
    addSign(busStop, 'BUS STOP', 1.5, 0.5, 2.7, 3.1, 0.68, {
      cw: 384, ch: 128, bg: '#FFF3D6', fg: '#2F5F8A', border: '#6FA8DC'
    });
    var timetable = new THREE.Mesh(
      new THREE.PlaneGeometry(1.2, 1.6),
      new THREE.MeshLambertMaterial({
        map: signTexture('12  ·  35', { cw: 256, ch: 320, bg: '#FFFDF8', fg: '#3A332B', radius: 10 }),
        transparent: true
      })
    );
    timetable.position.set(2.7, 1.9, 0.68);
    busStop.add(timetable);
    root.add(busStop);
    props.busStop = busStop;
    reg('bus_stop', busStop);

    /* ---------- 红绿灯 ---------- */

    function buildSignal(x, z, ry, offset) {
      var g = new THREE.Group();
      g.position.set(x, 0, z);
      g.rotation.y = ry || 0;
      cyl(g, 0.1, 0.13, 4.4, 8, '#4A4E55', 0, 2.2, 0);
      box(g, 0.82, 2.0, 0.42, '#23262B', 0, 3.5, 0.3);
      var bulbs = [];
      var defs = [['red', '#E5484D'], ['yellow', '#F5A524'], ['green', '#30A46C']];
      for (var i = 0; i < 3; i++) {
        var m = new THREE.Mesh(
          new THREE.SphereGeometry(0.19, 10, 8),
          new THREE.MeshBasicMaterial({ color: '#2A2A2A' })
        );
        m.position.set(0, 4.18 - i * 0.62, 0.53);
        g.add(m);
        bulbs.push({ name: defs[i][0], color: defs[i][1], mat: m.material });
      }
      box(g, 0.5, 0.82, 0.3, '#23262B', 0, 2.35, 0.3);
      var pr = new THREE.Mesh(new THREE.SphereGeometry(0.1, 8, 6), new THREE.MeshBasicMaterial({ color: '#572B2B' }));
      pr.position.set(0, 2.52, 0.47);
      g.add(pr);
      var pgr = new THREE.Mesh(new THREE.SphereGeometry(0.1, 8, 6), new THREE.MeshBasicMaterial({ color: '#234A38' }));
      pgr.position.set(0, 2.2, 0.47);
      g.add(pgr);
      root.add(g);
      var sig = {
        group: g, bulbs: bulbs, pedRed: pr.material, pedGreen: pgr.material,
        x: x, z: z, offset: offset || 0
      };
      props.signals.push(sig);
      return sig;
    }

    var signalWord = null;
    [[-10, 0], [35, 7]].forEach(function (it, idx) {
      var ix = it[0];
      var off = it[1];
      var corners = [
        [ix + 3.9, 5.7, 0],
        [ix - 3.9, 5.7, 0],
        [ix + 3.9, -5.7, Math.PI],
        [ix - 3.9, -5.7, Math.PI]
      ];
      corners.forEach(function (c) {
        var s = buildSignal(c[0], c[1], c[2], off);
        if (!signalWord && idx === 0 && c[1] > 0) { signalWord = s; }
      });
    });
    reg('traffic_light', signalWord.group);

    reg('fountain', fountain);

    /* ---------- 北侧：医院 / 消防站 / 学校 / 图书馆 ---------- */

    var hospital = makeBuilding({
      x: -42, z: -21, w: 18, d: 13, h: 14,
      color: '#EAF4EF', roofColor: '#CFE3D8', cols: 5, rows: 4, doorW: 2.6
    });
    box(hospital, 6.2, 0.3, 3.0, '#CFE3D8', 0, 3.5, 8.0);
    cyl(hospital, 0.14, 0.14, 3.3, 6, '#B9CFC4', -2.6, 1.72, 9.0);
    cyl(hospital, 0.14, 0.14, 3.3, 6, '#B9CFC4', 2.6, 1.72, 9.0);
    addSign(hospital, 'HOSPITAL', 7.4, 1.5, 0, 4.7, 6.78, {
      bg: '#FFFDF8', fg: '#2E6B5A', border: '#9EC9B9'
    });
    box(hospital, 2.6, 0.8, 0.16, '#E5484D', 0, 8.6, 6.56);
    box(hospital, 0.8, 2.6, 0.16, '#E5484D', 0, 8.6, 6.56);
    box(hospital, 3.0, 0.5, 0.4, '#E5484D', 0, 14.5, 5.0);
    box(hospital, 0.5, 3.0, 0.4, '#E5484D', 0, 15.6, 5.0);
    flatPlane(hospital, 7.0, 4.0, '#E9E4D8', 8.0, 0.03, 9.5);
    /* 医院门前：救护车坡道雨棚 + 轮椅坡道扶手 + 长椅 + 绿篱 */
    (function hospitalExtras() {
      // 入口雨棚（悬挑）
      box(hospital, 8.4, 0.22, 3.4, '#DCEDE6', 0, 4.4, 7.4, { cast: true });
      cyl(hospital, 0.1, 0.1, 4.3, 6, '#B9CFC4', -3.8, 2.15, 8.85);
      cyl(hospital, 0.1, 0.1, 4.3, 6, '#B9CFC4', 3.8, 2.15, 8.85);
      // 无障碍坡道
      var ramp = new THREE.Group();
      ramp.position.set(-6.4, 0, 7.2);
      box(ramp, 3.2, 0.14, 3.6, '#DFD8C9', 0, 0.42, 0, { rx: -0.09 });
      box(ramp, 0.08, 0.7, 3.6, '#B9C0C9', -1.55, 0.85, 0);
      box(ramp, 0.08, 0.7, 3.6, '#B9C0C9', 1.55, 0.85, 0);
      hospital.add(ramp);
      // 长椅
      var hb = new THREE.Group();
      hb.position.set(5.6, 0, 8.4);
      hb.rotation.y = Math.PI;
      box(hb, 2.0, 0.14, 0.55, '#C08B5C', 0, 0.48, 0);
      box(hb, 2.0, 0.6, 0.1, '#C08B5C', 0, 0.82, -0.24);
      box(hb, 0.1, 0.44, 0.44, '#8A6B4A', -0.84, 0.22, 0);
      box(hb, 0.1, 0.44, 0.44, '#8A6B4A', 0.84, 0.22, 0);
      hospital.add(hb);
      // 绿篱
      for (var hi2 = 0; hi2 < 6; hi2++) {
        var hedge = new THREE.Mesh(new THREE.IcosahedronGeometry(0.52, 0), mat(hi2 % 2 ? P.leaf : P.leafDeep));
        hedge.position.set(-8.6 + hi2 * 1.0, 0.5, 9.4);
        hedge.scale.set(1, 0.85, 1);
        hospital.add(hedge);
      }
    })();
    root.add(hospital);
    reg('hospital', hospital);

    var fireStation = makeBuilding({
      x: -22, z: -23, w: 14, d: 11, h: 8.4,
      color: '#D9705C', roofColor: '#B45444', cols: 4, rows: 2, doorW: 3.2, bricks: true
    });
    box(fireStation, 4.4, 4.0, 0.16, '#8C3F32', -3.4, 2.0, 5.58);
    box(fireStation, 4.4, 4.0, 0.16, '#8C3F32', 2.4, 2.0, 5.58);
    for (var si = 0; si < 7; si++) {
      box(fireStation, 4.2, 0.06, 0.04, '#A64F40', -3.4, 0.45 + si * 0.55, 5.67);
      box(fireStation, 4.2, 0.06, 0.04, '#A64F40', 2.4, 0.45 + si * 0.55, 5.67);
    }
    addSign(fireStation, 'FIRE STATION', 7.6, 1.4, 0, 5.7, 5.62, {
      bg: '#FFF3D6', fg: '#8C3F32', border: '#E0A48F'
    });
    box(fireStation, 0.5, 2.2, 0.5, '#C9BFAE', 5.2, 9.4, -1.5);
    root.add(fireStation);
    reg('fire_station', fireStation);

    var school = makeBuilding({
      x: 14, z: -21, w: 24, d: 14, h: 11,
      color: '#FFF3D6', roofColor: '#E37D64', cols: 6, rows: 3, doorW: 3.0
    });
    box(school, 4.2, 7.0, 4.2, '#F5E3BC', 0, 14.5, 0, { cast: true });
    var clockPair = canvas2d(128, 128);
    var cg2 = clockPair[1];
    cg2.fillStyle = '#FFFDF8';
    cg2.beginPath(); cg2.arc(64, 64, 58, 0, Math.PI * 2); cg2.fill();
    cg2.strokeStyle = '#E37D64'; cg2.lineWidth = 8;
    cg2.beginPath(); cg2.arc(64, 64, 54, 0, Math.PI * 2); cg2.stroke();
    cg2.strokeStyle = '#3A332B'; cg2.lineWidth = 5;
    cg2.beginPath(); cg2.moveTo(64, 64); cg2.lineTo(64, 30); cg2.stroke();
    cg2.beginPath(); cg2.moveTo(64, 64); cg2.lineTo(90, 72); cg2.stroke();
    var clockFace = new THREE.Mesh(
      new THREE.PlaneGeometry(3.0, 3.0),
      new THREE.MeshLambertMaterial({ map: toTex(clockPair[0]), transparent: true })
    );
    clockFace.position.set(0, 15.4, 2.15);
    school.add(clockFace);
    var clockRoof = new THREE.Mesh(new THREE.ConeGeometry(3.4, 2.4, 4), mat('#E37D64'));
    clockRoof.rotation.y = Math.PI / 4;
    clockRoof.position.set(0, 19.2, 0);
    school.add(clockRoof);
    addSign(school, 'SCHOOL', 7.0, 1.5, 0, 3.9, 7.1, {
      bg: '#FFFDF8', fg: '#B4553F', border: '#F0B49F'
    });
    cyl(school, 0.09, 0.11, 13.0, 6, '#C9BFAE', -10.5, 6.5, 6.0);
    var flagMesh = new THREE.Mesh(
      new THREE.PlaneGeometry(2.4, 1.5),
      new THREE.MeshLambertMaterial({ color: P.coral, side: THREE.DoubleSide })
    );
    flagMesh.position.set(-9.2, 12.2, 6.0);
    school.add(flagMesh);
    props.flags.push(flagMesh);
    root.add(school);
    reg('school', school);

    var library = makeBuilding({
      x: 46, z: -24, w: 12, d: 10, h: 9,
      color: '#CFE7F5', roofColor: '#A9CFE3', cols: 3, rows: 3, doorW: 2.2
    });
    for (var ai = 0; ai < 3; ai++) {
      var arch = new THREE.Mesh(new THREE.CircleGeometry(0.7, 12, 0, Math.PI), mat('#FFF9EC'));
      arch.position.set(-3 + ai * 3, 5.2, 5.06);
      library.add(arch);
    }
    addSign(library, 'LIBRARY', 6.0, 1.3, 0, 6.8, 5.06, {
      bg: '#FFFDF8', fg: '#2F5F8A', border: '#A9CFE3'
    });
    box(library, 2.4, 2.0, 0.2, '#6FA8DC', 4.6, 4.6, 5.1);
    box(library, 0.3, 1.7, 0.25, '#FFFDF8', 4.6, 4.6, 5.2);
    flatPlane(library, 6, 2, '#D8CDBB', 0, 0.02, 6.4);
    root.add(library);
    reg('library', library);

    /* 校门与围栏 */
    (function schoolGateFence() {
      var gate = new THREE.Group();
      gate.position.set(10, 0, -8.2);
      box(gate, 0.5, 3.0, 0.5, '#FFF3D6', -2.6, 1.5, 0);
      box(gate, 0.5, 3.0, 0.5, '#FFF3D6', 2.6, 1.5, 0);
      box(gate, 6.6, 0.5, 0.6, '#E37D64', 0, 3.1, 0);
      addSign(gate, 'SCHOOL', 5.2, 0.9, 0, 3.15, 0.32, { cw: 384, ch: 96, fg: '#8C3F32' });
      root.add(gate);
      for (var fx = 2; fx <= 26; fx += 3) {
        if (fx > 7 && fx < 13) { continue; }
        box(root, 0.16, 1.1, 0.16, '#E8E1D4', fx, 0.55, -8.2);
      }
      box(root, 24, 0.1, 0.1, '#E8E1D4', 14, 1.0, -8.2);
      flatPlane(root, 22, 10, '#EDE4D1', 14, 0.03, -14);

      /* 操场：跑道 + 篮球架 + 球门 + 跳房子格子（图书馆东侧空地，默认视角不被建筑挡住） */
      var yard = new THREE.Group();
      yard.position.set(56, 0, -12);
      // 塑胶跑道
      var trackOuter = new THREE.Mesh(new THREE.RingGeometry(5.2, 7.0, 32), mat('#D9705C'));
      trackOuter.rotation.x = -Math.PI / 2;
      trackOuter.position.y = 0.05;
      yard.add(trackOuter);
      var trackInner = new THREE.Mesh(new THREE.CircleGeometry(5.15, 32), mat('#7ECB6A'));
      trackInner.rotation.x = -Math.PI / 2;
      trackInner.position.y = 0.055;
      yard.add(trackInner);
      for (var lane = 0; lane < 4; lane++) {
        var ln = new THREE.Mesh(new THREE.RingGeometry(5.5 + lane * 0.4, 5.56 + lane * 0.4, 32), mat('#F8F5EA'));
        ln.rotation.x = -Math.PI / 2;
        ln.position.y = 0.06;
        yard.add(ln);
      }
      // 篮球架 ×2
      [-1, 1].forEach(function (side) {
        var hoop = new THREE.Group();
        hoop.position.set(side * 4.2, 0, side * 7.4);
        hoop.rotation.y = side > 0 ? Math.PI : 0;
        cyl(hoop, 0.09, 0.11, 3.0, 6, '#8A8F96', 0, 1.5, 0);
        box(hoop, 1.6, 1.0, 0.1, '#FFFDF8', 0, 3.2, 0.12);
        var rim = new THREE.Mesh(new THREE.TorusGeometry(0.26, 0.04, 5, 12), mat('#E5484D'));
        rim.rotation.x = Math.PI / 2;
        rim.position.set(0, 2.86, 0.4);
        hoop.add(rim);
        yard.add(hoop);
      });
      // 球门
      [-1, 1].forEach(function (side) {
        var goal = new THREE.Group();
        goal.position.set(side * 8.4, 0, 0);
        goal.rotation.y = side > 0 ? Math.PI / 2 : -Math.PI / 2;
        box(goal, 0.1, 1.8, 0.1, '#FFFDF8', -1.6, 0.9, 0, { cast: true });
        box(goal, 0.1, 1.8, 0.1, '#FFFDF8', 1.6, 0.9, 0, { cast: true });
        box(goal, 3.3, 0.1, 0.1, '#FFFDF8', 0, 1.82, 0);
        // 球网：半透明网格面（用 matA 避免无效 rgba 颜色）
        box(goal, 3.2, 1.8, 0.06, '#FFFFFF', 0, 0.9, -0.1, { material: matA('#FFFFFF', 0.3) });
        yard.add(goal);
      });
      // 跳房子格子
      for (var hb = 0; hb < 6; hb++) {
        box(yard, 0.9, 0.02, 0.9, hb % 2 ? '#F2C14E' : '#F8F5EA', -6.5 + (hb % 2) * 0.5, 0.07, -3.4 + hb * 1.0);
      }
      addStatic(yard);
    })();

    /* ---------- 南侧：超市 / 面包店 / 咖啡馆 / 邮局 / 警察局 / 电影院 ---------- */

    var supermarket = makeBuilding({
      x: -42, z: 21, w: 26, d: 14, h: 8, rotY: Math.PI,
      color: '#F6E6C4', roofColor: '#E5D3AC', cols: 7, rows: 2, doorW: 4.0
    });
    addAwning(supermarket, 16, 4.1, 7.7, '#E5484D', '#F2C14E');
    addSign(supermarket, 'SUPERMARKET', 10.0, 1.6, 0, 6.2, 7.25, {
      bg: '#FFFDF8', fg: '#A9472F', border: '#F0C8A8'
    });
    cyl(supermarket, 1.4, 1.4, 2.2, 10, '#C9BFAE', 8.5, 9.2, -3.0);
    box(supermarket, 2.6, 0.3, 2.6, '#B7A88E', 8.5, 8.2, -3.0);
    box(supermarket, 3.2, 0.6, 1.6, '#C08B5C', -10, 0.3, 7.4);
    for (var fi = 0; fi < 8; fi++) {
      var fruit = new THREE.Mesh(
        new THREE.SphereGeometry(0.22, 8, 6),
        mat(fi % 2 ? P.coral : P.mustard)
      );
      fruit.position.set(-11.1 + (fi % 4) * 0.6, 0.72, 7.0 + Math.floor(fi / 4) * 0.55);
      supermarket.add(fruit);
    }
    root.add(supermarket);
    reg('supermarket', supermarket);

    /* 超市门前：购物车 + 促销立牌 + 停车场雨棚支架（购物车是氛围，不占单词位） */
    (function supermarketExtras() {
      function trolley(x, z, ry) {
        var t = new THREE.Group();
        t.position.set(x, 0, z);
        t.rotation.y = ry || 0;
        box(t, 0.72, 0.5, 0.92, '#B9C0C9', 0, 0.62, 0, { cast: true });
        box(t, 0.72, 0.04, 0.92, '#8A94A0', 0, 0.88, 0);
        box(t, 0.06, 0.5, 0.06, '#8A94A0', -0.32, 0.36, -0.4);
        box(t, 0.06, 0.5, 0.06, '#8A94A0', 0.32, 0.36, -0.4);
        cyl(t, 0.1, 0.1, 0.05, 6, '#33302C', -0.3, 0.14, -0.4, { rz: Math.PI / 2 });
        cyl(t, 0.1, 0.1, 0.05, 6, '#33302C', 0.3, 0.14, -0.4, { rz: Math.PI / 2 });
        box(t, 0.5, 0.5, 0.06, '#8A94A0', 0, 1.1, 0.46);
        return t;
      }
      // 超市 rotY = π，正面朝 -z，所以推车和促销牌放在 z ≈ 13 的地面一侧
      root.add(trolley(-35.6, 13.4, 0.5));
      root.add(trolley(-34.3, 13.0, -0.3));
      // 促销 A 字牌
      var promo = new THREE.Group();
      promo.position.set(-31.6, 0, 13.4);
      promo.rotation.y = 0.4;
      var board = new THREE.Mesh(
        new THREE.PlaneGeometry(1.3, 1.1),
        new THREE.MeshLambertMaterial({
          map: signTexture('SALE', { cw: 256, ch: 216, bg: '#E5484D', fg: '#FFFDF8', radius: 14 }),
          transparent: true, side: THREE.DoubleSide
        })
      );
      board.position.set(0, 0.9, 0);
      board.rotation.x = -0.12;
      promo.add(board);
      box(promo, 0.08, 1.1, 0.08, '#8A6B4A', -0.6, 0.55, 0.1);
      box(promo, 0.08, 1.1, 0.08, '#8A6B4A', 0.6, 0.55, 0.1);
      root.add(promo);
    })();

    var bakery = makeBuilding({
      x: -34, z: 10, w: 8, d: 7, h: 5, rotY: Math.PI,
      color: '#FFF0D8', roofColor: '#D99C6B', cols: 2, rows: 1,
      doorW: 1.8, roof: 'pyramid', roofH: 2.4
    });
    addAwning(bakery, 5.2, 3.2, 3.7, '#F2826A', '#FFF3D6');
    addSign(bakery, 'BAKERY', 4.4, 1.0, 0, 4.0, 3.6, {
      bg: '#FFFDF8', fg: '#A9631A', border: '#F2C14E'
    });
    box(bakery, 0.9, 2.4, 0.9, '#C77B52', 2.6, 5.8, -1.4);
    box(bakery, 2.6, 0.8, 0.12, '#F5E6C8', -1.2, 2.2, 3.56);
    for (var bi2 = 0; bi2 < 4; bi2++) {
      var bread = new THREE.Mesh(new THREE.SphereGeometry(0.2, 8, 6), mat('#D9A25C'));
      bread.scale.set(1.5, 0.8, 1);
      bread.position.set(-2.1 + bi2 * 0.55, 2.32, 3.62);
      bakery.add(bread);
    }
    root.add(bakery);
    reg('bakery', bakery);

    (function bakerySmoke() {
      for (var i = 0; i < 6; i++) {
        var puff = new THREE.Mesh(
          new THREE.SphereGeometry(0.28, 8, 6),
          new THREE.MeshLambertMaterial({ color: '#F4F1EA', transparent: true, opacity: 0.7 })
        );
        puff.position.set(-36.6, 6.4, 11.4);
        root.add(puff);
        props.smoke.push({ mesh: puff, phase: i / 6 });
      }
    })();

    var cafe = makeBuilding({
      x: -20, z: 27, w: 9, d: 7, h: 4.6, rotY: Math.PI,
      color: '#FBE7C9', roofColor: '#D9A45C', cols: 2, rows: 1, doorW: 1.8
    });
    addAwning(cafe, 6.2, 3.1, 3.7, '#F2C14E', '#FFF3D6');
    addSign(cafe, 'CAFE', 3.4, 0.9, 0, 3.85, 3.62, {
      bg: '#3A332B', fg: '#FFF3D6', border: '#3A332B'
    });
    (function cafeTerrace() {
      var spots = [[-4.2, 4.6], [4.2, 5.0], [-4.0, 8.0]];
      spots.forEach(function (tp, idx) {
        var table = new THREE.Group();
        table.position.set(tp[0], 0, tp[1]);
        cyl(table, 0.7, 0.7, 0.08, 12, '#FFF9EC', 0, 0.72, 0);
        cyl(table, 0.06, 0.08, 0.72, 6, '#8A8F96', 0, 0.36, 0);
        cyl(table, 0.03, 0.03, 2.0, 6, '#B7A88E', 0, 1.2, 0);
        var um = new THREE.Mesh(
          new THREE.ConeGeometry(1.35, 0.6, 8),
          mat(idx === 1 ? '#F2826A' : '#6FCF97')
        );
        um.position.y = 2.25;
        table.add(um);
        cafe.add(table);
      });
      var menu = new THREE.Group();
      menu.position.set(3.0, 0, 9.2);
      box(menu, 0.08, 1.2, 0.06, '#8A6B4A', -0.6, 0.6, 0);
      box(menu, 0.08, 1.2, 0.06, '#8A6B4A', 0.6, 0.6, 0);
      var board = new THREE.Mesh(
        new THREE.PlaneGeometry(1.4, 1.0),
        new THREE.MeshLambertMaterial({
          map: signTexture('MENU', { cw: 256, ch: 192, bg: '#3A332B', fg: '#FFF3D6', radius: 10 }),
          transparent: true
        })
      );
      board.position.set(0, 0.85, 0.02);
      menu.add(board);
      cafe.add(menu);
    })();
    root.add(cafe);
    reg('cafe', cafe);

    var postOffice = makeBuilding({
      x: -52, z: 10.5, w: 9, d: 6, h: 7.2, rotY: Math.PI,
      color: '#BDD9F0', roofColor: '#96BEDF', cols: 3, rows: 2, doorW: 2.2
    });
    addSign(postOffice, 'POST OFFICE', 6.0, 1.3, 0, 4.8, 3.06, {
      bg: '#FFFDF8', fg: '#2F5F8A', border: '#96BEDF'
    });
    box(postOffice, 1.1, 0.8, 1.0, '#C08B5C', 4.0, 0.4, -3.0);
    box(postOffice, 0.9, 0.7, 0.8, '#D9A25C', 4.0, 1.15, -3.0);
    box(postOffice, 1.2, 0.9, 1.0, '#C08B5C', 5.4, 0.45, -3.2);
    root.add(postOffice);
    reg('post_office', postOffice);

    var police = makeBuilding({
      x: -22, z: 11.5, w: 10, d: 8, h: 7.2, rotY: Math.PI,
      color: '#E8F1FA', roofColor: '#B9D2EA', cols: 3, rows: 2, doorW: 2.2
    });
    addSign(police, 'POLICE', 5.2, 1.2, 0, 4.7, 4.06, {
      bg: '#2F5F8A', fg: '#FFFDF8', border: '#2F5F8A'
    });
    box(police, 3.2, 0.18, 0.18, '#3D7BFF', -3.4, 3.6, 4.1);
    root.add(police);
    reg('police_station', police);

    var cinema = makeBuilding({
      x: 48, z: 14, w: 13, d: 10, h: 9, rotY: Math.PI,
      color: '#F3D9D2', roofColor: '#D8A79B', cols: 3, rows: 2, doorW: 3.0
    });
    var cinemaPair = canvas2d(128, 512);
    var cs = cinemaPair[1];
    cs.fillStyle = '#3A332B';
    roundRect(cs, 4, 4, 120, 504, 14);
    cs.fill();
    cs.fillStyle = '#FFD08A';
    cs.font = '800 78px ' + FONT;
    cs.textAlign = 'center';
    cs.textBaseline = 'middle';
    var letters = 'CINEMA'.split('');
    for (var li2 = 0; li2 < letters.length; li2++) {
      cs.fillText(letters[li2], 64, 62 + li2 * 74);
    }
      var cinemaSign = new THREE.Mesh(
        new THREE.PlaneGeometry(1.8, 7.2),
        new THREE.MeshLambertMaterial({
          map: toTex(cinemaPair[0]), transparent: true,
          emissive: new THREE.Color('#FFCA7A'), emissiveIntensity: 0
        })
      );
      cinemaSign.position.set(-7.0, 5.6, 5.06);
      cinema.add(cinemaSign);
      props.neonMats.push(cinemaSign.material);
      // 电影院屋檐的小灯泡串：夜晚发亮
      for (var blb = 0; blb < 12; blb++) {
        var bulbMat = new THREE.MeshBasicMaterial({ color: '#FFF1C8' });
        var bulbMesh = new THREE.Mesh(new THREE.SphereGeometry(0.11, 6, 5), bulbMat);
        bulbMesh.position.set(-5.5 + blb * 1.0, 4.14, 5.82);
        cinema.add(bulbMesh);
        props.lamps.push(bulbMat);
      }
    box(cinema, 10.0, 0.4, 2.0, '#FFD08A', 0, 3.9, 5.8);
    addSign(cinema, 'CINEMA', 6.0, 1.2, 0, 3.9, 6.82, {
      bg: '#3A332B', fg: '#FFD08A'
    });
    box(cinema, 3.6, 0.05, 3.0, '#C0392B', 0, 0.06, 8.0);
    box(cinema, 2.2, 2.6, 2.0, '#FFF3D6', -6.0, 1.3, 8.4);
    box(cinema, 2.4, 0.3, 2.2, '#F2826A', -6.0, 2.75, 8.4);
    root.add(cinema);
    reg('cinema', cinema);

    /* ---------- 公园入口与街具 ---------- */

    var parkGate = new THREE.Group();
    parkGate.position.set(28, 0, 8.6);
    parkGate.rotation.y = Math.PI;
    box(parkGate, 0.7, 3.6, 0.7, '#8A6B4A', -3.0, 1.8, 0);
    box(parkGate, 0.7, 3.6, 0.7, '#8A6B4A', 3.0, 1.8, 0);
    box(parkGate, 6.4, 0.6, 0.8, '#8A6B4A', 0, 3.9, 0);
    addSign(parkGate, 'PARK', 5.0, 1.1, 0, 3.9, 0.46, {
      cw: 384, ch: 128, bg: '#FFF3D6', fg: '#3F7A45'
    });
    for (var ph = 0; ph < 6; ph++) {
      var bush = new THREE.Mesh(
        new THREE.IcosahedronGeometry(0.55, 0),
        mat(ph % 2 ? P.leaf : P.leafDeep)
      );
      bush.position.set(-3.0 + ph * 1.2, 0.55, 1.2);
      parkGate.add(bush);
    }
    root.add(parkGate);
    reg('park', parkGate);

    flatPlane(root, 26, 3.0, '#E9DFC8', 20, 0.03, 12.4);
    flatPlane(root, 3.0, 22, '#E9DFC8', 30, 0.031, 22);

    /* 公园细节：碎石小径、花丛、野餐桌、灌木球、木栅栏、蝴蝶
       注意空地边界：游乐场在 x 11..25 / z 14..26，公园路在 x 31.5..38.5，
       所以可用的绿化带是 x 25.5..31 的纵向窄条 + 游乐场南侧 z 26..30。 */
    (function parkDetails() {
      var park = new THREE.Group();
      // 蜿蜒小径：用压扁圆盘铺出自然曲线（同时保证行人道从这里穿过）
      var pathPts = [
        [28, 10.5], [27, 13], [29, 16], [27.6, 19], [29, 22], [28, 25], [24, 28], [17, 29.5]
      ];
      for (var pi = 0; pi < pathPts.length - 1; pi++) {
        for (var seg = 0; seg < 5; seg++) {
          var tk = seg / 5;
          var px2 = pathPts[pi][0] + (pathPts[pi + 1][0] - pathPts[pi][0]) * tk;
          var pz2 = pathPts[pi][1] + (pathPts[pi + 1][1] - pathPts[pi][1]) * tk;
          var pad = new THREE.Mesh(new THREE.CircleGeometry(1.35, 9), mat('#DFD2B8'));
          pad.rotation.x = -Math.PI / 2;
          pad.position.set(px2, 0.032, pz2);
          park.add(pad);
        }
      }
      // 灌木球：贴着绿化带两侧生长，中间留给小径与行人
      var bushSpots = [[25.6, 11.8], [30.6, 13.2], [30.7, 17.6], [25.5, 16.2],
                       [30.6, 21.4], [25.4, 24.2], [22.5, 27.2], [16.5, 29.0]];
      bushSpots.forEach(function (b, i) {
        var s = 0.72 + (i % 3) * 0.2;
        var bb = new THREE.Mesh(new THREE.IcosahedronGeometry(0.6 * s, 0), mat(i % 2 ? P.leaf : P.leafDeep));
        bb.position.set(b[0], 0.55 * s, b[1]);
        bb.castShadow = true;
        park.add(bb);
        var bb2 = new THREE.Mesh(new THREE.IcosahedronGeometry(0.42 * s, 0), mat(P.leafDeep));
        bb2.position.set(b[0] + 0.45 * s, 0.4 * s, b[1] + 0.28 * s);
        park.add(bb2);
      });
      // 小花圃：四组矮花，颜色错开
      var bedColors = ['#F2826A', '#F2C14E', '#FF8FA3', '#A78BFA'];
      [[27, 12.4], [30, 19.4], [26, 26.6], [19, 28.4]].forEach(function (bp, bi4) {
        var bed = new THREE.Group();
        bed.position.set(bp[0], 0, bp[1]);
        box(bed, 1.9, 0.16, 1.1, '#B7966B', 0, 0.08, 0);
        for (var fi = 0; fi < 5; fi++) {
          cyl(bed, 0.03, 0.03, 0.32, 4, '#4FA554', -0.7 + fi * 0.35, 0.3, 0);
          var blm = new THREE.Mesh(new THREE.SphereGeometry(0.12, 6, 5), mat(bedColors[(bi4 + fi) % 4]));
          blm.position.set(-0.7 + fi * 0.35, 0.48, 0);
          bed.add(blm);
        }
        park.add(bed);
      });
      // 野餐桌：放在绿化带南北两端的稍宽处
      [[29.5, 14.6], [20, 28.6]].forEach(function (tp) {
        var tb = new THREE.Group();
        tb.position.set(tp[0], 0, tp[1]);
        tb.rotation.y = tp[0] > 25 ? 0.5 : -0.4;
        box(tb, 1.9, 0.14, 0.95, '#C08B5C', 0, 0.74, 0, { cast: true });
        box(tb, 0.13, 0.72, 0.13, '#8A6B4A', -0.76, 0.37, 0);
        box(tb, 0.13, 0.72, 0.13, '#8A6B4A', 0.76, 0.37, 0);
        box(tb, 1.9, 0.12, 0.36, '#C08B5C', 0, 0.44, 0.74);
        box(tb, 1.9, 0.12, 0.36, '#C08B5C', 0, 0.44, -0.74);
        box(tb, 0.13, 0.4, 0.13, '#8A6B4A', -0.76, 0.19, 0.66);
        box(tb, 0.13, 0.4, 0.13, '#8A6B4A', 0.76, 0.19, 0.66);
        park.add(tb);
      });
      // 木栅栏：公园西边界与南边界（南边界留出小径缺口通往河边步道）
      function fenceRun(x0, z0, x1, z1, gap) {
        var len = Math.hypot(x1 - x0, z1 - z0);
        var n = Math.max(1, Math.floor(len / 2.0));
        for (var f = 0; f <= n; f++) {
          var ft = f / n;
          var fx2 = x0 + (x1 - x0) * ft;
          var fz2 = z0 + (z1 - z0) * ft;
          if (gap && Math.abs(fx2 - gap[0]) < 2.0 && Math.abs(fz2 - gap[1]) < 2.0) { continue; }
          box(park, 0.12, 0.85, 0.12, '#B7966B', fx2, 0.43, fz2);
          if (f < n) {
            var mt = ft + 0.5 / n;
            var mx2 = x0 + (x1 - x0) * mt;
            var mz2 = z0 + (z1 - z0) * mt;
            if (gap && Math.abs(mx2 - gap[0]) < 2.2 && Math.abs(mz2 - gap[1]) < 2.2) { continue; }
            var ry2 = Math.atan2(x1 - x0, z1 - z0);
            box(park, 0.07, 0.09, 1.9, '#C9A87C', mx2, 0.68, mz2, { ry: ry2 });
            box(park, 0.07, 0.09, 1.9, '#C9A87C', mx2, 0.4, mz2, { ry: ry2 });
          }
        }
      }
      fenceRun(11.4, 9.8, 11.4, 30.4, [11.4, 12.4]);
      fenceRun(11.4, 30.6, 44, 30.6, [17, 30.6]);
      // 蝴蝶：在花圃与灌木上方绕小圈
      var butterflyMat = [
        new THREE.MeshBasicMaterial({ color: '#FF9AB5', side: THREE.DoubleSide }),
        new THREE.MeshBasicMaterial({ color: '#F2C14E', side: THREE.DoubleSide })
      ];
      props.butterflies = [];
      [[27.5, 13.5], [30.4, 19.8], [26.4, 25.4], [21, 28.4]].forEach(function (bp, bi3) {
        var bf = new THREE.Group();
        var wL = new THREE.Mesh(new THREE.PlaneGeometry(0.26, 0.19), butterflyMat[bi3 % 2]);
        wL.position.x = -0.13;
        bf.add(wL);
        var wR = new THREE.Mesh(new THREE.PlaneGeometry(0.26, 0.19), butterflyMat[bi3 % 2]);
        wR.position.x = 0.13;
        bf.add(wR);
        bf.position.set(bp[0], 1.2, bp[1]);
        park.add(bf);
        props.butterflies.push({
          group: bf, wingL: wL, wingR: wR,
          phase: bi3 * 1.6, cx: bp[0], cz: bp[1]
        });
      });
      root.add(park);
    })();

    var heroTree = buildTree(1.55, '#5FB96F');
    heroTree.position.set(8, 0, 24);
    root.add(heroTree);
    reg('tree', heroTree);
    props.trees.push({ group: heroTree, phase: 0.4, amp: 0.022 });

    var grassPatch = new THREE.Group();
    grassPatch.position.set(57, 0, 24);
    var grassBase = new THREE.Mesh(new THREE.CircleGeometry(2.6, 18), mat('#6BC25F'));
    grassBase.rotation.x = -Math.PI / 2;
    grassBase.position.y = 0.02;
    grassPatch.add(grassBase);
    for (var gu = 0; gu < 12; gu++) {
      var blade = new THREE.Mesh(new THREE.ConeGeometry(0.08, 0.5, 3), mat('#4FA554'));
      blade.position.set(Math.sin(gu * 2.1) * 1.8, 0.26, Math.cos(gu * 1.7) * 1.8);
      grassPatch.add(blade);
    }
    root.add(grassPatch);
    reg('grass', grassPatch);

    var flowerBed = new THREE.Group();
    flowerBed.position.set(10, 0, 9.6);
    box(flowerBed, 4.2, 0.35, 2.2, '#C08B5C', 0, 0.17, 0);
    var flowerColors = ['#F2826A', '#F2C14E', '#FF8FA3', '#FFF3D6'];
    for (var fl = 0; fl < 9; fl++) {
      var fbx = -1.7 + (fl % 3) * 1.65;
      var fbz = -0.6 + Math.floor(fl / 3) * 0.6;
      cyl(flowerBed, 0.035, 0.035, 0.5, 4, '#4FA554', fbx, 0.55, fbz);
      var bloom = new THREE.Mesh(
        new THREE.SphereGeometry(0.17, 8, 6),
        mat(flowerColors[fl % flowerColors.length])
      );
      bloom.position.set(fbx, 0.84, fbz);
      flowerBed.add(bloom);
    }
    root.add(flowerBed);
    reg('flower', flowerBed);

    function buildBench() {
      var b = new THREE.Group();
      box(b, 2.2, 0.16, 0.6, '#C08B5C', 0, 0.5, 0);
      box(b, 2.2, 0.7, 0.12, '#C08B5C', 0, 0.9, -0.28);
      box(b, 0.12, 0.5, 0.5, '#8A6B4A', -0.9, 0.25, 0);
      box(b, 0.12, 0.5, 0.5, '#8A6B4A', 0.9, 0.25, 0);
      return b;
    }
    var bench = buildBench();
    bench.position.set(28.5, 0, 15.0);
    bench.rotation.y = -0.5;
    root.add(bench);
    reg('bench', bench);
    var bench2 = buildBench();
    bench2.position.set(-4.8, 0, 9.5);
    bench2.rotation.y = Math.PI / 2;
    root.add(bench2);

    var trash = new THREE.Group();
    trash.position.set(6.5, 0, 6.2);
    cyl(trash, 0.34, 0.3, 0.9, 10, '#4F7A63', 0, 0.45, 0);
    cyl(trash, 0.38, 0.38, 0.1, 10, '#3F6652', 0, 0.95, 0);
    root.add(trash);
    reg('trash_can', trash);

    function buildLamp(x, z, ry) {
      var g = new THREE.Group();
      g.position.set(x, 0, z);
      if (ry) { g.rotation.y = ry; }
      cyl(g, 0.09, 0.13, 5.2, 6, '#5A6068', 0, 2.6, 0);
      box(g, 1.6, 0.12, 0.12, '#5A6068', 0.8, 5.1, 0);
      var headMat = new THREE.MeshBasicMaterial({ color: '#D8CDB6' });
      var head = new THREE.Mesh(new THREE.SphereGeometry(0.26, 10, 8), headMat);
      head.position.set(1.5, 5.0, 0);
      g.add(head);
      cone(g, 0.38, 0.3, 8, '#3A3F45', 1.5, 5.24, 0);

      // 夜间光晕与地面光池：共用材质，黄昏开关统一淡入
      if (!props.lampGlowMat) {
        var gp = canvas2d(64, 64);
        var gg = gp[1];
        var grad = gg.createRadialGradient(32, 32, 1, 32, 32, 31);
        grad.addColorStop(0, 'rgba(255,236,190,0.95)');
        grad.addColorStop(0.35, 'rgba(255,208,130,0.5)');
        grad.addColorStop(1, 'rgba(255,190,90,0)');
        gg.fillStyle = grad;
        gg.fillRect(0, 0, 64, 64);
        var glowTex = toTex(gp[0]);
        props.lampGlowMat = new THREE.SpriteMaterial({
          map: glowTex, transparent: true, opacity: 0,
          depthWrite: false, blending: THREE.AdditiveBlending
        });
        props.lampPoolMat = new THREE.MeshBasicMaterial({
          map: glowTex, transparent: true, opacity: 0,
          depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide
        });
        props.lampPoolGeo = new THREE.PlaneGeometry(5.5, 5.5);
      }
      var arm = new THREE.Vector3(1.5, 0, 0).applyAxisAngle(new THREE.Vector3(0, 1, 0), ry || 0);
      var halo = new THREE.Sprite(props.lampGlowMat);
      halo.position.set(x + arm.x, 5.0, z + arm.z);
      halo.scale.set(2.8, 2.8, 1);
      root.add(halo);
      var pool = new THREE.Mesh(props.lampPoolGeo, props.lampPoolMat);
      pool.rotation.x = -Math.PI / 2;
      pool.position.set(x + arm.x, 0.2, z + arm.z);
      root.add(pool);
      props.lamps.push(headMat);

      root.add(g);
      return g;
    }
    var lampWord = buildLamp(-3.5, 5.9, 0);
    reg('streetlight', lampWord);
    buildLamp(20, 5.9, 0);
    buildLamp(44, 5.9, 0);
    buildLamp(-30, 5.9, 0);
    buildLamp(-54, 5.9, 0);
    buildLamp(-4, -5.9, Math.PI);
    buildLamp(24, -5.9, Math.PI);

    var mailbox = new THREE.Group();
    mailbox.position.set(-49.5, 0, 5.5);
    cyl(mailbox, 0.05, 0.05, 0.9, 6, '#3F5E7A', 0, 0.45, 0);
    box(mailbox, 0.9, 1.2, 0.7, '#3D7BFF', 0, 1.4, 0);
    box(mailbox, 0.7, 0.1, 0.04, '#1F3E5C', 0, 1.7, 0.36);
    root.add(mailbox);
    reg('mailbox', mailbox);

    function hydrant(x, z) {
      var g = new THREE.Group();
      g.position.set(x, 0, z);
      cyl(g, 0.18, 0.2, 0.7, 8, '#D9483A', 0, 0.35, 0);
      cyl(g, 0.12, 0.16, 0.2, 8, '#C33F33', 0, 0.78, 0);
      box(g, 0.5, 0.12, 0.14, '#C33F33', 0, 0.55, 0);
      root.add(g);
    }
    hydrant(2, 6.6);
    hydrant(-38, -6.2);
    hydrant(42, 8.0);

    function coneTraffic(x, z) {
      cone(root, 0.22, 0.55, 8, '#FF9F43', x, 0.28, z);
      box(root, 0.44, 0.06, 0.44, '#FF9F43', x, 0.03, z);
    }
    coneTraffic(-16, -2.6);
    coneTraffic(-15.2, -2.0);
    coneTraffic(38.6, 18.0);

    (function billboard() {
      var bb = new THREE.Group();
      bb.position.set(-44, 0, 8.6);
      bb.rotation.y = Math.PI;
      box(bb, 0.2, 3.2, 0.2, '#6B6F76', -2.4, 1.6, 0);
      box(bb, 0.2, 3.2, 0.2, '#6B6F76', 2.4, 1.6, 0);
      box(bb, 5.6, 2.6, 0.2, '#FFF3D6', 0, 3.9, 0);
      var ad = new THREE.Mesh(
        new THREE.PlaneGeometry(5.2, 2.2),
        new THREE.MeshLambertMaterial({
          map: signTexture('WORD CITY', { cw: 512, ch: 220, bg: '#FF9F43', fg: '#3A2306', radius: 12 }),
          transparent: true
        })
      );
      ad.position.set(0, 3.9, 0.12);
      bb.add(ad);
      root.add(bb);
    })();

    /* ---------- 学校门口值日警察 ---------- */

    var guard = buildPerson('police');
    guard.group.position.set(10, 0, 4.3);
    guard.group.rotation.y = Math.PI;
    root.add(guard.group);
    var guardSign = new THREE.Group();
    box(guardSign, 0.06, 1.1, 0.06, '#8A6B4A', 0, 0.55, 0);
    var stopBoard = new THREE.Mesh(
      new THREE.CircleGeometry(0.52, 8),
      new THREE.MeshLambertMaterial({
        map: signTexture('STOP', { cw: 256, ch: 256, bg: '#E5484D', fg: '#FFFDF8', radius: 28 }),
        transparent: true
      })
    );
    stopBoard.position.set(0, 1.2, 0.04);
    guardSign.add(stopBoard);
    guardSign.position.set(0.05, -0.55, 0.16);
    guard.rightArm.add(guardSign);
    props.guard = { person: guard, sign: guardSign };
    reg('police_officer', guard.group);

    /* ---------- 地标人物 ---------- */

    function placePerson(type, x, z, ry, id) {
      var p = buildPerson(type);
      p.group.position.set(x, 0, z);
      p.group.rotation.y = ry || 0;
      p.group.scale.setScalar(1.05);
      root.add(p.group);
      if (id) { reg(id, p.group); }
      return p;
    }

    placePerson('teacher', 8.4, -9.0, 0.5, 'teacher');
    placePerson('student', 18, -9.0, -0.4, 'student');
    placePerson('doctor', -38.5, -13.4, 0.2, 'doctor');
    placePerson('nurse', -45.5, -13.4, -0.2, 'nurse');
    placePerson('firefighter', -18.5, -18.2, 0.1, 'firefighter');
    placePerson('driver', 13.8, 6.3, -0.8, 'driver');
    placePerson('baker', -31.5, 6.1, 0.1, 'baker');

    (function balloonSeller() {
      var seller = buildPerson('parent');
      seller.group.position.set(-5.2, 0, 17.2);
      seller.group.rotation.y = 0.6;
      root.add(seller.group);
      var colors = ['#F2826A', '#F2C14E', '#6FCF97', '#6FA8DC', '#A78BFA'];
      for (var i = 0; i < 5; i++) {
        var b = new THREE.Mesh(new THREE.SphereGeometry(0.32, 10, 8), mat(colors[i]));
        b.position.set(-5.2 + Math.sin(i * 1.3) * 0.9, 2.4 + (i % 3) * 0.35, 17.2 + Math.cos(i * 1.1) * 0.5);
        root.add(b);
      }
    })();

    /* ---------- 游乐场 ---------- */

    var playground = new THREE.Group();
    playground.position.set(18, 0, 20);
    var sand = box(playground, 14, 0.12, 12, '#EED9A6', 0, 0.06, 0);
    sand.receiveShadow = true;
    box(playground, 14.4, 0.2, 0.3, '#C08B5C', 0, 0.1, 6.0);
    box(playground, 14.4, 0.2, 0.3, '#C08B5C', 0, 0.1, -6.0);

    var swing = new THREE.Group();
    swing.position.set(-4, 0, 0);
    box(swing, 0.18, 3.0, 0.18, '#6FA8DC', -2.2, 1.5, -1.4, { rz: 0.28 });
    box(swing, 0.18, 3.0, 0.18, '#6FA8DC', -2.2, 1.5, 1.4, { rz: -0.28 });
    box(swing, 0.18, 3.0, 0.18, '#6FA8DC', 2.2, 1.5, -1.4, { rz: -0.28 });
    box(swing, 0.18, 3.0, 0.18, '#6FA8DC', 2.2, 1.5, 1.4, { rz: 0.28 });
    box(swing, 5.0, 0.18, 0.18, '#4F8CC9', 0, 2.9, 0);
    var seatPivot = new THREE.Group();
    seatPivot.position.set(0, 2.85, 0);
    box(seatPivot, 0.05, 2.0, 0.05, '#8A8F96', -0.7, -1.0, 0.18);
    box(seatPivot, 0.05, 2.0, 0.05, '#8A8F96', -0.7, -1.0, -0.18);
    box(seatPivot, 0.05, 2.0, 0.05, '#8A8F96', 0.7, -1.0, 0.18);
    box(seatPivot, 0.05, 2.0, 0.05, '#8A8F96', 0.7, -1.0, -0.18);
    box(seatPivot, 1.7, 0.12, 0.55, '#C08B5C', 0, -2.0, 0);
    swing.add(seatPivot);
    props.swingSeat = seatPivot;
    playground.add(swing);
    reg('swing', swing);

    var slide = new THREE.Group();
    slide.position.set(3.4, 0, 3.2);
    slide.rotation.y = -0.5;
    box(slide, 2.0, 0.2, 2.0, '#F2C14E', 0, 2.0, 0);
    box(slide, 0.16, 2.0, 0.16, '#6FA8DC', -0.9, 1.0, -0.9);
    box(slide, 0.16, 2.0, 0.16, '#6FA8DC', 0.9, 1.0, -0.9);
    box(slide, 0.16, 2.0, 0.16, '#6FA8DC', -0.9, 1.0, 0.9);
    box(slide, 0.16, 2.0, 0.16, '#6FA8DC', 0.9, 1.0, 0.9);
    box(slide, 1.8, 0.12, 0.18, '#4F8CC9', 0, 2.6, 0.94);
    box(slide, 1.6, 0.14, 4.8, '#F2826A', 0, 1.05, 3.3, { rx: 0.36 });
    box(slide, 0.14, 0.5, 4.8, '#E06E58', -0.9, 1.35, 3.3, { rx: 0.36 });
    box(slide, 0.14, 0.5, 4.8, '#E06E58', 0.9, 1.35, 3.3, { rx: 0.36 });
    for (var st = 0; st < 4; st++) {
      box(slide, 1.6, 0.08, 0.16, '#8A8F96', 0, 0.4 + st * 0.5, 1.5 - st * 0.35);
    }
    playground.add(slide);
    reg('slide', slide);

    var seesaw = new THREE.Group();
    seesaw.position.set(4.6, 0, -3.2);
    seesaw.rotation.y = 0.4;
    cone(seesaw, 0.5, 0.9, 4, '#8A6B4A', 0, 0.45, 0);
    var beam = new THREE.Group();
    beam.position.set(0, 0.95, 0);
    box(beam, 4.4, 0.16, 0.5, '#6FCF97', 0, 0, 0);
    box(beam, 0.5, 0.16, 0.72, '#F2826A', -2.1, 0.16, 0);
    box(beam, 0.5, 0.16, 0.72, '#F2C14E', 2.1, 0.16, 0);
    seesaw.add(beam);
    props.seesawBeam = beam;
    playground.add(seesaw);
    reg('seesaw', seesaw);
    root.add(playground);

    /* ---------- 池塘、鸭子、小狗、滑板车 ---------- */

    var pond = new THREE.Group();
    pond.position.set(46.5, 0, 25);
    var pondWater = new THREE.Mesh(new THREE.CircleGeometry(1, 40), matA('#6FB7D8', 0.9));
    pondWater.rotation.x = -Math.PI / 2;
    pondWater.scale.set(7.2, 4.4, 1);
    pondWater.position.y = 0.07;
    pond.add(pondWater);
    var pondRim = new THREE.Mesh(new THREE.RingGeometry(0.94, 1.04, 40), mat('#C9BFAE'));
    pondRim.rotation.x = -Math.PI / 2;
    pondRim.scale.set(7.6, 4.7, 1);
    pondRim.position.y = 0.06;
    pond.add(pondRim);
    for (var li3 = 0; li3 < 5; li3++) {
      var pad = new THREE.Mesh(new THREE.CircleGeometry(0.55, 10), mat('#5FAE54'));
      pad.rotation.x = -Math.PI / 2;
      pad.position.set(Math.sin(li3 * 2.2) * 4.5, 0.09, Math.cos(li3 * 1.7) * 2.6);
      pond.add(pad);
    }
    for (var re = 0; re < 8; re++) {
      var rx = Math.sin(re * 1.9) * 7.2;
      var rz = Math.cos(re * 1.3) * 4.2;
      cyl(pond, 0.035, 0.05, 1.1 + (re % 3) * 0.3, 4, '#4F8F52', rx, 0.55, rz);
    }
    root.add(pond);
    reg('pond', pond);

    for (var di = 0; di < 3; di++) {
      var duck = buildDuck();
      duck.position.set(46.5 + di * 1.5, 0.02, 25 + di);
      duck.scale.setScalar(0.9);
      root.add(duck);
      props.ducks.push({ group: duck, phase: di * 2.1, r: 2.4 + di * 0.9 });
      if (di === 0) { reg('duck', duck); }
    }

    var dog = buildDog();
    dog.group.position.set(28, 0, 26);
    dog.group.rotation.y = -0.8;
    root.add(dog.group);
    props.dog = dog;
    reg('dog', dog.group);

    var scooter = buildVehicle('scooter');
    scooter.group.position.set(29.5, 0, 10.2);
    scooter.group.rotation.y = -0.4;
    root.add(scooter.group);
    reg('scooter', scooter.group);

    /* ---------- 实例化树木与花丛 ---------- */

    var treeSpots = [
      [8, 8], [20, 9.5], [23, 8.8], [40, 8.5], [56, 20], [27, 27], [26, 30],
      [8, 17], [14, 29], [22, 30], [50, 30], [4, 26], [0, -12], [24, -12],
      [28, -18], [-2, -38], [24, -40], [30, -24], [-54, -12], [-56, -24],
      [-32, -28], [-36, -12], [-58, 18], [-46, 30], [-34, 30], [-10, 30],
      [-58, -8], [56, -40], [42, -38], [-62, 12]
    ];
    (function instancedTrees() {
      var trunkGeo = new THREE.CylinderGeometry(0.26, 0.36, 2.4, 6);
      var crownGeo = new THREE.IcosahedronGeometry(1.7, 0);
      var crown2Geo = new THREE.IcosahedronGeometry(1.15, 0);
      var trunks = new THREE.InstancedMesh(trunkGeo, mat(P.trunk), treeSpots.length);
      var crowns = new THREE.InstancedMesh(crownGeo, mat(P.leaf), treeSpots.length);
      var crowns2 = new THREE.InstancedMesh(crown2Geo, mat(shade(P.leaf, 0.12)), treeSpots.length);
      var m4 = new THREE.Matrix4();
      var q = new THREE.Quaternion();
      var pos = new THREE.Vector3();
      var scl = new THREE.Vector3();
      for (var i = 0; i < treeSpots.length; i++) {
        var s = 0.8 + ((i * 37) % 10) / 22;
        pos.set(treeSpots[i][0], 1.2 * s, treeSpots[i][1]);
        scl.set(s, s, s);
        m4.compose(pos, q, scl);
        trunks.setMatrixAt(i, m4);
        pos.set(treeSpots[i][0], 3.2 * s, treeSpots[i][1]);
        m4.compose(pos, q, scl);
        crowns.setMatrixAt(i, m4);
        pos.set(treeSpots[i][0] + 0.5 * s, 4.0 * s, treeSpots[i][1] + 0.2 * s);
        scl.set(s * 0.9, s * 0.9, s * 0.9);
        m4.compose(pos, q, scl);
        crowns2.setMatrixAt(i, m4);
      }
      trunks.instanceMatrix.needsUpdate = true;
      crowns.instanceMatrix.needsUpdate = true;
      crowns2.instanceMatrix.needsUpdate = true;
      trunks.castShadow = true;
      crowns.castShadow = true;
      root.add(trunks);
      root.add(crowns);
      root.add(crowns2);
    })();

    (function instancedFlowers() {
      var spots = [];
      var lcg = 20240501;
      function rnd() {
        lcg = (lcg * 1664525 + 1013904223) % 4294967296;
        return lcg / 4294967296;
      }
      for (var i = 0; i < 90; i++) {
        var x = -60 + rnd() * 120;
        var z = -40 + rnd() * 80;
        if (Math.abs(z) < 8.5) { continue; }
        if (Math.abs(x + 10) < 6.5) { continue; }
        if (Math.abs(x - 35) < 5.5) { continue; }
        if (Math.abs(z + 32) < 4) { continue; }
        if (z > 31 && z < 42) { continue; }
        spots.push([x, z, rnd()]);
      }
      var stemGeo = new THREE.CylinderGeometry(0.03, 0.03, 0.42, 4);
      var bloomGeo = new THREE.SphereGeometry(0.13, 6, 5);
      var stems = new THREE.InstancedMesh(stemGeo, mat('#4FA554'), spots.length);
      var blooms = new THREE.InstancedMesh(bloomGeo, mat('#FFFFFF'), spots.length);
      var m4 = new THREE.Matrix4();
      var colors = ['#F2826A', '#F2C14E', '#FF8FA3', '#A78BFA', '#FFF3D6'];
      var col = new THREE.Color();
      for (var j = 0; j < spots.length; j++) {
        m4.makeTranslation(spots[j][0], 0.2, spots[j][1]);
        stems.setMatrixAt(j, m4);
        m4.makeTranslation(spots[j][0], 0.44, spots[j][1]);
        blooms.setMatrixAt(j, m4);
        col.set(colors[Math.floor(spots[j][2] * colors.length)]);
        blooms.setColorAt(j, col);
      }
      stems.instanceMatrix.needsUpdate = true;
      blooms.instanceMatrix.needsUpdate = true;
      if (blooms.instanceColor) { blooms.instanceColor.needsUpdate = true; }
      root.add(stems);
      root.add(blooms);
    })();

    /* ---------- 城市扩展细节：电线杆 / 工地 / 停车场 / 河边步道 / 市集 ---------- */

    (function powerLines() {
      // 北侧电线杆一根根立起来，电线用 CatmullRom 曲线做出自然下垂
      var poleMat = '#8A7A64';
      var pts = [];
      for (var px = -60; px <= 56; px += 19) {
        pts.push([px, -37.5]);
      }
      var wireMat = new THREE.LineBasicMaterial({ color: '#5E5648', transparent: true, opacity: 0.55 });
      var poleRoot = new THREE.Group();
      pts.forEach(function (p, i) {
        var g = new THREE.Group();
        g.position.set(p[0], 0, p[1]);
        cyl(g, 0.16, 0.22, 8.2, 6, poleMat, 0, 4.1, 0);
        box(g, 2.6, 0.14, 0.14, shade(poleMat, 0.16), 0, 7.6, 0);
        box(g, 1.8, 0.12, 0.12, shade(poleMat, 0.16), 0, 6.9, 0);
        for (var k = -1; k <= 1; k += 2) {
          cyl(g, 0.1, 0.1, 0.3, 5, '#E8E1D4', k * 1.1, 7.78, 0);
        }
        cyl(g, 0.1, 0.1, 0.3, 5, '#E8E1D4', 0, 7.08, 0);
        poleRoot.add(g);
        if (i < pts.length - 1) {
          var nxt = pts[i + 1];
          [-1.1, 0, 1.1].forEach(function (off, wi) {
            var y0 = wi === 1 ? 7.08 : 6.6;
            var c1 = new THREE.CatmullRomCurve3([
              new THREE.Vector3(p[0] + off, y0, p[1]),
              new THREE.Vector3((p[0] + nxt[0]) / 2, y0 - 0.55, (p[1] + nxt[1]) / 2),
              new THREE.Vector3(nxt[0] + off, y0, nxt[1])
            ]);
            var wire = new THREE.Line(new THREE.BufferGeometry().setFromPoints(c1.getPoints(10)), wireMat);
            root.add(wire);
          });
        }
      });
      // 电线杆本身是静态的，合批；电线（Line）留给 draw call，数量很少
      staticBag.push(poleRoot);
      root.add(poleRoot);
    })();

    (function constructionSite() {
      // 西北角空地：围挡 + 塔吊 + 在建楼层 + 料堆，让城市有「正在长大」的感觉
      var site = new THREE.Group();
      site.position.set(-57, 0, -35);

      var groundPad = box(site, 20, 0.1, 14, '#C4B79C', 0, 0.08, 0);
      groundPad.receiveShadow = true;
      var dirt = flatPlane(site, 15, 10, '#B9A985', 1, 0.1, 1);
      dirt.receiveShadow = true;

      // 围挡
      for (var fx = -10; fx <= 10; fx += 2.5) {
        box(site, 0.12, 2.0, 0.12, '#8A8F96', fx, 1.0, 7.0);
        box(site, 0.12, 2.0, 0.12, '#8A8F96', fx, 1.0, -7.0);
      }
      box(site, 20, 0.12, 0.1, '#8A8F96', 0, 1.95, 7.0);
      box(site, 20, 0.12, 0.1, '#8A8F96', 0, 1.95, -7.0);
      box(site, 0.1, 0.12, 14, '#8A8F96', -10, 1.95, 0);
      for (var hx = -9.5; hx <= 9.5; hx += 2.0) {
        box(site, 1.9, 1.6, 0.08, '#F2C14E', hx, 0.95, 7.02);
        box(site, 1.9, 1.6, 0.08, '#F2C14E', hx, 0.95, -7.02);
      }
      for (var hz = -6.5; hz <= 6.5; hz += 2.0) {
        box(site, 0.08, 1.6, 1.9, '#F2C14E', -10.02, 0.95, hz);
      }

      // 在建楼：只有骨架和一半楼板
      var frame = new THREE.Group();
      frame.position.set(3, 0, -1);
      for (var fl = 0; fl < 3; fl++) {
        var fy = 0.4 + fl * 2.6;
        box(frame, 9, 0.24, 7, '#CFC7B6', 0, fy, 0, { cast: true });
        for (var ci = 0; ci < 4; ci++) {
          box(frame, 0.18, 2.6, 0.18, '#A9A296', -4 + ci * 2.66, fy + 1.3, -3.4);
          box(frame, 0.18, 2.6, 0.18, '#A9A296', -4 + ci * 2.66, fy + 1.3, 3.4);
        }
      }
      box(frame, 9, 0.24, 7, '#CFC7B6', 0, 0.4 + 2 * 2.6 + 2.7, 0);
      site.add(frame);

      // 塔吊
      var crane = new THREE.Group();
      crane.position.set(-3.5, 0, 0);
      box(crane, 1.0, 0.6, 1.0, '#B7A88E', 0, 0.3, 0);
      for (var seg = 0; seg < 6; seg++) {
        box(crane, 0.16, 2.4, 0.16, '#F5A524', -0.36, 0.7 + seg * 2.4, -0.36);
        box(crane, 0.16, 2.4, 0.16, '#F5A524', 0.36, 0.7 + seg * 2.4, -0.36);
        box(crane, 0.16, 2.4, 0.16, '#F5A524', -0.36, 0.7 + seg * 2.4, 0.36);
        box(crane, 0.16, 2.4, 0.16, '#F5A524', 0.36, 0.7 + seg * 2.4, 0.36);
        box(crane, 0.8, 0.1, 0.08, '#E09020', 0, 1.9 + seg * 2.4, 0.36);
      }
      var craneTop = 0.7 + 6 * 2.4;
      box(crane, 1.0, 1.2, 1.2, '#E09020', 0, craneTop + 0.6, 0);
      // 驾驶室
      box(crane, 1.4, 1.2, 1.4, '#F5F1E6', 1.2, craneTop + 0.4, 0, { cast: true });
      box(crane, 1.42, 0.5, 1.42, '#3E4E5C', 1.2, craneTop + 0.7, 0);
      // 吊臂
      var jib = new THREE.Group();
      jib.position.set(0, craneTop + 1.1, 0);
      jib.rotation.y = 0.62;
      box(jib, 16, 0.3, 0.36, '#F5A524', 6.5, 0, 0);
      box(jib, 16, 0.1, 0.9, '#E09020', 6.5, 0.2, 0);
      for (var jb = 0; jb < 8; jb++) {
        box(jib, 0.08, 0.5, 0.08, '#D8841C', 0.6 + jb * 1.9, -0.2, 0.42);
        box(jib, 0.08, 0.5, 0.08, '#D8841C', 0.6 + jb * 1.9, -0.2, -0.42);
      }
      box(jib, 3.4, 0.5, 0.6, '#8A8F96', -2.2, 0, 0);
      // 配重
      box(jib, 1.6, 1.1, 1.4, '#A9A296', -3.2, -0.4, 0);
      // 小车 + 吊钩
      var hookGroup = new THREE.Group();
      hookGroup.position.set(9.5, 0, 0);
      box(hookGroup, 0.7, 0.28, 0.7, '#8A8F96', 0, -0.1, 0);
      var cable = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 6, 4), mat('#5E5648'));
      cable.position.y = -3.1;
      hookGroup.add(cable);
      box(hookGroup, 0.5, 0.5, 0.36, '#A9A296', 0, -6.2, 0);
      jib.add(hookGroup);
      crane.add(jib);
      site.add(crane);
      props.craneJib = jib;
      props.craneHook = hookGroup;

      // 料堆：沙 / 砖 / 钢管
      var sandPile = new THREE.Mesh(new THREE.ConeGeometry(1.7, 1.1, 7), mat('#D9C79A'));
      sandPile.position.set(-6.5, 0.55, 3.6);
      site.add(sandPile);
      for (var br = 0; br < 3; br++) {
        box(site, 1.6, 0.5, 1.0, '#C0855B', -6.0 + br * 1.7, 0.25 + br * 0.04, 1.2);
      }
      for (var pp = 0; pp < 6; pp++) {
        cyl(site, 0.14, 0.14, 2.6, 6, '#8A8F96', -7.4 + (pp % 3) * 0.4, 0.3 + Math.floor(pp / 3) * 0.3, -3.4, { rz: Math.PI / 2 });
      }
      // 搅拌机
      var mixer = new THREE.Group();
      mixer.position.set(-6.8, 0, -5.0);
      box(mixer, 2.2, 0.5, 1.0, '#8A8F96', 0, 0.35, 0);
      var drum = new THREE.Mesh(new THREE.CylinderGeometry(0.72, 0.62, 1.8, 10), mat('#E8E1D4'));
      drum.rotation.z = 0.4;
      drum.position.set(0, 1.35, 0);
      mixer.add(drum);
      site.add(mixer);
      addStatic(site);
    })();

    (function parkingLot() {
      // 医院西侧停车场：车位线 + 三辆停着的车 + 一根挡车杆
      var lot = new THREE.Group();
      lot.position.set(-58, 0, -6.5);
      var pad = box(lot, 16, 0.1, 8, '#5A6068', 0, 0.055, 0);
      pad.receiveShadow = true;
      for (var s = -1; s <= 1; s++) {
        box(lot, 0.14, 0.02, 3.4, '#F8F5EA', s * 2.6, 0.11, 0);
      }
      box(lot, 8, 0.02, 0.12, '#F8F5EA', 0, 0.11, -1.9);
      ['#6FA8DC', '#F2C14E', '#FFF3D6'].forEach(function (c, i) {
        var parked = buildVehicle('car', c);
        parked.group.position.set(-2.6 + i * 2.6, 0.06, i === 1 ? 1.6 : -1.6);
        parked.group.rotation.y = i === 1 ? Math.PI : 0;
        lot.add(parked.group);
      });
      addStatic(lot);
    })();

    (function riverWalk() {
      // 河南岸步道：木栈道 + 护栏 + 长椅 + 垂柳
      var walk = new THREE.Group();
      walk.position.set(-20, 0, 45.5);
      box(walk, 96, 0.14, 4.6, '#C9A87C', 0, 0.09, 0);
      for (var wp = -47; wp <= 47; wp += 1.6) {
        box(walk, 0.1, 0.06, 4.5, '#B7966B', wp, 0.17, 0);
      }
      // 靠河一侧护栏
      for (var rp = -47; rp <= 47; rp += 3.2) {
        box(walk, 0.12, 1.0, 0.12, '#A9845A', rp, 0.62, -2.2);
      }
      box(walk, 96, 0.1, 0.12, '#A9845A', 0, 1.1, -2.2);
      box(walk, 96, 0.08, 0.1, '#B7966B', 0, 0.62, -2.2);
      // 沿途路灯与小长椅
      for (var bp = -42; bp <= 42; bp += 21) {
        var b = new THREE.Group();
        b.position.set(bp, 0, 1.4);
        b.rotation.y = Math.PI;
        box(b, 1.9, 0.14, 0.55, '#C08B5C', 0, 0.5, 0);
        box(b, 1.9, 0.6, 0.1, '#C08B5C', 0, 0.85, -0.24);
        box(b, 0.1, 0.45, 0.45, '#8A6B4A', -0.8, 0.23, 0);
        box(b, 0.1, 0.45, 0.45, '#8A6B4A', 0.8, 0.23, 0);
        walk.add(b);
      }
      // 花坛
      for (var fb = -35; fb <= 35; fb += 17.5) {
        box(walk, 3.2, 0.4, 1.4, '#B7966B', fb, 0.25, -1.4);
        for (var fi = 0; fi < 6; fi++) {
          var bl2 = new THREE.Mesh(new THREE.SphereGeometry(0.16, 6, 5), mat(fi % 2 ? '#FF8FA3' : '#FFF3D6'));
          bl2.position.set(fb - 1.2 + fi * 0.5, 0.55, -1.4 + (fi % 2) * 0.35);
          walk.add(bl2);
        }
      }
      addStatic(walk);
    })();

    (function marketStalls() {
      // 广场东侧小市集：三个条纹顶棚摊位 + 水果箱
      var stallColors = [
        ['#E5484D', '#FFF3D6'], ['#6FCF97', '#FFFDF8'], ['#F2C14E', '#FFFDF8']
      ];
      stallColors.forEach(function (cc, i) {
        var st = new THREE.Group();
        st.position.set(-27 + i * 5.6, 0, 18.4);
        st.rotation.y = Math.PI;
        box(st, 4.2, 1.0, 1.8, '#C08B5C', 0, 0.5, 0, { cast: true });
        box(st, 4.2, 0.12, 1.9, '#A9845A', 0, 1.0, 0);
        box(st, 0.12, 2.2, 0.12, '#8A6B4A', -1.9, 1.1, -0.7);
        box(st, 0.12, 2.2, 0.12, '#8A6B4A', 1.9, 1.1, -0.7);
        var canopy = new THREE.Mesh(
          geoBox(4.6, 0.18, 2.4),
          new THREE.MeshLambertMaterial({ map: stripeTexture(cc[0], cc[1]), flatShading: true })
        );
        canopy.position.set(0, 2.35, -0.3);
        canopy.rotation.x = -0.16;
        canopy.castShadow = true;
        st.add(canopy);
        for (var ci = 0; ci < 4; ci++) {
          box(st, 0.7, 0.4, 0.7, '#B98B5E', -1.5 + ci * 1.0, 1.22, 0.1);
        }
        addStatic(st);
      });
    })();

    (function skylineRing() {
      // 城市外围远景：一圈更低矮、更模糊的小房子，把「岛」变成「城市的一部分」
      // 先铺一层半径 210 的远景地面，远处房子和树群就「坐」在它上面，不会浮空
      var farGround = new THREE.Mesh(
        new THREE.CircleGeometry(212, 56),
        new THREE.MeshLambertMaterial({ color: '#A9CE9E', flatShading: true })
      );
      farGround.rotation.x = -Math.PI / 2;
      farGround.position.y = -1.15;
      farGround.receiveShadow = false;
      root.add(farGround);
      props.farGround = farGround.material;

      var ringColors = ['#DCD3C2', '#CFC7B6', '#C6D6CE', '#D8C9BE', '#CBC3D2'];
      var ringRoot = new THREE.Group();
      var seed = 7717;
      function rnd() {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        return seed / 2147483648;
      }
      // 远景楼按颜色分桶，每种颜色共享一张立面贴图 + 一个材质
      var distantMats = ringColors.map(function (c) {
        return new THREE.MeshLambertMaterial({ map: distantFacade(c), flatShading: true });
      });
      for (var i = 0; i < 34; i++) {
        var ang = (i / 34) * Math.PI * 2 + rnd() * 0.12;
        var rad = 90 + rnd() * 30;
        var bx = Math.cos(ang) * rad;
        var bz = Math.sin(ang) * rad;
        var hgt = 4 + rnd() * 15;
        var bw = 6 + rnd() * 8;
        var bd = 6 + rnd() * 8;
        var b = new THREE.Mesh(geoBox(bw, hgt, bd), distantMats[i % distantMats.length]);
        b.position.set(bx, hgt / 2 - 1.1, bz);
        b.rotation.y = rnd() * Math.PI;
        ringRoot.add(b);
        // 屋顶小帽子
        if (rnd() > 0.5) {
          var cap = new THREE.Mesh(new THREE.ConeGeometry(Math.max(bw, bd) * 0.55, 2.4, 4), mat(shade(ringColors[i % ringColors.length], -0.16)));
          cap.rotation.y = Math.PI / 4;
          cap.position.set(bx, hgt - 1.1 + 1.2, bz);
          ringRoot.add(cap);
        }
      }
      // 远处的树群：树干 + 树冠，避免只剩一团绿悬空
      for (var t = 0; t < 46; t++) {
        var ta = (t / 46) * Math.PI * 2 + 0.1;
        var tr = 80 + rnd() * 46;
        var tx = Math.cos(ta) * tr;
        var tz = Math.sin(ta) * tr;
        var ts = 1.1 + rnd() * 0.9;
        cyl(ringRoot, 0.22 * ts, 0.3 * ts, 2.2 * ts, 5, P.trunk, tx, 1.1 * ts - 1.1, tz);
        var crown = new THREE.Mesh(new THREE.IcosahedronGeometry(1.7 * ts, 0), mat(t % 3 ? '#6BB862' : '#5FAE54'));
        crown.position.set(tx, 2.6 * ts - 1.1, tz);
        ringRoot.add(crown);
      }
      staticBag.push(ringRoot);
      root.add(ringRoot);
    })();

    /* ---------- 天空：太阳、月亮、星星 ---------- */

    (function sky() {
      // 太阳：暖光晕 + 双层圆盘，跟随主光源方向，白天可见、黄昏下沉
      var sunGroup = new THREE.Group();
      sunGroup.position.set(96, 118, 62);
      var sunCore = new THREE.Mesh(
        new THREE.SphereGeometry(6.5, 16, 12),
        new THREE.MeshBasicMaterial({ color: '#FFF6D8' })
      );
      sunGroup.add(sunCore);
      var haloMat = new THREE.SpriteMaterial({
        map: glowTexture(), transparent: true, opacity: 0.85,
        depthWrite: false, blending: THREE.AdditiveBlending, fog: false
      });
      var halo = new THREE.Sprite(haloMat);
      halo.scale.set(52, 52, 1);
      sunGroup.add(halo);
      root.add(sunGroup);
      props.sunSprite = { group: sunGroup, halo: haloMat, core: sunCore.material };

      // 月亮：只在夜灯模式下淡入
      var moonGroup = new THREE.Group();
      moonGroup.position.set(-104, 128, -74);
      var moonMat = new THREE.MeshBasicMaterial({
        color: '#FFF8E4', transparent: true, opacity: 0, fog: false, depthWrite: false
      });
      var moon = new THREE.Mesh(new THREE.SphereGeometry(5.4, 16, 12), moonMat);
      moonGroup.add(moon);
      var moonHaloMat = new THREE.SpriteMaterial({
        map: glowTexture(), transparent: true, opacity: 0,
        depthWrite: false, blending: THREE.AdditiveBlending, fog: false, color: '#CBD8FF'
      });
      var moonHalo = new THREE.Sprite(moonHaloMat);
      moonHalo.scale.set(34, 34, 1);
      moonGroup.add(moonHalo);
      root.add(moonGroup);
      props.moonSprite = { group: moonGroup, core: moonMat, halo: moonHaloMat };

      // 星星：300 颗，贴近地平线的低仰角为主——俯视视角下也能出现在画面顶部
      var starCount = 300;
      var starPos = new Float32Array(starCount * 3);
      var starSeed = 9091;
      function rnd() {
        starSeed = (starSeed * 1103515245 + 12345) % 2147483648;
        return starSeed / 2147483648;
      }
      for (var i = 0; i < starCount; i++) {
        var a = rnd() * Math.PI * 2;
        var el = 0.03 + rnd() * rnd() * 1.15;
        var r = 230 + rnd() * 90;
        starPos[i * 3] = Math.cos(a) * Math.cos(el) * r;
        starPos[i * 3 + 1] = Math.sin(el) * r + 6;
        starPos[i * 3 + 2] = Math.sin(a) * Math.cos(el) * r;
      }
      var starGeo = new THREE.BufferGeometry();
      starGeo.setAttribute('position', new THREE.BufferAttribute(starPos, 3));
      // 关闭距离衰减：无论镜头拉多远，星星都保持可读的像素大小
      var starMat = new THREE.PointsMaterial({
        color: '#FFF6DC', size: 2.2, sizeAttenuation: false,
        transparent: true, opacity: 0, depthWrite: false, fog: false
      });
      var stars = new THREE.Points(starGeo, starMat);
      stars.frustumCulled = false;
      root.add(stars);
      props.stars = { points: stars, mat: starMat };

      // 远处的海／地平线色带，避免小岛边缘突兀
      var horizon = new THREE.Mesh(
        new THREE.RingGeometry(150, 420, 48, 1),
        new THREE.MeshBasicMaterial({ color: '#CFE9DE', transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false, fog: false })
      );
      horizon.rotation.x = -Math.PI / 2;
      horizon.position.y = -1.6;
      root.add(horizon);
      props.horizon = horizon.material;
    })();

    /* ---------- 天气预备件：雨伞 / 水洼 / 雪堆 ---------- */

    (function weatherProps() {
      /* 雨伞：给几个行人和门卫撑起来。伞面和伞杆分别成组，晴天整体隐藏 */
      var umbrellaColors = ['#E5484D', '#6FA8DC', '#F2C14E', '#6FCF97', '#A78BFA'];
      var umbrellaSpots = [
        // 跟随行人的伞由 scene 层挂到人物身上，这里只做"放在街边的"静态伞
        [-16, 0, 6.9, 0.4], [6.5, 0, 7.2, -0.3], [42, 0, 6.8, 0.8],
        [-4.6, 0, 18.2, 0.2],
        // 校门口值日警察、公交站等位置
        [11.4, 0, 5.6, 1.1]
      ];
      // 街边伞：细杆 + 伞面各合成一个 InstancedMesh（原先 5 把 × 4 件 = 20 个网格）
      var umbRoot = new THREE.Group();
      umbRoot.visible = false;
      root.add(umbRoot);
      var canopyGeoShared = new THREE.ConeGeometry(0.88, 0.5, 8, 1, true);
      var poleGeoShared = new THREE.CylinderGeometry(0.026, 0.026, 1.46, 5);
      var tipGeoShared = new THREE.CylinderGeometry(0.028, 0.028, 0.3, 5);
      var handleGeoShared = new THREE.TorusGeometry(0.085, 0.024, 4, 8, Math.PI);
      umbrellaSpots.forEach(function (u, i) {
        var color = umbrellaColors[i % umbrellaColors.length];
        var cm = new THREE.MeshLambertMaterial({
          color: color, flatShading: true, side: THREE.DoubleSide
        });
        var canopy = new THREE.Mesh(canopyGeoShared, cm);
        canopy.position.set(u[0], 1.6, u[2]);
        canopy.rotation.y = u[3];
        umbRoot.add(canopy);
        cyl(umbRoot, 0.028, 0.028, 0.3, 5, '#8A8F96', u[0], 1.98, u[2]);
        cyl(umbRoot, 0.026, 0.026, 1.46, 5, '#8A8F96', u[0], 0.86, u[2]);
        var hd = new THREE.Mesh(handleGeoShared, mat('#8A6B4A'));
        hd.position.set(u[0] + 0.085, 0.14, u[2]);
        hd.rotation.z = Math.PI / 2;
        hd.rotation.y = u[3];
        umbRoot.add(hd);
      });
      props.umbrellas.push({ group: umbRoot, base: 1, isStreet: true });

      /* 水洼：雨天在路面低洼处出现，用半透明深色圆盘 + 高光 */
      var puddleSpots = [
        [-24, 0.07, 1.4, 3.2, 1.4], [-2, 0.07, -1.8, 2.6, 1.2],
        [18, 0.07, 2.0, 3.6, 1.6], [40, 0.07, -1.2, 2.8, 1.3],
        [-10, 0.07, 12.0, 2.2, 1.1], [35, 0.07, -18, 2.4, 1.2],
        [-34, 0.07, 5.6, 2.6, 1.2], [12, 0.07, -14, 2.0, 1.0]
      ];
      props.puddleMat = new THREE.MeshLambertMaterial({
        color: '#6C8496', transparent: true, opacity: 0, depthWrite: false,
        emissive: '#AFC8D8', emissiveIntensity: 0.18
      });
      props.puddleGeo = new THREE.CircleGeometry(1, 12);
      props.puddles = [];
      // 水洼用 InstancedMesh：8 个同材质圆盘合成 1 个 draw call
      var puddleInst = new THREE.InstancedMesh(props.puddleGeo, props.puddleMat, puddleSpots.length);
      puddleInst.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      var pm4 = new THREE.Matrix4();
      var pq = new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2, 0, 0));
      puddleSpots.forEach(function (p, pi3) {
        pm4.compose(
          new THREE.Vector3(p[0], p[1], p[2]),
          pq,
          new THREE.Vector3(p[3], p[4], 1)
        );
        puddleInst.setMatrixAt(pi3, pm4);
      });
      puddleInst.instanceMatrix.needsUpdate = true;
      puddleInst.visible = false;
      puddleInst.frustumCulled = false;
      root.add(puddleInst);
      props.puddleMesh = puddleInst;

      /* 雪堆：草地里、树下、路边的小白丘，下雪时渐显 */
      var driftSpots = [
        [8.4, 24.6], [15, 12.6], [30.5, 8.4], [-46, 7.6], [-13, 28.4],
        [46, 32.5], [-60, 30], [22, 31.4], [-28, -8.2], [50, -8.6],
        [2, 30.2], [-36, 33.4], [58, 18], [-64, 18]
      ];
      // 雪堆也合成一个 InstancedMesh
      var driftGeo = new THREE.SphereGeometry(1.05, 7, 5);
      var driftInst = new THREE.InstancedMesh(driftGeo, M.snowMat, driftSpots.length);
      var dm4 = new THREE.Matrix4();
      driftSpots.forEach(function (d, i) {
        dm4.compose(
          new THREE.Vector3(d[0], 0.06, d[1]),
          new THREE.Quaternion(),
          new THREE.Vector3(1.55, 0.44, 1.25)
        );
        driftInst.setMatrixAt(i, dm4);
      });
      driftInst.instanceMatrix.needsUpdate = true;
      driftInst.visible = false;
      driftInst.frustumCulled = false;
      root.add(driftInst);
      props.snowDriftMesh = driftInst;
    })();

    /* ---------- 云、飞鸟、风筝 ---------- */

    (function clouds() {
      // 云放在更高、更外围：避免任何视角下压到屋顶或挡住街道
      // 云要抬到「常规相机高度之上」，否则竖屏近距离视角时视线会水平穿过云层，
      // 看起来像有白色方块糊在建筑前面（之前放在 y≈74，相机也在这个高度）。
      var cloudSpots = [
        [-84, 128, -70], [-18, 140, -64], [54, 126, -74],
        [104, 134, 20], [-70, 130, 72], [32, 142, 68], [112, 120, -26], [-112, 124, 16]
      ];
      // 所有云共用一份材质：雨天要统一变厚变灰，不能每朵一个材质
      var cloudMat = new THREE.MeshLambertMaterial({
        color: '#FFFFFF', emissive: '#FFFFFF', emissiveIntensity: 0.42,
        transparent: true, opacity: 0.9, flatShading: true
      });
      props.cloudMats.push(cloudMat);
      cloudSpots.forEach(function (p, idx) {
        var g = new THREE.Group();
        g.position.set(p[0], p[1], p[2]);
        for (var i = 0; i < 4; i++) {
          var s = 2.0 + (i % 3) * 0.9;
          var puff = new THREE.Mesh(new THREE.IcosahedronGeometry(s, 0), cloudMat);
          puff.position.set(i * 1.9 - 2.8, (i % 2) * 0.7, (i % 3) * 0.7 - 0.7);
          g.add(puff);
        }
        g.scale.setScalar(1.25);
        root.add(g);
        props.clouds.push({ group: g, speed: 0.4 + idx * 0.09, phase: idx * 40 });
      });
    })();

    (function birds() {
      for (var i = 0; i < 4; i++) {
        var g = new THREE.Group();
        var body = new THREE.Mesh(new THREE.SphereGeometry(0.28, 8, 6), mat('#4A4A4A'));
        body.scale.set(1, 0.75, 1.7);
        g.add(body);
        var wingGeo = new THREE.BoxGeometry(1.2, 0.06, 0.36);
        var wingL = new THREE.Mesh(wingGeo, mat('#5A5A5A'));
        wingL.position.set(-0.68, 0.08, 0);
        wingL.rotation.z = 0.15;
        g.add(wingL);
        var wingR = new THREE.Mesh(wingGeo, mat('#5A5A5A'));
        wingR.position.set(0.68, 0.08, 0);
        wingR.rotation.z = -0.15;
        g.add(wingR);
        g.position.set(0, 22 + i * 2, 0);
        g.scale.setScalar(1.2);
        root.add(g);
        props.birds.push({
          group: g, wingL: wingL, wingR: wingR,
          phase: i * 1.7, r: 22 + i * 5, y: 22 + i * 2
        });
        if (i === 0) { reg('bird', g); }
      }
    })();

    var kiteKid = buildPerson('child');
    kiteKid.group.position.set(24, 0, 22);
    kiteKid.group.rotation.y = Math.PI;
    root.add(kiteKid.group);

    /* ---------- 小动物氛围：广场鸽子、墙头小橘猫 ---------- */

    (function pigeons() {
      // 广场上一小群鸽子，时不时低头啄食、短距离换位
      var shadowMat = new THREE.MeshBasicMaterial({
        map: shadowTexture(), transparent: true, opacity: 0.5, depthWrite: false
      });
      for (var i = 0; i < 7; i++) {
        var g = new THREE.Group();
        var body = new THREE.Mesh(new THREE.SphereGeometry(0.19, 8, 6), mat(i % 3 ? '#9AA4AE' : '#E8E1D4'));
        body.scale.set(1, 0.9, 1.35);
        body.position.y = 0.2;
        g.add(body);
        var hd = new THREE.Mesh(new THREE.SphereGeometry(0.11, 7, 6), mat(i % 3 ? '#8A94A0' : '#DCD5C8'));
        hd.position.set(0, 0.32, 0.2);
        g.add(hd);
        cone(g, 0.045, 0.16, 5, '#E09020', 0, 0.31, 0.34, { rx: Math.PI / 2 });
        var tail = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.04, 0.24), mat('#7A848E'));
        tail.position.set(0, 0.24, -0.28);
        tail.rotation.x = 0.3;
        g.add(tail);
        g.position.set(-4 + (i % 4) * 1.6, 0.16, 12.6 + Math.floor(i / 4) * 1.2);
        var sh = new THREE.Mesh(new THREE.PlaneGeometry(0.6, 0.6), shadowMat);
        sh.rotation.x = -Math.PI / 2;
        sh.position.y = 0.005;
        g.add(sh);
        root.add(g);
        props.pigeons.push({
          group: g, head: hd, phase: i * 0.9,
          home: g.position.clone(), bob: 0
        });
      }
    })();

    (function wallCat() {
      // 咖啡馆后墙上一只小橘猫，尾巴一直摆
      var cat = new THREE.Group();
      cat.position.set(-20, 0.16, 30.4);
      cat.rotation.y = Math.PI;
      box(cat, 0.42, 0.3, 0.7, '#E8A04A', 0, 0.2, 0, { cast: true });
      box(cat, 0.3, 0.28, 0.28, '#E8A04A', 0, 0.36, 0.34);
      box(cat, 0.09, 0.16, 0.08, '#D18C3A', -0.1, 0.5, 0.34);
      box(cat, 0.09, 0.16, 0.08, '#D18C3A', 0.1, 0.5, 0.34);
      box(cat, 0.06, 0.05, 0.04, '#2D2A26', -0.06, 0.38, 0.47);
      box(cat, 0.06, 0.05, 0.04, '#2D2A26', 0.06, 0.38, 0.47);
      var catTail = new THREE.Group();
      catTail.position.set(0, 0.26, -0.34);
      box(catTail, 0.09, 0.09, 0.5, '#E8A04A', 0, 0.08, -0.2, { rx: 0.5 });
      cat.add(catTail);
      box(cat, 0.1, 0.2, 0.1, '#D18C3A', -0.14, 0.1, 0.22);
      box(cat, 0.1, 0.2, 0.1, '#D18C3A', 0.14, 0.1, 0.22);
      root.add(cat);
      props.cat = { group: cat, tail: catTail };
    })();

    /* ---------- 静态接触阴影：让建筑「坐」在地上 ---------- */

    (function contactShadows() {
      var shadowMatBig = new THREE.MeshBasicMaterial({
        map: shadowTexture(), transparent: true, opacity: 0.34, depthWrite: false
      });
      var spots = [
        [-42, -21, 22, 17], [-22, -23, 18, 15], [14, -21, 28, 18], [46, -24, 16, 14],
        [-42, 21, 30, 18], [-34, 10, 11, 10], [-20, 27, 12, 10], [-52, 10.5, 12, 9],
        [-22, 11.5, 13, 11], [48, 14, 17, 14], [10, 6.4, 7, 3], [46.5, 25, 17, 12]
      ];
      // 12 块阴影共用一个材质，合成一个网格即可（透明材质不进 mergeStatic，手动合）
      var group = new THREE.Group();
      spots.forEach(function (s) {
        var m = new THREE.Mesh(new THREE.PlaneGeometry(s[2], s[3]), shadowMatBig);
        m.rotation.x = -Math.PI / 2;
        m.position.set(s[0], 0.03, s[1]);
        group.add(m);
      });
      root.add(group);
      group.updateMatrixWorld(true);
      // 透明材质默认不进合批，这里显式允许（阴影贴图是加色/半透明，但只在同一材质内合并）
      var mergedShadow = mergeStatic([group], true);
      mergedShadow.forEach(function (m) { root.add(m); });
    })();

    var kite = new THREE.Group();
    var diamond = new THREE.Mesh(
      new THREE.PlaneGeometry(2.2, 2.2),
      new THREE.MeshLambertMaterial({ color: P.coral, side: THREE.DoubleSide })
    );
    diamond.rotation.z = Math.PI / 4;
    kite.add(diamond);
    var kc1 = new THREE.Mesh(new THREE.BoxGeometry(0.08, 2.8, 0.08), mat('#8A6B4A'));
    kc1.rotation.z = Math.PI / 4;
    kite.add(kc1);
    var kc2 = new THREE.Mesh(new THREE.BoxGeometry(0.08, 2.8, 0.08), mat('#8A6B4A'));
    kc2.rotation.z = -Math.PI / 4;
    kite.add(kc2);
    for (var kt = 0; kt < 3; kt++) {
      var tail = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.5, 0.04), mat('#F2C14E'));
      tail.position.set(0, -1.5 - kt * 0.42, 0);
      tail.rotation.z = Math.sin(kt) * 0.3;
      kite.add(tail);
    }
    kite.position.set(26, 18, 26);
    kite.scale.setScalar(1.3);
    root.add(kite);
    reg('kite', kite);
    props.kite = { group: kite, kid: kiteKid, base: new THREE.Vector3(26, 18, 26) };

    /* ---------------- 局部模型函数 ---------------- */

    function buildTree(scale, leafColor) {
      var g = new THREE.Group();
      var s = scale || 1;
      cyl(g, 0.24 * s, 0.34 * s, 2.2 * s, 7, P.trunk, 0, 1.1 * s, 0, { cast: true });
      var c1 = new THREE.Mesh(new THREE.IcosahedronGeometry(1.6 * s, 0), mat(leafColor || P.leaf));
      c1.position.set(0, 3.0 * s, 0);
      c1.castShadow = true;
      g.add(c1);
      var c2 = new THREE.Mesh(
        new THREE.IcosahedronGeometry(1.15 * s, 0),
        mat(shade(leafColor || P.leaf, 0.12))
      );
      c2.position.set(0.7 * s, 3.9 * s, 0.2 * s);
      c2.castShadow = true;
      g.add(c2);
      var c3 = new THREE.Mesh(
        new THREE.IcosahedronGeometry(1.0 * s, 0),
        mat(shade(leafColor || P.leaf, -0.12))
      );
      c3.position.set(-0.6 * s, 3.7 * s, -0.3 * s);
      g.add(c3);
      return g;
    }

    function buildDuck() {
      var g = new THREE.Group();
      var body = new THREE.Mesh(new THREE.SphereGeometry(0.42, 10, 8), mat('#FFF3D6'));
      body.scale.set(1, 0.82, 1.3);
      body.position.y = 0.36;
      g.add(body);
      var head = new THREE.Mesh(new THREE.SphereGeometry(0.24, 10, 8), mat('#FFF3D6'));
      head.position.set(0, 0.72, 0.34);
      g.add(head);
      cone(g, 0.1, 0.26, 6, '#F5A524', 0, 0.7, 0.58, { rx: Math.PI / 2 });
      cone(g, 0.16, 0.4, 5, '#F7E9C9', 0, 0.48, -0.5, { rx: -Math.PI / 2.6 });
      box(g, 0.06, 0.05, 0.05, '#2D2A26', -0.1, 0.78, 0.55);
      box(g, 0.06, 0.05, 0.05, '#2D2A26', 0.1, 0.78, 0.55);
      return g;
    }

    function buildDog() {
      var g = new THREE.Group();
      box(g, 0.44, 0.34, 0.86, '#C08B5C', 0, 0.52, 0, { cast: true });
      box(g, 0.38, 0.34, 0.34, '#C08B5C', 0, 0.72, 0.5);
      box(g, 0.3, 0.16, 0.22, '#B57C4D', 0, 0.6, 0.72);
      box(g, 0.1, 0.18, 0.12, '#8A5A34', -0.14, 0.9, 0.46);
      box(g, 0.1, 0.18, 0.12, '#8A5A34', 0.14, 0.9, 0.46);
      box(g, 0.1, 0.34, 0.1, '#B57C4D', -0.15, 0.2, 0.28);
      box(g, 0.1, 0.34, 0.1, '#B57C4D', 0.15, 0.2, 0.28);
      box(g, 0.1, 0.34, 0.1, '#B57C4D', -0.15, 0.2, -0.3);
      box(g, 0.1, 0.34, 0.1, '#B57C4D', 0.15, 0.2, -0.3);
      var tail = new THREE.Group();
      tail.position.set(0, 0.68, -0.44);
      box(tail, 0.08, 0.08, 0.42, '#B57C4D', 0, 0.1, -0.18, { rx: 0.5 });
      g.add(tail);
      box(g, 0.06, 0.04, 0.04, '#2D2A26', -0.08, 0.78, 0.68);
      box(g, 0.06, 0.04, 0.04, '#2D2A26', 0.08, 0.78, 0.68);
      return { group: g, tail: tail };
    }

    /* ---------- 屋顶积雪：按记录参数生成 InstancedMesh ---------- */

    (function snowCaps() {
      var caps = M.worldSnowCaps;
      if (!caps.length || !M.snowMat) { return; }
      var coneCaps = caps.filter(function (c) { return c.kind === 'cone'; });
      var slabCaps = caps.filter(function (c) { return c.kind === 'slab'; });

      function build(inst, list, makeGeo, makeScale) {
        var m4 = new THREE.Matrix4();
        var q = new THREE.Quaternion();
        var e = new THREE.Euler();
        list.forEach(function (c, i) {
          e.set(0, c.rotY || 0, 0);
          q.setFromEuler(e);
          m4.compose(
            new THREE.Vector3(c.x, c.y, c.z),
            q,
            makeScale(c)
          );
          inst.setMatrixAt(i, m4);
        });
        inst.instanceMatrix.needsUpdate = true;
        inst.visible = false;
        inst.frustumCulled = false;
        root.add(inst);
        props.snowCaps.push(inst);
      }

      if (coneCaps.length) {
        // 锥形屋顶雪盖：用统一的单位锥再缩放
        var coneGeo = new THREE.ConeGeometry(1, 1, 4);
        var coneInst = new THREE.InstancedMesh(coneGeo, M.snowMat, coneCaps.length);
        build(coneInst, coneCaps, null, function (c) {
          return new THREE.Vector3(c.w, c.h, c.w);
        });
      }
      if (slabCaps.length) {
        var slabGeo = new THREE.BoxGeometry(1, 0.16, 1);
        var slabInst = new THREE.InstancedMesh(slabGeo, M.snowMat, slabCaps.length);
        build(slabInst, slabCaps, null, function (c) {
          return new THREE.Vector3(c.w, 1, c.d);
        });
      }
      M.worldSnowCaps = [];
    })();

    /* ---------- 静态合批 ---------- */

    // 工地 / 停车场 / 河边步道 / 市集摊位 只有静态装饰，合批后 draw call 大幅下降。
    // 注意：合批会重建几何体，所以必须在所有 reg() 完成后执行（包围盒计算不依赖它）。
    root.updateMatrixWorld(true);
    var merged = mergeStatic(staticBag);
    merged.forEach(function (m) { root.add(m); });

    return { root: root, words: words, props: props };
  };
})();
