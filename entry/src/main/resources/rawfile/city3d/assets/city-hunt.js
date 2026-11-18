/* ============================================================
   小词城 · 单词寻宝
   ------------------------------------------------------------
   一轮 5 个单词、按分区轮换。玩家根据线索在 3D 小城里点出目标：
   - 点对：绿色爆闪 + 加分 + 自动进下一个
   - 点错：轻轻抖一下，并告诉玩家他点到的是什么
   - 提示：三级递进（光圈 → 光柱 → 镜头带路），每次扣分
   ------------------------------------------------------------
   模块只负责「游戏」，不碰 3D 内部：
   依赖注入的 ctx 提供 scene / data / toast / 打开单词卡等能力。
   ============================================================ */
(function (global) {
  'use strict';

  var ROUND_SIZE = 5;
  // 分区轮换顺序：从最好逛的商业街开始
  var ZONE_ORDER = ['main_street', 'park_zone', 'school_zone', 'hospital_zone'];
  var ZONE_NAME = {
    main_street: '商业街',
    park_zone: '公园',
    school_zone: '学校',
    hospital_zone: '医院',
    overview: '全城'
  };
  // 找不动的兜底：静止多久自动给提示（毫秒）
  var AUTO_HINT_1 = 22000;
  var AUTO_HINT_2 = 45000;

  var ctx = null;
  var els = {};
  var active = false;
  var paused = false;
  // 「已答对、正在播反馈动画」的锁：这段时间内忽略点击，
  // 否则连点会把同一个目标重复加分
  var resolving = false;

  var queue = [];
  var index = 0;
  var targetId = null;
  var roundZone = 'main_street';
  var zoneCursor = 0;

  var hintLevel = 0;        // 0 未提示 / 1 光圈 / 2 光柱 / 3 镜头
  var hintsThisWord = 0;
  var score = 0;
  var found = [];
  var startedAt = 0;
  var wordShownAt = 0;
  var lastTickAt = 0;
  var tickTimer = null;

  var reduceMotion = false;

  function $(id) { return document.getElementById(id); }

  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }

  function fmtTime(ms) {
    var s = Math.floor(ms / 1000);
    var m = Math.floor(s / 60);
    var r = s % 60;
    return m + ':' + (r < 10 ? '0' : '') + r;
  }

  /* ---------------- 出题 ---------------- */

  function wordsInZone(zone) {
    return ctx.data.objects.filter(function (o) {
      return o.zone === zone || o.zone === 'citywide';
    });
  }

  function pickRound() {
    // 找一个词够用的分区，按顺序轮换，避免每次都从商业街开始
    var tries = 0;
    while (tries < ZONE_ORDER.length) {
      var z = ZONE_ORDER[zoneCursor % ZONE_ORDER.length];
      zoneCursor++;
      var pool = wordsInZone(z);
      if (pool.length >= ROUND_SIZE) {
        roundZone = z;
        return sample(pool, ROUND_SIZE);
      }
      tries++;
    }
    // 兜底：全城随机
    roundZone = 'overview';
    return sample(ctx.data.objects, ROUND_SIZE);
  }

  // 洗牌后取前 n 个，避免同一轮里重复
  function sample(list, n) {
    var pool = list.slice();
    for (var i = pool.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var t = pool[i];
      pool[i] = pool[j];
      pool[j] = t;
    }
    return pool.slice(0, Math.min(n, pool.length));
  }

  /* ---------------- 渲染 ---------------- */

  function renderDots() {
    if (!els.dots) { return; }
    els.dots.innerHTML = '';
    for (var i = 0; i < queue.length; i++) {
      var d = document.createElement('span');
      d.className = 'hunt-dot';
      if (i < index) { d.className += ' is-done'; }
      else if (i === index) { d.className += ' is-current'; }
      els.dots.appendChild(d);
    }
  }

  function renderScore() {
    // 分数只允许整数，避免半次提示算出小数
    if (els.score) { els.score.textContent = String(Math.round(score)); }
  }

  function renderClue(o) {
    if (!els.clue) { return; }
    els.eyebrow.textContent = '在' + (ZONE_NAME[roundZone] || '小城') + '找一找';
    els.word.textContent = o.word;
    els.zh.textContent = o.zh;
    // 提示文案用 kidDefinition 的第一句，不直接说位置，只描述「长什么样」
    els.tip.textContent = o.kidDefinition;
    if (els.hint) {
      els.hint.setAttribute('aria-disabled', hintLevel >= 3 ? 'true' : 'false');
      els.hint.textContent = hintLevel === 0 ? '给点提示' : hintLevel >= 3 ? '已带路' : '再提示一点';
    }
  }

  function showClueCard(on) {
    if (els.card) { els.card.classList.toggle('is-on', !!on); }
  }

  function showHud(on) {
    if (els.hunt) { els.hunt.hidden = !on; }
    // 寻宝时把时间条、视角工具收起来，把画面让给线索卡
    if (document.body) { document.body.classList.toggle('is-hunting', !!on); }
  }

  /* ---------------- 计时 ---------------- */

  function startTick() {
    stopTick();
    tickTimer = global.setInterval(function () {
      if (!active || paused) { return; }
      var now = Date.now();
      if (els.timer) { els.timer.textContent = fmtTime(now - startedAt); }
      // 卡太久自动升级提示，避免孩子干着急
      var idle = now - wordShownAt;
      if (hintLevel === 0 && idle > AUTO_HINT_1) { escalateHint(true); }
      else if (hintLevel < 3 && idle > AUTO_HINT_2) { escalateHint(true); }
    }, 500);
  }

  function stopTick() {
    if (tickTimer) {
      global.clearInterval(tickTimer);
      tickTimer = null;
    }
  }

  /* ---------------- 提示 ---------------- */

  function escalateHint(silent) {
    if (!active || !targetId) { return; }
    if (hintLevel >= 3) { return; }
    hintLevel++;
    hintsThisWord++;
    if (hintLevel === 1) {
      ctx.scene.setHuntTarget(targetId, 0.42);
      if (!silent) { ctx.toast('地上亮起了一圈光，就在附近'); }
    } else if (hintLevel === 2) {
      ctx.scene.setHuntTarget(targetId, 1);
      if (!silent) { ctx.toast('光柱指出来了，看那边'); }
    } else {
      ctx.scene.setHuntTarget(targetId, 1);
      // 第三级：镜头带到目标分区，并在画面外时用边缘箭头指方向
      var o = byIdSafe(targetId);
      if (o && ctx.scene.setView) {
        var zone = o.zone === 'citywide' ? roundZone : o.zone;
        if (ctx.scene.setView && ZONE_NAME[zone]) { ctx.scene.setView(zone, false); }
      }
      if (!silent) { ctx.toast('跟着边上的箭头走，就到了'); }
      // 箭头要等镜头飞完再显示，否则会先指一个错的旧方向
      global.setTimeout(function () { if (active && hintLevel >= 3) { updatePointer(); } }, 950);
    }
    renderClue(byIdSafe(targetId));
    renderScore();
  }

  function byIdSafe(id) {
    if (!id) { return null; }
    for (var i = 0; i < ctx.data.objects.length; i++) {
      if (ctx.data.objects[i].id === id) { return ctx.data.objects[i]; }
    }
    return null;
  }

  /* ---------------- 回合流程 ---------------- */

  function nextTarget() {
    if (index >= queue.length) { finish(); return; }
    resolving = false;
    var o = queue[index];
    targetId = o.id;
    hintLevel = 0;
    hintsThisWord = 0;
    wordShownAt = Date.now();
    renderDots();
    renderClue(o);
    // 线索阶段不显示标记，也不显示英文标签（标签会直接泄露答案）
    ctx.scene.setHuntTarget(null);
    // 换题了，上一题的箭头必须立刻收起，否则会指向旧目标
    hidePointer();
    showClueCard(false);
    // 让线索卡淡入
    global.setTimeout(function () { showClueCard(true); }, 40);
    // 只在「本轮第一个词」时把镜头带到分区；之后不再打断孩子自己转视角
    if (roundZone !== 'overview' && index === 0) { ctx.scene.setView(roundZone, false); }
  }

  function onCorrect(id) {
    if (resolving) { return; }
    resolving = true;
    var o = byIdSafe(id);
    // 提示次数只按整数算，扣分才有规律（点错不扣，只是少给提示的次数）
    score += Math.max(40, 100 - hintsThisWord * 15);
    found.push({ id: id, hints: hintsThisWord });
    renderScore();

    ctx.scene.setHuntTarget(null);
    ctx.scene.burstAt(id);

    // 找到的短暂反馈，1.1 秒后进下一个
    if (els.foundStrip) {
      els.foundStrip.innerHTML = '<span class="hfs-check">✓</span>' +
        '<span class="hfs-word" lang="en">' + escapeHtml(o ? o.word : id) + '</span>' +
        '<span class="hfs-zh">' + escapeHtml(o ? o.zh : '') + ' 找到了</span>';
      els.foundStrip.classList.add('is-on');
    }
    index++;
    renderDots();
    showClueCard(false);

    global.setTimeout(function () {
      if (els.foundStrip) { els.foundStrip.classList.remove('is-on'); }
      resolving = false;
      if (!active) { return; }
      nextTarget();
    }, reduceMotion ? 420 : 1100);
  }

  function onWrong(id) {
    var o = byIdSafe(id);
    if (els.card) {
      els.card.classList.remove('is-shake');
      // 强制重排才能重放动画
      void els.card.offsetWidth;
      els.card.classList.add('is-shake');
    }
    if (o) {
      ctx.toast('那是 ' + o.word + '（' + o.zh + '），不是我们要找的');
    } else {
      ctx.toast('这里没有哦，再看看线索');
    }
    // 点错了也顺手把目标的光圈点亮一点点，降低挫败感。
    // 注意不要动 hintsThisWord：点错不该扣分，否则孩子会不敢试。
    if (hintLevel === 0 && targetId) {
      ctx.scene.setHuntTarget(targetId, 0.3);
    }
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function finish() {
    stopTick();
    stopPointer();
    active = false;
    resolving = false;
    ctx.scene.setHuntTarget(null);
    showClueCard(false);

    var elapsed = Date.now() - startedAt;
    // 速度奖励：越快越高，上限 300
    var speedBonus = Math.max(0, 300 - Math.floor(elapsed / 1000) * 2);
    var total = score + speedBonus;
    var hints = found.reduce(function (a, f) { return a + (f.hints > 0 ? 1 : 0); }, 0);
    var stars = total >= 560 ? 3 : total >= 420 ? 2 : 1;

    renderResult({
      stars: stars,
      total: total,
      base: score,
      bonus: speedBonus,
      elapsed: elapsed,
      found: found,
      hints: hints,
      zone: roundZone
    });
  }

  function renderResult(r) {
    if (!els.result) { return; }
    els.result.hidden = false;

    var starHtml = '';
    for (var i = 0; i < 3; i++) {
      starHtml += '<span class="hres-star' + (i < r.stars ? ' is-on' : '') + '" aria-hidden="true">' +
        '<svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3.2 14.5 9l6.3.6-4.8 4.2 1.5 6.2L12 16.6 6.5 20l1.5-6.2L3.2 9.6 9.5 9Z"/></svg>' +
        '</span>';
    }
    els.resStars.innerHTML = starHtml;
    els.resStars.setAttribute('aria-label', r.stars + ' 颗星');

    els.resTitle.textContent = r.stars === 3 ? '全部找到了，太厉害了！'
      : r.stars === 2 ? '找得不错，再来一轮？'
      : '都找到了，继续加油';
    els.resScore.textContent = String(r.total);
    els.resMeta.innerHTML =
      '<span>' + fmtTime(r.elapsed) + '</span>' +
      '<span>' + r.found.length + ' 个单词</span>' +
      '<span>' + (r.hints > 0 ? r.hints + ' 次提示' : '零提示') + '</span>' +
      '<span>速度 +' + r.bonus + '</span>';

    // 本轮找到的单词列表，点一下可以看单词卡
    els.resList.innerHTML = '';
    r.found.forEach(function (f) {
      var o = byIdSafe(f.id);
      if (!o) { return; }
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'hres-chip';
      btn.innerHTML = '<span lang="en">' + escapeHtml(o.word) + '</span>' +
        '<span class="hres-chip-zh">' + escapeHtml(o.zh) + '</span>';
      btn.addEventListener('click', function () {
        closeResult();
        stop(true);
        ctx.openWord(o.id);
      });
      els.resList.appendChild(btn);
    });
  }

  function closeResult() {
    if (els.result) { els.result.hidden = true; }
  }

  /* ---------------- 屏幕外方向箭头 ---------------- */

  /* 目标在画面外（或在相机背后）时，在画布边缘放一个指向它的箭头，并显示距离。
     目标进入画面后箭头自动淡出——孩子在画面里已经能直接看到目标了。 */
  var pointerTimer = null;
  var pointerShown = false;

  // 把「从画布中心指向目标」的方向投射到内缩矩形的边缘上。
  // 顶部要多让一些，否则箭头会压到顶部 HUD；底部让出线索卡的空间。
  // 窄屏上 HUD 与线索卡都更矮，内缩量要相应减小。
  function edgePoint(angle, w, h) {
    var narrow = w < 620;
    var padX = narrow ? 26 : 38;
    var padTop = narrow ? 74 : 122;
    var padBottom = narrow ? 128 : 186;

    var cx = w / 2;
    var cy = h / 2;
    var dx = Math.cos(angle);
    var dy = Math.sin(angle);
    var halfX = Math.max(1, w / 2 - padX);
    var halfYUp = Math.max(1, h / 2 - padTop);
    var halfYDown = Math.max(1, h / 2 - padBottom);
    var tx = Math.abs(dx) < 1e-6 ? Infinity : halfX / Math.abs(dx);
    var ty = Math.abs(dy) < 1e-6 ? Infinity
      : (dy < 0 ? halfYUp : halfYDown) / Math.abs(dy);
    var t = Math.min(tx, ty);
    return { x: cx + dx * t, y: cy + dy * t };
  }

  function updatePointer() {
    if (!active || !targetId || hintLevel < 3) {
      hidePointer();
      return;
    }
    var pos = ctx.scene.getWordScreenPos ? ctx.scene.getWordScreenPos(targetId) : null;
    if (!pos) { hidePointer(); return; }

    // 已经在画面里：不需要箭头
    if (pos.onScreen) { hidePointer(); return; }

    var p = edgePoint(pos.angle, pos.width, pos.height);
    if (els.pointer) {
      els.pointer.style.transform = 'translate(' + p.x.toFixed(1) + 'px,' + p.y.toFixed(1) + 'px)';
      els.pointer.classList.add('is-on');
    }
    if (els.pointerArrow) {
      var deg = (pos.angle * 180) / Math.PI;
      els.pointerArrow.style.transform = 'rotate(' + deg.toFixed(1) + 'deg)';
    }
    if (els.pointerDist) {
      var d = ctx.scene.distanceToWord ? ctx.scene.distanceToWord(targetId) : Infinity;
      els.pointerDist.textContent = isFinite(d) ? Math.round(d) + ' 米' : '';
      // 近处换个颜色，暗示「就在旁边了」
      els.pointer.classList.toggle('is-near', isFinite(d) && d < 16);
    }
    pointerShown = true;
  }

  function hidePointer() {
    if (!els.pointer) { return; }
    if (!pointerShown && !els.pointer.classList.contains('is-on')) { return; }
    els.pointer.classList.remove('is-on');
    els.pointer.classList.remove('is-near');
    pointerShown = false;
  }

  function startPointer() {
    stopPointer();
    // 每帧算太重（要遍历包围盒），100ms 一次足够跟手
    pointerTimer = global.setInterval(function () {
      if (!active || paused) { return; }
      updatePointer();
    }, 100);
    updatePointer();
  }

  function stopPointer() {
    if (pointerTimer) {
      global.clearInterval(pointerTimer);
      pointerTimer = null;
    }
    hidePointer();
  }

  /* ---------------- 对外接口 ---------------- */

  function start(forceZone) {
    if (!ctx) { return false; }
    if (active) { stop(true); }
    if (forceZone && ZONE_NAME[forceZone]) {
      roundZone = forceZone;
      var i = ZONE_ORDER.indexOf(forceZone);
      if (i >= 0) { zoneCursor = i; }
    }
    queue = pickRound();
    index = 0;
    score = 0;
    found = [];
    hintLevel = 0;
    hintsThisWord = 0;
    targetId = null;
    active = true;
    paused = false;
    resolving = false;
    startedAt = Date.now();
    wordShownAt = Date.now();

    showHud(true);
    closeResult();
    renderScore();
    renderDots();
    if (els.timer) { els.timer.textContent = '0:00'; }
    startTick();
    startPointer();

    // 寻宝时关掉英文标签，否则等于把答案写在墙上
    if (ctx.onEnter) { ctx.onEnter(); }

    nextTarget();
    return true;
  }

  function stop(silent) {
    var wasActive = active;
    active = false;
    resolving = false;
    stopTick();
    stopPointer();
    targetId = null;
    if (ctx && ctx.scene) { ctx.scene.setHuntTarget(null); }
    showHud(false);
    showClueCard(false);
    if (els.foundStrip) { els.foundStrip.classList.remove('is-on'); }
    closeResult();
    // 只有真正从「游戏进行中」退出时才需要恢复界面（标签开关等）
    if (wasActive && ctx && ctx.onExit) { ctx.onExit(); }
  }

  function handlePick(id) {
    if (!active) { return false; }
    // 正在播「找到了」的反馈，忽略这段时间的点击
    if (resolving) { return true; }
    if (!id) {
      // 点到空地：不算错，只提示
      ctx.toast('那里没有东西，找找建筑或车子');
      return true;
    }
    if (id === targetId) { onCorrect(id); }
    else { onWrong(id); }
    return true;
  }

  function init(context) {
    ctx = context;
    els.hunt = $('hunt');
    els.dots = $('huntDots');
    els.timer = $('huntTimer');
    els.score = $('huntScore');
    // 线索卡容器就是 huntCard；写成不存在的 id 会让整张卡永不刷新
    els.clue = $('huntCard');
    els.card = $('huntCard');
    els.eyebrow = $('huntEyebrow');
    els.word = $('huntWord');
    els.zh = $('huntZh');
    els.tip = $('huntTip');
    els.hint = $('huntHint');
    els.foundStrip = $('huntFound');
    els.result = $('huntResult');
    els.pointer = $('huntPointer');
    els.pointerArrow = els.pointer ? els.pointer.querySelector('.hp-arrow') : null;
    els.pointerDist = $('huntPointerDist');
    els.resStars = $('hresStars');
    els.resTitle = $('hresTitle');
    els.resScore = $('hresScore');
    els.resMeta = $('hresMeta');
    els.resList = $('hresList');

    try {
      reduceMotion = global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch (err) { /* 忽略 */ }

    if (els.hint) {
      els.hint.addEventListener('click', function () {
        if (hintLevel >= 3) { return; }
        escalateHint(false);
      });
    }
    var closeBtn = $('huntClose');
    if (closeBtn) {
      closeBtn.addEventListener('click', function () {
        // 结算面板已经弹出来时 active 已是 false，但界面还没收拾，仍要走一遍退出
        if (!active) {
          closeResult();
          showHud(false);
          if (document.body) { document.body.classList.remove('is-hunting'); }
          if (ctx && ctx.onExit) { ctx.onExit(); }
          return;
        }
        stop(false);
      });
    }

    var againBtn = $('hresAgain');
    if (againBtn) { againBtn.addEventListener('click', function () { closeResult(); start(); }); }
    var doneBtn = $('hresDone');
    if (doneBtn) { doneBtn.addEventListener('click', function () { closeResult(); stop(true); }); }

    return true;
  }

  global.WordCityHunt = {
    init: init,
    start: start,
    stop: stop,
    handlePick: handlePick,
    isActive: function () { return active; },
    getTarget: function () { return targetId; },
    // 供页面隐藏时暂停计时
    setPaused: function (on) { paused = !!on; }
  };
})(window);
