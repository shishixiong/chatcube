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

  /* 当前所在的室内 id（null 表示在街道上）。
     提到这里声明，因为 emitLabels 等帧循环里的函数也要读它。 */
  var insideId = null;

  /* ============================================================
     昼夜时间系统
     hour 是 0..24 的浮点「城市时间」，所有光照 / 天空 / 灯光都从它派生。
     - 手动模式：setNight(true/false) 把 hour 缓动到 20.0 / 10.0
     - 自动模式：setTimeFlow(true) 让 hour 自己走，一整圈 = 1440 秒（可选倍速）
     ============================================================ */
  var hour = 10;
  var hourGoal = 10;
  var timeFlow = false;
  // timeScale：一天（24 小时）走完需要多少现实秒。默认 300 秒 = 5 分钟一天，
  // 适合当背景动画；UI 上的播放按钮用的就是这个速度。
  var daySeconds = 300;
  var phaseCb = null;

  /* 一天中的 6 个关键帧：每个关键帧给出完整的配色与光照参数。
     插值由 sampleSky() 完成，所以「清晨 / 正午 / 黄昏 / 夜晚」不是切换而是连续过渡。 */
  var SKY_KEYS = [
    { // 00:30 深夜
      h: 0.5,
      sky: '#2A2440', ground: '#2E2A3A', fog: '#33304A',
      ambColor: '#6E6A96', sun: '#8FA4D8',
      hemiSky: '#4E4A78', hemiGround: '#332F42',
      hemi: 0.34, amb: 0.4, sunI: 0.16, sunY: 60, sunX: 60, sunZ: 40
    },
    { // 06:00 黎明
      h: 6,
      sky: '#C9B0C6', ground: '#8A7A78', fog: '#CDBAC6',
      ambColor: '#B9A6BE', sun: '#FFC58F',
      hemiSky: '#D8C4CE', hemiGround: '#A89284',
      hemi: 0.86, amb: 0.42, sunI: 0.85, sunY: 34, sunX: 105, sunZ: 30
    },
    { // 09:00 上午：主色调（也是「白天」的基准）
      h: 9.5,
      sky: '#DDF3FF', ground: '#F0E6D2', fog: '#EAF7F4',
      ambColor: '#FFFFFF', sun: '#FFF4E0',
      hemiSky: '#DDF3FF', hemiGround: '#F0E6D2',
      hemi: 1.35, amb: 0.22, sunI: 1.85, sunY: 98, sunX: 68, sunZ: 44
    },
    { // 13:30 正午偏后：最亮、影子最短
      h: 13.5,
      sky: '#E4F6FF', ground: '#F5EDDC', fog: '#EFFAF6',
      ambColor: '#FFFFFF', sun: '#FFFAEE',
      hemiSky: '#E4F6FF', hemiGround: '#F5EDDC',
      hemi: 1.5, amb: 0.2, sunI: 2.05, sunY: 128, sunX: 12, sunZ: 26
    },
    { // 18:30 黄昏：暖橙 + 长影（这是最出气氛的时刻，饱和度给足）
      h: 18.5,
      sky: '#FFC08A', ground: '#B08068', fog: '#F0AE84',
      ambColor: '#E0A882', sun: '#FF8A3C',
      hemiSky: '#FFCB9C', hemiGround: '#8A6A5E',
      hemi: 1.12, amb: 0.34, sunI: 1.35, sunY: 30, sunX: 122, sunZ: 16
    },
    { // 19:40 暮色：天还没全黑，屋里灯已经亮
      h: 19.7,
      sky: '#8A6E92', ground: '#4E4058', fog: '#8A7088',
      ambColor: '#9A84A2', sun: '#C98A78',
      hemiSky: '#A88AA8', hemiGround: '#4C4058',
      hemi: 0.78, amb: 0.4, sunI: 0.5, sunY: 34, sunX: -30, sunZ: -30
    },
    { // 20:30 入夜
      h: 20.5,
      sky: '#4A4060', ground: '#3E3450', fog: '#575074',
      ambColor: '#7A7098', sun: '#B49AD8',
      hemiSky: '#6A6494', hemiGround: '#3A3450',
      hemi: 0.5, amb: 0.4, sunI: 0.24, sunY: 50, sunX: -70, sunZ: -40
    },
    { // 23:59 深夜（与 00:30 接近，保证首尾闭合）
      h: 23.9,
      sky: '#2A2440', ground: '#2E2A3A', fog: '#33304A',
      ambColor: '#6E6A96', sun: '#8FA4D8',
      hemiSky: '#4E4A78', hemiGround: '#332F42',
      hemi: 0.34, amb: 0.4, sunI: 0.16, sunY: 60, sunX: 60, sunZ: 40
    }
  ];

  // 预编译颜色对象，避免每帧 new Color
  SKY_KEYS.forEach(function (k) {
    k._sky = new THREE.Color(k.sky);
    k._ground = new THREE.Color(k.ground);
    k._fog = new THREE.Color(k.fog);
    k._ambColor = new THREE.Color(k.ambColor);
    k._sun = new THREE.Color(k.sun);
    k._hemiSky = new THREE.Color(k.hemiSky);
    k._hemiGround = new THREE.Color(k.hemiGround);
  });

  // 采样结果放这里复用，避免每帧分配
  var skySample = {
    sky: new THREE.Color(), ground: new THREE.Color(), fog: new THREE.Color(),
    ambColor: new THREE.Color(), sun: new THREE.Color(),
    hemiSky: new THREE.Color(), hemiGround: new THREE.Color(),
    hemi: 1, amb: 0.2, sunI: 1, sunY: 98, sunX: 68, sunZ: 44,
    // 派生量
    night: 0, warm: 0, sunUp: 0
  };

  /* 在关键帧之间做环形插值。hour 落在两帧之间就用 smoothstep 混合，
     这样任何时刻的颜色都是连续的，不会出现「啪」地一下变色。 */
  function sampleSky(h) {
    var i, a, b;
    for (i = 0; i < SKY_KEYS.length - 1; i++) {
      if (h >= SKY_KEYS[i].h && h <= SKY_KEYS[i + 1].h) { break; }
    }
    if (i >= SKY_KEYS.length - 1) { i = SKY_KEYS.length - 2; }
    a = SKY_KEYS[i];
    b = SKY_KEYS[i + 1];
    var span = Math.max(0.0001, b.h - a.h);
    var t = clamp((h - a.h) / span, 0, 1);
    var e = t * t * (3 - 2 * t);   // smoothstep：两端变化慢，中间快

    var out = skySample;
    out.sky.lerpColors(a._sky, b._sky, e);
    out.ground.lerpColors(a._ground, b._ground, e);
    out.fog.lerpColors(a._fog, b._fog, e);
    out.ambColor.lerpColors(a._ambColor, b._ambColor, e);
    out.sun.lerpColors(a._sun, b._sun, e);
    out.hemiSky.lerpColors(a._hemiSky, b._hemiSky, e);
    out.hemiGround.lerpColors(a._hemiGround, b._hemiGround, e);
    out.hemi = lerp(a.hemi, b.hemi, e);
    out.amb = lerp(a.amb, b.amb, e);
    out.sunI = lerp(a.sunI, b.sunI, e);
    out.sunY = lerp(a.sunY, b.sunY, e);
    out.sunX = lerp(a.sunX, b.sunX, e);
    out.sunZ = lerp(a.sunZ, b.sunZ, e);

    // 派生量：夜里（灯光强度）、暖色程度（黄昏）、太阳高度（阴影/色温）
    // night 提前到黄昏后期就开始爬升，因为 18:30 天暗了就该开灯
    var n;
    if (h >= 17.6) {
      n = clamp((h - 17.6) / 2.6, 0, 1);
    } else if (h <= 5.4) {
      n = clamp(1 - (h - 4.0) / 1.4, 0, 1);
    } else {
      n = 0;
    }
    out.night = n;

    // warm: 黄昏/黎明最暖，正午为 0
    var warmDusk = (h >= 16.5 && h <= 20) ? Math.sin(((h - 16.5) / 3.5) * Math.PI) : 0;
    var warmDawn = (h >= 4.6 && h <= 7.6) ? Math.sin(((h - 4.6) / 3.0) * Math.PI) : 0;
    out.warm = Math.max(warmDusk, warmDawn);
    out.sunUp = clamp((out.sunY - 26) / 90, 0, 1);
    return out;
  }

  function hourLabel(h) {
    var hh = Math.floor(((h % 24) + 24) % 24);
    var mm = Math.floor((h - Math.floor(h)) * 60);
    return (hh < 10 ? '0' : '') + hh + ':' + (mm < 10 ? '0' : '') + mm;
  }
  S.hourLabel = hourLabel;


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

  /* 相机限制。街景用 D.camera；进入室内会换成更小的范围，
     否则室内会被允许拉到 320 米远，直接穿到楼外面去。 */
  var camLimits = {
    minRadius: D.camera.minRadius,
    maxRadius: D.camera.maxRadius,
    minPhi: D.camera.minPhi,
    maxPhi: D.camera.maxPhi
  };

  var raycaster = new THREE.Raycaster();
  var ndc = new THREE.Vector2();
  var pointers = new Map();
  var pinchState = null;
  var tap = { candidate: false, pointerId: -1, x: 0, y: 0, moved: 0, time: 0 };
  var dragButton = 0;

  var tmpV = new THREE.Vector3();
  var tmpV2 = new THREE.Vector3();
  var tmpV3 = new THREE.Vector3();
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
    cam.phi = clamp(cam.phi, camLimits.minPhi, camLimits.maxPhi);
    cam.radius = clamp(cam.radius, camLimits.minRadius, camLimits.maxRadius);
    var sp = Math.sin(cam.phi);
    camera.position.set(
      cam.target.x + cam.radius * sp * Math.sin(cam.theta),
      Math.max(2.6, cam.target.y + cam.radius * Math.cos(cam.phi)),
      cam.target.z + cam.radius * sp * Math.cos(cam.theta)
    );
    camera.lookAt(cam.target);
  }

  var LAMP_DAY = new THREE.Color('#D8CDB6');
  var LAMP_DUSK = new THREE.Color('#FFF3C4');
  var HEAD_DAY = new THREE.Color('#FFF3D6');
  var HEAD_NIGHT = new THREE.Color('#FFFDF0');
  var TAIL_DAY = new THREE.Color('#C0392B');
  var TAIL_NIGHT = new THREE.Color('#FF5A48');
  var FAR_DAY = new THREE.Color('#A9CE9E');
  var FAR_DUSK = new THREE.Color('#3A3550');

  /* ---------------- 天气 ---------------- */

  /* 0 = 晴，1 = 雨，2 = 雪 */
  var WEATHER = { CLEAR: 0, RAIN: 1, SNOW: 2 };
  var weatherTarget = WEATHER.CLEAR;
  var rainAmt = 0;      // 0..1 雨强度（缓动）
  var snowAmt = 0;      // 0..1 雪强度（缓动）

  var RAIN_COUNT = 900;
  var RAIN_AREA_X = 78;
  var RAIN_AREA_Z = 62;
  var RAIN_TOP = 46;
  var SNOW_COUNT = 700;
  var rainDrops = [];
  var snowFlakes = [];
  var rainMesh = null;
  var rainMat = null;
  var snowMesh = null;
  var snowMat = null;
  var rainPositions = null;
  var snowPositions = null;
  // 雨雪相对镜头的偏移：让雨幕始终罩住当前视野
  var weatherCenter = new THREE.Vector3();

  var RAIN_SKY = new THREE.Color('#8E9AA6');
  var RAIN_FOG = new THREE.Color('#8E9AA6');
  var RAIN_HEMI_SKY = new THREE.Color('#AEBAC2');
  var RAIN_HEMI_GROUND = new THREE.Color('#6E7A62');
  var RAIN_SUN = new THREE.Color('#C6D2DA');
  var SNOW_SKY = new THREE.Color('#C8D4DE');
  var SNOW_FOG = new THREE.Color('#CBD6DF');
  var SNOW_HEMI_SKY = new THREE.Color('#DCE6EF');
  var SNOW_HEMI_GROUND = new THREE.Color('#C6CFD2');
  var SNOW_SUN = new THREE.Color('#EEF4FA');

  var GRASS_RAIN = new THREE.Color('#5B8452');
  var GRASS_SNOW = new THREE.Color('#DCE7E2');
  var ROAD_RAIN = new THREE.Color('#333B44');
  var ROAD_SNOW = new THREE.Color('#B9C4CC');
  var CLOUD_RAIN = new THREE.Color('#9AA5AE');
  var CLOUD_SNOW = new THREE.Color('#E4EBF2');
  var CLOUD_NIGHT = new THREE.Color('#6E6A88');
  var tmpColor = new THREE.Color();

  function buildRain() {
    rainPositions = new Float32Array(RAIN_COUNT * 6);
    for (var i = 0; i < RAIN_COUNT; i++) {
      rainDrops.push({
        x: (Math.random() - 0.5) * 2 * RAIN_AREA_X,
        y: Math.random() * RAIN_TOP,
        z: (Math.random() - 0.5) * 2 * RAIN_AREA_Z,
        speed: 30 + Math.random() * 12,
        len: 0.7 + Math.random() * 0.5
      });
    }
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(rainPositions, 3));
    rainMat = new THREE.LineBasicMaterial({
      color: '#C8DEEC', transparent: true, opacity: 0, depthWrite: false, fog: false
    });
    rainMesh = new THREE.LineSegments(geo, rainMat);
    rainMesh.frustumCulled = false;
    rainMesh.visible = false;
    scene.add(rainMesh);
  }

  function buildSnow() {
    snowPositions = new Float32Array(SNOW_COUNT * 3);
    for (var i = 0; i < SNOW_COUNT; i++) {
      snowFlakes.push({
        x: (Math.random() - 0.5) * 2 * RAIN_AREA_X,
        y: Math.random() * RAIN_TOP,
        z: (Math.random() - 0.5) * 2 * RAIN_AREA_Z,
        fall: 3.2 + Math.random() * 2.4,
        drift: Math.random() * Math.PI * 2,
        driftSpeed: 0.6 + Math.random() * 0.8
      });
    }
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(snowPositions, 3));
    // 雪花用「像素大小不随距离衰减」的点，远近都能看见
    snowMat = new THREE.PointsMaterial({
      color: '#FFFFFF', size: 2.6, sizeAttenuation: false,
      transparent: true, opacity: 0, depthWrite: false, fog: false
    });
    snowMesh = new THREE.Points(geo, snowMat);
    snowMesh.frustumCulled = false;
    snowMesh.visible = false;
    scene.add(snowMesh);
  }

  function updateWeatherParticles(dt) {
    var t = elapsed;
    // 雨幕跟着镜头目标走，保证任何视角都在雨里
    weatherCenter.set(cam.target.x, 0, cam.target.z);

    if (rainMesh && rainMesh.visible) {
      var arr = rainPositions;
      for (var i = 0; i < RAIN_COUNT; i++) {
        var d = rainDrops[i];
        d.y -= d.speed * dt;
        if (d.y < 0) {
          d.y += RAIN_TOP;
          // 重新随机水平位置，避免雨幕出现固定竖直条纹
          d.x = (Math.random() - 0.5) * 2 * RAIN_AREA_X;
          d.z = (Math.random() - 0.5) * 2 * RAIN_AREA_Z;
        }
        var idx = i * 6;
        var px = weatherCenter.x + d.x;
        var pz = weatherCenter.z + d.z;
        arr[idx] = px;
        arr[idx + 1] = d.y;
        arr[idx + 2] = pz;
        // 雨丝略微倾斜，像被风吹斜
        arr[idx + 3] = px - 0.18 * rainAmt;
        arr[idx + 4] = d.y + d.len + 0.6 * rainAmt;
        arr[idx + 5] = pz;
      }
      rainMesh.geometry.attributes.position.needsUpdate = true;
    }

    if (snowMesh && snowMesh.visible) {
      var sarr = snowPositions;
      for (var j = 0; j < SNOW_COUNT; j++) {
        var f = snowFlakes[j];
        f.y -= f.fall * dt;
        f.drift += dt * f.driftSpeed;
        if (f.y < 0) {
          f.y += RAIN_TOP;
          f.x = (Math.random() - 0.5) * 2 * RAIN_AREA_X;
          f.z = (Math.random() - 0.5) * 2 * RAIN_AREA_Z;
        }
        var si = j * 3;
        // 雪花左右轻轻飘
        sarr[si] = weatherCenter.x + f.x + Math.sin(f.drift + t * 0.6) * 1.4;
        sarr[si + 1] = f.y;
        sarr[si + 2] = weatherCenter.z + f.z + Math.cos(f.drift * 0.8 + t * 0.4) * 1.2;
      }
      snowMesh.geometry.attributes.position.needsUpdate = true;
    }
  }

  /* 天气对光照与材质的影响统一在这里叠加：
     晴 → 原样；雨 → 压暗去饱和、雾更近；雪 → 冷白、环境光提升 */
  function applyWeatherLook(sample) {
    var r = rainAmt;
    var s = snowAmt;
    if (r > 0.001) {
      sample.sky.lerp(RAIN_SKY, r * 0.78);
      sample.fog.lerp(RAIN_FOG, r * 0.8);
      sample.hemiSky.lerp(RAIN_HEMI_SKY, r * 0.7);
      sample.hemiGround.lerp(RAIN_HEMI_GROUND, r * 0.7);
      sample.sun.lerp(RAIN_SUN, r * 0.72);
      sample.hemi *= (1 - 0.16 * r);
      sample.sunI *= (1 - 0.72 * r);
    }
    if (s > 0.001) {
      sample.sky.lerp(SNOW_SKY, s * 0.72);
      sample.fog.lerp(SNOW_FOG, s * 0.78);
      sample.hemiSky.lerp(SNOW_HEMI_SKY, s * 0.7);
      sample.hemiGround.lerp(SNOW_HEMI_GROUND, s * 0.7);
      sample.sun.lerp(SNOW_SUN, s * 0.6);
      sample.hemi *= (1 + 0.1 * s);
      sample.amb *= (1 + 0.22 * s);
      sample.sunI *= (1 - 0.42 * s);
    }
  }

  function applyLighting() {
    if (!hemiLight || !ambLight || !dirLight || !scene) { return; }
    var sample = sampleSky(hour);
    applyWeatherLook(sample);

    var t = sample.night;

    hemiLight.color.copy(sample.hemiSky);
    hemiLight.groundColor.copy(sample.hemiGround);
    hemiLight.intensity = sample.hemi;
    ambLight.color.copy(sample.ambColor);
    ambLight.intensity = sample.amb;
    dirLight.color.copy(sample.sun);
    dirLight.intensity = sample.sunI;
    dirLight.position.set(sample.sunX, sample.sunY, sample.sunZ);
    if (scene.fog) {
      scene.fog.color.copy(sample.fog);
      // 雨雪天雾拉近：远处建筑被雨幕吃掉，氛围更浓
      var wet = Math.max(rainAmt * 0.85, snowAmt * 0.7);
      scene.fog.near = lerp(300, 150, wet);
      scene.fog.far = lerp(700, 470, Math.max(rainAmt * 0.9, snowAmt * 0.75));
    }
    // 3D 底色保持透明：天空由 CSS 渐变层画，这样夜空星点才能透出来。
    // 真正的天空颜色通过 sample() 暴露给 UI 层，由它写进 CSS 变量。
    // （不要把 clearColor 设成不透明色，否则会把 CSS 星空层整个盖住）
    if (renderer && renderer.getClearAlpha() !== 0) {
      renderer.setClearColor(0x000000, 0);
    }

    if (props) {
      if (props.lamps) {
        for (var i = 0; i < props.lamps.length; i++) {
          var mat = props.lamps[i];
          if (mat && mat.color) { mat.color.lerpColors(LAMP_DAY, LAMP_DUSK, t); }
        }
      }
      if (props.lampGlowMat) { props.lampGlowMat.opacity = 0.78 * t; }
      if (props.lampPoolMat) { props.lampPoolMat.opacity = 0.34 * t; }

      // 建筑窗户：入夜逐渐亮起，亮窗位置固定在贴图里
      if (props.windows) {
        // 黄昏就开始点灯（比全黑更真实），暗下来后亮度拉满
        var winGlow = clamp(t * 1.35, 0, 1);
        for (var wi = 0; wi < props.windows.length; wi++) {
          props.windows[wi].emissiveIntensity = 1.15 * winGlow;
        }
      }
      // 车灯：夜里最亮；雨雪天雾大，白天也开灯
      var lampBoost = Math.max(t, rainAmt * 0.55, snowAmt * 0.42);
      if (props.headlampMats) {
        for (var hi = 0; hi < props.headlampMats.length; hi++) {
          props.headlampMats[hi].color.lerpColors(HEAD_DAY, HEAD_NIGHT, lampBoost);
        }
      }
      if (props.taillampMats) {
        for (var ti = 0; ti < props.taillampMats.length; ti++) {
          props.taillampMats[ti].color.lerpColors(TAIL_DAY, TAIL_NIGHT, lampBoost);
        }
      }
      // 霓虹灯牌：夜里整块亮起来
      if (props.neonMats) {
        for (var ni = 0; ni < props.neonMats.length; ni++) {
          if (props.neonMats[ni]) { props.neonMats[ni].emissiveIntensity = 0.85 * t; }
        }
      }
      // 地面：雨天压暗、雪天泛白
      if (props.groundMats) {
        for (var gi = 0; gi < props.groundMats.length; gi++) {
          var gEnt = props.groundMats[gi];
          tmpColor.copy(gEnt.base);
          if (rainAmt > 0.001) { tmpColor.lerp(GRASS_RAIN, rainAmt * 0.62); }
          if (snowAmt > 0.001) { tmpColor.lerp(GRASS_SNOW, snowAmt * 0.82); }
          gEnt.mat.color.copy(tmpColor);
        }
      }
      // 路面：湿沥青更深，积雪更浅
      if (props.roadMats) {
        for (var ri2 = 0; ri2 < props.roadMats.length; ri2++) {
          var rEnt = props.roadMats[ri2];
          tmpColor.copy(rEnt.base);
          if (rainAmt > 0.001) { tmpColor.lerp(ROAD_RAIN, rainAmt * 0.55); }
          if (snowAmt > 0.001) { tmpColor.lerp(ROAD_SNOW, snowAmt * 0.62); }
          rEnt.mat.color.copy(tmpColor);
        }
      }
      // 云：雨天变厚变灰、雪天变冷白，夜里一起压暗
      if (props.cloudMats) {
        for (var ci = 0; ci < props.cloudMats.length; ci++) {
          var cm = props.cloudMats[ci];
          tmpColor.set('#FFFFFF');
          if (rainAmt > 0.001) { tmpColor.lerp(CLOUD_RAIN, rainAmt * 0.72); }
          if (snowAmt > 0.001) { tmpColor.lerp(CLOUD_SNOW, snowAmt * 0.9); }
          tmpColor.lerp(CLOUD_NIGHT, t * 0.5);
          cm.color.copy(tmpColor);
          cm.emissive.copy(tmpColor);
          cm.emissiveIntensity = 0.42 * (1 - t * 0.2);
        }
      }
      // 水洼与屋顶积雪
      if (props.puddleMat) { props.puddleMat.opacity = 0.55 * rainAmt; }
      if (props.puddleMesh) { props.puddleMesh.visible = rainAmt > 0.02; }
      if (props.snowDriftMesh) { props.snowDriftMesh.visible = snowAmt > 0.02; }
      if (props.snowCaps) {
        for (var sci = 0; sci < props.snowCaps.length; sci++) {
          props.snowCaps[sci].visible = snowAmt > 0.02;
        }
      }
      // 星空 / 月亮 / 太阳：雨雪天看不见
      var clearSky = 1 - Math.max(rainAmt, snowAmt) * 0.95;
      if (props.stars) { props.stars.mat.opacity = 0.95 * t * clearSky; }
      if (props.sunSprite) {
        props.sunSprite.halo.opacity = lerp(0.85, 0.15, t) * clearSky;
        // 太阳位置随时间移动：清晨东升、正午最高、黄昏西沉
        var sunAngle = ((hour - 6) / 12) * Math.PI;
        var sunDist = 150;
        props.sunSprite.group.position.set(
          Math.cos(sunAngle) * sunDist,
          Math.max(6, Math.sin(sunAngle) * 130),
          -70 + Math.sin(sunAngle * 0.5) * 40
        );
        props.sunSprite.group.visible = hour > 5.2 && hour < 19.2;
        props.sunSprite.core.opacity = clearSky;
      }
      if (props.moonSprite) {
        // 月亮与太阳反向：夜里升起
        props.moonSprite.core.opacity = t * clearSky;
        props.moonSprite.halo.opacity = 0.55 * t * clearSky;
        var moonAngle = ((hour - 18) / 12) * Math.PI;
        props.moonSprite.group.position.set(
          -Math.cos(moonAngle) * 140,
          Math.max(8, Math.sin(moonAngle) * 120),
          -60
        );
        props.moonSprite.group.visible = hour > 17.8 || hour < 6.2;
      }
      if (props.horizon) { props.horizon.opacity = lerp(0.5, 0.1, t); }
      if (props.farGround) {
        tmpColor.copy(FAR_DAY);
        tmpColor.lerp(FAR_DUSK, t);
        if (rainAmt > 0.001) { tmpColor.lerp(GRASS_RAIN, rainAmt * 0.5); }
        if (snowAmt > 0.001) { tmpColor.lerp(GRASS_SNOW, snowAmt * 0.75); }
        props.farGround.color.copy(tmpColor);
      }
    }

    // 雨雪粒子与雨伞：统一在这里同步可见性
    if (rainMesh) {
      rainMesh.visible = rainAmt > 0.01;
      rainMat.opacity = 0.62 * rainAmt;
    }
    if (snowMesh) {
      snowMesh.visible = snowAmt > 0.01;
      snowMat.opacity = 0.9 * snowAmt;
    }
    if (props && props.umbrellas) {
      for (var ui = 0; ui < props.umbrellas.length; ui++) {
        var u = props.umbrellas[ui];
        u.group.visible = rainAmt > 0.02;
        u.group.scale.setScalar(0.001 + 0.999 * rainAmt);
      }
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
      // 竖屏（aspect < 0.85）时水平视野被压得很窄，分区镜头要退得更远，
      // 否则会像贴在建筑上一样、只看见一条马路或半条河。
      var aspect = camera.aspect || 1;
      var narrowBoost = 1;
      if (aspect < 0.85) {
        narrowBoost = 1.45 * clamp(0.85 / Math.max(0.4, aspect), 1, 1.7);
      }
      radius = v.radius * narrowBoost;
    }
    radius = clamp(radius, camLimits.minRadius, camLimits.maxRadius);
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
      // 室内词只在室内显示，街景词只在街上显示，互不串场
      if (item.interior) {
        if (item.interior !== insideId) { return; }
      } else if (insideId) {
        return;
      }
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
    if (tour.active) { S.stopTour(); }
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
          camLimits.minRadius,
          camLimits.maxRadius
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
      cam.phi = clamp(cam.phi + dy * 0.005, camLimits.minPhi, camLimits.maxPhi);
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
    if (tour.active) { S.stopTour(); }
    cam.radius = clamp(
      cam.radius * Math.exp(e.deltaY * 0.0012),
      camLimits.minRadius,
      camLimits.maxRadius
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
    scene.fog = new THREE.Fog('#EAF7F4', 300, 700);
    camera = new THREE.PerspectiveCamera(
      45,
      Math.max(0.2, el.clientWidth / Math.max(1, el.clientHeight)),
      0.5,
      900
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

    // 室内模块：等街道搭完再初始化，它要把房间挂到同一个 scene 下
    if (window.WordCityInterior) {
      window.WordCityInterior.init({
        scene: scene,
        worldRoot: world.root,
        tools: MD.tools,
        register: function (id, node, interiorId) {
          // 室内词也登记进 words，这样拾取、标签、高亮全都能复用
          var labelOffset = new THREE.Vector3(0, 2.2, 0);
          var bb = new THREE.Box3().setFromObject(node);
          if (!bb.isEmpty()) {
            var c = bb.getCenter(new THREE.Vector3());
            labelOffset = node.worldToLocal(new THREE.Vector3(c.x, bb.max.y + 0.7, c.z));
          }
          // 拾取盒挂在物件自身下：室内有自己的坐标系，
          // 不能像街景那样统一挂到 world.root（会偏到楼外去）。
          // 房间组在隐藏时整棵子树都不可见，射线自然打不到，不需要额外开关。
          bb.getSize(tmpSize);
          var hx = Math.max(tmpSize.x * 1.16, 0.7);
          var hy = Math.max(tmpSize.y * 1.12, 0.7);
          var hz = Math.max(tmpSize.z * 1.16, 0.7);
          var hit = new THREE.Mesh(
            new THREE.BoxGeometry(hx, hy, hz),
            new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false })
          );
          hit.layers.set(2);
          hit.userData.wordId = id;
          hit.position.copy(node.worldToLocal(bb.getCenter(new THREE.Vector3())));
          node.add(hit);
          hitMeshes.push(hit);

          words.set(id, {
            node: node,
            labelOffset: labelOffset,
            interior: interiorId || null,
            hit: hit
          });
        }
      });
    }
    buildRain();
    buildSnow();

    buildTraffic();
    buildPedestrians();
    buildCrossers();
    buildHitboxes();
    buildKiteString();
    // 伞要挂到人物手上，必须在 buildPedestrians 之后；
    // 而 applyLighting 要处理这些伞的显隐，所以放在最后统一刷一次。
    attachUmbrellasToPeople();
    applyLighting();

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
      updateTime(dt);
      updateWeatherBlend(dt);
      updateTraffic(dt);
      updatePedestrians(dt);
      updateCrossers(dt);
      updateProps(dt);
      updateSignals(dt);
      updateTour(dt);
      updateHighlightPulse();
      updateHunt(dt);
      updateWeatherParticles(dt);
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

  /* ---------------- 室内 ---------------- */

  /* 进入 / 退出室内。
     室内是场景内的独立房间组，进入时把街道根节点整体隐藏，
     相机换成室内视角并把轨道限制收紧到房间尺度。 */

  var savedCam = null;
  var savedZone = null;
  var savedCamLimits = null;

  S.hasInterior = function (id) {
    return !!(window.WordCityInterior && window.WordCityInterior.hasInterior(id));
  };

  S.enterInterior = function (id, immediate) {
    var IN = window.WordCityInterior;
    if (!IN || !IN.hasInterior(id)) { return false; }
    if (insideId === id) { return true; }

    // 记下街景状态，退出时原样还原
    if (!insideId) {
      savedCam = {
        target: cam.target.clone(),
        radius: cam.radius,
        phi: cam.phi,
        theta: cam.theta
      };
      savedZone = currentZone;
      savedCamLimits = {
        minRadius: camLimits.minRadius,
        maxRadius: camLimits.maxRadius,
        minPhi: camLimits.minPhi,
        maxPhi: camLimits.maxPhi
      };
    }

    var def = IN.enter(id);
    if (!def) { return false; }
    insideId = id;

    // 室内是近距离观察，轨道范围要收紧到房间尺度
    var diag = Math.hypot(def.w, def.d);
    camLimits.minRadius = Math.max(7, diag * 0.3);
    camLimits.maxRadius = diag * 1.4;
    camLimits.minPhi = 0.75;
    camLimits.maxPhi = 1.5;

    // 清掉街区高亮，避免残留光圈飘在室内
    highlight(null);
    if (S.stopTour) { S.stopTour(); }
    // 寻宝标记也收回，室内不参与街道寻宝
    S.setHuntTarget(null);

    /* 室内镜头不能直接照搬配置里的 radius/phi：
       房间只有十几米，稍大一点相机就跑到墙外，画面变成一片墙色。
       这里按房间尺寸算一个「保证相机在室内」的位置：
       - 相机放在门口内侧一点点（+z 方向），朝屋内看
       - 高度压到天花板下 1/3 处，避免顶到天花板
       - 距离取「能看到整面后墙」的最短距离 */
    var v = (def.view && def.view.target) ? def.view : null;
    var targetX = v ? v.target[0] : 0;
    var targetZ = v ? v.target[2] : 0;
    var targetY = v ? v.target[1] : 1.2;

    var halfD = def.d / 2;
    // 相机 z 位置：房间里侧留 1.2 米余量，别贴在墙上
    var eyeZ = Math.min(halfD - 0.6, targetZ + def.d * 0.56);
    var backDist = Math.max(3, eyeZ - targetZ);
    // 相机高度：天花板下留 0.8 米
    var eyeY = Math.min(def.h - 0.55, Math.max(2.4, def.h * 0.80));
    var rise = Math.max(0.2, eyeY - targetY);

    // 由水平距离与高度差反推 phi（与竖直方向夹角）
    var horiz = backDist;
    var phi = Math.atan2(horiz, rise);
    var radius = Math.hypot(horiz, rise);

    // target 往房间深处推一点，让后墙货架成为视觉中心
    var tz = v ? v.target[2] : 0;

    flyTo(
      new THREE.Vector3(targetX, targetY, tz),
      radius, phi, 0,
      immediate ? 0 : D.camera.flightMs
    );

    // 进出室内后立刻刷一次标签，别等下一帧
    // （后台标签页 / 嵌入 iframe 里 rAF 可能被暂停，等帧会一直不更新）
    if (labelsEnabled) { emitLabels(); }
    return true;
  };

  S.exitInterior = function (immediate) {
    if (!insideId) { return false; }
    var IN = window.WordCityInterior;
    insideId = null;
    if (IN) { IN.exit(); }

    // 恢复相机限制
    if (savedCamLimits) {
      camLimits.minRadius = savedCamLimits.minRadius;
      camLimits.maxRadius = savedCamLimits.maxRadius;
      camLimits.minPhi = savedCamLimits.minPhi;
      camLimits.maxPhi = savedCamLimits.maxPhi;
      savedCamLimits = null;
    }

    // 回到进入前的镜头位置；如果当时没记过就退回该分区默认视角
    if (savedCam) {
      flyTo(savedCam.target, savedCam.radius, savedCam.phi, savedCam.theta,
        immediate ? 0 : D.camera.flightMs);
      savedCam = null;
    } else if (savedZone) {
      applyView(savedZone, !!immediate);
    }
    savedZone = null;
    highlight(null);
    return true;
  };

  S.isInsideInterior = function () { return !!insideId; };
  S.getInteriorId = function () { return insideId; };

  /* ---------------- 寻宝标记 ---------------- */

  /* 给待寻找的目标打一个浮动的光柱 + 地面光圈。
     线索模式下用弱化版（只有光圈），玩家找不到时才用强提示。
     intensity: 0 = 关闭，1 = 强提示（光柱 + 光圈 + 上下浮动） */
  var huntMarker = null;
  var huntId = null;
  var huntIntensity = 0;

  function ensureHuntMarker() {
    if (huntMarker) { return; }
    huntMarker = new THREE.Group();
    // 地面光圈：两层同心圆，内层亮、外层淡，形成柔和光晕
    var ringMat = new THREE.MeshBasicMaterial({
      color: '#FFD75E', transparent: true, opacity: 0,
      side: THREE.DoubleSide, depthWrite: false, depthTest: false
    });
    var halo = new THREE.Mesh(new THREE.RingGeometry(0.86, 1.0, 40), ringMat);
    halo.rotation.x = -Math.PI / 2;
    huntMarker.add(halo);
    var haloOuter = new THREE.Mesh(new THREE.RingGeometry(1.06, 1.34, 40), ringMat);
    haloOuter.rotation.x = -Math.PI / 2;
    huntMarker.add(haloOuter);
    // 光柱：半透明圆柱，越往上越淡
    var beamMat = new THREE.MeshBasicMaterial({
      color: '#FFE9A8', transparent: true, opacity: 0,
      depthWrite: false, side: THREE.DoubleSide
    });
    var beam = new THREE.Mesh(new THREE.CylinderGeometry(0.52, 0.78, 1, 12, 1, true), beamMat);
    beam.position.y = 0.5;
    huntMarker.add(beam);
    // 顶部的小箭头，指示方向（俯视角下光柱投影很短，靠这个锚点最有效）
    var arrowMat = new THREE.MeshBasicMaterial({
      color: '#FFD75E', transparent: true, opacity: 0, depthWrite: false, depthTest: false
    });
    var arrow = new THREE.Mesh(new THREE.ConeGeometry(0.85, 1.5, 6), arrowMat);
    arrow.rotation.x = Math.PI;
    arrow.position.y = 1.5;
    huntMarker.add(arrow);
    // 箭头外面套一圈描边，浅色地面上也能看清
    var arrowRing = new THREE.Mesh(
      new THREE.RingGeometry(1.15, 1.42, 6),
      new THREE.MeshBasicMaterial({
        color: '#3A8A5C', transparent: true, opacity: 0, side: THREE.DoubleSide,
        depthWrite: false, depthTest: false
      })
    );
    arrowRing.rotation.x = -Math.PI / 2;
    arrowRing.position.y = 0.2;
    huntMarker.add(arrowRing);

    huntMarker.visible = false;
    huntMarker.renderOrder = 20;
    scene.add(huntMarker);
    huntMarker.userData = {
      ring: ringMat, beam: beamMat, arrow: arrowMat, arrowRing: arrowRing.material,
      halo: halo, haloOuter: haloOuter, beamMesh: beam, arrowMesh: arrow, arrowRingMesh: arrowRing
    };
    return huntMarker;
  }

  /* 把标记放到某个单词对象上。strength: 0..1 */
  S.setHuntTarget = function (id, strength) {
    ensureHuntMarker();
    var ud = huntMarker.userData;
    if (!id) {
      huntId = null;
      huntIntensity = 0;
      huntMarker.visible = false;
      return false;
    }
    var w = words.get(id);
    if (!w || !w.node) { return false; }
    huntId = id;
    huntIntensity = clamp(typeof strength === 'number' ? strength : 1, 0, 1);
    huntMarker.visible = true;

    world.root.updateMatrixWorld(true);
    var bb = new THREE.Box3().setFromObject(w.node);
    if (bb.isEmpty()) { huntMarker.visible = false; return false; }
    bb.getCenter(tmpCenter);
    bb.getSize(tmpSize);
    var radius = Math.max(1.4, Math.max(tmpSize.x, tmpSize.z) * 0.42);
    radius = Math.min(radius, 10);
    huntMarker.position.set(tmpCenter.x, Math.max(0.14, bb.min.y + 0.06), tmpCenter.z);
    var height = Math.min(26, Math.max(7, tmpSize.y + 6));
    ud.halo.scale.setScalar(radius);
    ud.haloOuter.scale.setScalar(radius * 1.7);
    ud.beamMesh.scale.set(1, height, 1);
    ud.beamMesh.position.y = height / 2;
    ud.arrowMesh.position.y = height + 1.0;
    ud.arrowRingMesh.position.y = height + 1.0;
    ud.ring.opacity = 0.72 * huntIntensity;
    ud.beam.opacity = 0.26 * huntIntensity;
    ud.arrow.opacity = 0.95 * huntIntensity;
    ud.arrowRing.opacity = 0.6 * huntIntensity;
    return true;
  };

  /* 找到时的爆闪：光圈快速放大淡出，给即时正反馈 */
  var burst = { t: -1, pos: new THREE.Vector3(), scale: 1 };
  S.burstAt = function (id) {
    var w = words.get(id);
    if (!w || !w.node) { return; }
    world.root.updateMatrixWorld(true);
    var bb = new THREE.Box3().setFromObject(w.node);
    if (bb.isEmpty()) { return; }
    bb.getCenter(tmpCenter);
    bb.getSize(tmpSize);
    burst.pos.copy(tmpCenter);
    burst.pos.y = Math.max(0.2, bb.min.y + 0.2);
    burst.scale = Math.max(1.6, Math.max(tmpSize.x, tmpSize.z) * 0.6);
    burst.t = 0;
    ensureBurst();
    burstMesh.visible = true;
  };

  var burstMesh = null;
  var burstMat = null;
  function ensureBurst() {
    if (burstMesh) { return; }
    burstMat = new THREE.MeshBasicMaterial({
      color: '#8CE0A8', transparent: true, opacity: 0,
      side: THREE.DoubleSide, depthWrite: false, depthTest: false
    });
    burstMesh = new THREE.Mesh(new THREE.RingGeometry(0.8, 1.0, 40), burstMat);
    burstMesh.rotation.x = -Math.PI / 2;
    burstMesh.renderOrder = 21;
    burstMesh.visible = false;
    scene.add(burstMesh);
  }

  function updateHunt(dt) {
    if (huntMarker && huntMarker.visible && huntId) {
      var ud = huntMarker.userData;
      // 缓脉动，别闪太快（低龄用户容易视觉疲劳）
      var pulse = 1 + Math.sin(elapsed * 2.4) * 0.07;
      var w = words.get(huntId);
      if (w && w.node) {
        world.root.updateMatrixWorld(true);
        var bb2 = tmpBox.setFromObject(w.node);
        if (!bb2.isEmpty()) {
          bb2.getSize(tmpSize);
          var r = Math.min(10, Math.max(1.4, Math.max(tmpSize.x, tmpSize.z) * 0.42));
          ud.halo.scale.setScalar(r * pulse);
          ud.haloOuter.scale.setScalar(r * (1.7 + Math.sin(elapsed * 1.6) * 0.1));
          ud.arrowMesh.rotation.y = elapsed * 1.4;
          var arrowScale = Math.max(1, r * 0.42);
          ud.arrowMesh.scale.setScalar(arrowScale);
          ud.arrowRingMesh.scale.setScalar(arrowScale);
          ud.arrowRingMesh.rotation.z = -elapsed * 0.8;
        }
      }
    }
    if (burst.t >= 0) {
      burst.t += dt;
      var k = burst.t / 0.72;
      if (k >= 1) {
        burst.t = -1;
        if (burstMesh) { burstMesh.visible = false; }
      } else {
        ensureBurst();
        burstMesh.visible = true;
        burstMesh.position.copy(burst.pos);
        var s = burst.scale * (1 + k * 3.2);
        burstMesh.scale.set(s, s, 1);
        burstMat.opacity = 0.85 * (1 - k) * (1 - k);
      }
    }
  }

  /* 取某个单词在屏幕上的位置，用于把提示气泡贴到目标附近、
     以及给屏幕外的目标画方向箭头。

     返回：
       x / y       —— 目标在画布内的像素坐标（可能是负数或超出宽高，调用方自己夹取）
       onScreen    —— 是否在可视区域内
       behind      —— 是否在相机背后（此时 x/y 已做过镜像翻转）
       angle       —— 从画布中心指向目标的屏幕角度（弧度，0 = 正右方）
       dist        —— 画布中心到目标的像素距离
       width/height—— 画布尺寸，方便调用方做边缘裁剪 */
  S.getWordScreenPos = function (id) {
    if (!renderer || !camera) { return null; }
    var w = words.get(id);
    if (!w || !w.node || !w.node.parent) { return null; }
    world.root.updateMatrixWorld(true);
    var bb = new THREE.Box3().setFromObject(w.node);
    if (bb.isEmpty()) { return null; }
    bb.getCenter(tmpCenter);
    tmpCenter.y = bb.max.y;
    var el2 = renderer.domElement;
    var width = el2.clientWidth;
    var height = el2.clientHeight;
    if (!width || !height) { return null; }

    camera.updateMatrixWorld();
    // 用相机空间判断「背后」：相机看向 -Z，所以 z > 0 就在相机后面。
    // 投影后 z 会落进 [0,1]，光看 tmpV.z 无法区分「远」和「背后」。
    tmpV3.copy(tmpCenter).applyMatrix4(camera.matrixWorldInverse);
    var behind = tmpV3.z > 0;

    tmpV.copy(tmpCenter).project(camera);
    var nx = tmpV.x;
    var ny = tmpV.y;
    var onScreen = !behind && nx > -1 && nx < 1 && ny > -1 && ny < 1;
    // 在背后时投影结果会左右颠倒，翻回来方向才正确
    if (behind) {
      nx = -nx;
      ny = -ny;
    }
    var px = (nx * 0.5 + 0.5) * width;
    var py = (-ny * 0.5 + 0.5) * height;
    return {
      x: px,
      y: py,
      onScreen: onScreen,
      behind: behind,
      angle: Math.atan2(py - height / 2, px - width / 2),
      dist: Math.hypot(px - width / 2, py - height / 2),
      width: width,
      height: height
    };
  };

  /* 距离目标多远（用于「热/冷」提示，也用于判断是否需要导航箭头） */
  S.distanceToWord = function (id) {
    var w = words.get(id);
    if (!w || !w.node) { return Infinity; }
    world.root.updateMatrixWorld(true);
    var bb = new THREE.Box3().setFromObject(w.node);
    if (bb.isEmpty()) { return Infinity; }
    bb.getCenter(tmpCenter);
    return Math.hypot(tmpCenter.x - cam.target.x, tmpCenter.z - cam.target.z);
  };

  /* ---------------- 昼夜时间 API ---------------- */

  /* 兼容旧接口：宿主 / 旧版链接还传 true/false。
     true  = 去夜晚（20:30），false = 回白天（10:00），带缓动；instant 立即到位。 */
  S.setNight = function (on, instant) {
    S.setHour(on ? 20.5 : 10, instant);
  };

  /* 直接设定时刻（0..24），默认缓动到目标；instant=true 立即跳变。
     缓动时按「最短方向」跨过 0 点，避免 23:50 → 00:10 走一大圈。 */
  S.setHour = function (h, instant) {
    h = ((h % 24) + 24) % 24;
    hourGoal = h;
    if (instant || reduced) {
      hour = h;
      applyLighting();
      emitPhase();
    }
  };

  /* 时间流动：on=true 时 hour 自己往前走。
     secondsPerDay 可选，表示「走完一整天要用多少现实秒」，越小越快。 */
  S.setTimeFlow = function (on, secondsPerDay) {
    timeFlow = !!on;
    if (typeof secondsPerDay === 'number' && secondsPerDay > 1) {
      daySeconds = secondsPerDay;
    }
  };

  S.isTimeFlowing = function () { return timeFlow; };

  S.getHour = function () { return hour; };

  S.getTimeLabel = function () { return hourLabel(hour); };

  /* 把当前采样的天空色 / 夜色强度 / 暖色强度交给 UI 层，
     UI 用它来同步 CSS 背景层与暗角，做到 3D 与 CSS 完全一致。 */
  S.getSkyState = function () {
    var s = sampleSky(hour);
    applyWeatherLook(s);
    return {
      sky: '#' + s.sky.getHexString(),
      fog: '#' + s.fog.getHexString(),
      night: s.night,
      warm: s.warm,
      rain: rainAmt,
      snow: snowAmt
    };
  };

  /* 当前时段名，UI 用来显示「清晨 / 正午 / 黄昏 / 夜晚」 */
  function phaseOf(h) {
    if (h < 4.5) { return { id: 'night', label: '深夜' }; }
    if (h < 7.5) { return { id: 'dawn', label: '清晨' }; }
    if (h < 11.5) { return { id: 'morning', label: '上午' }; }
    if (h < 14.5) { return { id: 'noon', label: '正午' }; }
    if (h < 17.5) { return { id: 'afternoon', label: '下午' }; }
    if (h < 19.8) { return { id: 'dusk', label: '黄昏' }; }
    return { id: 'night', label: '夜晚' };
  }
  S.phaseOf = phaseOf;
  S.getPhase = function () { return phaseOf(hour); };

  var lastPhaseId = '';
  function emitPhase() {
    var p = phaseOf(hour);
    if (p.id === lastPhaseId) { return; }
    lastPhaseId = p.id;
    if (phaseCb) { phaseCb(p, hour); }
  }

  /* 天气 API：'clear' | 'rain' | 'snow' */
  S.setWeather = function (kind, instant) {
    var next = WEATHER.CLEAR;
    if (kind === 'rain' || kind === 1) { next = WEATHER.RAIN; }
    else if (kind === 'snow' || kind === 2) { next = WEATHER.SNOW; }
    weatherTarget = next;
    if (instant || reduced) {
      rainAmt = next === WEATHER.RAIN ? 1 : 0;
      snowAmt = next === WEATHER.SNOW ? 1 : 0;
      applyLighting();
    }
  };

  S.getWeather = function () {
    if (weatherTarget === WEATHER.RAIN) { return 'rain'; }
    if (weatherTarget === WEATHER.SNOW) { return 'snow'; }
    return 'clear';
  };

  S.setPaused = function (on) { userPaused = !!on; };

  S.isReady = function () { return ready; };

  S.getZone = function () { return currentZone; };

  S.getWordCount = function () { return words.size; };

  /* 只读调试句柄：给验证脚本 / 排查渲染问题用，不要在产品代码里依赖它 */
  S.__debugScene = function () { return scene; };
  S.__debugProps = function () { return props; };
  S.__debugVehicles = function () { return vehicles; };
  S.__debugCamera = function () {
    return {
      pos: camera.position.toArray(),
      target: cam.target.toArray(),
      radius: cam.radius,
      phi: cam.phi,
      theta: cam.theta,
      elapsed: elapsed,
      running: running,
      pageHidden: pageHidden,
      hasGoal: !!goal,
      goalT: goal ? goal.t : -1,
      goalDur: goal ? goal.dur : -1,
      limits: {
        minRadius: camLimits.minRadius,
        maxRadius: camLimits.maxRadius,
        minPhi: camLimits.minPhi,
        maxPhi: camLimits.maxPhi
      }
    };
  };
  // 手动推进交通若干秒（不依赖 rAF），用于自动化验证跟车逻辑。
  // 只推进车辆，不动相机/天气，跑完把 elapsed 的时间和本地时间各自还原。
  S.__debugStepTraffic = function (dt, steps) {
    var n = Math.max(1, steps || 1);
    for (var i = 0; i < n; i++) {
      elapsed += dt;
      updateTraffic(dt);
    }
  };

  S.updateCamera = updateCamera;

  /* ---------------- 时间 / 天气的每帧推进 ---------------- */

  function updateTime(dt) {
    var before = hour;
    if (timeFlow) {
      // 自动流动：24 小时 / daySeconds 秒，跨过 24 就回绕
      hour = (hour + (dt / daySeconds) * 24) % 24;
      hourGoal = hour;
    } else if (Math.abs(hourGoal - hour) > 0.0005) {
      // 缓动到目标：按最短弧长走
      var diff = hourGoal - hour;
      if (diff > 12) { diff -= 24; }
      if (diff < -12) { diff += 24; }
      var step = diff * Math.min(1, dt * 2.2);
      hour = (hour + step + 24) % 24;
      if (Math.abs(hourGoal - hour) < 0.01) { hour = hourGoal; }
    } else {
      return;
    }
    if (Math.abs(hour - before) > 0.0001) {
      applyLighting();
      emitPhase();
    }
  }

  function updateWeatherBlend(dt) {
    var rGoal = weatherTarget === WEATHER.RAIN ? 1 : 0;
    var sGoal = weatherTarget === WEATHER.SNOW ? 1 : 0;
    var changed = false;
    if (Math.abs(rainAmt - rGoal) > 0.001) {
      rainAmt += (rGoal - rainAmt) * Math.min(1, dt * 1.6);
      if (Math.abs(rainAmt - rGoal) < 0.004) { rainAmt = rGoal; }
      changed = true;
    }
    if (Math.abs(snowAmt - sGoal) > 0.001) {
      snowAmt += (sGoal - snowAmt) * Math.min(1, dt * 1.4);
      if (Math.abs(snowAmt - sGoal) < 0.004) { snowAmt = sGoal; }
      changed = true;
    }
    if (changed) { applyLighting(); }
  }

  /* ---------------- 自动巡游 ---------------- */

  // 依次飞过一张分区清单，每站停留 tout.dwell 秒；任何手动操作都会打断。
  var tour = {
    active: false,
    zones: [],
    index: 0,
    wait: 0,
    dwell: 7.5,
    cb: null
  };

  function tourGo() {
    if (!tour.active) { return; }
    var id = tour.zones[tour.index % tour.zones.length];
    if (D.views[id]) {
      applyView(id, false);
      tour.wait = tour.dwell;
      if (tour.cb) { tour.cb(id, tour.index); }
    }
    tour.index++;
  }

  S.startTour = function (zones, onZone) {
    tour.zones = (zones && zones.length) ? zones.slice() : ['main_street', 'school_zone', 'park_zone', 'hospital_zone'];
    tour.index = 0;
    tour.active = true;
    tour.cb = onZone || null;
    tourGo();
    return true;
  };

  S.stopTour = function () {
    var was = tour.active;
    tour.active = false;
    tour.cb = null;
    return was;
  };

  S.isTouring = function () { return tour.active; };

  function updateTour(dt) {
    if (!tour.active) { return; }
    if (flying) { return; }
    tour.wait -= dt;
    if (tour.wait <= 0) { tourGo(); }
  }

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

  /* ---------------- 车辆尺寸与跟车 ---------------- */

  /* 各车型的车身长度（米，沿前进方向）。用于算跟车间距：
     跟车距离至少要「前车尾 + 本车头 + 一个安全间隙」。
     数值来自 models 里各车型的 box 尺寸，留了一点余量。 */
  var VEHICLE_LENGTH = {
    car: 4.4,
    taxi: 4.4,
    bus: 8.6,
    school_bus: 8.6,
    ambulance: 6.2,
    fire_truck: 8.2,
    truck: 5.0,
    bicycle: 1.7,
    scooter: 1.4
  };

  function vehicleLength(type) {
    return VEHICLE_LENGTH[type] || 4.5;
  }

  /* 车身宽度（米），用于判断两条相邻车道横向是否真的会碰。
     数值同样来自 models 里的 box 尺寸。 */
  var VEHICLE_WIDTH = {
    car: 1.92,
    taxi: 1.92,
    bus: 2.5,
    school_bus: 2.5,
    ambulance: 2.24,
    fire_truck: 2.44,
    truck: 2.34,
    bicycle: 0.6,
    scooter: 0.55
  };

  function vehicleWidth(type) {
    return VEHICLE_WIDTH[type] || 2.0;
  }

  /* 两轮车（自行车/滑板车）走靠路边一侧，其余走车道中心 */
  function isBikeType(type) {
    return type === 'bicycle' || type === 'scooter';
  }

  /* 车道横向偏移（米，沿曲线左法线方向）。
     需要同时满足两件事：
     1. 不能和主道车撞：最宽的车是公交 2.5 米，半宽 1.25；自行车半宽 0.3
        → 静态需要 ≥ 1.55 米。但弯道上两车走不同半径的曲线，横向会被压缩，
        实测压缩量约 0.5 米，所以实际需要 ≥ 2.1 米。
     2. 不能跑出路面：路面半宽 4.5 米，偏移 2.9 + 半宽 0.3 = 3.2 < 4.5，安全。
     取 2.9 米：既有足够余量，又稳稳在柏油路面上。 */
  var BIKE_LANE_OFFSET = 2.9;

  function laneOffsetOf(type) {
    return isBikeType(type) ? BIKE_LANE_OFFSET : 0;
  }

  /* 车辆的「车道标识」：同一条 loop 上，两轮车走偏移道，其余走主道。
     只有车道相同的车才会互相阻挡。 */
  function laneKey(v) {
    return v.cfg.loop + '|' + (isBikeType(v.cfg.type) ? 'bike' : 'main');
  }

  /* 车辆在 curve 上的向前距离（米）。u 是 0..1 归一化参数，乘 loop 长度即米。
     环形接缝：b 在 a 后面时（如 a=0.97, b=0.03），向前走要绕大半圈，
     取模自然得到正确值，这里不需要额外特判。 */
  function loopGapMeters(a, b) {
    var d = b.u - a.u;
    if (d < 0) { d += 1; }
    return d * a.len;
  }

  /* 找出同一车道、前方最近的车辆。
     用每个车道的排队顺序，避免每帧 O(n²) 全量比较（车辆数不多但每帧都跑）。 */
  var laneGroups = null;

  function buildLaneGroups() {
    laneGroups = {};
    for (var i = 0; i < vehicles.length; i++) {
      var v = vehicles[i];
      if (v.cfg.loop === 'river') { continue; }
      var k = laneKey(v);
      if (!laneGroups[k]) { laneGroups[k] = []; }
      laneGroups[k].push(v);
    }
    // 每个车道按 u 排序，供后面的环形扫描使用
    for (var k2 in laneGroups) {
      laneGroups[k2].sort(function (a, b) { return a.u - b.u; });
    }
  }

  /* 前方最近车辆：返回 { v, gap, realDist }。
     gap 是沿 loop 向前的弧长（米），realDist 是真实 3D 中心距。

     接缝处理：单纯用 (b.u - a.u) 取模在环形 loop 上是**错的**。
     例：a=0.97、b=0.03 时算出 94% 圈（146 米），但 b 其实就在 a 前方
     6% 圈（约 9 米）。判断方法是比较两个方向的弧长取小的那个，
     同时用真实距离兜底 —— 真实距离不会骗人。 */
  function leaderOf(v, opts) {
    if (!laneGroups) { return null; }
    var keys = [laneKey(v)];
    if (opts && opts.includeAdjacent && !isBikeType(v.cfg.type)) {
      keys.push(v.cfg.loop + '|bike');
    }
    var best = null;
    var bestGap = Infinity;
    var bestReal = Infinity;
    for (var ki = 0; ki < keys.length; ki++) {
      var list = laneGroups[keys[ki]];
      if (!list) { continue; }
      for (var i = 0; i < list.length; i++) {
        var other = list[i];
        if (other === v) { continue; }

        // 真实 3D 距离（从实际渲染位置取，弯道/接缝都准确）
        var pa = v.curve.getPointAt(v.u);
        var pb = other.curve.getPointAt(other.u);
        var realDist = Math.hypot(pa.x - pb.x, pa.z - pb.z);
        // 真实距离太远就不可能是紧邻前车（一圈总长也有限）
        if (realDist > v.len * 0.5) { continue; }

        // 判断「是否在前方」：用真实位置相对本车切向的投影。
        // 投影为正 = 在车头这一侧。切向要用稳定版本，接缝处才不会判反。
        var tan = stableTangent(v.curve, v.u);
        var ahead = (pb.x - pa.x) * tan.x + (pb.z - pa.z) * tan.z;
        if (ahead <= 0) { continue; }

        var gap = loopGapMeters(v, other);
        if (gap < 0.01) { continue; }
        if (gap < bestGap) { bestGap = gap; best = other; bestReal = realDist; }
      }
    }
    return best ? { v: best, gap: bestGap, realDist: bestReal } : null;
  }

  /* 根据前车位置算出「本车可以走多快」。
     这是一个简化版 IDM（智能驾驶员模型）：距离越近减得越狠，
     而不是简单地开关刹车，视觉上更像真车在跟车。 */
  function followSpeed(v) {
    // 汽车同时看主道和两轮道：不允许高速从自行车旁边擦过。
    var lead = leaderOf(v, { includeAdjacent: true });
    if (!lead) { return Infinity; }

    var adjacentBike = isBikeType(lead.v.cfg.type) && !isBikeType(v.cfg.type);
    // 侧面车道（两轮车有 2.9 米偏移）。
    // 直线段横向错得开，汽车可以直接超；但长车（公交/消防车 8 米以上）
    // 在弯道上车身会「扫」到内侧车道，几何上必然压过自行车。
    // 所以：长车遇到两轮车就老实跟住，等它拉开距离；短车正常超。
    if (adjacentBike) {
      var myLen = vehicleLength(v.cfg.type);
      var sideRoom = lead.realDist - (myLen / 2 + vehicleLength(lead.v.cfg.type) / 2);
      // 长车（≥ 7 米）保守一些：空档 12 米内就跟着；短车 9 米。
      // 9/12 这两个值来自 100 秒仿真，低于此会偶发压到自行车。
      var followDist = myLen >= 7 ? 12 : 9;
      if (sideRoom > followDist) { return Infinity; }
      var bikeCap = lead.v.speed + Math.max(0, (sideRoom - 3) * 0.9);
      return clamp(bikeCap, 0, v.cfg.speed);
    }

    var myLen = vehicleLength(v.cfg.type);
    var leadLen = vehicleLength(lead.v.cfg.type);
    // 空档取「参数弧长」和「真实距离」的较小值：
    // 弯道上真实距离更短，用它才安全；接缝处参数距离不可靠，也靠它兜底。
    var centerGap = Math.min(lead.gap, lead.realDist);
    var gap = centerGap - myLen / 2 - leadLen / 2;
    // 安全空档：车越长、开得越快，留得越多。下限 2.5 米，保证视觉上
    // 一眼就能看出「这是两辆车」，而不是贴在一起的一坨。
    var safeGap = Math.max(2.5, 1.8 + v.speed * 0.55);

    if (gap <= 0.6) { return 0; }
    if (gap >= safeGap) { return Infinity; }

    // 在安全区间内线性降速；比例越低越慢
    var ratio = clamp((gap - 0.6) / Math.max(0.1, safeGap - 0.6), 0, 1);
    // 前车实际速度（已含它自己的跟车/红绿灯结果）；本车最多跟到它的速度，
    // 否则会顶上去。ratio 高时允许略微超一点，避免变成「一慢全慢」的排队僵局。
    var cap = lead.v.speed + Math.max(0, ratio - 0.6) * 2.2;
    return Math.min(v.cfg.speed * ratio, Math.max(cap, 0));
  }

  /* 取 curve 上某处的「稳定的横向法线」。
     直接用 getTangentAt 在闭合接缝（u≈0 / u≈1）会跳变：
     u=0.9999 时切向是 (0.98, 0.18)，一跨过去变成 (0.00, 1.00)，
     导致两轮车的横向偏移方向突然甩到另一个方向，看起来像「车道错位」。
     改成用前后两个采样点的位置差求切向，跨接缝时也能保持连续。 */
  function stableTangent(curve, u) {
    var eps = 0.004;
    var ua = u - eps;
    var ub = u + eps;
    // 环绕处理
    if (ua < 0) { ua += 1; }
    if (ub > 1) { ub -= 1; }
    var pa = curve.getPointAt(ua);
    var pb = curve.getPointAt(ub);
    var dx = pb.x - pa.x;
    var dz = pb.z - pa.z;
    var len = Math.hypot(dx, dz);
    if (len < 1e-6) {
      var t = curve.getTangentAt(clamp(u, 0, 1));
      return { x: t.x, z: t.z };
    }
    return { x: dx / len, z: dz / len };
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
      var t0 = stableTangent(v.curve, v.u);
      var lane0 = laneOffsetOf(cfg.type);
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
    // 每帧重排各车道的先后顺序：车在动，上一帧的排序这一帧就失效了
    buildLaneGroups();

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
      } else {
        // 跟车：前车太近就跟着减速，绝不允许穿过去
        var follow = followSpeed(v);
        if (follow < targetSpeed) { targetSpeed = follow; }
      }

      var accel = targetSpeed > v.speed ? 4.5 : 16;
      var diff = targetSpeed - v.speed;
      v.speed += clamp(diff, -accel * dt, accel * dt);

      if (v.speed > 0.02) {
        v.u = (v.u + (v.speed * dt) / v.len) % 1;
      }

      // 硬性防穿模：用「真实 3D 坐标」判断，不依赖 loop 参数距离。
      //
      // 为什么不用 u 算：loop 是环形的，接缝处（一辆车 u≈0.97、另一辆 u≈0.03）
      // 参数距离会算出 146 米，但它们其实只隔 6 米 —— 参数距离在这里不可靠。
      // 真实坐标没有这个问题，弯道、接缝都天然正确。
      //
      // 只对「同一车道」生效：两轮车有 2.2 米的独立偏移车道，把它算进来的话
      // 汽车会被无谓地往回拉，最后卡死在自行车旁边（两车 u 完全相同、都动不了）。
      var hardLead = leaderOf(v);
      if (hardLead && !(isBikeType(hardLead.v.cfg.type) && !isBikeType(v.cfg.type))) {
        var pa = v.curve.getPointAt(v.u);
        var pb = hardLead.v.curve.getPointAt(hardLead.v.u);
        var realDist = Math.hypot(pa.x - pb.x, pa.z - pb.z);
        var minCenterGap = vehicleLength(v.cfg.type) / 2
          + vehicleLength(hardLead.v.cfg.type) / 2 + 0.8;
        // 真实距离不够（含弯道收缩），或者参数距离已经贴脸
        if (realDist < minCenterGap || hardLead.gap < minCenterGap) {
          // 用真实缺口反推要退多少米；弯道上真实距离 ≤ 参数距离，取真实值更保守
          var shortfall = minCenterGap - Math.min(realDist, hardLead.gap);
          if (shortfall > 0) {
            v.u = (v.u - shortfall / v.len) % 1;
            if (v.u < 0) { v.u += 1; }
          }
          v.speed = Math.min(v.speed, hardLead.v.speed);
        }
      }

      var pp = v.curve.getPointAt(v.u);
      // 用稳定切向：接缝处 getTangentAt 会跳变，横向偏移会甩到错误方向
      var tt = stableTangent(v.curve, v.u);
      var lane = laneOffsetOf(v.cfg.type);
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

  /* 雨天给一部分行人发伞：把伞挂到人物右手上，走路时跟着摆。
     和 models 里那批"街边静态伞"分开管理，各自独立显隐。 */
  function attachUmbrellasToPeople() {
    if (!props || !MD.makeUmbrella) { return; }
    var palette = ['#E5484D', '#6FA8DC', '#F2C14E', '#6FCF97', '#A78BFA', '#FF9F43'];
    var holders = [];
    // 巡街行人里挑一部分（每四个挑一个，避免满街都是伞，也控制网格开销）
    for (var i = 0; i < peds.length; i++) {
      if (i % 4 !== 0) { continue; }
      holders.push({ person: peds[i].obj, key: 'ped' + i });
    }
    // 门口站着的两个地标人物也发伞
    ['driver', 'baker'].forEach(function (id) {
      var w = words.get(id);
      if (w && w.node) {
        var obj = findPersonParts(w.node);
        if (obj) { holders.push({ person: obj, key: 'land' + id }); }
      }
    });

    holders.forEach(function (h, idx) {
      if (!h.person || !h.person.rightArm) { return; }
      var umbrella = MD.makeUmbrella(palette[idx % palette.length]);
      // 挂在右手末端，稍微前移，像真的举在头顶
      umbrella.position.set(0, -0.55, 0.1);
      umbrella.rotation.z = 0.12;
      umbrella.visible = false;
      umbrella.scale.setScalar(0.001);
      h.person.rightArm.add(umbrella);
      props.umbrellas.push({ group: umbrella, follows: h.key });
    });
  }

  // 从一个人物 group 里找回 buildPerson 返回的那套部件（rightArm 等）
  function findPersonParts(node) {
    var found = null;
    node.traverse(function (o) {
      if (found) { return; }
      if (o.userData && o.userData.personParts) { found = o.userData.personParts; }
    });
    return found;
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

    if (props.pigeons) {
      for (i = 0; i < props.pigeons.length; i++) {
        var pg = props.pigeons[i];
        var pPhase = (t * 0.42 + pg.phase) % 6.2;
        // 0-1.4s 站立，1.4-2.2s 低头啄食，2.2-4.4s 走到新位置，剩下面向调整
        var peck = pPhase > 1.4 && pPhase < 2.2;
        var walk = pPhase > 2.2 && pPhase < 4.4;
        var wob = Math.sin(t * 2.3 + pg.phase);
        pg.head.rotation.x = peck ? 0.9 + Math.sin(t * 16) * 0.25 : 0;
        pg.head.position.z = 0.2 + (peck ? 0.04 : 0);
        if (walk) {
          var wp = (pPhase - 2.2) / 2.2;
          pg.group.position.x = pg.home.x + Math.sin(wp * Math.PI * 2 + pg.phase) * 1.3;
          pg.group.position.z = pg.home.z + Math.cos(wp * Math.PI * 2 + pg.phase) * 1.0;
          pg.group.rotation.y = Math.atan2(Math.cos(wp * Math.PI * 2 + pg.phase), -Math.sin(wp * Math.PI * 2 + pg.phase));
        } else {
          pg.group.position.x += (pg.home.x - pg.group.position.x) * Math.min(1, dt * 1.2);
          pg.group.position.z += (pg.home.z - pg.group.position.z) * Math.min(1, dt * 1.2);
        }
        pg.group.position.y = 0.16 + (walk ? Math.abs(Math.sin(t * 9 + pg.phase)) * 0.035 : 0);
        pg.group.rotation.z = walk ? wob * 0.06 : 0;
      }
    }

    if (props.cat) {
      props.cat.tail.rotation.y = Math.sin(t * 2.2) * 0.55;
      props.cat.tail.rotation.x = Math.sin(t * 1.7) * 0.2;
      props.cat.group.position.y = 0.16 + Math.sin(t * 1.4) * 0.012;
    }

    if (props.craneJib) {
      props.craneJib.rotation.y = 0.62 + Math.sin(t * 0.11) * 0.5;
      if (props.craneHook) {
        props.craneHook.position.y = Math.sin(t * 0.32) * 1.6;
        props.craneHook.rotation.y = Math.sin(t * 0.2) * 0.1;
      }
    }

    if (props.ducks) {
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
        if (cl.group.position.x > 105) { cl.group.position.x = -105; }
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
    if (props.butterflies) {
      for (i = 0; i < props.butterflies.length; i++) {
        var bf = props.butterflies[i];
        var bx = bf.cx + Math.sin(t * 0.5 + bf.phase) * 2.2;
        var bz = bf.cz + Math.cos(t * 0.42 + bf.phase) * 1.8;
        var by = 1.1 + Math.sin(t * 1.3 + bf.phase) * 0.35;
        bf.group.position.set(bx, by, bz);
        bf.group.rotation.y = Math.atan2(Math.cos(t * 0.5 + bf.phase), -Math.sin(t * 0.42 + bf.phase));
        var flap2 = Math.sin(t * 14 + bf.phase) * 0.9;
        bf.wingL.rotation.y = flap2;
        bf.wingR.rotation.y = -flap2;
      }
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
