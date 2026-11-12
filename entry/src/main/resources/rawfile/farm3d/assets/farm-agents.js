(function (global) {
  'use strict';

  // 农场智能体层：给动物/人物加短小的“生活片段”和双语气泡。
  // 由 farm-scene.js 注入场景内部句柄，在每帧 updateScene 末尾驱动。
  var D = global.FarmData;

  var STORY_FIRST_DELAY = 8;
  var TICK_MIN = 14;
  var TICK_MAX = 26;
  var STORY_GAP = 7;
  var AGENT_COOLDOWN_MIN = 22;
  var AGENT_COOLDOWN_MAX = 40;
  var STORY_REPEAT_LOCK = 90;
  var BUBBLE_MS = 6500;
  var MAX_BUBBLES = 2;
  var PROJECT_INTERVAL = 80;
  var CLICK_TTS_GAP = 1200;
  var ZONE_STORY_DELAY = 1; // 秒：镜头切到分区后等补间结束再讲故事

  var ZONE_STORIES = {
    farmyard_zone: ['chicken_peck', 'pig_wallow', 'grandma_feed', 'rabbit_hop', 'cat_stretch'],
    pasture_zone: ['cow_graze', 'sheep_graze', 'goat_graze', 'horse_run'],
    orchard_pond_zone: ['duck_swim', 'goose_swim', 'bird_chirp'],
    field_zone: ['bird_chirp', 'bee_hover']
  };

  var STORIES = {
    rabbit_hop: {
      agent: 'rabbit', dur: 2.6, zone: 'farmyard_zone', grainLock: true,
      bubble: { zh: '我跳得最高！', en: 'I can hop so high!' }
    },
    rabbit_report: {
      agent: 'rabbit', dur: 5.4, zone: 'farmyard_zone', grainLock: true, farmer: true,
      bubbles: [
        { at: 0.35, who: 'agent', zh: '主人，胡萝卜地又长好啦！', en: 'Farmer, the carrots are ready!' },
        { at: 2.0, who: 'farmer', zh: '谢谢你，小兔子！', en: 'Thank you, little rabbit!' }
      ]
    },
    cow_graze: {
      agent: 'cow', dur: 6.2, zone: 'pasture_zone',
      bubble: { zh: '这里的草真甜。', en: 'The grass is sweet here.' }
    },
    sheep_graze: {
      agent: 'sheep', dur: 6.0, zone: 'pasture_zone',
      bubble: { zh: '咩～我在吃草。', en: 'Baa! I am eating grass.' }
    },
    horse_run: {
      agent: 'horse', dur: 5.2, zone: 'pasture_zone',
      bubble: { zh: '跑起来啦！', en: 'Watch me run!' }
    },
    goat_graze: {
      agent: 'goat', dur: 5.8, zone: 'pasture_zone',
      bubble: { zh: '咩！看我顶一下。', en: 'Maa! Watch me butt.' }
    },
    pig_wallow: {
      agent: 'pig', dur: 4.6, zone: 'farmyard_zone',
      bubble: { zh: '泥巴最舒服！', en: 'Mud feels so good!' }
    },
    chicken_peck: {
      agent: 'chicken', dur: 2.8, zone: 'farmyard_zone',
      bubble: { zh: '啄啄啄，找小虫。', en: 'Peck, peck, find a bug.' }
    },
    rooster_crow: {
      agent: 'rooster', dur: 2.4, zone: 'farmyard_zone', manual: true,
      bubble: { zh: '喔喔喔！天亮啦！', en: 'Cock-a-doodle-doo!' }
    },
    duck_swim: {
      agent: 'duck', dur: 5.2, zone: 'orchard_pond_zone',
      bubble: { zh: '水好凉快！', en: 'The water is cool!' }
    },
    goose_swim: {
      agent: 'goose', dur: 5.2, zone: 'orchard_pond_zone',
      bubble: { zh: '嘎嘎！我是农场卫士。', en: 'Honk! I guard the farm.' }
    },
    cat_stretch: {
      agent: 'cat', dur: 2.6, zone: 'farmyard_zone',
      bubble: { zh: '伸个大懒腰。', en: 'Big lazy stretch.' }
    },
    dog_bark: {
      agent: 'dog', dur: 2.0, zone: 'farmyard_zone', actor: 'dog',
      bubble: { zh: '汪汪！我在这儿。', en: 'Woof! I am here.' }
    },
    bee_hover: {
      agent: 'bee', dur: 2.6, zone: 'field_zone',
      bubble: { zh: '嗡嗡嗡，我去采蜜。', en: 'Buzz! Off to make honey.' }
    },
    bird_chirp: {
      agent: 'bird', dur: 2.6, zone: 'orchard_pond_zone',
      bubble: { zh: '啾啾！今天天气真好。', en: 'Tweet! What a nice day.' }
    },
    grandma_feed: {
      agent: 'grandma', dur: 5.4, zone: 'farmyard_zone', chicken: true,
      bubble: { zh: '来，小鸡们吃饭啦。', en: 'Here, little chickens, lunchtime!' }
    },
    farmer_wave: {
      agent: 'farmer', dur: 2.6, zone: 'farmyard_zone', actor: 'farmer', grainLock: true,
      bubble: { zh: '早上好，农场！', en: 'Good morning, farm!' }
    },
    child_play: {
      agent: 'child', dur: 2.8, zone: 'farmyard_zone', actor: 'child',
      bubble: { zh: '一起玩呀！', en: 'Let us play together!' }
    }
  };

  var CLICK_KIND = {
    rabbit: 'rabbit_hop',
    cow: 'cow_graze',
    sheep: 'sheep_graze',
    horse: 'horse_run',
    goat: 'goat_graze',
    pig: 'pig_wallow',
    chicken: 'chicken_peck',
    rooster: 'rooster_crow',
    duck: 'duck_swim',
    goose: 'goose_swim',
    cat: 'cat_stretch',
    dog: 'dog_bark',
    bee: 'bee_hover',
    bird: 'bird_chirp',
    farmer: 'farmer_wave',
    child: 'child_play',
    grandma: 'grandma_feed'
  };

  var CLICK_DUR = {
    horse_run: 5.2,
    duck_swim: 4.6,
    goose_swim: 4.6,
    rabbit_report: 5.4
  };

  var ANCHOR_Y = {
    rabbit: 1.05, cow: 2.45, sheep: 1.95, horse: 3.5, goat: 1.95, pig: 1.7,
    chicken: 1.25, rooster: 1.45, duck: 1.0, goose: 1.45, cat: 1.25, dog: 1.55,
    bee: 0.45, bird: 0.55, farmer: 2.45, child: 1.95, grandma: 2.25
  };

  var NIGHT_LINE = { zh: '嘘…我已经睡啦。', en: 'Shh… I am sleeping.' };

  var host = null;
  var ui = null;
  var ready = false;
  var rng = makeRng(20261108);
  var agents = {};
  var agentOrder = [];
  var sleepList = [];
  var story = null;
  var tickTimer = STORY_FIRST_DELAY;
  var zoneTimer = -1;
  var lastZone = 'overview';
  var nightOn = false;
  var sleepK = 0;
  var wasAsleep = false;
  var rainOn = false;
  var rainK = 0;
  var wasRainPose = false;
  var nowMs = 0;
  var lastProject = 0;
  var lastSpeakAt = 0;
  var bubbleMap = {};
  var bubbleOrder = [];
  var bubbleUid = 0;
  var tmpWorld = null;

  function makeRng(seed) {
    var s = seed >>> 0;
    return function () {
      s = (s * 1664525 + 1013904223) >>> 0;
      return s / 4294967296;
    };
  }

  function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }

  function easeInOut(k) {
    if (k < 0) k = 0;
    if (k > 1) k = 1;
    return k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
  }

  function findActor(id) {
    var list = host && host.built && host.built.actors;
    if (!list) return null;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i].obj;
    }
    return null;
  }

  function resolveRoot(id) {
    if (!host || !host.built) return null;
    if (id === 'bee') return host.built.bee || null;
    if (id === 'farmer' || id === 'child' || id === 'dog') {
      var actorRoot = findActor(id);
      if (actorRoot) return actorRoot;
    }
    var entry = host.built.objects[id];
    return entry ? entry.root : null;
  }

  function makeAgent(id, root) {
    if (!root) return null;
    var idle = root.userData && root.userData.idle ? root.userData.idle : null;
    var a = {
      id: id,
      root: root,
      zone: (D.objectsById && D.objectsById[id] ? D.objectsById[id].zone : '') || '',
      anchorY: ANCHOR_Y[id] || 1.4,
      actorId: (id === 'farmer' || id === 'child' || id === 'dog') ? id : '',
      idle: idle,
      head: idle && idle.head ? idle.head : null,
      earL: idle && idle.earL ? idle.earL : null,
      earR: idle && idle.earR ? idle.earR : null,
      tail: idle && idle.tail ? idle.tail : null,
      legs: idle && idle.legs ? idle.legs : null,
      cooldown: 0,
      repeat: {},
      temp: false,
      basePos: root.position.clone(),
      baseRot: { x: root.rotation.x, y: root.rotation.y, z: root.rotation.z },
      baseHeadX: idle && idle.head ? idle.head.rotation.x : 0,
      baseEarLZ: idle && idle.earL ? idle.earL.rotation.z : 0,
      baseEarRZ: idle && idle.earR ? idle.earR.rotation.z : 0,
      baseTailY: idle && idle.tail ? idle.tail.rotation.y : 0
    };
    return a;
  }

  function makeSleepAgent(root, cfg) {
    if (!root) return null;
    return {
      id: (cfg && cfg.kind) || '',
      root: root,
      idle: cfg || null,
      head: cfg && cfg.head ? cfg.head : null,
      earL: cfg && cfg.earL ? cfg.earL : null,
      earR: cfg && cfg.earR ? cfg.earR : null,
      tail: cfg && cfg.tail ? cfg.tail : null,
      actorId: '',
      basePos: root.position.clone(),
      baseRot: { x: root.rotation.x, y: root.rotation.y, z: root.rotation.z },
      baseHeadX: cfg && cfg.head ? cfg.head.rotation.x : 0,
      baseEarLZ: cfg && cfg.earL ? cfg.earL.rotation.z : 0,
      baseEarRZ: cfg && cfg.earR ? cfg.earR.rotation.z : 0,
      baseTailY: cfg && cfg.tail ? cfg.tail.rotation.y : 0
    };
  }

  function buildAgents() {
    agents = {};
    agentOrder = [];
    sleepList = [];
    var ids = ['rabbit', 'cow', 'sheep', 'horse', 'goat', 'pig', 'chicken', 'rooster',
      'duck', 'goose', 'cat', 'dog', 'bee', 'bird', 'farmer', 'child', 'grandma'];
    for (var i = 0; i < ids.length; i++) {
      var a = makeAgent(ids[i], resolveRoot(ids[i]));
      if (!a) continue;
      agents[ids[i]] = a;
      agentOrder.push(a);
    }
    // 夜间睡姿要覆盖所有 idle 实例（含牛群/羊群/懒猫等重复个体）
    var idles = (host && host.built && host.built.idles) ? host.built.idles : [];
    var seen = [];
    for (var j = 0; j < idles.length; j++) {
      var rec = makeSleepAgent(idles[j].root, idles[j].cfg);
      if (!rec) continue;
      if (rec.root.userData && rec.root.userData.coopBird) continue;
      sleepList.push(rec);
      seen.push(rec.root);
    }
    for (var k = 0; k < agentOrder.length; k++) {
      if (seen.indexOf(agentOrder[k].root) < 0) {
        if (agentOrder[k].root.userData && agentOrder[k].root.userData.coopBird) continue;
        sleepList.push(agentOrder[k]);
        seen.push(agentOrder[k].root);
      }
    }
  }

  function agentFor(id, root) {
    var base = agents[id];
    if (base && (!root || root === base.root)) return base;
    if (!root) return base || null;
    var temp = makeAgent(id, root);
    if (temp) temp.temp = true;
    return temp;
  }

  // ---------- 气泡 ----------

  function bubbleRect(rec) {
    return { x: rec.left - rec.w / 2, y: rec.top - rec.h, w: rec.w, h: rec.h };
  }

  function removeBubble(key) {
    var rec = bubbleMap[key];
    if (!rec) return;
    if (rec.el && rec.el.parentNode) rec.el.parentNode.removeChild(rec.el);
    delete bubbleMap[key];
    for (var i = 0; i < bubbleOrder.length; i++) {
      if (bubbleOrder[i] === key) { bubbleOrder.splice(i, 1); break; }
    }
  }

  function showBubble(key, agent, zh, en, ms) {
    if (!ui || !ui.layer || !agent || !agent.root) return;
    var rec = bubbleMap[key];
    if (!rec) {
      var el = global.document.createElement('button');
      el.type = 'button';
      el.className = 'bubble';
      el.setAttribute('data-agent', agent.id);
      var zhEl = global.document.createElement('span');
      zhEl.className = 'bubble-zh';
      var enEl = global.document.createElement('span');
      enEl.className = 'bubble-en';
      el.appendChild(zhEl);
      el.appendChild(enEl);
      rec = { el: el, zhEl: zhEl, enEl: enEl, anchor: agent.root, anchorY: agent.anchorY, w: 0, h: 0, left: 0, top: 0 };
      bubbleMap[key] = rec;
      bubbleOrder.push(key);
      (function (r) {
        el.addEventListener('click', function (e) {
          if (e && e.preventDefault) e.preventDefault();
          if (e && e.stopPropagation) e.stopPropagation();
          var now = Date.now();
          if (now - lastSpeakAt < CLICK_TTS_GAP) return;
          lastSpeakAt = now;
          var ok = false;
          if (ui && ui.speak) ok = ui.speak(r.enText || '', r.zhText || '');
          if (!ok && ui && ui.toast) ui.toast('当前环境无法播放发音');
        });
      })(rec);
      ui.layer.appendChild(el);
    }
    rec.zhText = zh || '';
    rec.enText = en || '';
    rec.zhEl.textContent = rec.zhText;
    rec.enEl.textContent = rec.enText;
    rec.w = 0;
    rec.h = 0;
    rec.el.setAttribute('aria-label', '朗读：' + rec.zhText + ' ' + rec.enText);
    rec.until = nowMs + (ms || BUBBLE_MS);
    rec.el.classList.add('is-entering');
    global.setTimeout(function () {
      if (rec.el) rec.el.classList.remove('is-entering');
    }, 30);
    while (bubbleOrder.length > MAX_BUBBLES) {
      removeBubble(bubbleOrder[0]);
    }
    updateBubble(rec);
  }

  function pickVisibleAnchor(w, h) {
    for (var i = 0; i < agentOrder.length; i++) {
      var a = agentOrder[i];
      if (!a || !a.root) continue;
      a.root.getWorldPosition(tmpWorld);
      var p = host.project(tmpWorld.x, tmpWorld.y + a.anchorY, tmpWorld.z);
      if (p.visible && p.x > 60 && p.x < w - 60 && p.y > 70 && p.y < h - 40) return a;
    }
    return null;
  }

  function updateBubble(rec) {
    if (!rec || !host || !ui) return null;
    var el = rec.el;
    if (!rec.w) {
      rec.w = el.offsetWidth || 150;
      rec.h = el.offsetHeight || 48;
    }
    var w = ui.stage.clientWidth || 1;
    var h = ui.stage.clientHeight || 1;
    rec.anchor.getWorldPosition(tmpWorld);
    var p = host.project(tmpWorld.x, tmpWorld.y + rec.anchorY, tmpWorld.z);
    if (rec.preferVisible && (!p.visible || p.x < 0 || p.x > w || p.y < 0 || p.y > h)) {
      var alt = pickVisibleAnchor(w, h);
      if (alt) {
        rec.anchor = alt.root;
        rec.anchorY = alt.anchorY;
        rec.anchor.getWorldPosition(tmpWorld);
        p = host.project(tmpWorld.x, tmpWorld.y + rec.anchorY, tmpWorld.z);
      }
    }
    if (!p.visible || p.x < -40 || p.x > w + 40 || p.y < 0 || p.y > h + 20) {
      el.style.visibility = 'hidden';
      return null;
    }
    el.style.visibility = 'visible';
    var x = clamp(p.x, rec.w / 2 + 8, w - rec.w / 2 - 8);
    var y = clamp(p.y, 56 + rec.h, h - 12);
    rec.left = x;
    rec.top = y;
    el.style.left = x + 'px';
    el.style.top = y + 'px';
    return bubbleRect(rec);
  }

  function rectsOverlap(a, b) {
    return a.x < b.x + b.w + 4 && a.x + a.w + 4 > b.x &&
      a.y < b.y + b.h + 4 && a.y + a.h + 4 > b.y;
  }

  function positionBubbles() {
    var placed = [];
    var stageH = ui && ui.stage ? (ui.stage.clientHeight || 1) : 1;
    for (var i = 0; i < bubbleOrder.length; i++) {
      var rec = bubbleMap[bubbleOrder[i]];
      if (!rec) continue;
      var rect = updateBubble(rec);
      if (!rect) continue;
      // 同屏第二条气泡与上一条重叠时，向上叠放，不互相遮挡
      var guard = 0;
      var hit = true;
      while (hit && guard < 8) {
        hit = false;
        guard++;
        for (var j = 0; j < placed.length; j++) {
          if (rectsOverlap(rect, placed[j])) {
            rec.top = Math.max(56 + rec.h, placed[j].y - 4);
            rec.el.style.top = rec.top + 'px';
            rect = bubbleRect(rec);
            hit = true;
            break;
          }
        }
      }
      if (rec.top > stageH - 12) {
        rec.top = stageH - 12;
        rec.el.style.top = rec.top + 'px';
        rect = bubbleRect(rec);
      }
      placed.push(rect);
    }
  }

  function pruneBubbles() {
    for (var i = bubbleOrder.length - 1; i >= 0; i--) {
      var key = bubbleOrder[i];
      var rec = bubbleMap[key];
      if (!rec || nowMs > rec.until) removeBubble(key);
    }
  }

  function clearBubbles() {
    var keys = bubbleOrder.slice();
    for (var i = 0; i < keys.length; i++) removeBubble(keys[i]);
  }

  function getOcclusionRects() {
    var out = [];
    for (var i = 0; i < bubbleOrder.length; i++) {
      var rec = bubbleMap[bubbleOrder[i]];
      if (rec && rec.el && rec.el.style.visibility !== 'hidden' && rec.w) out.push(bubbleRect(rec));
    }
    return out;
  }

  // ---------- 故事 ----------

  function snap(a) {
    a.sx = a.root.position.x;
    a.sy = a.root.position.y;
    a.sz = a.root.position.z;
    a.srx = a.root.rotation.x;
    a.sry = a.root.rotation.y;
    a.srz = a.root.rotation.z;
    a.sHeadX = a.head ? a.head.rotation.x : 0;
    a.sEarLZ = a.earL ? a.earL.rotation.z : 0;
    a.sEarRZ = a.earR ? a.earR.rotation.z : 0;
    a.sTailY = a.tail ? a.tail.rotation.y : 0;
    a.sLegs = null;
    if (a.legs) {
      a.sLegs = [];
      for (var li = 0; li < a.legs.length; li++) a.sLegs.push(a.legs[li].rotation.x);
    }
  }

  function restoreAgent(a) {
    a.root.position.set(a.sx, a.sy, a.sz);
    a.root.rotation.set(a.srx, a.sry, a.srz);
    if (a.head) a.head.rotation.x = a.sHeadX;
    if (a.earL) a.earL.rotation.z = a.sEarLZ;
    if (a.earR) a.earR.rotation.z = a.sEarRZ;
    if (a.tail) a.tail.rotation.y = a.sTailY;
    if (a.legs && a.sLegs) {
      for (var lr = 0; lr < a.legs.length; lr++) a.legs[lr].rotation.x = a.sLegs[lr];
    }
  }

  function releaseResources(s) {
    recomputeEnvironment();
  }

  function startStory(kind, opts) {
    opts = opts || {};
    if (!ready) return false;
    if (story) cancelStory();
    var def = STORIES[kind];
    if (!def) return false;
    if (def.grainLock && host.getGrainState().active) return false;

    var a = agentFor(def.agent, opts.root);
    if (!a) return false;

    var s = {
      kind: kind,
      def: def,
      t: 0,
      dur: opts.short ? (CLICK_DUR[kind] || Math.min(def.dur, 2.4)) : def.dur,
      agents: [a],
      bubbles: opts.short ? [] : (def.bubbles ? def.bubbles.slice() : (def.bubble ? [{ at: 0.2, who: 'agent', zh: def.bubble.zh, en: def.bubble.en }] : [])),
      sent: [],
      rabbit: a.id === 'rabbit',
      stableHorse: !!(a.root && a.root.userData && a.root.userData.stableHorse),
      heldActors: def.actor ? [def.actor] : [],
      farmer: null,
      chicken: null,
      opt: opts
    };

    if (def.farmer) {
      var f = agentFor('farmer', null);
      if (f) {
        s.farmer = f;
        s.agents.push(f);
        s.heldActors.push('farmer');
        // 目标点在故事开始时固定，避免农夫转头后目标点跟着漂移
        s.reportTx = f.root.position.x + Math.sin(f.root.rotation.y) * 1.6;
        s.reportTz = f.root.position.z + Math.cos(f.root.rotation.y) * 1.6;
      }
    }
    if (def.chicken) {
      var c = agentFor('chicken', null);
      if (c) {
        s.chicken = c;
        s.agents.push(c);
      }
    }

    s.coopBirds = false;
    for (var ci = 0; ci < s.agents.length; ci++) {
      var cr = s.agents[ci].root;
      if (cr && cr.userData && cr.userData.coopBird) { s.coopBirds = true; break; }
    }
    if (s.stableHorse && host.setHorseAuto) host.setHorseAuto(false);
    if (s.coopBirds && host.setCoopBirdsAuto) host.setCoopBirdsAuto(false);
    for (var i = 0; i < s.agents.length; i++) {
      var ag = s.agents[i];
      snap(ag);
      ag.cooldown = AGENT_COOLDOWN_MIN + rng() * (AGENT_COOLDOWN_MAX - AGENT_COOLDOWN_MIN);
    }
    if (s.rabbit) host.setRabbitAuto(false);
    if (s.farmer) host.holdActor('farmer', true);
    if (def.actor) host.holdActor(def.actor, true);
    if (s.chicken) {
      // 鸡跟着奶奶一起啄食，不再单独移动
      s.chicken.root.rotation.x = s.chicken.srx;
    }

    story = s;
    return true;
  }

  function cancelStory() {
    if (!story) return;
    var s = story;
    story = null;
    for (var i = 0; i < s.agents.length; i++) restoreAgent(s.agents[i]);
    releaseResources(s);
  }

  function finishStory() {
    if (!story) return;
    var s = story;
    cancelStory();
    tickTimer = STORY_GAP + rng() * 4;
    if (s.kind !== 'rooster_crow') lastFinish = s.kind;
  }

  var lastFinish = '';

  function emitStoryBubbles(prevT) {
    var s = story;
    if (!s) return;
    for (var i = 0; i < s.bubbles.length; i++) {
      if (s.sent[i]) continue;
      var b = s.bubbles[i];
      if (s.t < b.at) continue;
      s.sent[i] = true;
      var who = b.who === 'farmer' && s.farmer ? s.farmer : s.agents[0];
      if (!who) continue;
      showBubble('story:' + s.kind + ':' + i, who, b.zh, b.en);
    }
  }

  function poseRabbit(a, t) {
    a.root.position.y = a.sy + Math.abs(Math.sin(t * 7.4)) * 0.28;
    a.root.rotation.z = Math.sin(t * 7.4) * 0.05;
    if (a.earL) a.earL.rotation.z = 0.12 + Math.sin(t * 9) * 0.18;
    if (a.earR) a.earR.rotation.z = -0.12 - Math.sin(t * 9 + 0.5) * 0.18;
  }

  function poseRabbitReport(a, t) {
    var f = story.farmer;
    var fx = f.root.position.x;
    var fz = f.root.position.z;
    var tx = story.reportTx;
    var tz = story.reportTz;
    var k = easeInOut(Math.min(1, t / 1.25));
    a.root.position.x = a.sx + (tx - a.sx) * k;
    a.root.position.z = a.sz + (tz - a.sz) * k;
    a.root.position.y = a.sy + Math.sin(Math.PI * k) * 0.55 + (k >= 1 ? Math.abs(Math.sin(t * 8)) * 0.07 : 0);
    a.root.rotation.y = Math.atan2(fx - a.root.position.x, fz - a.root.position.z);
    if (a.earL) a.earL.rotation.z = 0.12 + Math.sin(t * 8) * 0.14;
    if (a.earR) a.earR.rotation.z = -0.12 - Math.sin(t * 8 + 0.4) * 0.14;
    f.root.rotation.y = Math.atan2(a.root.position.x - fx, a.root.position.z - fz);
    f.root.rotation.x = f.srx + Math.max(0, Math.sin(t * 2.4)) * 0.07;
  }

  function poseGraze(a, t, target, sway) {
    if (a.head) a.head.rotation.x = a.sHeadX + target * (0.72 + 0.28 * Math.sin(t * 1.4));
    a.root.rotation.z = a.srz + Math.sin(t * 0.9) * sway;
  }

  function poseHorseRun(a, t) {
    // 一圈正好在故事时长内跑完，结束时回到起点，不会瞬移
    var ang = (Math.PI * 2 / 5.2) * t;
    a.root.position.x = a.sx + Math.cos(ang) * 3.4 - 3.4;
    a.root.position.z = a.sz + Math.sin(ang) * 3.4;
    a.root.position.y = a.sy + Math.abs(Math.sin(t * 8)) * 0.18;
    a.root.rotation.y = -ang;
    if (a.tail) a.tail.rotation.z = Math.sin(t * 7) * 0.4;
    if (a.legs) {
      var gallop = t * 9.5;
      a.legs[0].rotation.x = Math.sin(gallop) * 0.55;
      a.legs[1].rotation.x = Math.sin(gallop + Math.PI) * 0.55;
      a.legs[2].rotation.x = Math.sin(gallop + Math.PI) * 0.45;
      a.legs[3].rotation.x = Math.sin(gallop) * 0.45;
    }
  }

  function poseWallow(a, t) {
    a.root.position.y = a.sy - 0.12 + Math.abs(Math.sin(t * 4)) * 0.06;
    a.root.rotation.z = a.srz + Math.sin(t * 2.4) * 0.38;
    if (a.head) a.head.rotation.x = a.sHeadX + 0.1 + Math.sin(t * 3.2) * 0.12;
    if (a.tail) a.tail.rotation.z = Math.sin(t * 3.4) * 0.2;
  }

  function posePeck(a, t, speed) {
    a.root.rotation.x = a.srx + 0.28 + 0.22 * Math.abs(Math.sin(t * speed));
    a.root.position.y = a.sy + Math.abs(Math.sin(t * speed * 1.2)) * 0.03;
  }

  function poseCrow(a, t) {
    a.root.rotation.x = a.srx - 0.18;
    a.root.position.y = a.sy + 0.08 + Math.abs(Math.sin(t * 6)) * 0.05;
    a.root.rotation.y = a.sry + Math.sin(t * 3) * 0.12;
  }

  function poseSwim(a, t, centerX, centerZ, radius, dur) {
    var dx = a.sx - centerX;
    var dz = a.sz - centerZ;
    var d0 = Math.sqrt(dx * dx + dz * dz);
    var ang0 = Math.atan2(dz, dx);
    var k = Math.min(1, t / dur);
    var ang = ang0 + (Math.PI * 2 / dur) * t;
    // 半径呈钟形：开头从当前位置缓缓游进圈，结尾再游回起点，避免瞬移
    var r = d0 + (radius - d0) * Math.sin(Math.PI * k);
    a.root.position.x = centerX + Math.cos(ang) * r;
    a.root.position.z = centerZ + Math.sin(ang) * r;
    a.root.position.y = a.sy;
    a.root.rotation.y = Math.atan2(-Math.sin(ang), Math.cos(ang));
    a.root.rotation.z = a.srz + Math.sin(t * 1.5) * 0.05;
  }

  function poseDive(a, t, k) {
    var s = Math.sin(Math.PI * k);
    a.root.position.y = a.sy - 0.22 * s;
    a.root.rotation.x = a.srx + 0.5 * s;
  }

  function poseStretch(a, t, k) {
    var s = Math.sin(Math.PI * k);
    a.root.rotation.x = a.srx - 0.10 * s;
    a.root.position.y = a.sy + 0.06 * s;
    if (a.tail) a.tail.rotation.y = a.sTailY + 0.4 * s;
    if (a.earL) a.earL.rotation.z = a.sEarLZ - 0.08 * s;
    if (a.earR) a.earR.rotation.z = a.sEarRZ + 0.08 * s;
  }

  function poseBark(a, t) {
    a.root.rotation.x = a.srx - 0.12 * Math.abs(Math.sin(t * 7));
    a.root.position.y = a.sy + Math.abs(Math.sin(t * 5)) * 0.04;
    if (a.earL) a.earL.rotation.z = a.sEarLZ - 0.1 * Math.abs(Math.sin(t * 6));
    if (a.earR) a.earR.rotation.z = a.sEarRZ + 0.1 * Math.abs(Math.sin(t * 6));
  }

  function poseBird(a, t) {
    a.root.position.y = a.sy + Math.abs(Math.sin(t * 10)) * 0.18;
    a.root.rotation.y = a.sry + Math.sin(t * 6) * 0.2;
  }

  function poseGrandma(a, t, k) {
    a.root.rotation.x = a.srx + 0.12 * Math.sin(Math.PI * Math.min(1, k));
    a.root.rotation.z = a.srz + Math.sin(t * 1.2) * 0.03;
  }

  function poseWave(a, t, k) {
    a.root.rotation.x = a.srx + 0.06 * Math.sin(Math.PI * Math.min(1, k));
    a.root.position.y = a.sy + Math.abs(Math.sin(t * 2.4)) * 0.03;
  }

  function poseChild(a, t) {
    a.root.position.y = a.sy + Math.abs(Math.sin(t * 5)) * 0.18;
    a.root.rotation.y = a.sry + Math.sin(t * 2) * 0.4;
  }

  function updateStory(dt, t) {
    var s = story;
    if (!s) return;
    s.t += dt;
    var a = s.agents[0];
    var k = clamp(s.t / s.dur, 0, 1);
    switch (s.kind) {
      case 'rabbit_hop': poseRabbit(a, s.t); break;
      case 'rabbit_report': poseRabbitReport(a, s.t); break;
      case 'cow_graze': poseGraze(a, s.t, 0.55, 0.02); break;
      case 'sheep_graze': poseGraze(a, s.t, 0.5, 0.018); break;
      case 'goat_graze': poseGraze(a, s.t, 0.55, 0.02); break;
      case 'horse_run': poseHorseRun(a, s.t); break;
      case 'pig_wallow': poseWallow(a, s.t); break;
      case 'chicken_peck': posePeck(a, s.t, 9); break;
      case 'rooster_crow': poseCrow(a, s.t); break;
      case 'duck_swim': poseSwim(a, s.t, 38, 26, 2.0, s.dur); break;
      case 'goose_swim': poseSwim(a, s.t, 33, 28, 1.6, s.dur); break;
      case 'cat_stretch': poseStretch(a, s.t, k); break;
      case 'dog_bark': poseBark(a, s.t); break;
      case 'bird_chirp': poseBird(a, s.t); break;
      case 'bee_hover': break;
      case 'grandma_feed':
        poseGrandma(a, s.t, k);
        if (s.chicken) posePeck(s.chicken, s.t, 8);
        break;
      case 'farmer_wave': poseWave(a, s.t, k); break;
      case 'child_play': poseChild(a, s.t); break;
      default: break;
    }
    emitStoryBubbles();
    if (s.t >= s.dur) finishStory();
  }

  // ---------- 夜间睡姿 ----------

  function applyNightPose(a, s, t) {
    if (!a || !a.root) return;
    var kind = a.idle && a.idle.kind ? a.idle.kind : a.id;
    if (kind === 'rabbit' || kind === 'rabbit_graze') {
      if (a.head) a.head.rotation.x = a.baseHeadX - 0.28 * s;
      if (a.earL) a.earL.rotation.z = 0.12 + 0.5 * s;
      if (a.earR) a.earR.rotation.z = -0.12 - 0.5 * s;
      a.root.position.y = a.basePos.y - 0.06 * s + Math.sin(t * 0.8) * 0.015 * s;
      a.root.rotation.z = a.baseRot.z + 0.3 * s;
    } else if (kind === 'cow' || kind === 'sheep' || kind === 'horse' || kind === 'goat') {
      if (a.head) a.head.rotation.x = a.baseHeadX + 0.4 * s;
      a.root.position.y = a.basePos.y - 0.22 * s;
      a.root.rotation.z = a.baseRot.z + 0.06 * s;
    } else if (kind === 'pig') {
      if (a.head) a.head.rotation.x = a.baseHeadX + 0.2 * s;
      a.root.position.y = a.basePos.y - 0.3 * s;
      a.root.rotation.z = a.baseRot.z + 1.05 * s;
    } else if (kind === 'chicken' || kind === 'rooster' || kind === 'duck' || kind === 'goose') {
      a.root.position.y = a.basePos.y - 0.1 * s;
      a.root.rotation.x = a.baseRot.x + 0.08 * s;
    } else if (kind === 'cat' || kind === 'lazy_cat') {
      if (a.head) a.head.rotation.x = a.baseHeadX + 0.22 * s;
      a.root.position.y = a.basePos.y - 0.05 * s;
    } else if (kind === 'dog' || kind === 'grandma' || kind === 'farmer' || kind === 'child' || kind === 'walk') {
      a.root.rotation.x = a.baseRot.x + 0.08 * s;
      a.root.position.y = Math.max(0.02, a.basePos.y - 0.05 * s);
    } else if (kind === 'bee' || kind === 'bird') {
      a.root.visible = s < 0.5;
    }
  }

  function applySleep(s, t) {
    for (var i = 0; i < sleepList.length; i++) applyNightPose(sleepList[i], s, t);
    wasAsleep = true;
  }

  function restoreFromSleep() {
    for (var i = 0; i < sleepList.length; i++) {
      var a = sleepList[i];
      if (!a) continue;
      if (a.head) a.head.rotation.x = a.baseHeadX;
      if (a.earL) a.earL.rotation.z = a.baseEarLZ;
      if (a.earR) a.earR.rotation.z = a.baseEarRZ;
      a.root.rotation.x = a.baseRot.x;
      a.root.rotation.z = a.baseRot.z;
      a.root.visible = true;
      if (!a.actorId) a.root.position.y = a.basePos.y;
    }
    wasAsleep = false;
  }

  // ---------- 雨天环境 ----------

  function recomputeEnvironment() {
    var held = nightOn || rainOn;
    if (host.setHorseAuto) host.setHorseAuto(!nightOn && !rainOn);
    if (host.setRabbitAuto) host.setRabbitAuto(!nightOn && !rainOn);
    if (host.setCoopBirdsAuto) host.setCoopBirdsAuto(!nightOn && !rainOn);
    host.holdActor('farmer', held);
    host.holdActor('child', held);
    host.holdActor('dog', held);
  }

  function rainKind(a) {
    if (!a) return '';
    if (a.idle && a.idle.kind) return a.idle.kind;
    return a.id || '';
  }

  function applyRainPose(k, t) {
    for (var i = 0; i < sleepList.length; i++) {
      var a = sleepList[i];
      if (!a || !a.root) continue;
      var kind = rainKind(a);
      if (kind === 'chicken' || kind === 'rooster' || kind === 'duck' || kind === 'goose') continue;
      if (kind === 'bee' || kind === 'bird') {
        a.root.visible = k < 0.5;
        continue;
      }
      var phase = (a.idle && a.idle.phase) ? a.idle.phase : 0;
      if (kind === 'cow' || kind === 'sheep' || kind === 'horse' || kind === 'goat') {
        if (a.head) a.head.rotation.x = a.baseHeadX + 0.3 * k;
        a.root.position.y = a.basePos.y - 0.03 * k;
        a.root.rotation.z = a.baseRot.z + Math.sin(t * 6 + phase) * 0.01 * k;
      } else if (kind === 'pig') {
        if (a.head) a.head.rotation.x = a.baseHeadX + 0.22 * k;
      } else if (kind === 'cat' || kind === 'lazy_cat') {
        if (a.head) a.head.rotation.x = a.baseHeadX + 0.2 * k;
      } else if (kind === 'rabbit' || kind === 'rabbit_graze') {
        if (a.head) a.head.rotation.x = a.baseHeadX + 0.2 * k;
        if (a.earL) a.earL.rotation.z = 0.12 + (0.3 + 0.2 * k);
        if (a.earR) a.earR.rotation.z = -0.12 - (0.3 + 0.2 * k);
      } else if (kind === 'dog' || kind === 'farmer' || kind === 'child' || kind === 'grandma' ||
        kind === 'walk') {
        a.root.rotation.x = a.baseRot.x + 0.05 * k;
        a.root.position.y = Math.max(0.02, a.basePos.y - 0.02 * k);
      }
    }
  }

  function restoreRainPose() {
    for (var i = 0; i < sleepList.length; i++) {
      var a = sleepList[i];
      if (!a) continue;
      if (a.head) a.head.rotation.x = a.baseHeadX;
      if (a.earL) a.earL.rotation.z = a.baseEarLZ;
      if (a.earR) a.earR.rotation.z = a.baseEarRZ;
      a.root.rotation.x = a.baseRot.x;
      a.root.rotation.z = a.baseRot.z;
      a.root.visible = true;
      if (!a.actorId) a.root.position.y = a.basePos.y;
    }
  }

  // ---------- 调度 ----------

  function agentOnScreen(a) {
    if (!a || !a.root || !host || !host.project || !tmpWorld) return true;
    var w = (host.canvas && host.canvas.clientWidth) || 0;
    var h = (host.canvas && host.canvas.clientHeight) || 0;
    if (!w || !h) return true;
    a.root.getWorldPosition(tmpWorld);
    var p = host.project(tmpWorld.x, tmpWorld.y + a.anchorY, tmpWorld.z);
    if (!p.visible) return false;
    return p.x > 20 && p.x < w - 20 && p.y > 40 && p.y < h - 20;
  }

  function storyAvailable(kind) {
    var def = STORIES[kind];
    if (!def) return false;
    if (def.manual) return false;
    if (rainOn && (kind === 'chicken_peck' || kind === 'grandma_feed' || kind === 'rooster_crow')) {
      return false;
    }
    if (def.grainLock && host.getGrainState().active) return false;
    var a = agents[def.agent];
    if (!a) return false;
    if (a.cooldown > 0) return false;
    if (!agentOnScreen(a)) return false;
    if (host.getTime() - (a.repeat[kind] || -999) < STORY_REPEAT_LOCK) return false;
    if (def.farmer && !agents.farmer) return false;
    if (def.chicken && !agents.chicken) return false;
    return true;
  }

  function pickScheduled(kindList) {
    var best = null;
    var bestScore = -1;
    for (var i = 0; i < kindList.length; i++) {
      var kind = kindList[i];
      if (!storyAvailable(kind)) continue;
      var def = STORIES[kind];
      var score = rng();
      if (def.zone === lastZone) score += 1.5;
      if (lastFinish && STORIES[lastFinish] && STORIES[lastFinish].agent === def.agent) score -= 0.4;
      if (score > bestScore) { bestScore = score; best = kind; }
    }
    return best;
  }

  function startScheduled(kind) {
    if (!kind) return false;
    var ok = startStory(kind, {});
    if (ok) {
      var def = STORIES[kind];
      var a = agents[def.agent];
      if (a) a.repeat[kind] = host.getTime();
      tickTimer = TICK_MIN + rng() * (TICK_MAX - TICK_MIN);
    }
    return ok;
  }

  function tick(realDt) {
    if (!ready) return;
    nowMs = Date.now();
    for (var i = 0; i < agentOrder.length; i++) {
      if (agentOrder[i].cooldown > 0) agentOrder[i].cooldown = Math.max(0, agentOrder[i].cooldown - realDt);
    }
    if (zoneTimer > 0) {
      zoneTimer -= realDt;
      if (zoneTimer <= 0 && !nightOn && !rainOn && !host.isReduceMotion()) {
        if (story) {
          // 正在跑别的故事（例如点击互动），稍后再补一次分区故事
          zoneTimer = 2;
        } else {
          var list = ZONE_STORIES[lastZone];
          if (list && list.length && !startScheduled(pickScheduled(list))) zoneTimer = 2;
        }
      }
    }
    if (nightOn || rainOn || host.isReduceMotion()) return;
    if (story) return;
    if (tickTimer > 0) {
      tickTimer -= realDt;
      return;
    }
    if (host.getGrainState().active) {
      tickTimer = 4;
      return;
    }
    var all = [];
    for (var k in STORIES) {
      if (STORIES.hasOwnProperty(k)) all.push(k);
    }
    if (!startScheduled(pickScheduled(all))) tickTimer = 4;
  }

  // ---------- 对外 API ----------

  var A = global.FarmAgents || (global.FarmAgents = {});

  A.init = function (h) {
    host = h;
    if (!tmpWorld) tmpWorld = new h.THREE.Vector3();
    // 补全 id → zone 映射（farm-data 的 objects 数组）
    D.objectsById = {};
    for (var i = 0; i < D.objects.length; i++) D.objectsById[D.objects[i].id] = D.objects[i];
    buildAgents();
    ready = true;
  };

  A.isReady = function () { return !!ready; };

  // 调试用：调度器内部状态（无头验证 / 真机排查时读取）
  A.debugState = function () {
    var list = [];
    for (var i = 0; i < agentOrder.length; i++) {
      var a = agentOrder[i];
      list.push(a.id + ':' + (agentOnScreen(a) ? 'on' : 'off') + ':' + Math.round(a.cooldown));
    }
    return {
      t: host ? Math.round(host.getTime() * 10) / 10 : -1,
      tick: Math.round(tickTimer * 10) / 10,
      zone: lastZone,
      zoneT: Math.round(zoneTimer * 10) / 10,
      story: story ? story.kind : '',
      bubbles: bubbleOrder.length,
      grain: host ? host.getGrainState() : null,
      ui: !!ui,
      agents: list.join(' ')
    };
  };

  A.attachUI = function (opts) {
    ui = opts || null;
    if (ui && ui.layer && ui.stage) {
      ui.layer.innerHTML = '';
      bubbleMap = {};
      bubbleOrder = [];
      positionBubbles();
    }
  };

  A.isAgent = function (id) { return !!CLICK_KIND[id]; };
  A.isRaining = function () { return rainOn; };
  A.isStoryActive = function () { return !!story; };

  A.update = function (realDt, motionDt, t) {
    if (!ready || !host) return;
    tick(realDt);

    if (nightOn && sleepK !== 1) {
      sleepK = Math.min(1, sleepK + realDt / 1.2);
      applySleep(sleepK, t);
    } else if (nightOn) {
      applySleep(1, t);
    } else if (sleepK > 0) {
      sleepK = Math.max(0, sleepK - realDt / 0.8);
      if (sleepK <= 0) restoreFromSleep();
      else applySleep(sleepK, t);
    }

    var wantRain = rainOn && !nightOn;
    if (wantRain) rainK = Math.min(1, rainK + realDt / 0.8);
    else rainK = Math.max(0, rainK - realDt / 0.8);
    if (rainK > 0 && !nightOn) {
      applyRainPose(rainK, t);
      wasRainPose = true;
    } else if (wasRainPose && !nightOn) {
      restoreRainPose();
      wasRainPose = false;
    }

    // 故事姿势在睡姿之后写入，保证夜间点击动物时能“醒一下”做反应
    if (motionDt > 0) updateStory(motionDt, t);
  };

  A.frame = function (now) {
    nowMs = now || Date.now();
    pruneBubbles();
    if (!ui) return;
    if (nowMs - lastProject < PROJECT_INTERVAL) return;
    lastProject = nowMs;
    positionBubbles();
  };

  A.interact = function (id, root) {
    if (!ready) return false;
    if ((rainOn || nightOn) &&
      (id === 'farmer' || id === 'child' || id === 'dog' || id === 'cat' || id === 'grandma' ||
        id === 'horse' || id === 'sheep' || id === 'goat')) {
      var homeAgent = agentFor(id, root) || agents[id];
      if (homeAgent) {
        var homeLine;
        if (id === 'horse') {
          homeLine = rainOn
            ? { zh: '下雨啦，我回马厩啦。', en: 'Rain! Back to the stable.' }
            : { zh: '天黑啦，我回马厩睡觉。', en: 'It is dark. Back to the stable.' };
        } else if (id === 'sheep' || id === 'goat') {
          homeLine = { zh: '我们要进羊圈啦。', en: 'We are going into the pen.' };
        } else {
          homeLine = rainOn
            ? { zh: '下雨啦，我们回农舍啦。', en: 'Rain! We are going home.' }
            : { zh: '天黑啦，我们回农舍睡觉。', en: 'It is dark. We are going home.' };
        }
        showBubble('click:' + id, homeAgent, homeLine.zh, homeLine.en, 2600);
      }
      return true;
    }
    if (id === 'chicken' || id === 'rooster' || id === 'grandma') {
      if (rainOn) {
        var shelterAgent = agentFor(id, root) || agents.chicken || agents.rooster;
        if (shelterAgent) {
          showBubble('click:' + id, shelterAgent, '我在躲雨呢。', 'I am hiding from the rain.', 2600);
        }
        return true;
      }
      if (nightOn) return false;
    }
    var kind = CLICK_KIND[id];
    if (!kind) return false;
    var a = agentFor(id, root);
    if (!a) return false;
    var def = STORIES[kind];
    var line = def && def.bubble ? def.bubble : NIGHT_LINE;
    removeBubble('night');
    showBubble('click:' + id, a, line.zh, line.en);
    if (host.isReduceMotion()) return true;
    startStory(kind, { short: true, root: root });
    return true;
  };

  A.trigger = function (kind) {
    if (!ready) return false;
    if (host.isReduceMotion()) return false;
    return startStory(kind, {});
  };

  A.onZoneChange = function (name) {
    if (!ready) return;
    if (name === lastZone) return;
    lastZone = name;
    zoneTimer = name === 'overview' ? -1 : ZONE_STORY_DELAY;
    if (!story || story.opt.click) return;
    // 镜头切走后，正在跑的定时故事不再暂停资源，直接收尾
    cancelStory();
  };

  A.onNightChange = function (on) {
    if (!ready) return;
    on = !!on;
    if (on === nightOn) return;
    nightOn = on;
    cancelStory();
    recomputeEnvironment();
    if (on) {
      var rabbit = agents.rabbit;
      if (rabbit) {
        rabbit.root.position.set(rabbit.basePos.x, rabbit.basePos.y, rabbit.basePos.z);
        rabbit.root.rotation.y = rabbit.baseRot.y;
        if (rabbit.head) rabbit.head.rotation.x = rabbit.baseHeadX;
      }
      var anchor = agents.cat || agents.chicken || agents.rabbit;
      if (anchor) {
        showBubble('night', anchor, '天黑啦，大家都回农舍啦。', 'It is dark. Everyone is going home.', 5200);
        if (bubbleMap.night) bubbleMap.night.preferVisible = true;
      }
    } else {
      restoreFromSleep();
      sleepK = 0;
      tickTimer = TICK_MIN * 0.6;
    }
  };

  A.onWeatherChange = function (on) {
    if (!ready) return;
    on = !!on;
    if (on === rainOn) return;
    rainOn = on;
    cancelStory();
    recomputeEnvironment();
    var anchor = agents.cat || agents.chicken || agents.rabbit;
    if (anchor) {
      if (on) {
        showBubble('weather', anchor, '下雨啦，大家都回农舍啦。',
          'It is raining. Everyone is going home.', 5200);
      } else {
        showBubble('weather', anchor, nightOn ? '雨停啦。' : '雨停啦，太阳出来喽。',
          'The rain stopped.', 4200);
      }
    }
  };

  A.getOcclusionRects = function () { return getOcclusionRects(); };

  A.clearBubbles = clearBubbles;

  A.dispose = function () {
    cancelStory();
    clearBubbles();
    if (ui && ui.layer) ui.layer.innerHTML = '';
    bubbleMap = {};
    bubbleOrder = [];
    if (host && host.built) {
      host.holdActor('farmer', false);
      host.holdActor('child', false);
      host.holdActor('dog', false);
      host.setRabbitAuto(true);
      if (host.setHorseAuto) host.setHorseAuto(true);
      if (host.setCoopBirdsAuto) host.setCoopBirdsAuto(true);
    }
    ready = false;
    ui = null;
    host = null;
    story = null;
    sleepK = 0;
    nightOn = false;
    wasAsleep = false;
    rainOn = false;
    rainK = 0;
    wasRainPose = false;
  };
})(window);
