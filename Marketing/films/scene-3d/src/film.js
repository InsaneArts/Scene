// Scene in 3D. Every frame is a pure function of t: the Three.js world is built once from the assets, then
// posed from t alone and rendered to a WebGL canvas that draw() copies onto the film canvas, with real motion blur
// from blended sub-frames. Times come from shotlist.md (100 BPM, one bar = 2.4 s).
import * as THREE from "./vendor/three.js";
import { clamp, ease, lerp, rng, span, spring } from "/lib.js";

const BAR = 2.4;
const T = { orb: 2 * BAR, waves: [3 * BAR, 4 * BAR, 5 * BAR, 6 * BAR], ring: 8 * BAR, end: 10 * BAR, name: 10.5 * BAR, line: 10.75 * BAR };
const FPS = 60;
const SUBFRAMES = 5;          // motion blur: sub-frames per frame across half the frame time
const data = await (await fetch("/film/assets/data.json")).json();
const CARDS = data.cards;

const assets = { icon: "assets/icon.png", grain: "assets/grain.png", chaos: "assets/screens/chaos.jpg" };
for (const h of data.heroes) assets[h] = `assets/screens/${h}.jpg`;
for (const c of CARDS) assets[`card:${c}`] = `assets/cards/${c}.jpg`;

// State 0 is the Mac where nothing matches; states 1 to 4 are the four themes.
const LOOKS = [
  { accent: "#ff4fa3", bg: "#1b1d2b", fg: "#f5f0d8", lines: ["#ff4fa3", "#ffe14d", "#3b6cff", "#3ad1ff", "#ff7a1a", "#9cff57"] },
  ...data.heroes.map((h) => {
    const p = data.palettes[h];
    return { accent: p.ui.accent, bg: p.ui.background, fg: p.ui.foreground, lines: p.ansi.slice(1, 7), ansi: p.ansi };
  }),
];
const CARD_JITTER = (() => { const r = rng(77); return Array.from({ length: 200 }, () => [r() - 0.5, r(), r() - 0.5]); })();
const CLASH = ["#ff3d9a", "#f2e14a", "#3657ff"]; // the three panes before the theme: nothing matches
const ORB_REST = new THREE.Vector3(0, -0.36, 0.62); // where the orb floats after it rises; each wave starts here

let W = null;

export default {
  duration: 12 * BAR,
  fps: FPS,
  formats: ["wide"],
  poster: 27.6,
  assets,

  draw(ctx, t, fmt, img) {
    W ??= build(fmt, img);
    const shutter = 0.5 / FPS;
    for (let k = 0; k < SUBFRAMES; k++) {
      const tk = Math.max(0, t + (k / (SUBFRAMES - 1) - 0.5) * shutter);
      pose(tk);
      W.composer.render();
      ctx.globalAlpha = 1 / (k + 1);
      ctx.drawImage(W.renderer.domElement, 0, 0);
    }
    ctx.globalAlpha = 1;
    finish(ctx, t, fmt, img);
  },

  audio(ac, out) { score(ac, out); },
};

// MARK: - The world

function texture(image) {
  const tex = new THREE.Texture(image);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  tex.needsUpdate = true;
  return tex;
}

/// A pane's face: a terminal-like block in a look's colors. Drawn once per look.
function paneTexture(look, seed, solid) {
  const c = document.createElement("canvas");
  c.width = 768; c.height = 480;
  const g = c.getContext("2d");
  g.fillStyle = solid ?? look.bg;
  g.fillRect(0, 0, c.width, c.height);
  const r = rng(seed);
  g.globalAlpha = solid ? 0.35 : 1;
  for (let row = 0; row < 11; row++) {
    let x = 44 + (row % 3 === 1 ? 36 : 0);
    const y = 48 + row * 36;
    for (let word = 0; word < 2 + Math.floor(r() * 4); word++) {
      const len = 40 + r() * 120;
      g.fillStyle = solid ? "#ffffff" : word === 0 ? look.fg : look.lines[Math.floor(r() * look.lines.length)];
      g.globalAlpha = solid ? 0.3 : word === 0 ? 0.9 : 1;
      g.beginPath(); g.roundRect(x, y, Math.min(len, c.width - 44 - x), 14, 7); g.fill();
      x += len + 18;
      if (x > c.width - 80) break;
    }
  }
  return texture(c);
}

