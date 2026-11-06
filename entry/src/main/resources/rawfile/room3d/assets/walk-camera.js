/*
 * 第一人称「走进去」相机：视线高度、按住前进、拖动环顾、看见多远、撞墙滑行。
 *
 * 只做相机，不做业务：
 *  - 不创建渲染器、不接管渲染循环。RoomScene 每帧把 dt 交给 update()，用同一台透视相机。
 *  - 拾取继续走 RoomExperience.pickAt → onTap → chooseObject，单词卡、发音、进度都不用改。
 *  - 英文标签仍由 room-app.js 的 getLabelAnchors() 摆放，这里只多告诉它一个 distance，
 *    让标签按「看见多远」分成清楚 / 半透明 / 藏起来三档。
 *  - 方位提示（「在你左手边」）只算几何：bearing() 给偏角，describe() 给落差。
 *    什么时候念、念几句是 room-app.js 的事——这里不碰语音。
 *
 * 坐标系：世界坐标就是户型坐标（米），地面 y = 0.03。房间墙在 ROOM 边界上，
 * 可走半径用 WALK_INSET 从墙边内收一个人宽，避免贴脸穿墙。
 *
 * 视角：yaw 0 = 朝 +z（和 RoomExperience 的轨道相机角度约定一致），+PI/2 朝 +x；
 * 出生朝向写在 room-layout.js 的 spawns 里，进去就在房间中央看着最有代表性的几件东西。
 */
