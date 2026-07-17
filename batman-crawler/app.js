(() => {
  const SIZE = 88;
  const SPEED = 110; // px per second
  const INSET = 4;
  const FACE_EVERY_MS = 4000;
  const FACE_DURATION_MS = 1200;
  const BATARANG_COUNT = 5;
  const BATARANG_SPEED = 520;
  const BATARANG_SPREAD = 0.28; // radians total fan

  const SPRITES = {
    left: "assets/batman-left.png",
    right: "assets/batman-right.png",
    front: "assets/batman-front.png",
  };
  const BATARANG_SRC = "assets/batarang.png";

  const batmanEl = document.getElementById("batman");
  const spriteEl = document.getElementById("batman-sprite");
  const projectilesEl = document.getElementById("projectiles");
  const hintEl = document.querySelector(".hint");

  document.documentElement.style.setProperty("--batman-size", `${SIZE}px`);

  /** @type {'bottom'|'right'|'top'|'left'} */
  let side = "bottom";
  /** Distance along the current side, from the clockwise start. */
  let along = 0;
  /** Clockwise travel. */
  let clockwise = true;

  let facingFront = false;
  let faceTimer = 0;
  let faceHold = 0;
  let firing = false;

  let lastTs = performance.now();
  /** @type {{el: HTMLImageElement, x: number, y: number, vx: number, vy: number, rot: number, spin: number, life: number}[]} */
  const batarangs = [];

  function dims() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const half = SIZE / 2;
    return {
      w,
      h,
      left: INSET + half,
      right: w - INSET - half,
      top: INSET + half,
      bottom: h - INSET - half,
    };
  }

  function sideLength(d, s) {
    if (s === "bottom" || s === "top") return Math.max(1, d.right - d.left);
    return Math.max(1, d.bottom - d.top);
  }

  function positionOnBorder() {
    const d = dims();
    const len = sideLength(d, side);
    along = ((along % len) + len) % len;

    let x;
    let y;
    /** Facing direction of travel as a unit vector. */
    let dirX = 0;
    let dirY = 0;
    /** Extra CSS rotation so feet stay on the outside edge. */
    let edgeRot = 0;

    if (side === "bottom") {
      x = clockwise ? d.left + along : d.right - along;
      y = d.bottom;
      dirX = clockwise ? 1 : -1;
      edgeRot = 0;
    } else if (side === "right") {
      x = d.right;
      y = clockwise ? d.bottom - along : d.top + along;
      dirY = clockwise ? -1 : 1;
      edgeRot = -90;
    } else if (side === "top") {
      x = clockwise ? d.right - along : d.left + along;
      y = d.top;
      dirX = clockwise ? -1 : 1;
      edgeRot = 180;
    } else {
      x = d.left;
      y = clockwise ? d.top + along : d.bottom - along;
      dirY = clockwise ? 1 : -1;
      edgeRot = 90;
    }

    return { x, y, dirX, dirY, edgeRot };
  }

  function advanceSide(distance) {
    const d = dims();
    along += distance;
    let guard = 0;
    while (along >= sideLength(d, side) && guard < 8) {
      along -= sideLength(d, side);
      side = nextSide(side, clockwise);
      guard += 1;
    }
  }

  function nextSide(s, cw) {
    const order = ["bottom", "right", "top", "left"];
    const i = order.indexOf(s);
    return order[cw ? (i + 1) % 4 : (i + 3) % 4];
  }

  function updateSprite(pos) {
    if (facingFront) {
      spriteEl.src = SPRITES.front;
      batmanEl.style.transform = `translate(-50%, -50%) rotate(${pos.edgeRot}deg)`;
      return;
    }

    // Pick left/right based on travel along the visual horizontal of the sprite
    // after edge rotation. For side views, "right" means moving toward sprite's right.
    let useRight;
    if (side === "bottom") {
      useRight = pos.dirX > 0;
    } else if (side === "top") {
      // Upside-down: visual left/right swaps relative to screen X
      useRight = pos.dirX < 0;
    } else if (side === "right") {
      // Rotated -90°: "right" sprite points up the screen when edgeRot applied... 
      // After -90°, the sprite's forward (right in image) maps to up.
      useRight = pos.dirY < 0;
    } else {
      // Left edge +90°: "right" sprite maps to down
      useRight = pos.dirY > 0;
    }

    spriteEl.src = useRight ? SPRITES.right : SPRITES.left;
    batmanEl.style.transform = `translate(-50%, -50%) rotate(${pos.edgeRot}deg)`;
  }

  function setPoseClass() {
    batmanEl.classList.toggle("walking", !facingFront && !firing);
    batmanEl.classList.toggle("facing", facingFront);
    batmanEl.classList.toggle("firing", firing);
  }

  function placeBatman() {
    const pos = positionOnBorder();
    batmanEl.style.left = `${pos.x}px`;
    batmanEl.style.top = `${pos.y}px`;
    updateSprite(pos);
    setPoseClass();
    return pos;
  }

  function fireBatarangs() {
    if (firing) return;
    const pos = positionOnBorder();
    const baseAngle = Math.atan2(pos.dirY, pos.dirX);

    firing = true;
    facingFront = false;
    setPoseClass();

    for (let i = 0; i < BATARANG_COUNT; i += 1) {
      const t = BATARANG_COUNT === 1 ? 0.5 : i / (BATARANG_COUNT - 1);
      const offset = (t - 0.5) * BATARANG_SPREAD;
      const angle = baseAngle + offset;
      const delay = i * 55;

      window.setTimeout(() => {
        spawnBatarang(pos.x, pos.y, Math.cos(angle), Math.sin(angle));
      }, delay);
    }

    window.setTimeout(() => {
      firing = false;
      setPoseClass();
    }, 400);
  }

  function spawnBatarang(x, y, dirX, dirY) {
    const el = document.createElement("img");
    el.src = BATARANG_SRC;
    el.className = "batarang";
    el.alt = "";
    el.draggable = false;
    projectilesEl.appendChild(el);

    const speed = BATARANG_SPEED * (0.88 + Math.random() * 0.24);
    batarangs.push({
      el,
      x,
      y,
      vx: dirX * speed,
      vy: dirY * speed,
      rot: Math.random() * 360,
      spin: (Math.random() > 0.5 ? 1 : -1) * (540 + Math.random() * 360),
      life: 2.4,
    });
  }

  function updateBatarangs(dt) {
    const w = window.innerWidth;
    const h = window.innerHeight;
    for (let i = batarangs.length - 1; i >= 0; i -= 1) {
      const b = batarangs[i];
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.rot += b.spin * dt;
      b.life -= dt;

      const margin = 80;
      const off =
        b.x < -margin ||
        b.x > w + margin ||
        b.y < -margin ||
        b.y > h + margin ||
        b.life <= 0;

      if (off) {
        b.el.remove();
        batarangs.splice(i, 1);
        continue;
      }

      const fade = Math.min(1, b.life / 0.35);
      b.el.style.left = `${b.x}px`;
      b.el.style.top = `${b.y}px`;
      b.el.style.opacity = String(fade);
      b.el.style.transform = `rotate(${b.rot}deg)`;
    }
  }

  function tick(ts) {
    const dt = Math.min(0.05, (ts - lastTs) / 1000);
    lastTs = ts;

    if (!facingFront && !firing) {
      faceTimer += dt * 1000;
      if (faceTimer >= FACE_EVERY_MS) {
        facingFront = true;
        faceHold = 0;
        faceTimer = 0;
      } else {
        advanceSide(SPEED * dt);
      }
    } else if (facingFront) {
      faceHold += dt * 1000;
      if (faceHold >= FACE_DURATION_MS) {
        facingFront = false;
        faceHold = 0;
      }
    }

    placeBatman();
    updateBatarangs(dt);
    requestAnimationFrame(tick);
  }

  batmanEl.addEventListener("click", (e) => {
    e.preventDefault();
    fireBatarangs();
  });

  window.addEventListener("keydown", (e) => {
    if (e.key === "f" || e.key === "F") {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen?.();
      } else {
        document.exitFullscreen?.();
      }
    }
  });

  window.addEventListener("resize", () => {
    along = Math.min(along, sideLength(dims(), side) - 0.001);
    placeBatman();
  });

  // Start mid-bottom walking right
  side = "bottom";
  along = dims().w * 0.25;
  spriteEl.src = SPRITES.right;
  placeBatman();

  window.setTimeout(() => hintEl?.classList.add("fade"), 4500);

  requestAnimationFrame((ts) => {
    lastTs = ts;
    requestAnimationFrame(tick);
  });
})();
