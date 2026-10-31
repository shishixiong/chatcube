/* Three.js 场景控制器：渲染、受限轨道相机、Raycast 拾取、悬停/选中高亮。 */
(function () {
  'use strict';

  const THREE = window.THREE;
  // 每间房一份取景参数（全屋 16.8m × 8.9m；主屋 11.8m × 6m 含开放厨房，
  // 东翼两间卧室各约 4.5m × 3.6m，南侧生活阳台 6.6m × 2.4m）。
  // 四间房摆在同一套世界坐标里，overview 全部显示，单间模式只显示当前房间。
  const FALLBACK_FRAME = {
    bounds: { minX: -4.35, maxX: 4.35, minZ: -3.2, maxZ: 3.2, centerX: 0, halfWidth: 4.35, halfDepth: 3.2 },
    target: { x: 0.12, y: 0.86, z: 0.05 },
    fitMin: 12.3,
    fitMax: 34,
    zoomMin: 2.2,
    panInsetX: 1.7,
    panInsetZ: 1.3
  };
  const FRAMES = (window.WordRoomModels && window.WordRoomModels.rooms) || { main: FALLBACK_FRAME };
  const DEFAULT_ROOM = 'overview';
  const PHI_MIN = 0.38;
  const PHI_MAX = 1.22;

  function wrapAngle(angle) {
    return Math.atan2(Math.sin(angle), Math.cos(angle));
  }

  function shortestAngle(delta) {
    return Math.atan2(Math.sin(delta), Math.cos(delta));
  }

  function frameOf(roomId) {
    return FRAMES[roomId] || FRAMES[DEFAULT_ROOM] || FALLBACK_FRAME;
  }
  const ACCENT = new THREE.Color('#2f9d80');
  const WARM = new THREE.Color('#f3b56a');

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function computeVisualBox(group) {
    const box = new THREE.Box3();
    group.updateWorldMatrix(true, true);
    group.traverse((node) => {
      if (!node.isMesh || node.userData.isHitbox || !node.visible || !node.geometry) return;
      if (!node.geometry.boundingBox) node.geometry.computeBoundingBox();
      if (!node.geometry.boundingBox) return;
      const temp = node.geometry.boundingBox.clone().applyMatrix4(node.matrixWorld);
      box.union(temp);
    });
    return box;
  }

  class RoomExperience {
    constructor(canvas, options) {
      this.canvas = canvas;
      this.options = options || {};
      this.stage = canvas.parentElement;
      this.objects = [];
      this.hitboxes = [];
      this.byId = new Map();
      this.selected = null;
      this.hovered = null;
      this.outline = null;
      this.outlineMeshes = [];
      this.outlineRing = null;
      this.destroyed = false;
      this.autoFit = true;
      this.reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      this.pointers = new Map();
      this.drag = null;
      this.pinch = null;
      this.gestureMoved = false;
      this.raycaster = new THREE.Raycaster();
      this.pointerNdc = new THREE.Vector2();
      this.lastFrame = performance.now();
      this.tmpVec = new THREE.Vector3();

      this.activeRoom = DEFAULT_ROOM;
      this.activeArea = null;
      this.frame = frameOf(DEFAULT_ROOM);
      this.roomGroups = {};
      this.roomObjects = {};
      this.roomHitboxes = {};
      const start = this.frame.target;
      this.orbit = {
        theta: 0.79,
        phi: 0.85,
        radius: 15.5,
        target: new THREE.Vector3(start.x, start.y, start.z)
      };
      this.desired = {
        theta: this.orbit.theta,
        phi: this.orbit.phi,
        radius: this.orbit.radius,
        target: this.orbit.target.clone()
      };
      this.spinTheta = 0;
      this.spinPhi = 0;
      this.lastLabelFrame = 0;

      this.init();
    }

    init() {
      const canvas = this.canvas;
      this.renderer = new THREE.WebGLRenderer({
        canvas,
        antialias: true,
        alpha: true,
        powerPreference: 'high-performance'
      });
      this.renderer.setClearColor(0x000000, 0);
      this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, window.innerWidth < 760 ? 1.4 : 2));
      this.renderer.outputColorSpace = THREE.SRGBColorSpace;
      // ACES 会把这种高亮柔和的场景压成灰白，Neutral 保留彩度。
      this.renderer.toneMapping = THREE.NeutralToneMapping;
      this.renderer.toneMappingExposure = 1.05;
      this.renderer.shadowMap.enabled = true;
      this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

      this.scene = new THREE.Scene();
      this.camera = new THREE.PerspectiveCamera(38, 1, 0.1, 120);

      this.addLights();

      const root = new THREE.Group();
      root.name = 'ROOM_ROOT';
      this.scene.add(root);
      this.root = root;

      const models = window.WordRoomModels;
      const createRoomGroup = (roomId, name) => {
        const group = new THREE.Group();
        group.name = name;
        group.userData.room = roomId;
        group.visible = true;
        root.add(group);
        this.roomGroups[roomId] = group;
        return group;
      };

      const mainGroup = createRoomGroup('main', 'ROOM_MAIN');
      const childGroup = createRoomGroup('child', 'ROOM_CHILD');
      const masterGroup = createRoomGroup('master', 'ROOM_MASTER');
      const balconyGroup = createRoomGroup('balcony', 'ROOM_BALCONY');

      const builtMain = models.buildRoom(mainGroup);
      const builtBeds = models.buildBedrooms(childGroup, masterGroup);
      const builtBalcony = models.buildBalcony(balconyGroup);

      Object.keys(models.offsets).forEach((id) => {
        const off = models.offsets[id];
        this.roomGroups[id].position.set(off.x, 0, off.z);
      });

      this.roomObjects.main = builtMain.objects;
      this.roomObjects.child = builtBeds.objects.filter((group) => group.userData.room === 'child');
      this.roomObjects.master = builtBeds.objects.filter((group) => group.userData.room === 'master');
      this.roomObjects.balcony = builtBalcony.objects;
      this.roomObjects.overview = this.roomObjects.main
        .concat(this.roomObjects.child, this.roomObjects.master, this.roomObjects.balcony);
      // 拾取盒都挂在各自物品 Group 下，房间归属直接读 Group 的 userData.room
      this.roomHitboxes.main = builtMain.hitboxes;
      this.roomHitboxes.child = builtBeds.hitboxes.filter((mesh) => mesh.parent.userData.room === 'child');
      this.roomHitboxes.master = builtBeds.hitboxes.filter((mesh) => mesh.parent.userData.room === 'master');
      this.roomHitboxes.balcony = builtBalcony.hitboxes;
      this.roomHitboxes.overview = this.roomHitboxes.main
        .concat(this.roomHitboxes.child, this.roomHitboxes.master, this.roomHitboxes.balcony);

      this.objects = this.roomObjects.overview;
      this.hitboxes = this.roomHitboxes.overview;

      this.prepareObjects();
      this.collectWalls();
      this.resize();
      this.snapCamera();
      this.updateShadowFrustum();
      this.bindEvents();
      this.startAnimation();
      this.options.onReady?.();
    }

    addLights() {
      const hemi = new THREE.HemisphereLight(
        new THREE.Color().setRGB(1.0, 0.96, 0.87, THREE.LinearSRGBColorSpace),
        new THREE.Color().setRGB(0.63, 0.72, 0.68, THREE.LinearSRGBColorSpace),
        0.85
      );
      this.scene.add(hemi);

      const key = new THREE.DirectionalLight(
        new THREE.Color().setRGB(1.0, 0.91, 0.77, THREE.LinearSRGBColorSpace),
        1.45
      );
      key.position.set(6.5, 9.5, 7.5);
      key.castShadow = true;
      key.shadow.mapSize.set(window.innerWidth < 760 ? 1024 : 2048, window.innerWidth < 760 ? 1024 : 2048);
      key.shadow.camera.left = -7;
      key.shadow.camera.right = 7;
      key.shadow.camera.top = 7;
      key.shadow.camera.bottom = -7;
      key.shadow.camera.near = 0.5;
      key.shadow.camera.far = 28;
      key.shadow.bias = -0.0004;
      key.shadow.normalBias = 0.022;
      key.target.position.set(0, 0.8, 0);
      this.scene.add(key);
      this.scene.add(key.target);
      this.keyLight = key;

      const fill = new THREE.DirectionalLight(
        new THREE.Color().setRGB(0.78, 0.9, 1.0, THREE.LinearSRGBColorSpace),
        0.38
      );
      fill.position.set(-6, 6, 6);
      this.scene.add(fill);

      const backFill = new THREE.DirectionalLight(
        new THREE.Color().setRGB(1.0, 0.83, 0.7, THREE.LinearSRGBColorSpace),
        0.20
      );
      backFill.position.set(1.5, 5, -5);
      this.scene.add(backFill);
    }

    prepareObjects() {
      this.root.updateMatrixWorld(true);
      this.objects.forEach((group) => {
        const clones = new Map();
        group.traverse((node) => {
          if (!node.isMesh || node.userData.isHitbox) return;
          if (Array.isArray(node.material)) {
            node.material = node.material.map((mat) => this.cloneObjectMaterial(mat, clones));
          } else {
            node.material = this.cloneObjectMaterial(node.material, clones);
          }
        });

        group.userData.materials = Array.from(clones.values());
        group.userData.visualBox = computeVisualBox(group);
        const box = group.userData.visualBox;
        const center = box.getCenter(new THREE.Vector3());
        let anchor;
        if (group.userData.labelAnchorLocal) {
          anchor = group.localToWorld(group.userData.labelAnchorLocal.clone());
        } else {
          anchor = new THREE.Vector3(center.x, box.max.y + 0.13, center.z);
        }
        group.userData.labelAnchor = anchor;
        this.byId.set(group.userData.objectId, group);
      });
    }

    cloneObjectMaterial(source, clones) {
      if (!source) return source;
      if (clones.has(source)) return clones.get(source);
      const mat = source.clone();
      mat.userData = { ...source.userData };
      if (mat.emissive) {
        mat.userData.baseEmissive = mat.emissive.clone();
        mat.userData.baseEmissiveIntensity = mat.emissiveIntensity || 0;
      }
      mat.userData.baseColor = mat.color ? mat.color.clone() : null;
      clones.set(source, mat);
      return mat;
    }

    bindEvents() {
      this.onPointerDown = this.handlePointerDown.bind(this);
      this.onPointerMove = this.handlePointerMove.bind(this);
      this.onPointerUp = this.handlePointerUp.bind(this);
      this.onPointerCancel = this.handlePointerCancel.bind(this);
      this.onWheel = this.handleWheel.bind(this);
      this.onPointerLeave = this.handlePointerLeave.bind(this);
      this.onKeyDown = this.handleKeyDown.bind(this);
      this.onContextMenu = (event) => event.preventDefault();

      this.canvas.addEventListener('pointerdown', this.onPointerDown);
      this.canvas.addEventListener('pointermove', this.onPointerMove);
      this.canvas.addEventListener('pointerup', this.onPointerUp);
      this.canvas.addEventListener('pointercancel', this.onPointerCancel);
      this.canvas.addEventListener('pointerleave', this.onPointerLeave);
      this.canvas.addEventListener('wheel', this.onWheel, { passive: false });
      this.canvas.addEventListener('keydown', this.onKeyDown);
      this.canvas.addEventListener('contextmenu', this.onContextMenu);

      if ('ResizeObserver' in window) {
        this.resizeObserver = new ResizeObserver(() => this.resize());
        this.resizeObserver.observe(this.stage);
      }
      this.onWindowResize = () => this.resize();
      window.addEventListener('resize', this.onWindowResize);
      this.visibilityHandler = () => {
        if (document.hidden) {
          this.renderer.setAnimationLoop(null);
        } else if (!this.destroyed) {
          this.lastFrame = performance.now();
          this.startAnimation();
        }
      };
      document.addEventListener('visibilitychange', this.visibilityHandler);
    }

    startAnimation() {
      this.renderer.setAnimationLoop(() => this.animate());
    }

    snapCamera() {
      this.orbit.radius = this.desired.radius;
      this.orbit.theta = this.desired.theta;
      this.orbit.phi = this.desired.phi;
      const sinPhi = Math.sin(this.orbit.phi);
      this.camera.position.set(
        this.orbit.target.x + this.orbit.radius * sinPhi * Math.sin(this.orbit.theta),
        this.orbit.target.y + this.orbit.radius * Math.cos(this.orbit.phi),
        this.orbit.target.z + this.orbit.radius * sinPhi * Math.cos(this.orbit.theta)
      );
      this.camera.lookAt(this.orbit.target);
    }

    resize() {
      if (this.destroyed || !this.stage) return;
      const rect = this.stage.getBoundingClientRect();
      const width = Math.max(1, Math.floor(rect.width));
      const height = Math.max(1, Math.floor(rect.height));
      this.renderer.setSize(width, height, false);
      const aspect = width / height;
      this.camera.aspect = aspect;
      this.camera.fov = aspect < 0.92 ? 44 : 38;
      this.camera.updateProjectionMatrix();
      if (this.autoFit) {
        this.desired.radius = this.fitRadius();
        if (this.orbit.radius > this.desired.radius * 1.16) this.orbit.radius = this.desired.radius;
      }
    }

    zoomRange() {
      const fit = this.fitRadius();
      // 0.36 只够看整间房，小物件（杯子、遥控器）要能看到桌面，允许再拉近到全屋取景的约 1/8。
      return { min: Math.max(this.frame.zoomMin, fit * 0.12), max: fit * 1.14 };
    }

    fitRadius() {
      const fov = (this.camera.fov * Math.PI) / 180;
      const tan = Math.tan(fov / 2);
      const aspect = Math.max(0.5, this.camera.aspect || 1);
      const halfWidth = this.frame.bounds.halfWidth || 4.35;
      const halfDepth = this.frame.bounds.halfDepth || 3.2;
      const widthFit = halfWidth / (tan * aspect);
      const heightFit = (halfDepth * 1.2) / tan;
      const scale = this.frame.fitScale || 1;
      return clamp(
        Math.max(this.frame.fitMin, widthFit * 1.13 * scale, heightFit * scale),
        this.frame.fitMin,
        this.frame.fitMax
      );
    }

    // 阴影相机跟着当前取景走：全屋比单间大很多，固定 14m 的盒子会裁掉东翼和阳台。
    updateShadowFrustum() {
      const key = this.keyLight;
      if (!key) return;
      const b = this.frame.bounds;
      const target = this.frame.target;
      key.position.set(target.x + 6.5, 0.8 + 8.7, target.z + 7.5);
      key.target.position.set(target.x, 0.8, target.z);
      key.target.updateMatrixWorld();
      const half = Math.max(b.maxX - b.minX, b.maxZ - b.minZ) / 2 + 2;
      key.shadow.camera.left = -half;
      key.shadow.camera.right = half;
      key.shadow.camera.top = half;
      key.shadow.camera.bottom = -half;
      key.shadow.camera.near = 0.5;
      key.shadow.camera.far = half * 2 + 30;
      key.shadow.camera.updateProjectionMatrix();
    }

    // 每帧按世界中心 + 迟滞更新显隐
    updateWalls() {
      const cam = this.camera.position;
      Object.keys(this.roomGroups).forEach((roomId) => {
        const b = frameOf(roomId).bounds;
        const state = this.wallHidden[roomId];
        if (!state) return;
        const centerZ = b.centerZ ?? (b.minZ + b.maxZ) / 2;
        const centerX = b.centerX ?? (b.minX + b.maxX) / 2;
        state.north = window.WordRoomWalls.nextWallHidden(cam.z, centerZ, state.north);
        state.west = window.WordRoomWalls.nextWallHidden(cam.x, centerX, state.west);

        const selected = this.selected;
        const forceNorth =
          Boolean(selected) && selected.userData.wallSide === 'north' && selected.userData.room === roomId;
        const forceWest =
          Boolean(selected) && selected.userData.wallSide === 'west' && selected.userData.room === roomId;

        this.roomWalls[roomId].north.forEach((mesh) => {
          mesh.visible = !state.north || forceNorth;
        });
        this.roomWalls[roomId].west.forEach((mesh) => {
          mesh.visible = !state.west || forceWest;
        });
        this.wallObjects[roomId].forEach((entry) => {
          entry.group.visible =
            entry.side === 'north' ? !state.north || forceNorth : !state.west || forceWest;
        });
      });
    }

    collectWalls() {
      this.roomWalls = {};
      this.wallObjects = {};
      this.wallHidden = {};
      Object.keys(this.roomGroups).forEach((roomId) => {
        const walls = { north: new Set(), west: new Set() };
        const objects = [];
        this.roomGroups[roomId].traverse((node) => {
          const side = node.userData && node.userData.wallSide;
          if (!side || !walls[side]) return;
          if (node.userData.interactive && node.userData.objectId) {
            objects.push({ group: node, side });
          } else if (node.isMesh) {
            walls[side].add(node);
          }
        });
        this.roomWalls[roomId] = { north: Array.from(walls.north), west: Array.from(walls.west) };
        this.wallObjects[roomId] = objects;
        this.wallHidden[roomId] = { north: false, west: false };
      });
    }

    // 换房间：只切可见性 + 重新取景，几何早就建好了，切换是瞬时的。
    setRoom(roomId) {
      const next = roomId === 'overview' || this.roomGroups[roomId] ? roomId : 'overview';
      if (next === this.activeRoom) {
        this.resetView();
        return this.activeRoom;
      }
      this.activeRoom = next;
      this.activeArea = null;
      this.frame = frameOf(next);
      Object.keys(this.roomGroups).forEach((id) => {
        this.roomGroups[id].visible = next === 'overview' || id === next;
      });
      this.hitboxes = this.roomHitboxes[next] || [];
      this.desired.theta = 0.79;
      this.desired.phi = 0.85;
      this.desired.radius = this.fitRadius();
      this.desired.target.set(this.frame.target.x, this.frame.target.y, this.frame.target.z);
      this.autoFit = true;
      this.spinTheta = 0;
      this.spinPhi = 0;
      this.updateShadowFrustum();
      this.clearOutline();
      this.selected = null;
      this.updateWalls();
      this.hovered = null;
      return this.activeRoom;
    }

    getRoomObjects(roomId) {
      return this.roomObjects[roomId || this.activeRoom] || [];
    }

    setPointer(event) {
      const rect = this.canvas.getBoundingClientRect();
      this.pointerNdc.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      this.pointerNdc.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    }

    pickAt(clientX, clientY) {
      const rect = this.canvas.getBoundingClientRect();
      this.pointerNdc.x = ((clientX - rect.left) / rect.width) * 2 - 1;
      this.pointerNdc.y = -((clientY - rect.top) / rect.height) * 2 + 1;
      this.raycaster.setFromCamera(this.pointerNdc, this.camera);
      const intersects = this.raycaster.intersectObjects(this.hitboxes, false);
      for (let i = 0; i < intersects.length; i += 1) {
        if (!intersects[i].object.parent || intersects[i].object.parent.visible === false) continue;
        const id = intersects[i].object.userData.objectId;
        if (id && this.byId.has(id)) return id;
      }
      return null;
    }

    handlePointerDown(event) {
      const isMouse = event.pointerType === 'mouse';
      if (isMouse && event.button !== 0 && event.button !== 2) return;
      const panIntent = isMouse && (event.button === 2 || (event.button === 0 && event.shiftKey));
      this.pointers.set(event.pointerId, {
        x: event.clientX,
        y: event.clientY,
        startX: event.clientX,
        startY: event.clientY
      });
      this.canvas.setPointerCapture?.(event.pointerId);
      this.gestureMoved = false;
      this.spinTheta = 0;
      this.spinPhi = 0;
      this.canvas.classList.add('is-dragging');

      if (this.pointers.size === 1) {
        this.drag = {
          id: event.pointerId,
          lastX: event.clientX,
          lastY: event.clientY,
          lastMoveTime: performance.now(),
          startX: event.clientX,
          startY: event.clientY,
          startTime: performance.now(),
          moved: 0,
          // 左键/单指旋转；右键或 Shift+左键/双指平移
          pan: panIntent
        };
        this.pinch = null;
      } else if (this.pointers.size === 2) {
        const points = Array.from(this.pointers.values());
        this.pinch = {
          distance: Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y),
          radius: this.desired.radius,
          midX: (points[0].x + points[1].x) / 2,
          midY: (points[0].y + points[1].y) / 2
        };
        this.drag = null;
        this.gestureMoved = true;
      }
    }

    handlePointerMove(event) {
      if (this.pointers.has(event.pointerId)) {
        const pointer = this.pointers.get(event.pointerId);
        pointer.x = event.clientX;
        pointer.y = event.clientY;
      }

      if (this.pointers.size === 2) {
        const points = Array.from(this.pointers.values());
        const distance = Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y);
        if (this.pinch && this.pinch.distance > 10) {
          const zoom = this.zoomRange();
          this.desired.radius = clamp(this.pinch.radius * (this.pinch.distance / Math.max(10, distance)), zoom.min, zoom.max);
          this.autoFit = false;
          this.gestureMoved = true;
        }
        if (this.pinch) {
          const midX = (points[0].x + points[1].x) / 2;
          const midY = (points[0].y + points[1].y) / 2;
          const panX = midX - (this.pinch.midX ?? midX);
          const panY = midY - (this.pinch.midY ?? midY);
          this.pinch.midX = midX;
          this.pinch.midY = midY;
          if (Math.abs(panX) + Math.abs(panY) > 1.5) {
            this.panByPixels(panX, panY);
            this.gestureMoved = true;
          }
        }
        return;
      }

      if (this.drag && this.drag.id === event.pointerId) {
        const dx = event.clientX - this.drag.lastX;
        const dy = event.clientY - this.drag.lastY;
        this.drag.lastX = event.clientX;
        this.drag.lastY = event.clientY;
        this.drag.moved += Math.abs(dx) + Math.abs(dy);
        if (this.drag.moved > 4) this.gestureMoved = true;

        if (this.drag.pan) {
          this.panByPixels(dx, dy);
          this.setHovered(null);
          return;
        }
        const now = performance.now();
        const moveDt = Math.max(0.008, (now - this.drag.lastMoveTime) / 1000);
        this.drag.lastMoveTime = now;
        this.desired.theta = wrapAngle(this.desired.theta - dx * 0.005);
        // 手指上滑 = 视角抬高（原来写反了：上滑会俯视下去）
        this.desired.phi = clamp(this.desired.phi - dy * 0.0028, PHI_MIN, PHI_MAX);
        this.spinTheta = clamp((-dx * 0.005) / moveDt, -3.5, 3.5);
        this.spinPhi = clamp((-dy * 0.0028) / moveDt, -2, 2);
        this.canvas.classList.add('is-dragging');
        this.setHovered(null);
        return;
      }

      if (event.pointerType === 'mouse' || event.pointerType === 'pen') {
        const id = this.pickAt(event.clientX, event.clientY);
        this.setHovered(id, event.clientX, event.clientY);
      }
    }

    handlePointerUp(event) {
      const pointer = this.pointers.get(event.pointerId);
      const wasDragging = this.drag && this.drag.id === event.pointerId;
      const canTap =
        wasDragging &&
        this.drag.moved < 7 &&
        performance.now() - this.drag.startTime < 800 &&
        !this.gestureMoved;

      if (wasDragging) {
        const recent = performance.now() - this.drag.lastMoveTime < 80;
        if (this.drag.moved > 4 && recent) {
          this.spinTheta *= 0.55;
          this.spinPhi *= 0.55;
        } else {
          this.spinTheta = 0;
          this.spinPhi = 0;
        }
      }

      if (pointer) {
        this.canvas.releasePointerCapture?.(event.pointerId);
        this.pointers.delete(event.pointerId);
      }

      if (canTap) {
        const id = this.pickAt(event.clientX, event.clientY);
        this.options.onTap?.(id || null);
      }

      if (this.pointers.size === 1) {
        const remaining = Array.from(this.pointers.entries())[0];
        this.drag = {
          id: remaining[0],
          lastX: remaining[1].x,
          lastY: remaining[1].y,
          lastMoveTime: performance.now(),
          startX: remaining[1].startX,
          startY: remaining[1].startY,
          startTime: performance.now(),
          moved: 99,
          pan: false
        };
        this.pinch = null;
      } else if (this.pointers.size === 0) {
        this.drag = null;
        this.pinch = null;
        this.canvas.classList.remove('is-dragging');
      }
    }

    handlePointerCancel(event) {
      this.pointers.delete(event.pointerId);
      this.drag = null;
      this.pinch = null;
      this.spinTheta = 0;
      this.spinPhi = 0;
      this.canvas.classList.remove('is-dragging');
    }

    handlePointerLeave() {
      if (!this.pointers.size) {
        this.setHovered(null);
        this.canvas.classList.remove('is-dragging');
      }
    }

    handleWheel(event) {
      event.preventDefault();
      const direction = Math.sign(event.deltaY);
      if (!direction) return;
      const zoom = this.zoomRange();
      this.desired.radius = clamp(this.desired.radius * (1 + direction * 0.07), zoom.min, zoom.max);
      this.autoFit = false;
    }

    handleKeyDown(event) {
      const step = 0.07;
      let handled = true;
      if (event.key === 'ArrowLeft') this.desired.theta = wrapAngle(this.desired.theta - step);
      else if (event.key === 'ArrowRight') this.desired.theta = wrapAngle(this.desired.theta + step);
      else if (event.key === 'ArrowUp') this.desired.phi = clamp(this.desired.phi - step, PHI_MIN, PHI_MAX);
      else if (event.key === 'ArrowDown') this.desired.phi = clamp(this.desired.phi + step, PHI_MIN, PHI_MAX);
      else if (event.key === '+' || event.key === '=') {
        const zoom = this.zoomRange();
        this.desired.radius = clamp(this.desired.radius * 0.94, zoom.min, zoom.max);
        this.autoFit = false;
      } else if (event.key === '-' || event.key === '_') {
        const zoom = this.zoomRange();
        this.desired.radius = clamp(this.desired.radius * 1.06, zoom.min, zoom.max);
        this.autoFit = false;
      } else if (event.key === 'r' || event.key === 'R') {
        this.resetView();
      } else {
        handled = false;
      }
      if (handled) event.preventDefault();
    }

    setHovered(id, clientX, clientY) {
      const next = id && this.byId.has(id) ? this.byId.get(id) : null;
      if (next === this.hovered) {
        if (next) this.options.onHover?.(next.userData.objectId, clientX, clientY);
        return;
      }
      if (this.hovered && this.hovered !== this.selected) this.applyGlow(this.hovered, 'base');
      this.hovered = next;
      if (next && next !== this.selected) this.applyGlow(next, 'hover');
      this.canvas.classList.toggle('is-hovering', Boolean(next));
      this.options.onHover?.(next ? next.userData.objectId : null, clientX, clientY);
    }

    applyGlow(group, mode) {
      const mats = group.userData.materials || [];
      mats.forEach((mat) => {
        if (!mat.emissive) return;
        if (mode === 'base') {
          mat.emissive.copy(mat.userData.baseEmissive || new THREE.Color(0x000000));
          mat.emissiveIntensity = mat.userData.baseEmissiveIntensity || 0;
        } else if (mode === 'hover') {
          mat.emissive.copy(WARM);
          mat.emissiveIntensity = 0.13;
        } else {
          mat.emissive.copy(ACCENT);
          mat.emissiveIntensity = 0.34;
        }
      });
    }

    select(id) {
      const group = id ? this.byId.get(id) : null;
      if (this.selected === group) return;
      if (this.selected) this.applyGlow(this.selected, 'base');
      this.clearOutline();
      this.selected = group || null;
      this.updateWalls();

      if (this.selected) {
        this.applyGlow(this.selected, 'selected');
        this.buildOutline(this.selected);
        if (this.hovered && this.hovered !== this.selected) this.applyGlow(this.hovered, 'hover');
        this.options.onSelectionChange?.(this.selected.userData.objectId);
      } else {
        if (this.hovered) this.applyGlow(this.hovered, 'hover');
        this.options.onSelectionChange?.(null);
      }
    }

    buildOutline(group) {
      const outlineGroup = new THREE.Group();
      outlineGroup.name = 'SELECTION_OUTLINE';
      outlineGroup.renderOrder = 2;
      const box = group.userData.visualBox;
      const size = box.getSize(new THREE.Vector3());
      const center = box.getCenter(new THREE.Vector3());

      group.traverse((mesh) => {
        if (!mesh.isMesh || mesh.userData.isHitbox || !mesh.visible) return;
        const mat = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
        if (!mat || (mat.transparent && mat.opacity < 0.55)) return;
        if (mat.isMeshBasicMaterial && mat.map) return;
        if (!mesh.geometry) return;
        const geo = mesh.geometry.clone();
        if (!geo.boundingBox) geo.computeBoundingBox();
        if (!geo.boundingBox) return;
        const c = geo.boundingBox.getCenter(new THREE.Vector3());
        geo.translate(-c.x, -c.y, -c.z);
        geo.scale(1.026, 1.026, 1.026);
        geo.translate(c.x, c.y, c.z);
        const outlineMat = new THREE.MeshBasicMaterial({
          color: ACCENT,
          side: THREE.BackSide,
          transparent: true,
          opacity: 0.76,
          depthWrite: false,
          toneMapped: false
        });
        const outlineMesh = new THREE.Mesh(geo, outlineMat);
        outlineMesh.matrixAutoUpdate = false;
        outlineMesh.matrix.copy(mesh.matrixWorld);
        outlineMesh.renderOrder = 2;
        outlineGroup.add(outlineMesh);
        this.outlineMeshes.push(outlineMesh);
      });

      if (box.min.y <= 1.2 && Math.max(size.x, size.z) < 4.2) {
        // 圆环要贴着物品所在的台面：桌面/床面小物不能画到地板（会被桌子挡住，看起来像选中了桌子）。
        // 高处挂件（空调、海报、镜子等）没有可贴的台面，只保留网格描边。
        let ringY = 0.062;
        if (box.max.y < 0.18) {
          ringY = box.max.y + 0.012;
        } else if (box.min.y > 0.18) {
          ringY = box.min.y + 0.012;
        }
        const radius = Math.max(0.32, Math.max(size.x, size.z) * 0.6);
        const ringGeo = new THREE.RingGeometry(Math.max(0.2, radius - 0.035), radius, 48);
        const ringMat = new THREE.MeshBasicMaterial({
          color: ACCENT,
          transparent: true,
          opacity: 0.75,
          side: THREE.DoubleSide,
          depthWrite: false,
          toneMapped: false
        });
        const ring = new THREE.Mesh(ringGeo, ringMat);
        ring.rotation.x = -Math.PI / 2;
        ring.position.set(center.x, ringY, center.z);
        ring.renderOrder = 2;
        outlineGroup.add(ring);
        this.outlineRing = ring;
      }

      this.outline = outlineGroup;
      this.scene.add(outlineGroup);
    }

    clearOutline() {
      if (!this.outline) return;
      this.scene.remove(this.outline);
      this.outline.traverse((node) => {
        if (node.isMesh) {
          node.geometry.dispose();
          node.material.dispose();
        }
      });
      this.outline = null;
      this.outlineMeshes = [];
      this.outlineRing = null;
    }

    // 把手指位移换算成 target 在房间平面上的位移：1px ≈ 1px（按当前距离和 fov 换算）
    panByPixels(dx, dy) {
      if (!dx && !dy) return;
      const height = this.canvas.clientHeight || 1;
      const fov = (this.camera.fov * Math.PI) / 180;
      const worldPerPixel = (2 * this.orbit.radius * Math.tan(fov / 2)) / height;
      const theta = this.desired.theta;
      const rightX = Math.cos(theta);
      const rightZ = -Math.sin(theta);
      const upX = -Math.sin(theta);
      const upZ = -Math.cos(theta);
      const nextX = this.desired.target.x - rightX * dx * worldPerPixel + upX * dy * worldPerPixel;
      const nextZ = this.desired.target.z - rightZ * dx * worldPerPixel + upZ * dy * worldPerPixel;
      // 留出一点内缩量，别让画面中心跑到墙外变成大片空白
      const b = this.frame.bounds;
      this.desired.target.x = clamp(nextX, b.minX + this.frame.panInsetX, b.maxX - this.frame.panInsetX);
      this.desired.target.z = clamp(nextZ, b.minZ + this.frame.panInsetZ, b.maxZ - this.frame.panInsetZ);
      this.autoFit = false;
    }

    resetView() {
      this.autoFit = true;
      this.spinTheta = 0;
      this.spinPhi = 0;
      this.desired.theta = 0.79;
      this.desired.phi = 0.85;
      this.desired.radius = this.fitRadius();
      this.desired.target.set(this.frame.target.x, this.frame.target.y, this.frame.target.z);
      this.activeArea = null;
    }

    // 客餐厅分区取景（客厅 / 餐厅 / 厨房）：只换环绕中心与距离，保留当前旋转角度。
    // 半径会被 zoomRange() 夹紧，避免和缩放边界打架；autoFit 置 false，窗口 resize 不再抢回全屋取景。
    focusArea(areaId) {
      const areas = this.frame.areas;
      if (!areas || typeof areas !== 'object' || !areas[areaId]) return false;
      const area = areas[areaId];
      if (!area.target) return false;
      const zoom = this.zoomRange();
      this.desired.target.set(area.target.x, area.target.y, area.target.z);
      this.desired.radius = clamp(area.radius, zoom.min, zoom.max);
      this.autoFit = false;
      this.activeArea = areaId;
      return true;
    }

    getLabelAnchors() {
      const rect = this.canvas.getBoundingClientRect();
      const width = rect.width;
      const height = rect.height;
      const anchors = [];
      this.getRoomObjects().forEach((group) => {
        if (!group.visible) return;
        const world = group.userData.labelAnchor;
        if (!world) return;
        const projected = this.tmpVec.copy(world).project(this.camera);
        const visible =
          projected.z > -1 &&
          projected.z < 1 &&
          projected.x > -1.2 &&
          projected.x < 1.2 &&
          projected.y > -1.2 &&
          projected.y < 1.2;
        anchors.push({
          id: group.userData.objectId,
          x: (projected.x * 0.5 + 0.5) * width,
          y: (-projected.y * 0.5 + 0.5) * height,
          depth: projected.z,
          visible
        });
      });
      return anchors;
    }

    animate() {
      if (this.destroyed) return;
      const now = performance.now();
      const dt = Math.min(0.05, Math.max(0, (now - this.lastFrame) / 1000));
      this.lastFrame = now;

      if (!this.pointers.size && (this.spinTheta || this.spinPhi) && !this.reducedMotion) {
        this.desired.theta = wrapAngle(this.desired.theta + this.spinTheta * dt);
        this.desired.phi = clamp(this.desired.phi + this.spinPhi * dt, PHI_MIN, PHI_MAX);
        const decay = Math.exp(-dt * 3.2);
        this.spinTheta *= decay;
        this.spinPhi *= decay;
        if (Math.abs(this.spinTheta) < 0.01 && Math.abs(this.spinPhi) < 0.01) {
          this.spinTheta = 0;
          this.spinPhi = 0;
        }
      }

      const dragging = Boolean(this.drag || this.pinch);
      const rate = this.reducedMotion ? 1 : 1 - Math.exp(-dt * (dragging ? 18 : 6));
      this.orbit.theta = wrapAngle(this.orbit.theta + shortestAngle(this.desired.theta - this.orbit.theta) * rate);
      this.orbit.phi += (this.desired.phi - this.orbit.phi) * rate;
      this.orbit.radius += (this.desired.radius - this.orbit.radius) * rate;
      this.orbit.target.lerp(this.desired.target, rate);

      const sinPhi = Math.sin(this.orbit.phi);
      this.camera.position.set(
        this.orbit.target.x + this.orbit.radius * sinPhi * Math.sin(this.orbit.theta),
        this.orbit.target.y + this.orbit.radius * Math.cos(this.orbit.phi),
        this.orbit.target.z + this.orbit.radius * sinPhi * Math.cos(this.orbit.theta)
      );
      this.camera.lookAt(this.orbit.target);

      if (this.outlineRing) {
        if (this.reducedMotion) {
          this.outlineRing.material.opacity = 0.68;
          this.outlineRing.scale.set(1, 1, 1);
        } else {
          const time = performance.now() * 0.001;
          this.outlineRing.material.opacity = 0.58 + Math.sin(time * 2.6) * 0.14;
          const scale = 1 + Math.sin(time * 2.6) * 0.003;
          this.outlineRing.scale.set(scale, scale, scale);
        }
      }

      const moving =
        Math.abs(shortestAngle(this.desired.theta - this.orbit.theta)) > 1e-4 ||
        Math.abs(this.desired.phi - this.orbit.phi) > 1e-4 ||
        Math.abs(this.desired.radius - this.orbit.radius) > 1e-4 ||
        this.orbit.target.distanceToSquared(this.desired.target) > 1e-6 ||
        Boolean(this.spinTheta || this.spinPhi);

      this.updateWalls();
      this.renderer.render(this.scene, this.camera);
      this.options.onFrame?.(moving);
    }

    destroy() {
      this.destroyed = true;
      this.renderer.setAnimationLoop(null);
      this.resizeObserver?.disconnect();
      window.removeEventListener('resize', this.onWindowResize);
      document.removeEventListener('visibilitychange', this.visibilityHandler);
      this.canvas.removeEventListener('pointerdown', this.onPointerDown);
      this.canvas.removeEventListener('pointermove', this.onPointerMove);
      this.canvas.removeEventListener('pointerup', this.onPointerUp);
      this.canvas.removeEventListener('pointercancel', this.onPointerCancel);
      this.canvas.removeEventListener('pointerleave', this.onPointerLeave);
      this.canvas.removeEventListener('wheel', this.onWheel);
      this.canvas.removeEventListener('keydown', this.onKeyDown);
      this.canvas.removeEventListener('contextmenu', this.onContextMenu);
      this.canvas.classList.remove('is-dragging', 'is-hovering');
      this.clearOutline();
      this.scene.traverse((node) => {
        if (node.isMesh) {
          node.geometry?.dispose();
          if (Array.isArray(node.material)) node.material.forEach((mat) => mat.dispose());
          else node.material?.dispose();
        }
      });
      this.renderer.dispose();
    }
  }

  window.RoomExperience = RoomExperience;
})();