(function (global) {
  'use strict';

  // 视线高度：站立 1.25 m 对应小朋友的站姿；蹲下 0.8 m 和沙发座面齐平。
  var EYE = { stand: 1.25, crouch: 0.8 };
  var SPEED = 0.95; // m/s，比成年人走路慢一点，小朋友跟得上
  var PITCH_LIMIT = 1.2; // ±69°，不让人把镜头翻到头顶
  var LOOK_X = 0.0042; // 每像素转多少弧度：手机上划一整屏约转 90°
  var LOOK_Y = 0.0034;
  var WALK_INSET = 0.42; // 与墙的最小距离，按肩宽 + 手指误触留量
  var RADIUS = 0.26; // 身体半径，撞家具时用
  var HIGH_PROPS = 1.2; // 底边高过这个高度的碰撞盒当作挂件，不挡人
  var THIN_LOW = 0.12; // 贴地薄片（门槛石、踢脚线）当作平地，不挡人
  // 顶面低于这个高度的东西可以直接跨过去：地毯（0.14m）、地垫、矮门槛。
  // 只按「厚薄」判断会漏掉地毯——地毯比门槛石厚，但它本来就是用来踩的。
  var STEP_OVER = 0.18;
  var RANGE = { min: 1.5, max: 8, value: 5, step: 0.1 };
  var PITCH_START = -0.08; // 进房间时视线略向下，先看到地面再抬头
  // 「看见多远」以内还有两档：贴身的名字说全，走到跟前会看到的先淡淡显示。
  // far 的比例别调太小，否则站在房间中间一眼全是半透明，反而看不出远近。
  var RANGE_FAR = 0.62;
  var DEFAULT_SPAWN = { x: 4.6, z: 1.2, yaw: Math.PI / 2 }; // 客餐厅中部，面朝客厅

  // 方位提示的几何阈值。正面 ±20° 算「正前方」：给小朋友指路，越界一点就说「右前方」，
  // 比死板的 8 个罗盘方向好懂，也不会因为手抖来回跳。
  // 三个边界要错开，不能共用 FRONT：否则 90° 正好落在「右边」的判定边界上，
  // 严格大于写法会把它算成右前方，改成大于等于又会把 70° 算成右手边。
  var FRONT = Math.PI / 9; // 20°
  var SIDE_EDGE = Math.PI / 4; // 45°：越过这里就是「旁边」而不是「前方」
  var BEHIND_EDGE = Math.PI * 2 / 3; // 120°：越过这里就是「身后」
  var HIGH = 1.0; // m，和视线高度差多少才值得说「上面 / 下面」
  var NEAR_SPOT = 1.2; // m，再近就是「就在手边」
  var FAR_SPOT = 4.2; // m，再远就是「在房间另一头」

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function wrapAngle(angle) {
    return Math.atan2(Math.sin(angle), Math.cos(angle));
  }

  // 偏角 → 朝向文字：正前方 / 右前方 / 右手边 / 身后。
  // 只有四档（再加镜像）：小朋友听的方位越少越记得住，「右后方」和「右手边」都得先转身，区分它没有意义。
  function directionOf(angle) {
    if (typeof angle !== 'number' || isNaN(angle)) return '正前方';
    var a = Math.abs(angle);
    if (a <= FRONT) return '正前方';
    if (a <= SIDE_EDGE) return angle > 0 ? '右前方' : '左前方';
    if (a <= BEHIND_EDGE) return angle > 0 ? '右手边' : '左手边';
    return '身后';
  }

  // 个位数整米不念小数点：「在 2 米外」比「在 2.0 米外」更像人话
  function spokenMeters(value) {
    var rounded = Math.round(value * 10) / 10;
    return String(rounded).replace(/\.0$/, '');
  }

  function fallbackBounds() {
    return { minX: -4.19, maxX: 7.65, minZ: -3.19, maxZ: 3.19 };
  }

  class WalkCamera {
    // scene：RoomExperience 实例；options.spawns 来自 WordRoomLayout.spawns（{ x, z, yaw, room }）
    constructor(scene, options) {
      this.scene = scene;
      this.options = options || {};
      this.bounds = fallbackBounds();
      this.obstacles = [];
      this.walk = { x: DEFAULT_SPAWN.x, z: DEFAULT_SPAWN.z, y: EYE.stand };
      this.yaw = DEFAULT_SPAWN.yaw;
      this.pitch = PITCH_START;
      this.targetYaw = this.yaw;
      this.targetPitch = this.pitch;
      this.eyeMode = 'stand';
      this.range = RANGE.value;
      this.targetRange = RANGE.value;
      this.moving = false;
      this.obstaclesReady = false;
      this.keys = { forward: false, back: false, left: false, right: false };
      this.bobPhase = 0;
      this.reducedMotion = Boolean(global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches);
    }

    // 用可点物品的碰撞盒推出世界坐标 AABB：家具、隔墙、门框都算墙。
    // 挂墙装饰（画、钟、空调）底边在 1.2m 以上，挡不到膝盖，跳过。
    setColliders(hitboxes) {
      var items = hitboxes || [];
      if (!items.length) return;
      this.scene.root.updateMatrixWorld(true);
      var obstacles = [];
      for (var i = 0; i < items.length; i += 1) {
        var mesh = items[i];
        if (!mesh || !mesh.userData) continue;
        // 碰撞盒自身就是长方体，直接算 8 个角点的包围盒，比 setFromObject 遍历子节点快得多
        var bounds = this.worldBox(mesh);
        if (!bounds || bounds.minY > HIGH_PROPS) continue;
        // 门槛石、踢脚线这些贴地薄片不挡路：跨过去就是
        if (bounds.maxY - bounds.minY < THIN_LOW) continue;
        // 地毯、地垫顶面才十几厘米，踩上去就行，别当成墙
        if (bounds.maxY <= STEP_OVER) continue;
        obstacles.push(bounds);
      }
      this.obstacles = obstacles;
      this.obstaclesReady = true;
    }

    worldBox(mesh) {
      var geometry = mesh.geometry;
      if (!geometry || !geometry.boundingBox) {
        if (!geometry || !geometry.computeBoundingBox) return null;
        geometry.computeBoundingBox();
      }
      var bb = geometry.boundingBox;
      if (!bb) return null;
      var m = mesh.matrixWorld.elements;
      var minX = Infinity;
      var maxX = -Infinity;
      var minZ = Infinity;
      var maxZ = -Infinity;
      var minY = Infinity;
      var maxY = -Infinity;
      for (var c = 0; c < 8; c += 1) {
        var x = (c & 1) ? bb.max.x : bb.min.x;
        var y = (c & 2) ? bb.max.y : bb.min.y;
        var z = (c & 4) ? bb.max.z : bb.min.z;
        var wx = m[0] * x + m[4] * y + m[8] * z + m[12];
        var wy = m[1] * x + m[5] * y + m[9] * z + m[13];
        var wz = m[2] * x + m[6] * y + m[10] * z + m[14];
        if (wx < minX) minX = wx;
        if (wx > maxX) maxX = wx;
        if (wy < minY) minY = wy;
        if (wy > maxY) maxY = wy;
        if (wz < minZ) minZ = wz;
        if (wz > maxZ) maxZ = wz;
      }
      return { minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, minY: minY, maxY: maxY };
    }

    // spawn 来自 WordRoomLayout.spawns（room-layout.js）。落点先夹回这间房的可行走区域，再避开家具。
    place(spawn) {
      var point = spawn || DEFAULT_SPAWN;
      var frame = global.WordRoomModels && global.WordRoomModels.rooms && global.WordRoomModels.rooms[point.room];
      this.bounds = (frame && frame.bounds) || fallbackBounds();
      var inset = this.inset();
      var x = clamp(point.x, this.bounds.minX + inset, this.bounds.maxX - inset);
      var z = clamp(point.z, this.bounds.minZ + inset, this.bounds.maxZ - inset);
      var safe = this.pushOut(x, z, x, z);
      // 出生点正好压在家具上（户型改了、家具挪了）：推出去可能被推进另一件家具里，
      // 再在房间里找最近的空地。只在进门时跑一次，不计入每帧开销。
      if (!this.isFree(safe.x, safe.z)) safe = this.nearestFree(safe.x, safe.z);
      this.walk.x = safe.x;
      this.walk.z = safe.z;
      this.walk.y = this.eyeHeight();
      // 朝向照出生点原样：出生点本来就在家具外，被推开的距离通常只有几厘米，
      // 按「从哪儿被推过来」再转一次头，反而会让第一次报的方位和画面里的房间对不上
      this.yaw = typeof point.yaw === 'number' ? wrapAngle(point.yaw) : DEFAULT_SPAWN.yaw;
      this.targetYaw = this.yaw;
      this.pitch = PITCH_START;
      this.targetPitch = PITCH_START;
      this.moving = false;
      this.bobPhase = 0;
      this.apply(0);
    }

    inset() {
      // 东翼卧室只有约 4.4 m 宽，固定 0.42 m 的墙距会吃掉太多空间，按房间大小缩一点
      var b = this.bounds;
      return Math.min(WALK_INSET, Math.max(0.22, Math.min(b.maxX - b.minX, b.maxZ - b.minZ) * 0.12));
    }

    eyeHeight() {
      return this.eyeMode === 'crouch' ? EYE.crouch : EYE.stand;
    }

    setEyeMode(mode) {
      this.eyeMode = mode === 'crouch' ? 'crouch' : 'stand';
      return this.eyeMode;
    }

    setRange(meters) {
      this.targetRange = clamp(Number(meters) || RANGE.value, RANGE.min, RANGE.max);
      return this.targetRange;
    }

    // 立刻把平滑值对齐到目标值：进门、换房间时用，避免镜头从上一处滑过来
    snap() {
      this.yaw = this.targetYaw;
      this.pitch = this.targetPitch;
      this.range = this.targetRange;
      this.walk.y = this.eyeHeight();
      this.bobPhase = 0;
      this.apply(0);
    }

    // 拖动环顾：和轨道相机的方向一致（往左拖，眼前的房间往右转）
    look(dx, dy) {
      this.targetYaw = wrapAngle(this.targetYaw - dx * LOOK_X);
      this.targetPitch = clamp(this.targetPitch - dy * LOOK_Y, -PITCH_LIMIT, PITCH_LIMIT);
    }

    // 屏幕上的「按住前进」
    press(active) {
      this.moving = Boolean(active);
    }

    // 一口气松开所有输入：切后台、弹层挡住画面、指针丢了——都别让相机自己往前飘
    stopInput() {
      this.moving = false;
      this.keys.forward = false;
      this.keys.back = false;
      this.keys.left = false;
      this.keys.right = false;
    }

    // 键盘：WASD 可以叠加（斜着走）
    keyMove(dx, dz) {
      if (dz > 0) this.keys.forward = true;
      if (dz < 0) this.keys.back = true;
      if (dx > 0) this.keys.right = true;
      if (dx < 0) this.keys.left = true;
    }

    keyRelease(key) {
      if (key === 'w') this.keys.forward = false;
      else if (key === 's') this.keys.back = false;
      else if (key === 'a') this.keys.left = false;
      else if (key === 'd') this.keys.right = false;
    }

    // 前后轴：+1 向前；左右轴：+1 向右（屏幕方向，不是 +x）
    keyAxis() {
      return {
        forward: (this.keys.forward ? 1 : 0) - (this.keys.back ? 1 : 0),
        right: (this.keys.right ? 1 : 0) - (this.keys.left ? 1 : 0)
      };
    }

    // dt 秒；返回这一帧脚底移动的距离（用来驱动走路晃动和 onFrame 的 moving 标记）
    update(dt) {
      dt = Math.max(0, Math.min(0.05, dt || 0));
      var ease = this.reducedMotion ? 1 : 1 - Math.exp(-dt * 10);
      this.yaw = wrapAngle(this.yaw + wrapAngle(this.targetYaw - this.yaw) * ease);
      this.pitch += (this.targetPitch - this.pitch) * ease;
      this.range += (this.targetRange - this.range) * ease;
      this.walk.y += (this.eyeHeight() - this.walk.y) * Math.min(1, dt * 9);

      var fromX = this.walk.x;
      var fromZ = this.walk.z;
      var axis = this.keyAxis();
      // 按着「前进」按钮时按钮优先；S 要能退（axis.forward 是 -1，不能拿 Math.max 夹成 0）
      var forwardInput = this.moving ? 1 : axis.forward;
      if ((forwardInput || axis.right) && dt > 0) {
        this.move(SPEED * dt * forwardInput, SPEED * dt * axis.right);
      }
      var moved = Math.hypot(this.walk.x - fromX, this.walk.z - fromZ);

      if (moved > 1e-4) this.bobPhase += moved * 5.2;
      else this.bobPhase *= Math.max(0, 1 - dt * 6);
      this.apply(moved / Math.max(dt, 1e-3));
      return moved;
    }

    // 前后 + 左右（屏幕向右为正）：分轴推进，正面撞家具时还能顺着侧面滑过去，不会一头卡死
    move(forward, strafe) {
      // 斜着走（前后 + 左右同时按）不能比直着走快：两轴各降 1/√2，合成速度还是 SPEED
      if (forward && strafe) {
        forward *= Math.SQRT1_2;
        strafe *= Math.SQRT1_2;
      }
      var sinYaw = Math.sin(this.yaw);
      var cosYaw = Math.cos(this.yaw);
      var dx = sinYaw * forward + cosYaw * strafe;
      var dz = cosYaw * forward - sinYaw * strafe;
      var next = this.pushOut(this.walk.x + dx, this.walk.z, this.walk.x, this.walk.z);
      next = this.pushOut(next.x, next.z + dz, next.x, next.z);
      this.walk.x = next.x;
      this.walk.z = next.z;
    }

    // 把脚底从家具盒里推出去（挑最近的一条边推）；fromX / fromZ 是上一步的位置，
    // 用来在「刚好在边上」时保持原来的倾向，避免在角落来回抖
    pushOut(x, z, fromX, fromZ) {
      var inset = this.inset();
      x = clamp(x, this.bounds.minX + inset, this.bounds.maxX - inset);
      z = clamp(z, this.bounds.minZ + inset, this.bounds.maxZ - inset);
      for (var i = 0; i < this.obstacles.length; i += 1) {
        var o = this.obstacles[i];
        var minX = o.minX - RADIUS;
        var maxX = o.maxX + RADIUS;
        var minZ = o.minZ - RADIUS;
        var maxZ = o.maxZ + RADIUS;
        if (x <= minX || x >= maxX || z <= minZ || z >= maxZ) continue;
        var pushLeft = x - minX;
        var pushRight = maxX - x;
        var pushBack = z - minZ;
        var pushFront = maxZ - z;
        var best = Math.min(pushLeft, pushRight, pushBack, pushFront);
        if (best === pushLeft) x = fromX <= minX + 1e-3 || pushLeft <= pushRight ? minX : maxX;
        else if (best === pushRight) x = maxX;
        else if (best === pushBack) z = minZ;
        else z = maxZ;
      }
      return { x: x, z: z };
    }

    // 这个点站得下吗：墙内收 + 不压任何家具（和 pushOut 用同一套半径）
    isFree(x, z) {
      var inset = this.inset();
      if (x < this.bounds.minX + inset || x > this.bounds.maxX - inset) return false;
      if (z < this.bounds.minZ + inset || z > this.bounds.maxZ - inset) return false;
      for (var i = 0; i < this.obstacles.length; i += 1) {
        var o = this.obstacles[i];
        if (x > o.minX - RADIUS && x < o.maxX + RADIUS && z > o.minZ - RADIUS && z < o.maxZ + RADIUS) return false;
      }
      return true;
    }

    // 房间里离 (x, z) 最近的一块空地：0.2m 网格扫一遍，只在出生点被占时用
    nearestFree(x, z) {
      var inset = this.inset();
      var best = null;
      var bestDistance = Infinity;
      for (var gx = this.bounds.minX + inset; gx <= this.bounds.maxX - inset; gx += 0.2) {
        for (var gz = this.bounds.minZ + inset; gz <= this.bounds.maxZ - inset; gz += 0.2) {
          if (!this.isFree(gx, gz)) continue;
          var distance = Math.hypot(gx - x, gz - z);
          if (distance < bestDistance) {
            bestDistance = distance;
            best = { x: gx, z: gz };
          }
        }
      }
      return best || { x: x, z: z };
    }

    apply(speed) {
      var cam = this.scene.camera;
      var bob = 0;
      if (!this.reducedMotion && speed > 0.05) bob = Math.sin(this.bobPhase) * 0.012;
      cam.position.set(this.walk.x, this.walk.y + bob, this.walk.z);
      var cp = Math.cos(this.pitch);
      cam.lookAt(
        this.walk.x + Math.sin(this.yaw) * cp,
        this.walk.y + bob + Math.sin(this.pitch),
        this.walk.z + Math.cos(this.yaw) * cp
      );
    }

    // 标签距离：水平距离（抬头看空调、低头看地毯都不该让标签乱跳）
    distanceTo(point) {
      if (!point) return Infinity;
      return Math.hypot(point.x - this.walk.x, point.z - this.walk.z);
    }

    // 目标在视野里的水平偏角：0 = 正前方，正数 = 右边，±PI = 身后。
    // 用平滑后的 yaw（不是 targetYaw），拖到一半停下时报的就是你真正看到的方向。
    bearing(point) {
      if (!point) return null;
      var dx = point.x - this.walk.x;
      var dz = point.z - this.walk.z;
      if (Math.abs(dx) < 1e-6 && Math.abs(dz) < 1e-6) return 0;
      return wrapAngle(Math.atan2(dx, dz) - this.yaw);
    }

    // 朝向文字：正前方 / 左前方 / 右前方 / 左手边 / 右手边 / 身后
    direction(angle) {
      return directionOf(angle);
    }

    // 语音用的一句话：距离分三档（就在手边 / N 米外 / 房间另一头），
    // 距离远时先说方位（先把头转对），很近时先说「就在手边」。
    // point 是世界坐标；lift 是这件东西相对眼睛高多少（米，可省），正数在上面。
    describe(point, lift) {
      if (!point) return '';
      var angle = this.bearing(point);
      var where = this.direction(angle);
      var distance = this.distanceTo(point);
      // 判定用原始数值：距离正好 1.7 米时，±20° 的边界也走同一套比较，
      // 免得格式化后的「1.7」和阈值比较出现一半进一半出的情况
      var near = distance < NEAR_SPOT;
      var far = distance > FAR_SPOT;
      var parts = [];
      var place = '';
      if (near) place = '就在手边';
      else if (far) place = '在房间另一头';
      else place = '在' + spokenMeters(distance) + '米外';
      if (place === '就在手边') parts.push(place + '，' + where);
      else parts.push(where + '，' + place);
      // 高低只在远处值得提：贴身的东西人已经在跟前，一句「空调，就在手边」就够，
      // 再加「要抬头看」反而像在念说明。超过 HIGH 才说，免得把每句话都拖长。
      if (typeof lift === 'number' && !near) {
        if (lift > HIGH) parts.push('要抬头看');
        else if (lift < -HIGH) parts.push('要低头找');
      }
      return parts.join('，');
    }

    isMoving() {
      var axis = this.keyAxis();
      return (
        this.moving ||
        axis.forward !== 0 ||
        axis.right !== 0 ||
        Math.abs(wrapAngle(this.targetYaw - this.yaw)) > 1e-4 ||
        Math.abs(this.targetPitch - this.pitch) > 1e-4
      );
    }
  }

  global.WordRoomWalk = {
    WalkCamera: WalkCamera,
    EYE: EYE,
    RANGE: RANGE,
    SPEED: SPEED,
    direction: directionOf,
    // near：清楚；middle：半透明（还没走到跟前）；hidden：超出「看见多远」，先藏起来
    labelTier: function (distance, meters) {
      if (!(distance <= meters)) return 'hidden';
      return distance > meters * RANGE_FAR ? 'middle' : 'near';
    }
  };
})(typeof window !== 'undefined' ? window : globalThis);
