/* 认数字 Numberblocks — 长廊 / 舞台控制器（2026-11-14）
 *
 * 长廊：5×4 缩略角色，点谁放大谁（全部静止，不浮动不眨眼）。
 * 舞台：单角色大图，拖拽旋转 / 快扫切换 / 点击重播 / 自动巡游。
 * 原生桥：window.NumberBlocksNativeBridge（不存在时全部静默降级，浏览器里可直接调试）。
 */
(function () {
  'use strict'

  var TOTAL = 20
  var TOUR_INTERVAL_MS = 2400

  var galleryEl = document.getElementById('gallery')
  var stageEl = document.getElementById('stage')
  var stageTop = document.getElementById('stageTop')
  var stageNumEl = document.getElementById('stageNum')
  var stageCount = document.getElementById('stageCount')
  var stageBody = document.getElementById('stageBody')
  var stageSpace = document.getElementById('stageSpace')
  var stageRail = document.getElementById('stageRail')
  var backBtn = document.getElementById('backBtn')
  var replayBtn = document.getElementById('replayBtn')
  var tourBtn = document.getElementById('tourBtn')

  var state = {
    view: 'gallery',
    current: 1,
    numbers: [],
    seen: {},
    focus: 1,
    tourTimer: -1,
    tourIndex: 0,
    touring: false
  }

  var rig = null
  var ry = -22
  var rx = -10
  var amp = 1
  var ampTarget = 1
  var phase = 0
  var dragging = false
  var gestureStart = 0
  var gestureDx = 0
  var gestureDy = 0
  var lastX = 0
  var lastY = 0
  var pupilTimer = -1
  var activeTimer = -1

  /* ── 原生桥 ─────────────────────────────────────── */

  function bridge(name) {
    var b = window.NumberBlocksNativeBridge
    if (!b || typeof b[name] !== 'function') {
      return null
    }
    try {
      return b[name].apply(b, Array.prototype.slice.call(arguments, 1))
    } catch (e) {
      return null
    }
  }

  /* ── 数字集合 ───────────────────────────────────── */

  function allNumbers() {
    var out = []
    for (var i = 1; i <= TOTAL; i++) {
      out.push(i)
    }
    return out
  }

  function isMarked(n) {
    return state.numbers.indexOf(n) >= 0
  }

  function seenList() {
    var out = []
    for (var i = 1; i <= TOTAL; i++) {
      if (state.seen[i]) {
        out.push(i)
      }
    }
    return out
  }

  /* ── 角色构建 ───────────────────────────────────── */

  function buildRig(host, n) {
    var ch = CHARS[n - 1]
    if (!ch) {
      return null
    }
    var delay = (n * -0.4).toFixed(2)
    el('div', 'shadow', host,
      'top:' + (ch.top + ch.sh) + 'px;width:' + ch.shw + 'px;margin-left:' + (-ch.shw / 2) +
      'px;animation-delay:' + delay + 's')
    var anchor = el('div', 'anchor', host, 'top:' + ch.top + 'px')
    var rigEl = el('div', 'rig', anchor)
    var bob = el('div', 'bob', rigEl, 'animation-delay:' + delay + 's')
    ch.build(bob)
    return rigEl
  }

  /* ── 长廊 ───────────────────────────────────────── */

  function buildGallery() {
    galleryEl.innerHTML = ''
    for (var n = 1; n <= TOTAL; n++) {
      buildThumb(n)
    }
  }

  function buildThumb(n) {
    var ch = CHARS[n - 1]
    if (!ch) {
      return
    }
    var tint = ch.split || ch.color
    var thumb = el('div', 'thumb', galleryEl)
    thumb.setAttribute('data-n', String(n))

    el('div', '', thumb, 'position:absolute;inset:0;opacity:.12;background:' + tint)
    var space = el('div', 'thumb-space static', thumb)
    buildRig(space, n)

    var badge = el('div', 'thumb-num', thumb)
    badge.textContent = String(n)
    badge.style.background = tint
    if (isMarked(n)) {
      el('div', 'thumb-dot', thumb)
    }

    thumb.addEventListener('click', function () {
      showStage(n)
    })
  }

  function layoutThumbs() {
    var first = galleryEl.querySelector('.thumb')
    if (!first) {
      return
    }
    var h = first.clientHeight
    var w = first.clientWidth
    if (h <= 0 || w <= 0) {
      return
    }
    // 高度决定能放多高，宽度决定能放多宽：宽角色（4/9/15/16 的 shw 达 210）在窄屏上靠宽度这一项收住
    var s = Math.min(0.42, Math.max(0.1, Math.min(h / 560, w / 230)))
    galleryEl.style.setProperty('--thumb-scale', s.toFixed(4))
  }

  function pulseFocus() {
    var target = galleryEl.querySelector('.thumb[data-n="' + state.focus + '"]')
    if (!target) {
      return
    }
    target.classList.add('focus-pulse')
    window.setTimeout(function () {
      target.classList.remove('focus-pulse')
    }, 1300)
  }

  /* ── 舞台 ───────────────────────────────────────── */

  function applyBand(n) {
    var ch = CHARS[n - 1]
    stageTop.style.background = ch.split || ch.head || ch.color
    stageNumEl.textContent = String(n)
  }

  function renderStageRig(n) {
    stageSpace.innerHTML = ''
    rig = buildRig(stageSpace, n)
    ry = -22
    rx = -10
    amp = 1
    ampTarget = 1
    phase = n * 1.7
    pupilReset()
  }

  function renderRail() {
    stageRail.innerHTML = ''
    for (var i = 1; i <= TOTAL; i++) {
      var chip = el('button', 'rail-chip', stageRail)
      chip.type = 'button'
      chip.textContent = String(i)
      if (state.seen[i]) {
        chip.classList.add('seen')
        chip.style.background = CHARS[i - 1].split || CHARS[i - 1].color
      }
      if (i === state.current) {
        chip.classList.add('current')
      }
      var handler = makeChipHandler(i)
      chip.addEventListener('click', handler)
    }
    var cur = stageRail.querySelector('.rail-chip.current')
    if (cur && cur.scrollIntoView) {
      cur.scrollIntoView({ block: 'nearest', inline: 'center' })
    }
  }

  function makeChipHandler(n) {
    return function (e) {
      if (e && e.stopPropagation) {
        e.stopPropagation()
      }
      showStage(n)
    }
  }

  function renderCount() {
    stageCount.textContent = '已认识 ' + seenList().length + ' / ' + TOTAL
    bridge('onProgress', JSON.stringify(seenList()))
  }

  function layoutStage() {
    if (!stageEl.classList.contains('on')) {
      return
    }
    var w = stageBody.clientWidth
    var h = stageBody.clientHeight
    if (w <= 0 || h <= 0) {
      return
    }
    var s = Math.min(h / 520, w / 320) * 0.94
    stageSpace.style.setProperty('--stage-scale', Math.max(0.2, s).toFixed(4))
  }

  function showStage(n, keepTour) {
    if (n < 1 || n > TOTAL) {
      return
    }
    if (!keepTour) {
      stopTour()
    }
    state.view = 'stage'
    state.current = n
    state.seen[n] = true
    galleryEl.classList.add('off')
    stageEl.classList.add('on')
    applyBand(n)
    renderStageRig(n)
    renderRail()
    renderCount()
    layoutStage()
    speakNumber(n)
    bridge('onSelect', String(n))
  }

  function showGallery() {
    stopTour()
    bridge('stopSpeak')
    pupilReset()
    state.view = 'gallery'
    stageEl.classList.remove('on')
    galleryEl.classList.remove('off')
    layoutThumbs()
    var marked = galleryEl.querySelectorAll('.thumb.active')
    for (var i = 0; i < marked.length; i++) {
      marked[i].classList.remove('active')
    }
    var cur = galleryEl.querySelector('.thumb[data-n="' + state.current + '"]')
    if (cur) {
      cur.classList.add('active')
    }
    if (activeTimer !== -1) {
      window.clearTimeout(activeTimer)
    }
    activeTimer = window.setTimeout(function () {
      if (cur) {
        cur.classList.remove('active')
      }
    }, 900)
  }

  function stepNumber(delta) {
    var next = state.current + delta
    if (next < 1 || next > TOTAL) {
      return
    }
    showStage(next)
  }

  /* ── 朗读 ───────────────────────────────────────── */

  function speakNumber(n) {
    bridge('stopSpeak')
    bridge('speak', NUM_EN[n - 1], NUM_ZH[n - 1])
  }

  /* ── 自动巡游 ───────────────────────────────────── */

  function tourList() {
    return state.numbers.length > 0 ? state.numbers : allNumbers()
  }

  function startTour() {
    stopTour()
    state.touring = true
    state.tourIndex = 0
    tourBtn.classList.add('playing')
    tourBtn.textContent = '⏸ 停止巡游'
    stepTour()
  }

  function stepTour() {
    var list = tourList()
    if (!state.touring || state.tourIndex >= list.length) {
      stopTour()
      return
    }
    var n = list[state.tourIndex]
    state.tourIndex += 1
    showStage(n, true)
    state.tourTimer = window.setTimeout(stepTour, TOUR_INTERVAL_MS)
  }

  function stopTour() {
    if (state.tourTimer !== -1) {
      window.clearTimeout(state.tourTimer)
      state.tourTimer = -1
    }
    if (state.touring) {
      state.touring = false
      bridge('stopSpeak')
    }
    tourBtn.classList.remove('playing')
    tourBtn.textContent = '▶ 自动巡游'
  }

  /* ── 眼睛跟随 ───────────────────────────────────── */

  function pupilFollow(dx, dy) {
    var px = Math.max(-6, Math.min(6, dx * 0.5))
    var py = Math.max(-5, Math.min(5, dy * 0.4))
    document.body.style.setProperty('--px', px.toFixed(1))
    document.body.style.setProperty('--py', py.toFixed(1))
    if (pupilTimer !== -1) {
      window.clearTimeout(pupilTimer)
    }
    pupilTimer = window.setTimeout(pupilReset, 600)
  }

  function pupilReset() {
    if (pupilTimer !== -1) {
      window.clearTimeout(pupilTimer)
      pupilTimer = -1
    }
    document.body.style.setProperty('--px', '0')
    document.body.style.setProperty('--py', '0')
  }

  /* ── 指针交互 ───────────────────────────────────── */

  function onDown(e) {
    if (state.view !== 'stage') {
      return
    }
    dragging = true
    ampTarget = 0
    gestureStart = Date.now()
    gestureDx = 0
    gestureDy = 0
    lastX = e.clientX
    lastY = e.clientY
    stageBody.classList.add('dragging')
    if (stageBody.setPointerCapture && e.pointerId !== undefined) {
      try {
        stageBody.setPointerCapture(e.pointerId)
      } catch (err) {
      }
    }
  }

  function onMove(e) {
    if (!dragging) {
      return
    }
    var dx = e.clientX - lastX
    var dy = e.clientY - lastY
    lastX = e.clientX
    lastY = e.clientY
    gestureDx += dx
    gestureDy += dy
    ry += dx * 0.6
    rx = Math.max(-60, Math.min(60, rx - dy * 0.4))
    pupilFollow(dx, dy)
  }

  function onUp() {
    if (!dragging) {
      return
    }
    dragging = false
    ampTarget = 1
    stageBody.classList.remove('dragging')
    var dt = Date.now() - gestureStart
    var dist = Math.sqrt(gestureDx * gestureDx + gestureDy * gestureDy)
    if (dist < 8 && dt < 400) {
      speakNumber(state.current)
      return
    }
    // 快扫（不是慢拖旋转）= 切数字
    if (dt <= 260 && Math.abs(gestureDx) >= 60 && Math.abs(gestureDy) < 40) {
      stepNumber(gestureDx < 0 ? 1 : -1)
    }
  }

  /* ── 渲染循环 ───────────────────────────────────── */

  function loop() {
    amp += (ampTarget - amp) * 0.06
    if (rig && state.view === 'stage') {
      var sway = Math.sin(Date.now() / 1000 + phase) * 18 * amp
      rig.style.transform = 'rotateX(' + rx.toFixed(2) + 'deg) rotateY(' + (ry + sway).toFixed(2) + 'deg)'
    }
    window.requestAnimationFrame(loop)
  }

  /* ── 对外 API ───────────────────────────────────── */

  function setHostMode(on) {
    if (on) {
      document.body.classList.add('host')
    } else {
      document.body.classList.remove('host')
    }
  }

  function configure(cfg, animate) {
    var cfgObj = cfg || {}
    var raw = Array.isArray(cfgObj.numbers) ? cfgObj.numbers : []
    var uniq = []
    for (var i = 0; i < raw.length; i++) {
      var v = raw[i]
      if (typeof v === 'number' && v >= 1 && v <= TOTAL && Math.floor(v) === v && uniq.indexOf(v) < 0) {
        uniq.push(v)
      }
    }
    uniq.sort(function (a, b) {
      return a - b
    })
    state.numbers = uniq
    var focus = cfgObj.focus
    state.focus = typeof focus === 'number' && focus >= 1 && focus <= TOTAL ?
      focus : (uniq.length > 0 ? uniq[0] : 1)
    buildGallery()
    layoutThumbs()
    if (animate !== false) {
      pulseFocus()
    }
  }

  function destroy() {
    stopTour()
    bridge('stopSpeak')
    pupilReset()
    if (activeTimer !== -1) {
      window.clearTimeout(activeTimer)
      activeTimer = -1
    }
  }

  window.NumberBlocksApp = {
    setHostMode: setHostMode,
    configure: configure,
    showGallery: showGallery,
    showStage: showStage,
    destroy: destroy
  }

  /* ── 启动 ───────────────────────────────────────── */

  backBtn.addEventListener('click', showGallery)
  replayBtn.addEventListener('click', function () {
    speakNumber(state.current)
  })
  tourBtn.addEventListener('click', function () {
    if (state.touring) {
      stopTour()
    } else {
      startTour()
    }
  })

  stageBody.addEventListener('pointerdown', onDown)
  stageBody.addEventListener('pointermove', onMove)
  stageBody.addEventListener('pointerup', onUp)
  stageBody.addEventListener('pointercancel', onUp)
  stageBody.addEventListener('pointerleave', onUp)

  document.addEventListener('pointerdown', function (e) {
    // 巡游按钮自己按下时不要在这儿停：否则捕获阶段先停、click 阶段又当成「开始」重启，
    // 「停止巡游」会变成「重新巡游」。按钮的 click 处理器自己负责 toggle。
    if (state.touring && !(e.target && tourBtn.contains(e.target))) {
      stopTour()
    }
  }, true)

  window.addEventListener('resize', function () {
    layoutThumbs()
    layoutStage()
  })

  try {
    // 自举只画长廊：不脉冲，等原生 configure 再高亮真正的 focus
    configure({ numbers: [], focus: 1 }, false)
    window.requestAnimationFrame(loop)
    bridge('onReady')
  } catch (e) {
    bridge('onError', String(e && e.message ? e.message : e))
  }
})()
