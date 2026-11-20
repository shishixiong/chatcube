(function (global) {
  'use strict';

  var doc = global.document;
  var S = global.AirportScene;
  var DATA = global.AirportData || { objects: [], byId: {} };
  var TOTAL = DATA.objects.length;

  var CATEGORY_LABEL = {
    places: '地点',
    aircraft: '飞机',
    vehicles: '车辆',
    people: '人物',
    facilities: '设施'
  };
  var ZONE_LABEL = {
    overview: '全机场',
    terminal_zone: '航站楼',
    apron_zone: '停机坪',
    runway_zone: '跑道',
    hangar_zone: '机库维修'
  };
  var STORAGE_KEY = 'airport.discovered.v1';

  var booted = false;
  var sceneReady = false;
  var selectedId = null;
  var labelsOn = false;
  var discovered = {};
  var pointerStart = null;

  function $(id) { return doc.getElementById(id); }

  function bridgeCall(name, args) {
    var b = global.AirportNativeBridge;
    if (b && typeof b[name] === 'function') {
      try { return b[name].apply(b, args || []); } catch (e) { /* ignore */ }
    }
    return null;
  }

  // ---------------- persistence ----------------

  function loadDiscovered() {
    try {
      var raw = global.localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      var arr = JSON.parse(raw);
      if (Array.isArray(arr)) {
        for (var i = 0; i < arr.length; i++) {
          if (typeof arr[i] === 'string') discovered[arr[i]] = true;
        }
      }
    } catch (e) { /* ignore */ }
  }

  function saveDiscovered() {
    var ids = [];
    for (var id in discovered) if (discovered[id]) ids.push(id);
    try { global.localStorage.setItem(STORAGE_KEY, JSON.stringify(ids)); } catch (e) { /* ignore */ }
    return ids;
  }

  function discoveredIds() {
    var ids = [];
    for (var i = 0; i < DATA.objects.length; i++) {
      if (discovered[DATA.objects[i].id]) ids.push(DATA.objects[i].id);
    }
    return ids;
  }

  // ---------------- UI ----------------

  function setLoadProgress(done, total) {
    var bar = $('loadBar');
    var text = $('loadText');
    if (bar) bar.style.width = (total > 0 ? Math.round(done / total * 100) : 0) + '%';
    if (text) text.textContent = done >= total ? '准备起飞…' : ('正在装配机场… ' + done + ' / ' + total);
  }

  function showFail(reason) {
    var load = $('loadScreen');
    var fail = $('failCard');
    if (load) load.classList.add('done');
    if (fail) fail.hidden = false;
    var why = $('failReason');
    if (why) why.textContent = reason || 'unknown';
    bridgeCall('onError', [reason || 'unknown']);
  }

  function hideLoad() {
    var load = $('loadScreen');
    if (load) load.classList.add('done');
    var fail = $('failCard');
    if (fail) fail.hidden = true;
  }

  function buildZoneTabs() {
    var host = $('zoneTabs');
    if (!host) return;
    var zones = ['overview', 'terminal_zone', 'apron_zone', 'runway_zone', 'hangar_zone'];
    for (var i = 0; i < zones.length; i++) {
      (function (zone) {
        var b = doc.createElement('button');
        b.className = 'zone-tab';
        b.type = 'button';
        b.setAttribute('role', 'tab');
        b.setAttribute('aria-selected', zone === 'overview' ? 'true' : 'false');
        b.textContent = ZONE_LABEL[zone];
        b.addEventListener('click', function () {
          setView(zone);
          var all = host.querySelectorAll('.zone-tab');
          for (var k = 0; k < all.length; k++) {
            all[k].setAttribute('aria-selected', all[k] === b ? 'true' : 'false');
          }
          var pz = $('panelZone');
          if (pz) pz.textContent = ZONE_LABEL[zone];
        });
        host.appendChild(b);
      })(zones[i]);
    }
  }

  function buildPassport() {
    var grid = $('passportGrid');
    if (!grid) return;
    grid.innerHTML = '';
    for (var i = 0; i < DATA.objects.length; i++) {
      var o = DATA.objects[i];
      var dot = doc.createElement('div');
      dot.className = 'passport-dot' + (discovered[o.id] ? ' got' : '');
      dot.title = o.word + ' ' + o.zh;
      dot.textContent = discovered[o.id] ? o.word.slice(0, 4) : '·';
      grid.appendChild(dot);
    }
  }

  function buildVocab() {
    var list = $('vocabList');
    if (!list) return;
    list.innerHTML = '';
    var cats = ['places', 'aircraft', 'vehicles', 'people', 'facilities'];
    for (var c = 0; c < cats.length; c++) {
      var cat = cats[c];
      var head = doc.createElement('div');
      head.className = 'vocab-group';
      head.textContent = CATEGORY_LABEL[cat] + ' · ' + cat;
      list.appendChild(head);
      for (var i = 0; i < DATA.objects.length; i++) {
        var o = DATA.objects[i];
        if (o.category !== cat) continue;
        (function (word) {
          var btn = doc.createElement('button');
          btn.className = 'vocab-item';
          btn.type = 'button';
          var strong = doc.createElement('strong');
          strong.textContent = word.word;
          var phon = doc.createElement('span');
          phon.textContent = word.phonetic;
          var zh = doc.createElement('span');
          zh.className = 'vocab-zh';
          zh.textContent = word.zh;
          btn.appendChild(strong);
          btn.appendChild(phon);
          btn.appendChild(zh);
          btn.addEventListener('click', function () {
            select(word.id);
            closeVocab();
          });
          list.appendChild(btn);
        })(o);
      }
    }
  }

  function updateCounts() {
    var n = discoveredIds().length;
    var panelCount = $('panelCount');
    if (panelCount) panelCount.textContent = n + ' / ' + TOTAL;
    var pass = $('passportCount');
    if (pass) pass.textContent = n + ' / ' + TOTAL;
    var meta = $('metaPill');
    if (meta) meta.textContent = '5 个区域 · ' + TOTAL + ' 个单词';
    var peek = $('panelPeek');
    if (peek && n > 0) peek.textContent = '已经收集 ' + n + ' 个单词，继续点一点机场吧。';
  }

  function expandPanel() {
    var panel = $('panel');
    if (panel) panel.setAttribute('data-state', 'expanded');
    var btn = $('panelToggle');
    if (btn) btn.setAttribute('aria-expanded', 'true');
  }

  function renderWordCard(o) {
    var card = $('wordCard');
    var empty = $('emptyState');
    if (!card) return;
    card.hidden = false;
    if (empty) empty.hidden = true;
    var idx = DATA.objects.indexOf(o);
    setText('cardCat', CATEGORY_LABEL[o.category] || o.category);
    setText('cardIndex', (idx + 1) + ' / ' + TOTAL);
    setText('cardWord', o.word);
    setText('cardPhon', o.phonetic);
    setText('cardZh', o.zh);
    setText('cardDef', o.kidDefinition);
    setText('cardExampleText', o.example);
  }

  function setText(id, text) {
    var el = $(id);
    if (el) el.textContent = text;
  }

  function markDiscovered(o) {
    if (!discovered[o.id]) {
      discovered[o.id] = true;
      saveDiscovered();
      buildPassport();
      updateCounts();
      bridgeCall('onProgress', [JSON.stringify(discoveredIds())]);
    }
  }

  function select(wordId) {
    var o = DATA.byId[wordId];
    if (!o) return;
    selectedId = wordId;
    renderWordCard(o);
    expandPanel();
    S.focusWord(wordId);
    markDiscovered(o);
    bridgeCall('onSelect', [o.id, o.word]);
    bridgeCall('speak', [o.word, o.zh]);
  }

  function speakCurrent() {
    var o = DATA.byId[selectedId];
    if (o) bridgeCall('speak', [o.word, o.zh]);
  }

  function speakExample() {
    var o = DATA.byId[selectedId];
    if (o) bridgeCall('speak', [o.example, '']);
  }

  function stepWord(delta) {
    var idx = -1;
    for (var i = 0; i < DATA.objects.length; i++) {
      if (DATA.objects[i].id === selectedId) { idx = i; break; }
    }
    if (idx < 0) idx = 0;
    var next = (idx + delta + DATA.objects.length) % DATA.objects.length;
    select(DATA.objects[next].id);
  }

  function closeCard() {
    selectedId = null;
    var card = $('wordCard');
    var empty = $('emptyState');
    if (card) card.hidden = true;
    if (empty) empty.hidden = false;
  }

  function togglePanel() {
    var panel = $('panel');
    if (!panel) return;
    var expanded = panel.getAttribute('data-state') === 'expanded';
    panel.setAttribute('data-state', expanded ? 'collapsed' : 'expanded');
    var btn = $('panelToggle');
    if (btn) btn.setAttribute('aria-expanded', expanded ? 'false' : 'true');
  }

  function openVocab() {
    expandPanel();
    var v = $('vocabPanel');
    if (v) {
      v.hidden = false;
      try { v.scrollIntoView({ block: 'nearest' }); } catch (e) { /* ignore */ }
    }
  }

  function closeVocab() {
    var v = $('vocabPanel');
    if (v) v.hidden = true;
  }

  // ---------------- input ----------------

  function wirePointer() {
    var canvas = $('stageCanvas');
    if (!canvas) return;
    canvas.addEventListener('pointerdown', function (e) {
      pointerStart = { x: e.clientX, y: e.clientY, t: Date.now() };
    });
    canvas.addEventListener('pointerup', function (e) {
      if (!pointerStart) return;
      var dx = e.clientX - pointerStart.x;
      var dy = e.clientY - pointerStart.y;
      var moved = Math.sqrt(dx * dx + dy * dy);
      var dt = Date.now() - pointerStart.t;
      pointerStart = null;
      if (moved > 8 || dt > 900) return;
      var wordId = S.pick(e.clientX, e.clientY);
      if (wordId) select(wordId);
      else toast('这里没有单词，换一个地方点点看');
    });
  }

  var toastTimer = 0;
  function toast(text) {
    var el = $('sceneToast');
    if (!el) return;
    el.textContent = text;
    el.classList.add('show');
    if (toastTimer) global.clearTimeout(toastTimer);
    toastTimer = global.setTimeout(function () { el.classList.remove('show'); }, 1600);
  }

  function wireUi() {
    var failVocab = $('failVocabBtn');
    if (failVocab) failVocab.addEventListener('click', openVocab);
    var retry = $('failRetryBtn');
    if (retry) retry.addEventListener('click', function () { global.location.reload(); });

    var panelGrab = $('panelGrab');
    if (panelGrab) panelGrab.addEventListener('click', togglePanel);
    var panelToggle = $('panelToggle');
    if (panelToggle) panelToggle.addEventListener('click', togglePanel);

    var labels = $('labelsBtn');
    if (labels) labels.addEventListener('click', function () {
      labelsOn = !labelsOn;
      labels.setAttribute('aria-pressed', labelsOn ? 'true' : 'false');
      S.setLabels(labelsOn);
    });

    var vocab = $('vocabBtn');
    if (vocab) vocab.addEventListener('click', openVocab);
    var vocabClose = $('vocabClose');
    if (vocabClose) vocabClose.addEventListener('click', closeVocab);

    var speak = $('cardSpeak');
    if (speak) speak.addEventListener('click', speakCurrent);
    var example = $('cardExample');
    if (example) example.addEventListener('click', speakExample);
    var close = $('cardClose');
    if (close) close.addEventListener('click', closeCard);
    var prev = $('cardPrev');
    if (prev) prev.addEventListener('click', function () { stepWord(-1); });
    var next = $('cardNext');
    if (next) next.addEventListener('click', function () { stepWord(1); });

    var reset = $('resetBtn');
    if (reset) reset.addEventListener('click', function () { S.setView('overview'); });
  }

  // ---------------- boot ----------------

  function boot() {
    if (booted) return;
    booted = true;
    loadDiscovered();
    buildZoneTabs();
    buildPassport();
    buildVocab();
    updateCounts();
    wirePointer();
    wireUi();

    try {
      S.init();
    } catch (e) {
      showFail('webgl: ' + (e && e.message ? e.message : e));
      return;
    }

    S.loadAll(setLoadProgress, function onReady() {
      sceneReady = true;
      try {
        S.buildWorld();
        S.start();
      } catch (e) {
        console.error('AirportApp buildWorld failed', e);
        showFail('world: ' + ((e && e.stack) ? e.stack : (e && e.message ? e.message : e)).slice(0, 1200));
        return;
      }
      hideLoad();
      bridgeCall('onProgress', [JSON.stringify(discoveredIds())]);
      bridgeCall('onReady', []);
      var viewParam = /[?&]view=([a-z_]+)/.exec(global.location.search);
      if (viewParam) global.setTimeout(function () {
        if (/[?&]instant=1/.test(global.location.search)) S.setViewInstant(viewParam[1]);
        else S.setView(viewParam[1]);
      }, 600);
      var demo = /[?&]demo=([a-z_]+)/.exec(global.location.search);
      if (demo) global.setTimeout(function () {
        select(demo[1]);
        if (/[?&]instant=1/.test(global.location.search)) S.focusWordInstant(demo[1]);
      }, 600);
      if (/[?&]layout=1/.test(global.location.search)) {
        global.setTimeout(function () {
          var ids = ['labelsBtn', 'vocabBtn', 'resetBtn'];
          var out = [];
          for (var i = 0; i < ids.length; i++) {
            var el = $(ids[i]);
            if (!el) { out.push({ id: ids[i], missing: true }); continue; }
            var b = el.getBoundingClientRect();
            out.push({ id: ids[i], x: Math.round(b.x), w: Math.round(b.width), display: global.getComputedStyle(el).display });
          }
          var tb = $('webTopbar');
          var tbr = tb ? tb.getBoundingClientRect() : null;
          setSelftest('LAYOUT ' + JSON.stringify({ buttons: out, docW: doc.documentElement.scrollWidth, bodyW: doc.body.scrollWidth, innerW: global.innerWidth, dpr: global.devicePixelRatio, topbar: tbr ? { x: Math.round(tbr.x), w: Math.round(tbr.width) } : null }));
        }, 300);
      }
      if (isSelfTest()) runSelfTest();
      if (/[?&]stats=1/.test(global.location.search)) global.setTimeout(runStatsProbe, 500);
      if (/[?&]orbit=1/.test(global.location.search)) global.setTimeout(runOrbitProbe, 800);
    }, function onError(reason) {
      showFail(reason);
    });
  }

  // ---------------- self test ----------------

  function isSelfTest() {
    return /[?&]selftest=1/.test(global.location.search);
  }

  function pickWordAtScreen(wordId) {
    var root = S.getWordRoot(wordId);
    if (!root || !global.THREE) return null;
    var v = new global.THREE.Vector3();
    root.getWorldPosition(v);
    v.y += 1;
    v.project(S.camera());
    var canvas = $('stageCanvas');
    if (!canvas) return null;
    var r = canvas.getBoundingClientRect();
    var x = r.left + (v.x * 0.5 + 0.5) * r.width;
    var y = r.top + (-v.y * 0.5 + 0.5) * r.height;
    return S.pick(x, y);
  }

  function pickWorld(x, y, z) {
    if (!global.THREE) return null;
    var v = new global.THREE.Vector3(x, y, z);
    v.project(S.camera());
    var canvas = $('stageCanvas');
    if (!canvas) return null;
    var r = canvas.getBoundingClientRect();
    return S.pick(r.left + (v.x * 0.5 + 0.5) * r.width, r.top + (-v.y * 0.5 + 0.5) * r.height);
  }

  function setSelftest(text) {
    var el = $('selftestResult');
    if (el) el.textContent = text;
    doc.title = text;
    global.__selftestDone = true;
  }

  function runSelfTest() {
    try {
      var failures = [];
      for (var i = 0; i < DATA.objects.length; i++) {
        var o = DATA.objects[i];
        select(o.id);
        var shown = $('cardWord') ? $('cardWord').textContent : '';
        if (shown !== o.word) failures.push(o.id + ': card ' + shown);
        if (!S.getWordRoot(o.id)) failures.push(o.id + ': no scene root');
      }
      var moving = ['traveller', 'baggage_handler', 'follow_me_car'];
      for (var m = 0; m < moving.length; m++) {
        select(moving[m]);
        var w = $('cardWord') ? $('cardWord').textContent : '';
        if (!w) failures.push(moving[m] + ': moving target not clickable');
        S.focusWordInstant(moving[m]);
        var hit = pickWordAtScreen(moving[m]);
        if (hit !== moving[m]) failures.push(moving[m] + ': raycast returned ' + hit);
      }
      // Ground surfaces are big; click a known visible point from the overview instead of the bbox center.
      S.setViewInstant('overview');
      var grounds = [
        { id: 'runway', x: 0, z: -160 },
        { id: 'taxiway', x: -60, z: -112 },
        { id: 'apron', x: 120, z: -58 }
      ];
      for (var g = 0; g < grounds.length; g++) {
        var got = pickWorld(grounds[g].x, 0.2, grounds[g].z);
        if (got !== grounds[g].id) failures.push(grounds[g].id + ': ground pick ' + got);
      }

      var count = discoveredIds().length;
      if (count !== DATA.objects.length) {
        failures.push('discovered ' + count + ' / ' + DATA.objects.length);
      }
      var panel = $('panelCount') ? $('panelCount').textContent : '';
      if (panel.indexOf(String(DATA.objects.length)) < 0) {
        failures.push('panel count ' + panel);
      }
      setSelftest(failures.length === 0 ? 'SELFTEST PASS' : ('SELFTEST FAIL: ' + failures.join('; ')));
    } catch (e) {
      setSelftest('SELFTEST FAIL: ' + ((e && e.stack) ? e.stack : e));
    }
  }

  function runOrbitProbe() {
    var c = $('stageCanvas');
    var cam = S.camera();
    if (!c || !cam) { setSelftest('ORBIT FAIL no canvas'); return; }
    var before = cam.position.clone();
    c.dispatchEvent(new global.PointerEvent('pointerdown', { pointerId: 1, clientX: 200, clientY: 300, bubbles: true }));
    c.dispatchEvent(new global.PointerEvent('pointermove', { pointerId: 1, clientX: 320, clientY: 300, bubbles: true }));
    c.dispatchEvent(new global.PointerEvent('pointerup', { pointerId: 1, clientX: 320, clientY: 300, bubbles: true }));
    var moved = cam.position.distanceTo(before);
    var mid = cam.position.clone();
    c.dispatchEvent(new global.WheelEvent('wheel', { deltaY: -300, bubbles: true, cancelable: true }));
    var zoomed = cam.position.distanceTo(mid);
    setSelftest('ORBIT moved=' + moved.toFixed(2) + ' zoom=' + zoomed.toFixed(2));
  }

  function runStatsProbe() {
    var zones = ['overview', 'terminal_zone', 'apron_zone', 'runway_zone', 'hangar_zone'];
    var out = [];
    var i = 0;
    function next() {
      if (i >= zones.length) {
        setSelftest('STATS ' + JSON.stringify(out));
        return;
      }
      S.setView(zones[i]);
      global.setTimeout(function () {
        var st = S.stats();
        out.push({ zone: zones[i], meshes: st.meshes, triangles: st.triangles, drawCalls: st.drawCalls });
        i += 1;
        next();
      }, 900);
    }
    next();
  }

  function setView(focus) { S.setView(focus); }
  function setHostMode(on) { doc.body.classList.toggle('host', !!on); }

  global.AirportApp = {
    boot: boot,
    select: select,
    setView: setView,
    openVocab: openVocab,
    setLabels: function (on) { S.setLabels(!!on); },
    setHostMode: setHostMode,
    stats: function () { return S.stats(); }
  };

  if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', boot);
  else boot();
})(typeof window !== 'undefined' ? window : globalThis);