const WIPE = {
  vertexShader: "varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
  fragmentShader: `
    uniform sampler2D a; uniform sampler2D b; uniform float p; uniform vec3 edge; uniform float gain; uniform vec2 origin; uniform float aspect; uniform float reach;
    varying vec2 vUv;
    void main(){
      vec2 d = (vUv - origin) * vec2(aspect, 1.0);
      float r = length(d);
      float m = smoothstep(p - 0.015, p + 0.015, r);
      vec3 c = mix(texture2D(b, vUv).rgb, texture2D(a, vUv).rgb, m);
      float live = step(0.0001, p) * (1.0 - smoothstep(reach - 0.2, reach, p));
      c += edge * exp(-pow((r - p) / 0.025, 2.0)) * 3.0 * live;
      gl_FragColor = vec4(c * gain, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
    }`,
};
const wipeMaterial = (aspect, origin) =>
  new THREE.ShaderMaterial({ ...WIPE, uniforms: { a: { value: null }, b: { value: null }, p: { value: 0 }, edge: { value: new THREE.Color() },
    gain: { value: 1 }, origin: { value: new THREE.Vector2(...origin) }, aspect: { value: aspect }, reach: { value: 1.5 } } });

function build(fmt, img) {
  const canvas = document.createElement("canvas");
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(1);
  renderer.setSize(fmt.w, fmt.h, false);
  renderer.toneMapping = THREE.NeutralToneMapping;   // keeps the screens' colors, unlike ACES
  renderer.toneMappingExposure = 1.0;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color("#040507");
  scene.fog = new THREE.FogExp2("#040507", 0.075);
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new THREE.RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.32;

  const camera = new THREE.PerspectiveCamera(38, fmt.w / fmt.h, 0.05, 60);

  // Light: a cool key from above the screen, and an accent light that takes the theme's color.
  const key = new THREE.DirectionalLight("#dfe8ff", 1.2);
  key.position.set(1.5, 3, 4);
  scene.add(key);
  const accent = new THREE.PointLight("#ffffff", 0, 6, 1.6);
  scene.add(accent);
  const rim = new THREE.PointLight("#8fa7ff", 0, 8, 1.4);
  rim.position.set(-2.5, 1.2, -1.8);
  scene.add(rim);

  // The display: dark anodized aluminum with a thin glass front, and the screen.
  const display = new THREE.Group();
  const metal = new THREE.MeshPhysicalMaterial({ color: "#16181d", metalness: 0.85, roughness: 0.32, clearcoat: 0.7, clearcoatRoughness: 0.2 });
  display.add(new THREE.Mesh(new THREE.RoundedBoxGeometry(1.7, 1.1, 0.07, 6, 0.045), metal));
  const screenMat = wipeMaterial(1.6, [0.5, -0.05]);
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(1.6, 1.0), screenMat);
  screen.position.z = 0.0365;
  display.add(screen);
  const glass = new THREE.Mesh(new THREE.PlaneGeometry(1.66, 1.06),
    new THREE.MeshPhysicalMaterial({ color: "#ffffff", metalness: 0, roughness: 0.08, transparent: true, opacity: 0.035, clearcoat: 1 }));
  glass.position.z = 0.0372;
  display.add(glass);
  scene.add(display);

  // Three panes: a terminal, an editor, and a notes slab, floating around the display.
  const looks = LOOKS.map((look, i) => [0, 1, 2].map((j) => paneTexture(look, 11 + j * 7, i === 0 ? CLASH[j] : null)));
  const panes = [0, 1, 2].map((j) => {
    const group = new THREE.Group();
    group.add(new THREE.Mesh(new THREE.RoundedBoxGeometry(0.74, 0.47, 0.018, 4, 0.02),
      new THREE.MeshPhysicalMaterial({ color: "#0d0f13", metalness: 0.3, roughness: 0.25, clearcoat: 1, transparent: true, opacity: 0.92 })));
    const face = new THREE.Mesh(new THREE.PlaneGeometry(0.7, 0.4375), wipeMaterial(1.6, [j === 0 ? 1.1 : -0.1, 0.5]));
    face.position.z = 0.0095;
    group.add(face);
    scene.add(group);
    return { group, face };
  });

  // The theme orb: the theme's 16 terminal colors as bands of light on glass.
  const orbMat = new THREE.ShaderMaterial({
    uniforms: { colsA: { value: Array.from({ length: 16 }, () => new THREE.Color()) }, colsB: { value: Array.from({ length: 16 }, () => new THREE.Color()) },
      mixAB: { value: 0 }, rimColor: { value: new THREE.Color() }, turn: { value: 0 }, glow: { value: 1 } },
    vertexShader: `varying vec3 vN; varying vec3 vV; varying vec2 vUv;
      void main(){ vUv = uv; vec4 mv = modelViewMatrix * vec4(position, 1.0); vN = normalize(normalMatrix * normal); vV = normalize(-mv.xyz); gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform vec3 colsA[16]; uniform vec3 colsB[16]; uniform float mixAB; uniform vec3 rimColor; uniform float turn; uniform float glow;
      varying vec3 vN; varying vec3 vV; varying vec2 vUv;
      void main(){
        float u = clamp(vUv.y + 0.08 * sin(vUv.x * 6.2832 + turn), 0.0, 0.9999);
        int i = int(floor(u * 16.0));
        float f = fract(u * 16.0);
        vec3 band = mix(colsA[i], colsB[i], mixAB);
        float seam = smoothstep(0.0, 0.18, f) * smoothstep(1.0, 0.82, f);
        vec3 n = normalize(vN), v = normalize(vV);
        float facing = max(dot(n, v), 0.0);
        float fres = pow(1.0 - facing, 3.0);
        float spec = pow(max(dot(n, normalize(v + vec3(-0.4, 0.7, 0.4))), 0.0), 60.0);
        vec3 inner = band * seam * (0.35 + 0.9 * facing);
        vec3 c = inner * glow * 1.25 + rimColor * fres * 1.8 * glow + vec3(1.0) * spec * 1.6;
        gl_FragColor = vec4(c, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  });
  const orb = new THREE.Mesh(new THREE.SphereGeometry(0.16, 96, 96), orbMat);
  scene.add(orb);

  // The wave: a thin shell of light expanding from the orb.
  const waveMat = new THREE.ShaderMaterial({
    uniforms: { color: { value: new THREE.Color() }, strength: { value: 0 } },
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
    vertexShader: `varying vec3 vN; varying vec3 vV; void main(){ vec4 mv = modelViewMatrix * vec4(position, 1.0); vN = normalize(normalMatrix * normal); vV = normalize(-mv.xyz); gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform vec3 color; uniform float strength; varying vec3 vN; varying vec3 vV;
      void main(){ float f = pow(1.0 - abs(dot(normalize(vN), normalize(vV))), 4.0); gl_FragColor = vec4(color * f * strength, 1.0); }`,
  });
  const wave = new THREE.Mesh(new THREE.SphereGeometry(1, 64, 48), waveMat);
  scene.add(wave);

  // Dust in the air, seeded.
  const r = rng(42);
  const dust = new Float32Array(900 * 3);
  for (let i = 0; i < 900; i++) { dust[i * 3] = (r() - 0.5) * 9; dust[i * 3 + 1] = (r() - 0.5) * 5; dust[i * 3 + 2] = (r() - 0.5) * 9; }
  const dustGeo = new THREE.BufferGeometry();
  dustGeo.setAttribute("position", new THREE.BufferAttribute(dust.slice(), 3));
  const dustPoints = new THREE.Points(dustGeo, new THREE.PointsMaterial({ color: "#a8b4c8", size: 0.011, transparent: true, opacity: 0.4, depthWrite: false }));
  scene.add(dustPoints);

  // Every theme: cards on a tilted ring.
  const ring = new THREE.Group();
  ring.rotation.x = 0.32;
  const cards = CARDS.map((name, i) => {
    const mat = new THREE.MeshBasicMaterial({ map: texture(img[`card:${name}`]), transparent: true, opacity: 0, depthWrite: false });
    const card = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 0.3125), mat);
    ring.add(card);
    return card;
  });
  scene.add(ring);

  // The icon, with a soft halo behind it.
  const iconGroup = new THREE.Group();
  const halo = (() => {
    const c = document.createElement("canvas"); c.width = c.height = 512;
    const g = c.getContext("2d"); const grad = g.createRadialGradient(256, 256, 0, 256, 256, 256);
    grad.addColorStop(0, "rgba(255,255,255,0.4)"); grad.addColorStop(0.35, "rgba(255,255,255,0.08)"); grad.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = grad; g.fillRect(0, 0, 512, 512);
    return new THREE.Mesh(new THREE.PlaneGeometry(1.8, 1.8), new THREE.MeshBasicMaterial({ map: texture(c), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0 }));
  })();
  halo.position.z = -0.05;
  iconGroup.add(halo);
  const icon = new THREE.Mesh(new THREE.PlaneGeometry(0.52, 0.52), new THREE.MeshBasicMaterial({ map: texture(img.icon), transparent: true, opacity: 0 }));
  iconGroup.add(icon);
  scene.add(iconGroup);

  const composer = new THREE.EffectComposer(renderer);
  composer.addPass(new THREE.RenderPass(scene, camera));
  const bloom = new THREE.UnrealBloomPass(new THREE.Vector2(fmt.w, fmt.h), 0.55, 0.5, 0.86);
  composer.addPass(bloom);
  composer.addPass(new THREE.OutputPass());

  const screens = [texture(img.chaos), ...data.heroes.map((h) => texture(img[h]))];
  const colors = LOOKS.map((l) => ({ accent: new THREE.Color(l.accent), ansi: (l.ansi ?? [...l.lines, ...l.lines, ...l.lines]).slice(0, 16).map((c) => new THREE.Color(c)) }));
  return { renderer, scene, camera, composer, bloom, key, accent, rim, display, screenMat, glass, panes, looks, orb, orbMat, wave, waveMat,
    dustPoints, dust, ring, cards, iconGroup, icon, halo, screens, colors, metal };
}

// MARK: - Pose: everything from t

/// The look in effect at t: which switch is under way and how far along.
function lookAt(t) {
  let k = 0;
  for (const s of T.waves) if (t >= s) k++;
  const start = k > 0 ? T.waves[k - 1] : -1;
  return { from: Math.max(0, k - 1), to: k, since: k > 0 ? t - start : 99 };
}

/// Catmull-Rom through keyframes with their own times: smooth velocity across keys, still at both ends.
function path(keys, t) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 0; i < keys.length - 1; i++) {
    const [t1, p1] = keys[i], [t2, p2] = keys[i + 1];
    if (t > t2) continue;
    const p0 = (keys[i - 1] ?? keys[i])[1], p3 = (keys[i + 2] ?? keys[i + 1])[1];
    const u = ease.inOutCubic((t - t1) / (t2 - t1)) * 0.35 + ((t - t1) / (t2 - t1)) * 0.65;
    const u2 = u * u, u3 = u2 * u;
    return p1.map((_, d) => 0.5 * (2 * p1[d] + (-p0[d] + p2[d]) * u + (2 * p0[d] - 5 * p1[d] + 4 * p2[d] - p3[d]) * u2 + (-p0[d] + 3 * p1[d] - 3 * p2[d] + p3[d]) * u3));
  }
  return keys.at(-1)[1];
}

const CAMERA = [
  [0.0, [-0.55, 0.16, 2.95]],
  [4.8, [0.32, 0.12, 3.5]],
  [7.2, [0.18, 0.02, 3.05]],
  [9.6, [-1.15, 0.22, 2.75]],
  [12.0, [0.95, 0.85, 2.85]],
  [14.4, [-0.45, -0.22, 2.65]],
  [19.2, [0.05, 0.1, 3.0]],
  [21.6, [0.4, 1.55, 4.9]],
  [24.0, [0.0, 2.1, 5.6]],
  [26.4, [0.0, 0.25, 3.0]],
  [28.8, [0.0, 0.18, 2.75]],
];
const TARGET = [
  [0.0, [0, 0.0, 0]], [7.2, [0, -0.05, 0.1]], [14.4, [0, -0.02, 0]], [21.6, [0, 0.0, 0]], [24.0, [0, -0.1, 0]], [28.8, [0, 0.1, 0]],
];

function pose(t) {
  const w = W;
  const { from, to, since } = lookAt(t);
  const blend = to === 0 ? 0 : ease.inOutCubic(clamp(since / 0.7));
  const ca = w.colors[from], cb = w.colors[to];
  const accentNow = ca.accent.clone().lerp(cb.accent, blend);

  // Camera.
  const [cx, cy, cz] = path(CAMERA, t);
  const [tx, ty, tz] = path(TARGET, t);
  w.camera.position.set(cx, cy, cz);
  w.camera.lookAt(tx, ty, tz);

  // Bars 0–1: the display is lit from the first frame; it and the panes rise into place.
  const rise = ease.outCubic(span(t, 0, 1.8));
  const out = ease.inOutCubic(span(t, T.end, 0.9));          // the display, panes, and orb leave for the end card
  w.display.position.set(0, lerp(-0.22, 0, rise) + Math.sin(t * 0.9) * 0.006 + out * 0.25, 0);
  w.display.scale.setScalar(lerp(1, 0.6, out));
  w.display.visible = out < 0.999;
  w.key.intensity = lerp(0.05, 1.2, rise) * (1 - out);
  w.rim.intensity = lerp(0, 3.0, rise) * (1 - out);
  w.rim.color.copy(accentNow).lerp(new THREE.Color("#8fa7ff"), to === 0 ? 1 : 0.35);

  // The screen: the current look, wiping to the next from where the wave enters.
  const sw = since < 1.6 ? ease.outCubic(span(since, 0.12, 0.75)) * 1.5 : 0;
  w.screenMat.uniforms.a.value = w.screens[since < 1.6 ? from : to];
  w.screenMat.uniforms.b.value = w.screens[to];
  w.screenMat.uniforms.p.value = since < 1.6 ? sw : 0;
  w.screenMat.uniforms.edge.value.copy(cb.accent);
  w.screenMat.uniforms.gain.value = 1 - out;

  // Panes orbit the display, and each takes the theme when the wave reaches it.
  w.panes.forEach((pane, j) => {
    const phase = j * 2.1 + t * 0.16;
    const settle = to === 0 ? 0 : 1;
    const rx = [1.28, 1.36, 1.2][j], ry = [0.5, 0.38, 0.62][j];
    const x = Math.cos(phase) * rx, z = Math.sin(phase) * 0.9 - 0.15;
    const y = [0.36, -0.42, 0.05][j] + Math.sin(phase * 1.3) * 0.06 + ry * 0.0;
    pane.group.position.set(x, lerp(-0.6, y, rise) + out * 0.3, z);
    pane.group.lookAt(w.camera.position.x * 0.4, y * 0.5, w.camera.position.z);
    pane.group.rotation.z += Math.sin(phase) * 0.06 * (1 - settle * 0.5);
    pane.group.scale.setScalar(lerp(0.4, 1, rise) * (1 - out));
    pane.group.visible = out < 0.999;
    // The wipe starts at the edge nearest the orb and runs past the far corner by 0.6 s, with the wave.
    pane.group.updateMatrixWorld();
    const o = pane.face.worldToLocal(ORB_REST.clone());
    const ou = clamp(o.x / 0.7 + 0.5, -0.05, 1.05), ov = clamp(o.y / 0.4375 + 0.5, -0.05, 1.05);
    const reach = Math.max(...[[0, 0], [1, 0], [0, 1], [1, 1]].map(([cu, cv]) => Math.hypot((cu - ou) * 1.6, cv - ov))) + 0.1;
    const pp = since < 1.6 ? ease.outCubic(span(since, 0.06 + j * 0.05, 0.45)) * reach : 0;
    const u = pane.face.material.uniforms;
    u.origin.value.set(ou, ov);
    u.reach.value = reach;
    u.a.value = w.looks[since < 1.6 ? from : to][j];
    u.b.value = w.looks[to][j];
    u.p.value = pp;
    u.edge.value.copy(cb.accent);
  });

  // The orb: rises in bar 2, pulses on each wave.
  const orbIn = spring(t - T.orb, { freq: 0.9, damping: 0.75 });
  const pulse = to > 0 ? Math.exp(-since * 5) * Math.sin(Math.min(since, 0.6) * Math.PI / 0.6) : 0;
  w.orb.position.set(ORB_REST.x, lerp(-1.4, ORB_REST.y, orbIn) + Math.sin(t * 1.1) * 0.012 + out * 0.2, lerp(0.2, ORB_REST.z, orbIn));
  w.orb.scale.setScalar(lerp(0.2, 1, clamp(orbIn)) * (1 + 0.14 * pulse) * (1 - out));
  w.orb.visible = t > T.orb - 0.1 && out < 0.999;
  const mu = w.orbMat.uniforms;
  mu.colsA.value.forEach((c, i) => c.copy((to === 0 ? w.colors[1] : ca).ansi[i]));
  mu.colsB.value.forEach((c, i) => c.copy((to === 0 ? w.colors[1] : cb).ansi[i]));
  mu.mixAB.value = to === 0 ? 0 : blend;
  mu.rimColor.value.copy(to === 0 ? w.colors[1].accent : accentNow);
  mu.turn.value = t * 0.9;
  mu.glow.value = (1.15 + 0.9 * pulse) * clamp(orbIn * 1.3);
  w.orb.rotation.set(0.35, t * 0.35, 0.1);

  // The accent light sits at the orb and takes the theme's color.
  w.accent.position.copy(w.orb.position).add(new THREE.Vector3(0, 0.1, 0.25));
  w.accent.color.copy(to === 0 ? w.colors[1].accent : accentNow);
  w.accent.intensity = (t < T.orb ? 0 : 2.2 * clamp(orbIn)) * (1 + 2.5 * pulse) * (1 - out);

  // The wave expands from the orb, 0.9 s per switch.
  const wr = since < 1.2 ? ease.outCubic(span(since, 0, 1.1)) : 1;
  w.wave.visible = to > 0 && since < 1.2;
  w.wave.position.copy(w.orb.position);
  w.wave.scale.setScalar(0.18 + wr * 6.5);
  w.waveMat.uniforms.color.value.copy(cb.accent);
  w.waveMat.uniforms.strength.value = (1 - wr) * 1.8;

  // Dust drifts slowly, wrapping in its box. Positions come from t alone.
  const pos = w.dustPoints.geometry.attributes.position.array;
  for (let i = 0; i < pos.length; i += 3) {
    pos[i] = w.dust[i] + Math.sin(t * 0.13 + i) * 0.08;
    pos[i + 1] = ((w.dust[i + 1] + t * 0.05 + 2.5) % 5) - 2.5;
    pos[i + 2] = w.dust[i + 2];
  }
  w.dustPoints.geometry.attributes.position.needsUpdate = true;
  w.dustPoints.material.opacity = 0.35 * rise;

  // Bars 8–9: every theme on a tilted ring around the display; at the end the ring tightens and dims.
  const n = w.cards.length;
  const leave = ease.inOutCubic(span(t, T.end, 1.4));
  w.ring.rotation.y = (t - T.ring) * 0.12;
  w.ring.updateMatrixWorld();
  const facing = new THREE.Quaternion();
  w.ring.getWorldQuaternion(facing).invert().multiply(w.camera.quaternion);
  w.cards.forEach((card, i) => {
    const jr = CARD_JITTER[i];
    const a = (i / n) * Math.PI * 2 + jr[0] * 0.05;
    const radius = (2.15 + jr[1] * 0.55) * lerp(1, 1.5, leave);
    const arrive = clamp(spring(t - T.ring - (i % 20) * 0.05 - Math.floor(i / 20) * 0.3, { freq: 0.75, damping: 0.85 }), 0, 1.02);
    card.position.set(Math.cos(a) * radius, (1 - clamp(arrive)) * -1.4 + jr[2] * 0.42 - leave * 0.4, Math.sin(a) * radius);
    card.quaternion.copy(facing);
    card.material.opacity = clamp(arrive) * (1 - leave);
    card.visible = t > T.ring - 0.2 && leave < 0.999;
  });

  // Bars 10–11: the icon springs in at the center.
  const iconIn = spring(t - T.end - 0.3, { freq: 1.1, damping: 0.62 });
  w.iconGroup.position.set(0, 0.36, 0.35);
  w.iconGroup.lookAt(w.camera.position);
  w.iconGroup.scale.setScalar(Math.max(0.0001, iconIn));
  w.icon.material.opacity = clamp(iconIn * 1.5);
  w.halo.material.opacity = 0.35 * clamp(iconIn);
  w.halo.material.color.copy(w.colors[4].accent).lerp(new THREE.Color("#ffffff"), 0.6);
  w.iconGroup.visible = t > T.end;

  w.bloom.strength = 0.55 + 0.45 * pulse;
}

// MARK: - The finish: type, grain, and vignette in 2D

function finish(ctx, t, fmt, img) {
  const { w, h } = fmt;
  // Type on the end card: the name, then the tagline, white at 92%. Fades in with an 8 px rise, then holds.
  const name = ease.outCubic(span(t, T.name, 0.7)), line = ease.outCubic(span(t, T.line, 0.7));
  ctx.textAlign = "center";
  if (name > 0) {
    ctx.globalAlpha = 0.92 * name;
    ctx.fillStyle = "#ffffff";
    ctx.font = `600 128px -apple-system, "SF Pro Display", system-ui, sans-serif`;
    ctx.fillText("Scene", w / 2, h * 0.715 + (1 - name) * 8);
  }
  if (line > 0) {
    ctx.globalAlpha = 0.92 * line;
    ctx.fillStyle = "#ffffff";
    ctx.font = `400 64px -apple-system, "SF Pro Display", system-ui, sans-serif`;
    ctx.fillText("One theme for your whole Mac.", w / 2, h * 0.82 + (1 - line) * 8);
  }
  // Vignette.
  ctx.globalAlpha = 1;
  const v = ctx.createRadialGradient(w / 2, h / 2, h * 0.35, w / 2, h / 2, h * 0.95);
  v.addColorStop(0, "rgba(0,0,0,0)");
  v.addColorStop(1, "rgba(0,0,0,0.55)");
  ctx.fillStyle = v;
  ctx.fillRect(0, 0, w, h);
  // Grain, moving every frame (seeded by the frame number).
  const frame = Math.round(t * FPS), r = rng(frame + 7);
  ctx.globalAlpha = 0.05;
  ctx.globalCompositeOperation = "overlay";
  const gx = -Math.floor(r() * 256), gy = -Math.floor(r() * 256);
  for (let y = gy; y < h; y += img.grain.height) for (let x = gx; x < w; x += img.grain.width) ctx.drawImage(img.grain, x, y);
  ctx.globalCompositeOperation = "source-over";
  ctx.globalAlpha = 1;
  // Fade from black at the start. The end card holds to the last frame; only the sound fades.
  const black = 1 - span(t, 0, 0.4);
  if (black > 0) { ctx.globalAlpha = black; ctx.fillStyle = "#000"; ctx.fillRect(0, 0, w, h); ctx.globalAlpha = 1; }
}

// MARK: - Score: the same grid as the picture

function score(ac, out) {
  const master = ac.createDynamicsCompressor();
  master.threshold.value = -18; master.ratio.value = 3;
  const level = ac.createGain(); level.gain.value = 0.8;
  master.connect(level); level.connect(out);
  // A small seeded room.
  const verb = ac.createConvolver();
  const len = ac.sampleRate * 2.6, ir = ac.createBuffer(2, len, ac.sampleRate), r = rng(3);
  for (let ch = 0; ch < 2; ch++) { const d = ir.getChannelData(ch); for (let i = 0; i < len; i++) d[i] = (r() * 2 - 1) * (1 - i / len) ** 3.2; }
  verb.buffer = ir;
  const wet = ac.createGain(); wet.gain.value = 0.35; verb.connect(wet); wet.connect(master);
  const bus = (g) => { const n = ac.createGain(); n.gain.value = g; n.connect(master); n.connect(verb); return n; };
  const hz = (m) => 440 * 2 ** ((m - 69) / 12);

  // Pad: Dm9 through bar 7, Bbmaj9 for the ring, Fmaj9 to close. A lowpass opens over the first bars.
  const chords = [[0, [38, 45, 50, 53, 57, 64]], [8 * BAR, [34, 41, 50, 57, 60, 65]], [10 * BAR, [41, 48, 53, 57, 64, 67]]];
  const pad = bus(0.06);
  const lp = ac.createBiquadFilter(); lp.type = "lowpass"; lp.Q.value = 0.6; lp.connect(pad);
  lp.frequency.setValueAtTime(260, 0); lp.frequency.linearRampToValueAtTime(1500, 3 * BAR); lp.frequency.linearRampToValueAtTime(2400, 10 * BAR);
  chords.forEach(([start, notes], ci) => {
    const end = chords[ci + 1]?.[0] ?? 12 * BAR;
    for (const m of notes) for (const det of [-6, 6]) {
      const o = ac.createOscillator(); o.type = "sawtooth"; o.frequency.value = hz(m); o.detune.value = det;
      const g = ac.createGain();
      g.gain.setValueAtTime(0, start); g.gain.linearRampToValueAtTime(1, start + (ci ? 0.4 : 2.5));
      g.gain.setValueAtTime(1, Math.max(start + 0.5, end - 0.3)); g.gain.linearRampToValueAtTime(0, end + (ci === 2 ? 0 : 0.3));
      o.connect(g); g.connect(lp); o.start(start); o.stop(end + 0.4);
    }
  });
  // The orb: a shimmer that rises in bar 2.
  const shimmer = bus(0.025);
  for (const m of [81, 86, 88, 93]) {
    const o = ac.createOscillator(); o.type = "sine"; o.frequency.value = hz(m);
    const g = ac.createGain(); g.gain.setValueAtTime(0, T.orb); g.gain.linearRampToValueAtTime(1, T.orb + 1.6); g.gain.linearRampToValueAtTime(0, T.waves[0] + 0.3);
    o.connect(g); g.connect(shimmer); o.start(T.orb); o.stop(T.waves[0] + 0.5);
  }
  // Each wave: a noise swell into a deep pulse with a click.
  const noise = ac.createBuffer(1, ac.sampleRate * 2, ac.sampleRate), nr = rng(9), nd = noise.getChannelData(0);
  for (let i = 0; i < nd.length; i++) nd[i] = nr() * 2 - 1;
  for (const s of T.waves) {
    const src = ac.createBufferSource(); src.buffer = noise;
    const bp = ac.createBiquadFilter(); bp.type = "bandpass"; bp.Q.value = 1.2;
    bp.frequency.setValueAtTime(400, s - 0.6); bp.frequency.exponentialRampToValueAtTime(5200, s);
    const g = ac.createGain(); g.gain.setValueAtTime(0, s - 0.6); g.gain.linearRampToValueAtTime(0.12, s - 0.02); g.gain.exponentialRampToValueAtTime(0.0008, s + 0.5);
    src.connect(bp); bp.connect(g); g.connect(bus(1)); src.start(s - 0.6); src.stop(s + 0.6);
    const o = ac.createOscillator(); o.type = "sine";
    o.frequency.setValueAtTime(90, s); o.frequency.exponentialRampToValueAtTime(38, s + 0.45);
    const og = ac.createGain(); og.gain.setValueAtTime(0.0001, s); og.gain.exponentialRampToValueAtTime(0.55, s + 0.008); og.gain.exponentialRampToValueAtTime(0.0008, s + 0.9);
    o.connect(og); og.connect(bus(1)); o.start(s); o.stop(s + 1);
    const click = ac.createBufferSource(); click.buffer = noise;
    const hp = ac.createBiquadFilter(); hp.type = "highpass"; hp.frequency.value = 3000;
    const cg = ac.createGain(); cg.gain.setValueAtTime(0.18, s); cg.gain.exponentialRampToValueAtTime(0.0005, s + 0.04);
    click.connect(hp); hp.connect(cg); cg.connect(bus(1)); click.start(s, 0.5); click.stop(s + 0.06);
  }
  // The ring: a bell on every beat, from D minor pentatonic, seeded.
  const bells = bus(0.12), br = rng(21), scale = [74, 77, 79, 81, 84, 86];
  for (let b = 0; b < 8; b++) {
    const s = T.ring + b * (BAR / 4);
    const m = scale[Math.floor(br() * scale.length)];
    for (const [mult, amp] of [[1, 1], [2.76, 0.3], [5.4, 0.12]]) {
      const o = ac.createOscillator(); o.type = "sine"; o.frequency.value = hz(m) * mult;
      const g = ac.createGain(); g.gain.setValueAtTime(0.0001, s); g.gain.exponentialRampToValueAtTime(amp, s + 0.005); g.gain.exponentialRampToValueAtTime(0.0001, s + 1.4);
      o.connect(g); g.connect(bells); o.start(s); o.stop(s + 1.5);
    }
  }
  // "Scene": one soft bell.
  for (const [mult, amp] of [[1, 1], [2.76, 0.25]]) {
    const o = ac.createOscillator(); o.type = "sine"; o.frequency.value = hz(81) * mult;
    const g = ac.createGain(); g.gain.setValueAtTime(0.0001, T.name); g.gain.exponentialRampToValueAtTime(0.07 * amp, T.name + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, T.name + 3);
    o.connect(g); g.connect(bus(1)); o.start(T.name); o.stop(T.name + 3.2);
  }
  level.gain.setValueAtTime(0.8, 12 * BAR - 1.2); level.gain.linearRampToValueAtTime(0, 12 * BAR);
}
