/* Three.js 场景控制器：渲染、受限轨道相机、Raycast 拾取、悬停/选中高亮。 */
(function () {
  'use strict';

  const THREE = window.THREE;
  // 房间尺寸由模型层给出（客餐厅 8m + 厨房 3.8m），相机取景跟着走。
  const BOUNDS = (window.WordRoomModels && window.WordRoomModels.bounds) || {
    centerX: 0,
    halfWidth: 4.35,
    halfDepth: 3.2
  };
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

      this.orbit = {
        theta: 0.79,
        phi: 0.85,
        radius: 15.5,
        target: new THREE.Vector3(BOUNDS.centerX + 0.12, 0.86, 0.05)
      };
      this.desired = {
        theta: this.orbit.theta,
        phi: this.orbit.phi,
        radius: this.orbit.radius,
        target: this.orbit.target.clone()
      };
      this.currentTarget = this.orbit.target.clone();
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
      this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, window.innerWidth < 760 ? 1.65 : 2));
      this.renderer.outputColorSpace = THREE.SRGBColorSpace;
      // ACES 会把这种高亮柔和的场景压成灰白，Neutral 保留彩度。
      this.renderer.toneMapping = THREE.NeutralToneMapping;
      this.renderer.toneMappingExposure = 1.05;
      this.renderer.shadowMap.enabled = true;
      this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

      this.scene = new THREE.Scene();
      this.camera = new THREE.PerspectiveCamera(38, 1, 0.1, 60);

      this.addLights();

      const root = new THREE.Group();
      root.name = 'ROOM_ROOT';
      this.scene.add(root);
      this.root = root;

      const built = window.WordRoomModels.buildRoom(root);
      this.objects = built.objects;
      this.hitboxes = built.hitboxes;

      this.prepareObjects();
      this.resize();
      this.snapCamera();
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

      this.canvas.addEventListener('pointerdown', this.onPointerDown);
      this.canvas.addEventListener('pointermove', this.onPointerMove);
      this.canvas.addEventListener('pointerup', this.onPointerUp);
      this.canvas.addEventListener('pointercancel', this.onPointerCancel);
      this.canvas.addEventListener('pointerleave', this.onPointerLeave);
      this.canvas.addEventListener('wheel', this.onWheel, { passive: false });
      this.canvas.addEventListener('keydown', this.onKeyDown);

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
      this.currentTarget.copy(this.orbit.target);
      const sinPhi = Math.sin(this.orbit.phi);
      this.camera.position.set(
        this.orbit.target.x + this.orbit.radius * sinPhi * Math.sin(this.orbit.theta),
        this.orbit.target.y + this.orbit.radius * Math.cos(this.orbit.phi),
        this.orbit.target.z + this.orbit.radius * sinPhi * Math.cos(this.orbit.theta)
      );
      this.camera.lookAt(this.currentTarget);
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
      return { min: Math.max(5.4, fit * 0.36), max: fit * 1.14 };
    }

    fitRadius() {
      const fov = (this.camera.fov * Math.PI) / 180;
      const tan = Math.tan(fov / 2);
      const aspect = Math.max(0.5, this.camera.aspect || 1);
      const halfWidth = BOUNDS.halfWidth || 4.35;
      const halfDepth = BOUNDS.halfDepth || 3.2;
      const widthFit = halfWidth / (tan * aspect);
      const heightFit = (halfDepth * 1.2) / tan;
      return clamp(Math.max(12.3, widthFit * 1.13, heightFit), 12.3, 34);
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
        const id = intersects[i].object.userData.objectId;
        if (id && this.byId.has(id)) return id;
      }
      return null;
    }

    handlePointerDown(event) {
      if (event.button !== undefined && event.button !== 0 && event.pointerType === 'mouse') return;
      this.pointers.set(event.pointerId, {
        x: event.clientX,
        y: event.clientY,
        startX: event.clientX,
        startY: event.clientY
      });
      this.canvas.setPointerCapture?.(event.pointerId);
      this.gestureMoved = false;
      this.canvas.classList.add('is-dragging');

      if (this.pointers.size === 1) {
        this.drag = {
          id: event.pointerId,
          lastX: event.clientX,
          lastY: event.clientY,
          startX: event.clientX,
          startY: event.clientY,
          startTime: performance.now(),
          moved: 0
        };
        this.pinch = null;
      } else if (this.pointers.size === 2) {
        const points = Array.from(this.pointers.values());
        this.pinch = {
          distance: Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y),
          radius: this.desired.radius
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
        return;
      }

      if (this.drag && this.drag.id === event.pointerId) {
        const dx = event.clientX - this.drag.lastX;
        const dy = event.clientY - this.drag.lastY;
        this.drag.lastX = event.clientX;
        this.drag.lastY = event.clientY;
        this.drag.moved += Math.abs(dx) + Math.abs(dy);
        if (this.drag.moved > 4) this.gestureMoved = true;

        this.desired.theta = clamp(this.desired.theta - dx * 0.006, 0.18, 1.4);
        this.desired.phi = clamp(this.desired.phi + dy * 0.0048, 0.64, 1.24);
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
          startX: remaining[1].startX,
          startY: remaining[1].startY,
          startTime: performance.now(),
          moved: 99
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
      if (event.key === 'ArrowLeft') this.desired.theta = clamp(this.desired.theta - step, 0.18, 1.4);
      else if (event.key === 'ArrowRight') this.desired.theta = clamp(this.desired.theta + step, 0.18, 1.4);
      else if (event.key === 'ArrowUp') this.desired.phi = clamp(this.desired.phi - step, 0.64, 1.24);
      else if (event.key === 'ArrowDown') this.desired.phi = clamp(this.desired.phi + step, 0.64, 1.24);
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

      if (box.min.y < 0.55 && Math.max(size.x, size.z) < 4.2) {
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
        const ringY = box.max.y < 0.18 ? box.max.y + 0.012 : 0.062;
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

    resetView() {
      this.autoFit = true;
      this.desired.theta = 0.79;
      this.desired.phi = 0.93;
      this.desired.radius = this.fitRadius();
      this.desired.target.set(0, 0.86, 0.05);
    }

    getLabelAnchors() {
      const rect = this.canvas.getBoundingClientRect();
      const width = rect.width;
      const height = rect.height;
      const anchors = [];
      this.objects.forEach((group) => {
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
      const ease = this.reducedMotion ? 1 : 1 - Math.exp(-dt * 8.5);

      this.orbit.theta += (this.desired.theta - this.orbit.theta) * ease;
      this.orbit.phi += (this.desired.phi - this.orbit.phi) * ease;
      this.orbit.radius += (this.desired.radius - this.orbit.radius) * ease;
      this.orbit.target.lerp(this.desired.target, ease);
      this.currentTarget.lerp(this.orbit.target, ease);

      const sinPhi = Math.sin(this.orbit.phi);
      const targetPosition = this.tmpVec.set(
        this.orbit.target.x + this.orbit.radius * sinPhi * Math.sin(this.orbit.theta),
        this.orbit.target.y + this.orbit.radius * Math.cos(this.orbit.phi),
        this.orbit.target.z + this.orbit.radius * sinPhi * Math.cos(this.orbit.theta)
      );

      this.camera.position.lerp(targetPosition, this.reducedMotion ? 1 : 1 - Math.exp(-dt * 9));
      this.camera.lookAt(this.currentTarget);

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

      this.renderer.render(this.scene, this.camera);
      this.options.onFrame?.();
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
