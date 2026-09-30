'use strict';
// Scene's 30-second product film. window.render(t) draws the frame at t seconds; nothing else moves.
// The cut follows the music: 96 BPM, a beat is 0.625 s and a bar 2.5 s, and 12 bars make 30 s.

const ASSET = '../../build/film/';
const TH = window.FILM_THEMES;
const ALL = window.FILM_ALL;          // every bundled theme's name, in the app's order
const BEAT = 60 / 96;
const SW = 1440, SH = 900;            // the Mac's screen, in its own points

// MARK: - Timeline

// A Mac where nothing matches. Scene's menu bar panel picks a theme.
const MENU_CLICK = 6 * BEAT;
const TILE_CLICK = 8 * BEAT;
// One wave from the panel changes every app.
const WAVE = [8.3 * BEAT, 10.6 * BEAT];
// Scene's window: ↓ through the sidebar, two more backgrounds, then the light look.
const OPEN = 12 * BEAT;
const BROWSE = [13, 14, 15, 15.5, 16].map(b => b * BEAT);
const PICKS = [17 * BEAT, 18 * BEAT];
const LIGHT = 20 * BEAT;
const TOOLBAR = 23.5 * BEAT;
// The switcher: the window's preview becomes its card, → three times, a run, then ↩.
const MORPH = [23.65 * BEAT, 24.9 * BEAT];
const MOVES = [25, 26, 27, 28, 28.5, 29, 29.5, 29.75, 30, 30.25, 30.5, 31].map(b => b * BEAT);
const RETURN = 32 * BEAT;
const WAVE2 = [32.1 * BEAT, 34.3 * BEAT];
// The wall of themes, the icon, the name.
const WALL = [22.5, 23.9];
const THEMES_CAPTION = 37 * BEAT;
const RECEDE = [25.0, 26.3];
const ICON = [26.3, 27.5];
const END = 27.5;
const FILM = 30;
window.FILM_LENGTH = FILM;
// The fast moves. render.mjs gives these frames motion blur; the rest move too slowly to need it.
window.BLUR = [[3.55, WAVE[1] + 0.3], [OPEN - 0.05, OPEN + 0.6], [TOOLBAR, WAVE2[1] + 0.3], [WALL[0] - 0.05, WALL[1] + 0.2], [RECEDE[0] - 0.05, END]];

// MARK: - Themes on screen

const HERO = 'neon-noir:dark', LAST = 'vaporwave:dark';
// The backgrounds this Mac's owner picked. Every other look shows its first.
const PICK = { 'night-orbit:dark': 2, 'overprint:light': 1, 'phosphor:dark': 1, 'radiolaria:light': 2, 'moondust:dark': 2, 'rasterbar:dark': 1 };
const pick = key => PICK[key] || 0;
// The look a dark Mac shows for each theme: its dark one, when it has one.
const LOOK = {};
for (const key of Object.keys(TH)) { const f = TH[key].folder; if (!LOOK[f] || TH[key].look === 'dark') LOOK[f] = key; }
const FOLDERS = Object.keys(LOOK).sort((a, b) => TH[LOOK[a]].name.localeCompare(TH[LOOK[b]].name, 'en', { sensitivity: 'base' }));
// What Scene's window shows over time: [from, theme look, background].
const PAGES = [
  [OPEN, HERO, 0], [BROWSE[0], 'night-orbit:dark', 2], [BROWSE[1], 'overprint:light', 1], [BROWSE[2], 'packet:dark', 0],
  [BROWSE[3], 'phosphor:dark', 1], [BROWSE[4], 'primary:dark', 0], [PICKS[0], 'primary:dark', 1], [PICKS[1], 'primary:dark', 2],
  [LIGHT, 'primary:light', 0],
];
// The switcher, from Primary in the light look the window left it in, to Vaporwave.
const CAROUSEL = ['phosphor', 'primary', 'prism', 'punchcard', 'radiolaria', 'rain-bridge', 'rasterbar', 'ready', 'red-planet', 'red-team',
  'safelight', 'solarpunk', 'teletext', 'vaporwave', 'vector', 'wafer'].map(f => f === 'primary' ? 'primary:light' : LOOK[f]);
const CAROUSEL_START = 1;
// The menu bar panel's grid, scrolled to Neon Noir.
const GRID = ['matcha', 'moondust', 'moss', 'neon-noir', 'night-orbit', 'overprint', 'packet', 'phosphor', 'primary'].map(f => LOOK[f]);

// The Mac before Scene: a loud stock wallpaper, a green-on-black terminal, a white editor with a blue status bar.
TH.chaos = {
  key: 'chaos', look: 'dark', name: 'Before', wall: 'assets/chaos',
  ui: { background: '#ffffff', surface: '#f3f3f3', foreground: '#1f1f1f', muted: '#6e7681', border: '#c8c8c8', accent: '#007acc',
        selection: '#cfe5f7', currentLine: '#f2f2f2', cursor: '#000000' },
  onAccent: '#ffffff',
  term: { background: '#000000', foreground: '#39ff14', cursor: '#39ff14',
          ansi: ['#000000', '#ff3b30', '#39ff14', '#ffd60a', '#0a84ff', '#ff2d95', '#00e5ff', '#ffffff', '#5a5a5a', '#ff453a', '#39ff14', '#ffd60a', '#409cff', '#ff375f', '#64d2ff', '#ffffff'] },
  syn: { keyword: '#0000ff', type: '#267f99', function: '#795e26', variable: '#001080', property: '#001080', parameter: '#001080', string: '#a31515',
         number: '#098658', comment: '#008000', punctuation: '#1f1f1f', operator: '#1f1f1f', constant: '#0070c1', escape: '#ee0000', builtin: '#0000ff' },
};
const wallOf = key => key === 'chaos' ? TH.chaos.wall : TH[key].walls[pick(key)];

// MARK: - Math

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, p) => a + (b - a) * p;
const seg = (t, a, b) => clamp((t - a) / (b - a));

function bezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const X = s => ((ax * s + bx) * s + cx) * s, Y = s => ((ay * s + by) * s + cy) * s, dX = s => (3 * ax * s + 2 * bx) * s + cx;
  return p => {
    if (p <= 0) return 0;
    if (p >= 1) return 1;
    let s = p;
    for (let i = 0; i < 10; i++) {
      const d = dX(s), x = X(s) - p;
      if (Math.abs(x) < 1e-7 || Math.abs(d) < 1e-7) break;
      s = clamp(s - x / d);
    }
    return Y(s);
  };
}
const APPLE = bezier(0.32, 0.72, 0, 1);  // the curve of macOS window motion: quick start, long settle
const SMOOTH = bezier(0.65, 0, 0.35, 1); // symmetric, for camera moves
const IN = bezier(0.55, 0, 0.9, 0.4);   // for exits
const SINE = p => -(Math.cos(Math.PI * p) - 1) / 2;

// A damped spring from 0 to 1, as SwiftUI's .spring(response:dampingFraction:) moves.
function spring(t, response = 0.38, damping = 0.86) {
  if (t <= 0) return 0;
  const w = 2 * Math.PI / response, wd = w * Math.sqrt(1 - damping * damping);
  return 1 - Math.exp(-damping * w * t) * (Math.cos(wd * t) + (damping * w / wd) * Math.sin(wd * t));
}

function random(seed) {
  let s = seed >>> 0;
  return () => { s = (s + 0x6D2B79F5) >>> 0; let x = Math.imul(s ^ (s >>> 15), 1 | s); x ^= x + Math.imul(x ^ (x >>> 7), 61 | x); return ((x ^ (x >>> 14)) >>> 0) / 4294967296; };
}

// The index of the last moment in a sorted list that t has reached, or -1.
const stage = (t, times) => { let i = -1; while (i + 1 < times.length && t >= times[i + 1]) i++; return i; };

// MARK: - Color, mixed in OKLab so halfway colors stay clean

const labs = new Map();
function lab(color) {
  let v = labs.get(color);
  if (v) return v;
  let r, g, b, a = 1;
  if (color[0] === '#') {
    r = parseInt(color.slice(1, 3), 16) / 255; g = parseInt(color.slice(3, 5), 16) / 255; b = parseInt(color.slice(5, 7), 16) / 255;
  } else {
    [r, g, b, a] = color.match(/[\d.]+/g).map(Number);
    r /= 255; g /= 255; b /= 255;
    if (a === undefined) a = 1;
  }
  const lin = c => c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  const [R, G, B] = [lin(r), lin(g), lin(b)];
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  v = [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
       0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s, a];
  labs.set(color, v);
  return v;
}
function css([L, A, B, a]) {
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3, m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3, s = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3;
  const out = c => Math.round(clamp(c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(Math.max(c, 0), 1 / 2.4) - 0.055) * 255);
  const r = out(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s), g = out(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        b = out(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
  return a >= 0.999 ? `rgb(${r},${g},${b})` : `rgba(${r},${g},${b},${a.toFixed(3)})`;
}
function mix(c1, c2, p) {
  if (p <= 0) return c1;
  if (p >= 1) return c2;
  const x = lab(c1), y = lab(c2);
  return css([lerp(x[0], y[0], p), lerp(x[1], y[1], p), lerp(x[2], y[2], p), lerp(x[3], y[3], p)]);
}
const alpha = (hex, a) => `rgba(${parseInt(hex.slice(1, 3), 16)},${parseInt(hex.slice(3, 5), 16)},${parseInt(hex.slice(5, 7), 16)},${a})`;

function roleColor(theme, role) {
  const th = TH[theme], dark = th.look !== 'light';
  switch (role) {
    case 'menubar': return dark ? 'rgba(255,255,255,0.96)' : 'rgba(0,0,0,0.86)';
    case 'edge': return dark ? 'rgba(255,255,255,0.13)' : 'rgba(0,0,0,0.16)';
    case 'onAccent': return th.onAccent;
    case 'dp.menubar': return dark ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.85)';
    case 'dp.material': return dark ? 'rgba(24,24,27,0.4)' : 'rgba(250,250,250,0.48)';
    case 'dp.border': return alpha(th.ui.border, 0.6);
    case 'dp.muted': return alpha(th.ui.muted, 0.7);
  }
  const [group, key, index] = role.split('.');
  if (group === 'ui') return th.ui[key];
  if (group === 'term') return key === 'ansi' ? th.term.ansi[+index] : th.term[key];
  const value = th.syn[key] ?? th.ui.foreground;
  if (group === 'italic') return typeof value === 'object' && value.italic ? 'italic' : 'normal';
  if (group === 'bold') return typeof value === 'object' && value.bold ? '600' : '400';
  return typeof value === 'string' ? value : value.color;
}

// MARK: - Building

const frame = document.getElementById('frame');
function el(tag, cls, parent, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  if (parent) parent.appendChild(e);
  return e;
}
function img(src, cls, parent) {
  const e = el('img', cls, parent);
  if (src) e.src = ASSET + src;
  e.decoding = 'sync';
  return e;
}
function svg(markup, parent, cls) {
  const holder = el('span', cls || '', parent);
  holder.innerHTML = markup;
  return holder;
}
function style(node, props) {
  for (const k in props) node.style[k] = props[k];
}

const ICONS = {
  palette: '<svg width="17" height="17" viewBox="0 0 20 20"><path d="M10 2.6a7.4 7.4 0 1 0 0 14.8c1.1 0 1.7-.7 1.7-1.5 0-.9-.8-1.2-.8-2 0-.8.7-1.3 1.6-1.3h1.8a3.3 3.3 0 0 0 3.2-3.3C17.5 5.6 14.1 2.6 10 2.6z" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="6.3" cy="9.3" r="1.25" fill="currentColor"/><circle cx="8.6" cy="6.1" r="1.25" fill="currentColor"/><circle cx="12.4" cy="6.4" r="1.25" fill="currentColor"/></svg>',
  wifi: '<svg width="18" height="14" viewBox="0 0 18 14"><path d="M9 11.2l1.9 1.9L9 15 7.1 13.1z" fill="currentColor" transform="translate(0,-2)"/><path d="M4.6 7.4a6.2 6.2 0 0 1 8.8 0M2 4.8a9.9 9.9 0 0 1 14 0" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
  battery: '<svg width="27" height="13" viewBox="0 0 27 13"><rect x="0.75" y="0.75" width="22.5" height="11.5" rx="3.2" fill="none" stroke="currentColor" stroke-width="1.3" opacity=".55"/><rect x="2.6" y="2.6" width="15" height="7.8" rx="1.8" fill="currentColor"/><path d="M24.6 4.4v4.2c.9-.3 1.4-1.1 1.4-2.1s-.5-1.8-1.4-2.1z" fill="currentColor" opacity=".55"/></svg>',
  control: '<svg width="17" height="15" viewBox="0 0 17 15"><rect x="0.8" y="0.8" width="15.4" height="5.6" rx="2.8" fill="none" stroke="currentColor" stroke-width="1.4"/><circle cx="12.8" cy="3.6" r="1.7" fill="currentColor"/><rect x="0.8" y="8.6" width="15.4" height="5.6" rx="2.8" fill="none" stroke="currentColor" stroke-width="1.4"/><circle cx="4.2" cy="11.4" r="1.7" fill="currentColor"/></svg>',
  search: '<svg width="15" height="15" viewBox="0 0 15 15"><circle cx="6.2" cy="6.2" r="4.8" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M9.8 9.8l3.8 3.8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  moon: '<svg width="14" height="14" viewBox="0 0 14 14"><path d="M9.8 10.4A5.6 5.6 0 0 1 4.9 1.2 5.8 5.8 0 1 0 12.8 8.9a5.6 5.6 0 0 1-3 1.5z" fill="currentColor"/></svg>',
  sun: '<svg width="15" height="15" viewBox="0 0 16 16"><circle cx="8" cy="8" r="3.2" fill="currentColor"/><g stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 .9v1.8M8 13.3v1.8M.9 8h1.8M13.3 8h1.8M3 3l1.3 1.3M11.7 11.7L13 13M3 13l1.3-1.3M11.7 4.3L13 3"/></g></svg>',
  check: '<svg width="12" height="12" viewBox="0 0 12 12"><path d="M2 6.3l2.6 2.6L10 3.3" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  checkCircle: '<svg width="17" height="17" viewBox="0 0 17 17"><circle cx="8.5" cy="8.5" r="8" fill="currentColor"/><path d="M5 8.8l2.4 2.4L12.2 6" fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  sidebar: '<svg width="19" height="15" viewBox="0 0 19 15"><rect x="0.8" y="0.8" width="17.4" height="13.4" rx="3" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M6.8 1v13" stroke="currentColor" stroke-width="1.4"/><path d="M2.8 4.2h2.1M2.8 6.6h2.1M2.8 9h2.1" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>',
  switcher: '<svg width="21" height="17" viewBox="0 0 21 17"><rect x="5.6" y="1.2" width="13.8" height="10" rx="2.2" fill="none" stroke="currentColor" stroke-width="1.4" transform="rotate(-8 12.5 6.2)"/><rect x="1" y="5.4" width="13.8" height="10.2" rx="2.2" fill="rgba(0,0,0,.35)" stroke="currentColor" stroke-width="1.4"/></svg>',
  import: '<svg width="17" height="18" viewBox="0 0 17 18"><path d="M5.3 6.6H3.2a1.6 1.6 0 0 0-1.6 1.6v7.1a1.6 1.6 0 0 0 1.6 1.6h10.6a1.6 1.6 0 0 0 1.6-1.6V8.2a1.6 1.6 0 0 0-1.6-1.6h-2.1" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M8.5 1.2v9.6M5.4 7.8l3.1 3.1 3.1-3.1" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  undo: '<svg width="18" height="16" viewBox="0 0 18 16"><path d="M6 1.8L2 5.8l4 4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M2.4 5.8h8.4a4.6 4.6 0 0 1 0 9.2H8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  gear: '<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="2.6" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M9 1.3l1.2 1.9 2.2-.5.5 2.2 1.9 1.2-1.1 2 1.1 1.9-1.9 1.2-.5 2.2-2.2-.5L9 16.7l-1.2-1.9-2.2.5-.5-2.2-1.9-1.2 1.1-1.9-1.1-2 1.9-1.2.5-2.2 2.2.5z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>',
  people: '<svg width="16" height="13" viewBox="0 0 16 13"><circle cx="5.6" cy="3.6" r="2.5" fill="none" stroke="currentColor" stroke-width="1.1"/><path d="M1 12c0-2.6 2-4.3 4.6-4.3s4.6 1.7 4.6 4.3" fill="none" stroke="currentColor" stroke-width="1.1"/><circle cx="11.2" cy="4.2" r="2" fill="none" stroke="currentColor" stroke-width="1.1"/><path d="M11.4 7.8c2 .2 3.6 1.7 3.6 4" fill="none" stroke="currentColor" stroke-width="1.1"/></svg>',
  window: '<svg width="16" height="13" viewBox="0 0 16 13"><rect x="0.8" y="0.8" width="14.4" height="11.4" rx="2" fill="none" stroke="currentColor" stroke-width="1.1"/><path d="M1 3.6h14" stroke="currentColor" stroke-width="1.1"/></svg>',
  photo: '<svg width="16" height="13" viewBox="0 0 16 13"><rect x="0.8" y="0.8" width="14.4" height="11.4" rx="1.8" fill="none" stroke="currentColor" stroke-width="1.1"/><path d="M1.5 10.8l4.2-4.4 3 3 2.1-2 3.7 3.4" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linejoin="round"/><circle cx="10.8" cy="4.1" r="1.2" fill="currentColor"/></svg>',
  pointer: '<svg width="22" height="30" viewBox="0 0 22 30"><path d="M3 2v21.5l5.2-5 3.4 8 3.3-1.4-3.3-7.8h7.2z" fill="#fff" stroke="#000" stroke-width="1.3" stroke-linejoin="round"/></svg>',
};

// Everything a theme colors registers in the current list, so each desktop can be painted on its own.
let bindings = [];
function bind(node, prop, role) {
  bindings.push({ node, prop, role });
}
function paint(b, value) {
  if (b.prop[0] === '-') b.node.style.setProperty(b.prop, value);
  else if (b.prop === 'backgroundColor') b.node.style.background = value;
  else b.node.style[b.prop] = value;
}

// A Mac desktop: its wallpapers, the menu bar with Scene's item, a terminal, and an editor.
function buildDesk(parent, keys) {
  const list = [];
  const saved = bindings;
  bindings = list;
  const desk = el('div', 'desk', parent);
  const walls = {};
  for (const key of keys) walls[key] = img(wallOf(key) + '.jpg', 'wp', desk);

  const bar = el('div', 'menubar', desk);
  const left = el('div', 'left', bar);
  el('span', 'apple', left, '\uF8FF');
  el('b', '', left, 'Code');
  for (const item of ['File', 'Edit', 'Selection', 'View', 'Go', 'Window', 'Help']) el('span', '', left, item);
  const right = el('div', 'right', bar);
  const extra = svg(ICONS.palette, right, 'extra');
  for (const name of ['control', 'wifi', 'battery', 'search']) svg(ICONS[name], right);
  el('span', '', right, 'Wed Sep 30  9:41 AM');
  bind(bar, 'color', 'menubar');

  // Terminal, behind: its window is inactive.
  const term = el('div', 'win term', desk);
  Object.assign(term.style, { left: '92px', top: '118px', width: '668px', height: '436px' });
  const termBar = el('div', 'titlebar', term);
  const termLights = el('div', 'lights', termBar);
  for (let i = 0; i < 3; i++) bind(el('i', '', termLights), 'backgroundColor', 'ui.border');
  bind(el('div', 'title', termBar, 'scene — zsh'), 'color', 'ui.muted');
  const body = el('div', 'body', term);
  const prompt = [['➜ ', 2], [' scene ', 6], ['git:(', 4], ['main', 1], [') ', 4]];
  const lines = [
    [...prompt, ['git log --oneline -4']],
    [['c41f9e2 ', 3], ['Derive palettes from the art']],
    [['7f3b0d4 ', 3], ['Add fifty-four themes']],
    [['3e91a77 ', 3], ['Redesign the switcher']],
    [['f4cb26f ', 3], ['One theme for your whole Mac']],
    [...prompt, ['swift test']],
    [['✔ ', 2], ['Test run with 120 tests passed after 2.1 seconds.']],
    [...prompt, ['ls']],
    [['Packages  ', 12], ['Scripts  ', 12], ['Sources  ', 12], ['Themes  ', 12], ['README.md']],
    [],
    ['swatches', 0], ['swatches', 8],
    [...prompt, ['cursor']],
  ];
  for (const line of lines) {
    const row = el('div', 'row', body);
    if (line[0] === 'swatches') {
      for (let i = line[1]; i < line[1] + 8; i++) bind(el('span', 'swatch', row), 'backgroundColor', `term.ansi.${i}`);
      continue;
    }
    for (const [text, ansi] of line) {
      if (text === 'cursor') { bind(el('span', 'cursor-block', row), 'backgroundColor', 'term.cursor'); continue; }
      const span = el('span', '', row, text);
      if (ansi === 12) span.style.fontWeight = '600';
      bind(span, 'color', ansi == null ? 'term.foreground' : `term.ansi.${ansi}`);
    }
  }
  bind(term, 'backgroundColor', 'term.background');
  bind(term, '--edge', 'edge');

  // Editor, in front.
  const ed = el('div', 'win editor', desk);
  Object.assign(ed.style, { left: '612px', top: '236px', width: '752px', height: '560px' });
  bind(ed, 'backgroundColor', 'ui.surface');
  bind(ed, '--edge', 'edge');
  const edLights = el('div', 'lights', el('div', 'titlebar', ed));
  for (const c of ['#ff5f57', '#febc2e', '#28c840']) el('i', '', edLights).style.background = c;
  const tabs = el('div', 'tabs', ed);
  const tab1 = el('div', 'tab', tabs, 'Switcher.swift');
  bind(tab1, 'backgroundColor', 'ui.background');
  bind(tab1, 'color', 'ui.foreground');
  bind(el('div', 'bar', tab1), 'backgroundColor', 'ui.accent');
  bind(el('div', 'tab', tabs, 'Theme.swift'), 'color', 'ui.muted');
  const side = el('div', 'side', ed);
  bind(el('div', 'head', side, 'SCENE'), 'color', 'ui.muted');
  const tree = [['▾  Sources', 0], ['Engine.swift', 1, 1], ['Switcher.swift', 1, 1, true], ['Theme.swift', 1, 1], ['▾  Themes', 0],
                ['neon-noir', 1, 4], ['vaporwave', 1, 4], ['Package.swift', 0, 1], ['README.md', 0, 5]];
  for (const [name, depth, dot, selected] of tree) {
    const item = el('div', 'item', side);
    item.style.paddingLeft = `${18 + depth * 16}px`;
    if (dot != null) bind(el('i', 'dot', item), 'backgroundColor', `term.ansi.${dot}`);
    bind(el('span', '', item, name), 'color', selected ? 'ui.foreground' : 'ui.muted');
    if (selected) bind(item, 'backgroundColor', 'ui.selection');
  }
  const code = el('div', 'code', ed);
  bind(code, 'backgroundColor', 'ui.background');
  const K = 'keyword', T = 'type', P = 'punctuation', O = 'operator', F = 'function', V = 'variable', R = 'property', S = 'string', N = 'number';
  const source = [
    [['import', K], [' '], ['SwiftUI', T]],
    [],
    [['/// One keystroke. Every app.', 'comment']],
    [['struct', K], [' '], ['Switcher', T], [' {', P]],
    [['    '], ['let', K], [' themes', R], [': [', P], ['Theme', T], [']', P]],
    [['    '], ['var', K], [' selection', R], [' = ', O], ['0', N]],
    [],
    [['    '], ['func', K], [' apply', F], ['(_ ', P], ['theme', 'parameter'], [': ', P], ['Theme', T], [') ', P], ['async throws', K], [' {', P]],
    [['        '], ['try await', K], [' engine', V], ['.', P], ['apply', F], ['(', P], ['theme', V], [', ', P], ['to', 'parameter'], [': ', P], ['.everything', 'constant'], [')', P]],
    [['        '], ['print', F], ['(', P], ['"Applied ', S], ['\\(', 'escape'], ['theme', V], ['.', P], ['name', R], [')', 'escape'], ['"', S], [')', P]],
    [['    '], ['}', P]],
    [],
    [['    '], ['mutating func', K], [' next', F], ['() {', P]],
    [['        '], ['selection', R], [' = (', O], ['selection', R], [' + ', O], ['1', N], [') % ', O], ['themes', R], ['.', P], ['count', R]],
    [['    '], ['}', P]],
    [['}', P]],
  ];
  source.forEach((tokens, i) => {
    const line = el('div', 'line', code);
    if (i === 8) bind(el('div', 'current', line), 'backgroundColor', 'ui.currentLine');
    bind(el('span', 'num', line, String(i + 1)), 'color', i === 8 ? 'ui.foreground' : 'ui.muted');
    const text = el('span', '', line);
    text.style.position = 'relative';
    for (const [piece, role] of tokens) {
      const span = el('span', '', text, piece);
      if (['comment', 'parameter'].includes(role)) span.style.fontStyle = 'italic';
      bind(span, 'color', role ? `syn.${role}` : 'ui.foreground');
    }
    if (i === 8) {
      const caret = el('div', 'caret', line);
      caret.style.left = `${54 + 8.7 * 54}px`;
      bind(caret, 'backgroundColor', 'ui.cursor');
    }
  });
  const status = el('div', 'status', ed);
  for (const text of ['⎇  main', '✓ 120 tests']) el('span', '', status, text);
  el('span', 'spacer', status);
  for (const text of ['Ln 9, Col 55', 'Spaces: 4', 'Swift']) el('span', '', status, text);
  bind(status, 'backgroundColor', 'ui.accent');
  bind(status, 'color', 'onAccent');

  bindings = saved;
  return { desk, walls, extra, list, key: null };
}

function paintDesk(d, key) {
  if (d.key === key) return;
  d.key = key;
  for (const b of d.list) paint(b, roleColor(key, b.role));
  for (const [k, node] of Object.entries(d.walls)) node.style.opacity = k === key ? 1 : 0;
}

// The switcher's highlighter: CodePreview's tokenizer, so the preview's colors land where the app puts them.
const KEYWORDS = new Set(['import', 'struct', 'let', 'var', 'func', 'async', 'await', 'return', 'if', 'else', 'for', 'in']);
const TYPES = new Set(['SceneCore', 'Applier', 'Engine', 'Theme', 'Bool', 'Int', 'String']);
const BUILTINS = new Set(['print', 'true', 'false', 'self']);
function highlight(line) {
  const at = line.indexOf('//');
  if (at >= 0) return [[line.slice(0, at), null], [line.slice(at), 'comment']];
  const out = [];
  let i = 0, previous = '';
  while (i < line.length) {
    const c = line[i];
    if (c === '"') {
      let end = i + 1;
      while (end < line.length && line[end] !== '"') end++;
      if (end < line.length) end++;
      out.push([line.slice(i, end), 'string']);
      i = end;
    } else if (/[A-Za-z_]/.test(c)) {
      let end = i;
      while (end < line.length && /[A-Za-z0-9_]/.test(line[end])) end++;
      const word = line.slice(i, end), next = line[end] || ' ';
      let role;
      if (KEYWORDS.has(word)) role = 'keyword';
      else if (TYPES.has(word)) role = 'type';
      else if (BUILTINS.has(word)) role = word === 'print' ? 'function' : 'builtin';
      else if (next === '(' || previous === 'func') role = 'function';
      else if (previous === '.') role = 'property';
      else if (next === ':' && previous === '(') role = 'parameter';
      else role = 'variable';
      out.push([word, role]);
      previous = word;
      i = end;
    } else if (/[0-9]/.test(c)) {
      let end = i;
      while (end < line.length && /[0-9]/.test(line[end])) end++;
      out.push([line.slice(i, end), 'number']);
      i = end;
    } else {
      out.push([c, '=><&|!+-*/'.includes(c) ? 'operator' : 'punctuation']);
      if (c !== ' ') previous = c;
      i++;
    }
  }
  return out;
}

// DesktopPreview at 1440 x 900: the wallpaper, a mock menu bar, and a terminal and an editor in the theme's colors.
function buildPreview(parent) {
  const list = [];
  const saved = bindings;
  bindings = list;
  const W = 1440, H = 900, font = W / 62;
  const dp = el('div', 'dp', parent);
  const wall = img('', 'wpi', dp);
  const mb = el('div', 'mb', dp);
  el('span', '', mb, '\uF8FF');
  el('b', '', mb, 'Scene');
  for (const item of ['File', 'Edit', 'View']) el('span', '', mb, item);
  el('span', 'fill', mb);
  const dot = el('i', '', mb);
  Object.assign(dot.style, { width: `${font * 0.9}px`, height: `${font * 0.9}px`, borderRadius: '50%', display: 'block' });
  bind(dot, 'backgroundColor', 'ui.accent');
  const moon = svg(ICONS.moon.replace('width="14" height="14"', `width="${font * 0.95}" height="${font * 0.95}"`), mb);
  const sun = svg(ICONS.sun.replace('width="15" height="15"', `width="${font}" height="${font}"`), mb);
  el('span', '', mb, '9:41');
  bind(mb, 'color', 'dp.menubar');
  bind(mb, 'backgroundColor', 'dp.material');

  const mockWindow = (title, x, y, w, h) => {
    const box = el('div', 'w', dp);
    Object.assign(box.style, { left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px`, borderRadius: `${w * 0.025}px`,
                               boxShadow: `0 ${h * 0.02}px ${w * 0.06}px rgba(0,0,0,0.35)` });
    const bar = el('div', 'tb', box);
    const barH = h * 0.075;
    Object.assign(bar.style, { height: `${barH}px`, padding: `0 ${w * 0.025}px`, gap: `${w * 0.012}px` });
    bind(bar, 'backgroundColor', 'ui.surface');
    for (const c of ['rgb(255,94,87)', 'rgb(255,189,46)', 'rgb(41,201,64)']) {
      const light = el('i', '', bar);
      Object.assign(light.style, { width: `${barH - 0.5}px`, height: `${barH - 0.5}px`, background: c });
    }
    const name = el('div', 'tt', bar, title);
    name.style.fontSize = `${w * 0.028}px`;
    bind(name, 'color', 'ui.muted');
    const edge = el('div', '', box);
    Object.assign(edge.style, { position: 'absolute', inset: '0', borderRadius: 'inherit', borderWidth: '0.5px', borderStyle: 'solid', zIndex: 2 });
    bind(edge, 'borderColor', 'dp.border');
    return { box, top: barH };
  };

  const term = mockWindow('zsh', W * 0.05, H * 0.14, W * 0.5, H * 0.52);
  const tp = el('div', 'tp', term.box);
  tp.style.top = `${term.top}px`;
  bind(tp, 'backgroundColor', 'term.background');
  const TERM = [
    [['➜ ', 2], ['scene ', 6], ['git:(', 4], ['main', 1], [') ', 4], ['ls']],
    [['Sources  ', 4], ['Tests  ', 4], ['Themes  ', 4], ['Package.swift  '], ['build.sh', 2]],
    [['➜ ', 2], ['scene ', 6], ['git status --short']],
    [[' M ', 3], ['Sources/Engine.swift']],
    [['?? ', 1], ['Themes/tidewater/']],
    [['➜ ', 2], ['scene ', 6], ['swift test']],
    [['✔ ', 2], ['Test run with 104 tests passed']],
    [['  0 ', 8], ['1 ', 9], ['2 ', 10], ['3 ', 11], ['4 ', 12], ['5 ', 13], ['6 ', 14], ['7', 15]],
  ];
  for (const line of TERM) {
    const row = el('div', '', tp);
    for (const [text, ansi] of line) bind(el('span', '', row, text), 'color', ansi == null ? 'term.foreground' : `term.ansi.${ansi}`);
  }
  const last = el('div', '', tp);
  bind(el('span', '', last, '➜ '), 'color', 'term.ansi.2');
  const block = el('span', '', last);
  Object.assign(block.style, { display: 'inline-block', width: `${font * 0.6}px`, height: `${font * 1.15}px`, verticalAlign: '-4px' });
  bind(block, 'backgroundColor', 'term.cursor');

  const editor = mockWindow('Applier.swift', W * 0.43, H * 0.3, W * 0.52, H * 0.6);
  const cp = el('div', 'cp', editor.box);
  cp.style.top = `${editor.top}px`;
  bind(cp, 'backgroundColor', 'ui.background');
  const SAMPLE = ['import SceneCore', '', '/// Applies a theme and reports each app.', 'struct Applier {', '    let engine: Engine', '    var retries = 3', '',
    '    func run(_ theme: Theme) async -> Bool {', '        let report = await engine.apply(theme)', '        print("Applied \\(report.count) apps")',
    '        return retries > 0 && report.ok', '    }', '}'];
  const numbers = el('div', 'n', cp), code = el('div', 'c', cp);
  SAMPLE.forEach((line, i) => {
    bind(el('div', '', numbers, String(i + 1)), 'color', i === 8 ? 'ui.foreground' : 'dp.muted');
    const row = el('div', '', code);
    if (i === 8) bind(row, 'backgroundColor', 'ui.currentLine');
    if (!line) row.innerHTML = '&nbsp;';
    for (const [piece, role] of highlight(line)) {
      const span = el('span', '', row, piece);
      bind(span, 'color', role ? `syn.${role}` : 'ui.foreground');
      if (role) { bind(span, 'fontStyle', `italic.${role}`); bind(span, 'fontWeight', `bold.${role}`); }
    }
  });
  bindings = saved;
  return { dp, wall, moon, sun, list };
}

// The menu bar panel, under Scene's item: the current theme, a grid of themes, and the usual commands.
function buildPanel(parent, anchorX) {
  const panel = el('div', 'panel', parent);
  const left = Math.min(SW - 8 - 340, anchorX - 170);
  panel.style.left = `${left}px`;
  const current = el('div', 'current', panel);
  const heroImg = img(TH[HERO].walls[0] + '-small.jpg', '', current);
  el('div', 'shade', current);
  const text = el('div', 'text', current);
  const none = el('div', '', text), chosen = el('div', '', text);
  el('div', 'small', none, 'No theme yet');
  el('div', 'big', none, 'Pick one below');
  el('div', 'small', chosen, 'Current theme');
  el('div', 'big', chosen, TH[HERO].name);
  const grid = el('div', 'grid', panel);
  const cells = GRID.map((key, i) => {
    const cell = el('div', 'cell', grid);
    Object.assign(cell.style, { left: `${4 + (i % 3) * 106}px`, top: `${4 + Math.floor(i / 3) * 92}px` });
    const thumb = el('div', 'thumb', cell);
    img(wallOf(key) + '-small.jpg', '', thumb);
    const ring = el('div', 'ring', thumb);
    el('span', '', cell, TH[key].name);
    return { cell, thumb, ring, key };
  });
  el('hr', '', panel);
  const rows = [['Switch Theme…', '⌃⇧⌘Space'], ['Next Background', '⌃⌥⌘Space', true], ['Undo Last Theme', null, true]];
  for (const [title, key, off] of rows) {
    const row = el('div', off ? 'row off' : 'row', panel);
    el('span', '', row, title);
    if (key) el('span', 'key', row, key);
  }
  el('hr', '', panel);
  for (const title of ['Open Scene', 'Settings…', 'Quit Scene']) el('span', '', el('div', 'row', panel), title);
  return { panel, heroImg, none, chosen, cells, left };
}

// Scene's window: a glass sidebar of themes, a toolbar, and one theme page per moment in PAGES.
function buildApp(parent) {
  const app = el('div', 'app', parent);
  const ambient = el('div', 'ambient', app);
  const ambients = PAGES.map(([, key, i]) => {
    const layer = el('div', '', ambient);
    img(TH[key].walls[i] + '-small.jpg', '', layer);
    el('i', '', layer).style.background = TH[key].look === 'light' ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.5)';
    return layer;
  });

  const pages = PAGES.map(([, key, index]) => buildPage(app, key, index));

  const side = el('div', 'side', app);
  const lights = el('div', 'lights', side);
  for (const c of ['#ff5f57', '#febc2e', '#28c840']) el('i', '', lights).style.background = c;
  svg(ICONS.sidebar, side, 'toggle');
  const list = el('div', 'list', side);
  const selection = el('div', 'selection', list);
  const first = FOLDERS.indexOf('matcha');
  const rows = {};
  FOLDERS.slice(first, first + 15).forEach((folder, i) => {
    const key = LOOK[folder];
    const row = el('div', 'trow', list);
    row.style.top = `${i * 48}px`;
    const thumbs = [img(wallOf(key) + '-small.jpg', '', row)];
    if (folder === 'primary') thumbs.push(img(TH['primary:light'].walls[0] + '-small.jpg', '', row));
    el('div', 'n', row, TH[key].name);
    const dots = el('div', 'dots d', row);
    dots.style.gap = '2.8px';
    for (let a = 1; a <= 6; a++) Object.assign(el('i', '', dots).style, { width: '7px', height: '7px', background: TH[key].term.ansi[a] });
    if (key === HERO) { const check = svg(ICONS.checkCircle, row, 'check'); check.style.color = 'rgb(64,120,255)'; }
    rows[folder] = { row, top: i * 48, thumbs };
  });

  const tools = el('div', 'tools glass', app);
  const buttons = ['switcher', 'import', 'undo', 'gear'].map(name => svg(ICONS[name], tools));
  return { app, ambients, pages, selection, rows, buttons };
}

function buildPage(app, key, index) {
  const th = TH[key], light = th.look === 'light';
  const page = el('div', light ? 'page light' : 'page', app);
  const preview = el('div', 'preview', page);
  img(th.previews[index] + '.jpg', '', preview);
  const picker = el('div', 'picker', page);
  th.walls.forEach((wall, i) => {
    const one = el('div', 'pick', picker);
    img(wall + '-small.jpg', '', one);
    const ring = el('div', 'ring', one);
    if (i === index) ring.style.boxShadow = `inset 0 0 0 2.5px ${th.ui.accent}`;
  });
  const head = el('div', 'head', page);
  const name = el('div', 'name', head);
  el('span', '', name, th.name);
  if (key === HERO) {
    const pill = el('span', 'pill', name, 'Current');
    Object.assign(pill.style, { color: th.ui.accent, background: alpha(th.ui.accent, 0.15) });
  }
  el('div', 'summary', head, th.summary);
  const dots = el('div', 'dots', head);
  dots.style.gap = '5.6px';
  for (let a = 1; a <= 6; a++) Object.assign(el('i', '', dots).style, { width: '14px', height: '14px', background: th.term.ansi[a] });
  const right = el('div', 'right', head);
  let knob = null;
  if (th.looks.length > 1) {
    const seg = el('div', 'seg glass', right);
    if (light) seg.style.background = 'rgba(0,0,0,0.06)';
    knob = el('div', 'knob', seg);
    knob.style.background = light ? 'rgba(0,0,0,0.12)' : 'rgba(255,255,255,0.2)';
    el('span', '', seg, 'Dark');
    el('span', '', seg, 'Light');
  } else {
    const only = el('div', 'only', right);
    if (light) only.style.color = 'rgba(60,60,67,0.6)';
    svg(light ? ICONS.sun : ICONS.moon, only);
    el('span', '', only, light ? 'Light only' : 'Dark only');
  }
  const apply = el('div', 'apply', right, 'Apply…');
  Object.assign(apply.style, { background: th.ui.accent, color: th.onAccent });
  el('div', 'rule', page);
  const credits = el('div', 'credits', page);
  for (const [icon, line] of [['people', th.credits.by], ['window', th.credits.macos], ['photo', th.credits.wallpapers[index]]]) {
    if (!line) continue;
    const row = el('div', '', credits);
    svg(ICONS[icon], row);
    el('span', '', row, line);
  }
  return { page, preview, knob, segs: knob ? [...knob.parentNode.querySelectorAll('span')] : null };
}

function buildSwitcher(parent) {
  const root = el('div', 'switcher', parent);
  const backs = CAROUSEL.map(key => { const b = el('div', 'back', root); b.style.backgroundImage = `url(${ASSET}${wallOf(key)}-small.jpg)`; return b; });
  el('div', 'dim', root);
  const content = el('div', '', root);
  Object.assign(content.style, { position: 'absolute', inset: '0', transformOrigin: '720px 450px' });
  const cards = CAROUSEL.map(key => {
    const card = el('div', 'card', content);
    img(TH[key].previews[pick(key)] + '.jpg', '', card);
    el('div', 'ring', card);
    return card;
  });
  const infos = CAROUSEL.map(key => {
    const th = TH[key];
    const info = el('div', 'info', content);
    el('div', 'name', info, th.name);
    el('div', 'summary', info, th.summary);
    const meta = el('div', 'meta', info);
    const dots = el('div', 'dots', meta);
    for (let a = 1; a <= 6; a++) el('i', '', dots).style.background = th.term.ansi[a];
    const looks = el('div', 'looks glass', meta);
    for (const look of [...th.looks].reverse()) {
      const chip = el('span', look === th.look ? 'on' : '', looks);
      svg(look === 'dark' ? ICONS.moon : ICONS.sun, chip);
      el('span', '', chip, look === 'dark' ? 'Dark' : 'Light').style.padding = '0';
    }
    el('div', 'count', info, `${ALL.indexOf(th.name) + 1} of ${ALL.length}`);
    return info;
  });
  const hints = el('div', 'hints glass', content);
  const caps = {};
  for (const [keys, label] of [[['←', '→'], 'Choose'], [['↑', '↓'], 'Light / Dark'], [['↩'], 'Apply'], [['esc'], 'Close']]) {
    const hint = el('div', 'hint', hints);
    for (const k of keys) caps[k] = el('span', 'cap', hint, k);
    el('span', '', hint, label).style.marginLeft = '2px';
  }
  return { root, backs, content, cards, infos, hints, caps };
}

function buildWall(plane) {
  const looks = Object.keys(TH).filter(k => k !== LAST && k !== 'chaos');
  const rand = random(7);
  const cols = 13, rows = 11, cc = 6, cr = 5;
  const tiles = [];
  const holder = el('div', '', plane);
  holder.id = 'tiles';
  let last = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      if (r === cr && c === cc) continue;
      let key;
      do { key = looks[Math.floor(rand() * looks.length)]; } while (last.includes(key));
      last = [...last.slice(-14), key];
      // Tiles are laid out at a third of the screen's size and scaled up with their container, so each
      // one is a small layer; full-size tiles would ask the compositor for gigabytes and draw black frames.
      const tile = el('div', 'tile', holder);
      img(TH[key].previews[Math.floor(rand() * 3)] + '-small.jpg', '', tile);
      const x = (c - cc) * (SW + 120), y = (r - cr) * (SH + 120);
      tile.style.left = `${(x - SW / 2) / 3}px`;
      tile.style.top = `${(y - SH / 2) / 3}px`;
      tiles.push({ tile, x, y, d: Math.hypot(c - cc, (r - cr) * 1.1) });
    }
  }
  return tiles;
}

// Captions under the screen: [text, in, out].
const CAPTIONS = [['Nothing matches.', 2 * BEAT, 3.5], ['Now everything does.', 10 * BEAT, 7.6], ['Three backgrounds for every look.', 16.4 * BEAT, 12.2]];

function buildCaptions() {
  const layer = el('div', 'layer', frame);
  const shade = el('div', 'layer', layer);
  shade.id = 'shade';
  const lines = CAPTIONS.map(([text]) => { const line = el('div', 'caption', layer, text); line.style.top = '952px'; return line; });
  const vignette = el('div', 'layer', frame);
  vignette.id = 'vignette';
  const themes = el('div', 'caption big', frame);
  themes.style.top = '470px';
  el('span', 'spectrum', themes, String(ALL.length));
  el('span', '', themes, ' themes.');
  return { layer, shade, lines, vignette, themes };
}

function buildEnd() {
  const layer = el('div', 'layer', frame);
  layer.id = 'endcard';
  const aura = el('div', 'aura', layer);
  const morph = el('div', '', layer);
  Object.assign(morph.style, { position: 'absolute', overflow: 'hidden', opacity: '0' });
  const morphThumb = img(TH[LAST].previews[0] + '.jpg', '', morph);
  Object.assign(morphThumb.style, { position: 'absolute', inset: '0', width: '100%', height: '100%', objectFit: 'cover' });
  // The icon keeps its own shape: it is square, unclipped, and fades in over the tile as the tile becomes square.
  const morphIcon = img('assets/icon.png', '', layer);
  Object.assign(morphIcon.style, { position: 'absolute', opacity: '0' });
  const word = el('div', 'word', layer, 'Scene');
  const tag = el('div', 'tag', layer, 'One theme for your whole Mac.');
  return { layer, aura, morph, morphIcon, word, tag };
}

// Screen coordinates of an element's center, measured before the camera moves anything.
function center(node) {
  const r = node.getBoundingClientRect(), s = document.getElementById('screen').getBoundingClientRect();
  return { x: r.left - s.left + r.width / 2, y: r.top - s.top + r.height / 2, w: r.width, h: r.height };
}

// ?thumbs builds only DesktopPreview, to render the pictures that the window, the switcher, and the wall show.
const THUMBS = new URLSearchParams(location.search).has('thumbs');
let preview, stageLayer, plane, glows, tiles, screen, before, after, rim, panel, app, switcher, morph, pointer, captions, end, grain, fade, spots;
if (THUMBS) {
  preview = buildPreview(frame);
} else {
  stageLayer = el('div', 'layer', frame);
  stageLayer.id = 'stage';
  plane = el('div', '', stageLayer);
  plane.id = 'plane';
  glows = [el('div', 'screen-glow', plane), el('div', 'screen-glow', plane)];
  glows.forEach(g => Object.assign(g.style, { left: `${-SW / 2}px`, top: `${-SH / 2}px`, backgroundSize: 'cover' }));
  tiles = buildWall(plane);
  screen = el('div', '', plane);
  screen.id = 'screen';
  Object.assign(screen.style, { left: `${-SW / 2}px`, top: `${-SH / 2}px` });
  before = buildDesk(screen, ['chaos', HERO, LAST]);
  after = buildDesk(screen, [HERO, LAST]);
  rim = el('div', '', screen);
  rim.id = 'rim';
  app = buildApp(screen);
  const extra = center(before.extra);
  panel = buildPanel(screen, extra.x);
  switcher = buildSwitcher(screen);
  morph = el('div', '', screen);
  morph.id = 'morph';
  img(TH['primary:light'].previews[0] + '.jpg', '', morph);
  pointer = svg(ICONS.pointer, screen);
  pointer.id = 'pointer';
  captions = buildCaptions();
  end = buildEnd();
  grain = el('div', 'layer', frame);
  grain.id = 'grain';
  fade = el('div', 'layer', frame);
  fade.id = 'fade';
  [stageLayer, captions.layer, captions.vignette, captions.themes, end.layer, grain, fade].forEach((node, i) => { node.style.zIndex = String(i + 1); });
  // Where the pointer goes, in screen points.
  const tile = center(panel.cells[GRID.indexOf(HERO)].thumb);
  const lastPage = app.pages[app.pages.length - 1];
  const picks = [...app.pages[5].page.querySelectorAll('.pick')].map(center);
  const segs = [...app.pages[5].page.querySelectorAll('.seg span')].map(center);
  spots = { extra, tile, picks, light: segs[1], toolbar: center(app.buttons[0]), preview: center(lastPage.preview), panel: center(panel.panel) };
}

// MARK: - Rendering

// The camera is the plane's transform: the Mac's screen sits in its middle, and the wall of themes around it.
// Each key is [time, scale, x and y of the screen's middle in the frame].
const WIDE = [0.925, 960, 466];
function focus(k, point, at = [960, 540]) { return [k, at[0] - (point.x - SW / 2) * k, at[1] - (point.y - SH / 2) * k]; }
function camera(t) {
  const onPanel = focus(1.45, { x: spots.panel.x, y: spots.panel.y + 40 });
  // Each key is [time, framing, easing of the move that starts there]: holds drift on a sine, moves ease in and out.
  const keys = [
    [0, [0.9, 960, 468], SINE], [3.5, WIDE, SMOOTH], [4.55, onPanel, SINE], [TILE_CLICK, focus(1.47, { x: spots.panel.x, y: spots.panel.y + 40 }), SMOOTH],
    [WAVE[0] + 1.05, WIDE, SINE], [OPEN, [0.94, 960, 466], SMOOTH], [OPEN + 0.85, [1.1, 960, 452], SINE], [TOOLBAR, [1.13, 960, 452], SMOOTH],
    [MORPH[1], [1920 / SW, 960, 511], SINE], [RETURN, [1920 / SW, 960, 511], SMOOTH], [RETURN + 0.9, WIDE, SINE], [WALL[0], [0.95, 960, 466]],
  ];
  if (t < WALL[0]) {
    let i = 0;
    while (i < keys.length - 2 && t >= keys[i + 1][0]) i++;
    const [t0, a, ease] = keys[i], [t1, b] = keys[i + 1];
    const p = ease(seg(t, t0, t1));
    return { k: lerp(a[0], b[0], p), cx: lerp(a[1], b[1], p), cy: lerp(a[2], b[2], p), rx: 0, rz: 0 };
  }
  if (t < RECEDE[0]) {
    const p = SMOOTH(seg(t, WALL[0], WALL[1])), drift = seg(t, WALL[1], RECEDE[0]);
    return { k: lerp(0.95, 0.2, p) * (1 - 0.06 * drift), cx: 960 - 60 * SINE(drift), cy: lerp(466, 575, p), rx: 52 * p, rz: -27 * p + 3 * drift };
  }
  const p = SMOOTH(seg(t, RECEDE[0], RECEDE[1]));
  return { k: lerp(0.2 * 0.94, 0.3, p), cx: lerp(900, 960, p), cy: lerp(575, 430, p), rx: 52 * (1 - p), rz: -24 * (1 - p) };
}

// Which desktop shows, and a wave that reveals the next one from a point.
function renderDesks(t) {
  let a, b = null, p = 0, origin;
  if (t < WAVE[0]) a = 'chaos';
  else if (t < WAVE[1]) { a = 'chaos'; b = HERO; p = seg(t, WAVE[0], WAVE[1]); origin = spots.tile; }
  else if (t < WAVE2[0]) a = HERO;
  else if (t < WAVE2[1]) { a = HERO; b = LAST; p = seg(t, WAVE2[0], WAVE2[1]); origin = { x: SW / 2, y: 330 }; }
  else a = LAST;
  paintDesk(before, a);
  if (b) {
    paintDesk(after, b);
    const far = Math.max(...[[0, 0], [SW, 0], [0, SH], [SW, SH]].map(([x, y]) => Math.hypot(x - origin.x, y - origin.y)));
    const F = 110, r = SMOOTH(p) * (far + F + 40);
    const mask = `radial-gradient(circle at ${origin.x}px ${origin.y}px, #000 ${Math.max(0, r - F)}px, transparent ${r}px)`;
    style(after.desk, { display: '', webkitMaskImage: mask, maskImage: mask });
    const glow = TH[b].ui.accent;
    style(rim, {
      opacity: String(1 - SMOOTH(seg(p, 0.7, 1))),
      background: `radial-gradient(circle at ${origin.x}px ${origin.y}px, rgba(0,0,0,0) ${Math.max(0, r - F - 90)}px, ${alpha(glow, 0.5)} ${Math.max(0, r - F * 0.6)}px, rgba(255,255,255,0.42) ${Math.max(0, r - F * 0.22)}px, ${alpha(glow, 0.25)} ${Math.max(0, r - 6)}px, rgba(0,0,0,0) ${r + 22}px)`,
    });
  } else {
    after.desk.style.display = 'none';
    rim.style.opacity = '0';
  }
  // The light the screen throws on the dark around it.
  const shown = b && p > 0.5 ? b : a;
  const wall = `url(${ASSET}${wallOf(shown)}-small.jpg)`;
  glows[0].style.backgroundImage = wall;
  glows[0].style.opacity = String(0.3 * (1 - SMOOTH(seg(t, WALL[0], WALL[0] + 0.6))));
  glows[1].style.opacity = '0';
  // Scene's menu bar item lights up while its panel is open.
  const open = t >= MENU_CLICK && t < TILE_CLICK + 0.2;
  for (const d of [before, after]) d.extra.style.background = open ? 'rgba(255,255,255,0.22)' : 'transparent';
}

function renderPanel(t) {
  const shown = t >= MENU_CLICK && t < TILE_CLICK + 0.4;
  panel.panel.style.display = shown ? '' : 'none';
  if (!shown) return;
  const open = APPLE(seg(t, MENU_CLICK, MENU_CLICK + 0.22)), close = SMOOTH(seg(t, TILE_CLICK + 0.14, TILE_CLICK + 0.34));
  style(panel.panel, { opacity: String(Math.min(open * 1.4, 1) * (1 - close)), transform: `scale(${lerp(0.97, 1, open) - 0.01 * close})` });
  const picked = t >= TILE_CLICK;
  const swap = SMOOTH(seg(t, TILE_CLICK, TILE_CLICK + 0.12));
  panel.heroImg.style.opacity = String(swap);
  panel.none.style.opacity = String(1 - swap);
  panel.chosen.style.opacity = String(swap);
  for (const c of panel.cells) {
    c.ring.style.opacity = c.key === HERO && picked ? '1' : '0';
    c.thumb.style.opacity = c.key === HERO && t >= TILE_CLICK - 0.06 && t < TILE_CLICK + 0.08 ? '0.75' : '1';
  }
}

// The window's page at t, and how far the change to it has come.
function pageAt(t) {
  const i = Math.max(0, stage(t, PAGES.map(p => p[0])));
  const duration = i === PAGES.length - 1 ? 0.3 : PAGES[i][1] === (PAGES[i - 1] || [])[1] ? 0.2 : 0.12;
  return { i, from: Math.max(0, i - 1), p: i === 0 ? 1 : SMOOTH(seg(t, PAGES[i][0], PAGES[i][0] + duration)), ambient: i === 0 ? 1 : SMOOTH(seg(t, PAGES[i][0], PAGES[i][0] + 0.45)) };
}

function renderApp(t) {
  const shown = t >= OPEN && t < MORPH[1] + 0.05;
  app.app.style.display = shown ? '' : 'none';
  if (!shown) return;
  const open = spring(t - OPEN, 0.42, 0.86), fadeIn = SMOOTH(seg(t, OPEN, OPEN + 0.22));
  const leave = SMOOTH(seg(t, MORPH[0], MORPH[0] + 0.3));
  style(app.app, { opacity: String(fadeIn * (1 - leave)), transform: `scale(${lerp(0.94, 1, open) - 0.015 * leave})` });
  const { i, from, p, ambient } = pageAt(t);
  app.pages.forEach((pg, n) => { pg.page.style.opacity = String(n === i ? p : n === from && i !== from ? 1 - p : 0); });
  app.ambients.forEach((layer, n) => { layer.style.opacity = String(n === i ? ambient : n === from && i !== from ? 1 : 0); });
  // The page's preview hands over to the moving card when the switcher opens.
  app.pages[PAGES.length - 1].preview.style.visibility = t >= MORPH[0] ? 'hidden' : '';
  // The selection moves down the sidebar with each page.
  const rowOf = n => app.rows[PAGES[n][1].split(':')[0]].top;
  const y = lerp(rowOf(from), rowOf(i), SMOOTH(seg(t, PAGES[i][0], PAGES[i][0] + 0.14)));
  app.selection.style.top = `${y + 2}px`;
  const primary = app.rows.primary.thumbs;
  primary[1].style.opacity = String(SMOOTH(seg(t, LIGHT, LIGHT + 0.3)));
  // The Dark / Light control slides to Light.
  const k = SMOOTH(seg(t, LIGHT, LIGHT + 0.25));
  for (const pg of app.pages) {
    if (!pg.knob) continue;
    const [d, l] = pg.segs;
    style(pg.knob, { left: `${lerp(d.offsetLeft, l.offsetLeft, k)}px`, width: `${lerp(d.offsetWidth, l.offsetWidth, k)}px` });
  }
  // The toolbar's switcher button, pressed.
  const hit = t >= TOOLBAR - 0.03 && t < TOOLBAR + 0.25 ? Math.exp(-Math.max(0, t - TOOLBAR) * 9) : 0;
  app.buttons[0].style.background = `rgba(255,255,255,${0.28 * hit})`;
}

function renderSwitcher(t) {
  const sw = switcher;
  // On ↩ the cards and text leave first, then the blurred backdrop, over the desktop that is already changing.
  const open = SMOOTH(seg(t, MORPH[0], MORPH[0] + 0.5));
  const leave = IN(seg(t, RETURN, RETURN + 0.2));
  const clear = SMOOTH(seg(t, RETURN + 0.05, RETURN + 0.5));
  const visible = open * (1 - clear);
  sw.root.style.display = visible > 0 ? '' : 'none';
  if (visible <= 0) return;
  sw.root.style.opacity = String(visible);
  style(sw.content, { opacity: String(1 - leave), transform: `scale(${1 - 0.04 * leave})`, filter: leave > 0 ? `blur(${leave * 10}px)` : 'none' });
  const s = CAROUSEL_START + MOVES.reduce((sum, m) => sum + spring(t - m), 0);
  sw.backs.forEach((b, i) => { b.style.opacity = String(clamp(1 - Math.abs(i - s) * 1.4)); });
  const width = SW * 0.44, height = width * 10 / 16, step = width * 0.7 + 24;
  const enter = spring(t - (MORPH[0] + 0.25), 0.5, 0.9);
  sw.cards.forEach((card, i) => {
    const d = i - s, ad = Math.abs(d), near = Math.min(ad, 1);
    const scale = 1 - 0.2 * near;
    const rot = -24 * clamp(d, -1, 1);
    let opacity = ad <= 1 ? 1 - 0.3 * ad : Math.max(0, 0.7 - (ad - 1) * 0.35);
    if (i === CAROUSEL_START && t < MORPH[1]) opacity = 0;        // the moving card stands in for it
    else if (i !== CAROUSEL_START) opacity *= enter;
    const x = 720 + d * step * enter, y = 318;
    const selected = 1 - near;
    style(card, {
      display: opacity > 0.002 ? '' : 'none',
      transform: `translate(${x - width / 2}px, ${y - height / 2}px) perspective(1100px) rotateY(${rot}deg) scale(${scale})`,
      opacity: String(opacity), zIndex: String(100 - Math.round(ad * 10)),
      boxShadow: `0 ${lerp(10, 26, selected)}px ${lerp(16, 44, selected)}px rgba(0,0,0,${lerp(0.3, 0.55, selected)})`,
    });
    card.querySelector('.ring').style.boxShadow = `inset 0 0 0 1px rgba(255,255,255,${lerp(0.12, 0.35, selected)})`;
  });
  const infoIn = APPLE(seg(t, MORPH[0] + 0.35, MORPH[0] + 0.95));
  sw.infos.forEach((info, i) => {
    const w = clamp(1 - Math.abs(i - s) * 2.2);
    style(info, { display: w > 0 ? '' : 'none', opacity: String(w * infoIn), filter: w < 1 ? `blur(${(1 - w) * 6}px)` : 'none', transform: `translateY(${(1 - infoIn) * 14}px)` });
  });
  const hintsIn = APPLE(seg(t, MORPH[0] + 0.45, MORPH[0] + 1.05));
  style(sw.hints, { opacity: String(hintsIn), transform: `translateX(-50%) translateY(${(1 - hintsIn) * 12}px)` });
  const pressed = (times, key) => {
    const hit = Math.max(0, ...times.map(m => t >= m - 0.02 ? Math.exp(-(t - m + 0.02) * 7) : 0));
    style(sw.caps[key], { background: `rgba(255,255,255,${0.1 + 0.75 * hit})`, color: hit > 0.5 ? '#111' : '#f5f5f7', transform: `scale(${1 - 0.1 * hit})` });
  };
  pressed(MOVES, '→');
  pressed([RETURN], '↩');
}

// The window's preview grows into the switcher's middle card.
function renderMorph(t) {
  const active = t >= MORPH[0] && t < MORPH[1];
  morph.style.display = active ? 'block' : 'none';
  if (!active) return;
  const p = APPLE(seg(t, MORPH[0], MORPH[1]));
  const a = { x: spots.preview.x - spots.preview.w / 2, y: spots.preview.y - spots.preview.h / 2, w: spots.preview.w, h: spots.preview.h };
  const w = SW * 0.44, h = w * 10 / 16, b = { x: 720 - w / 2, y: 318 - h / 2, w, h };
  style(morph, {
    left: `${lerp(a.x, b.x, p)}px`, top: `${lerp(a.y, b.y, p)}px`, width: `${lerp(a.w, b.w, p)}px`, height: `${lerp(a.h, b.h, p)}px`,
    borderRadius: '14px', boxShadow: `0 ${lerp(16, 26, p)}px ${lerp(30, 44, p)}px rgba(0,0,0,${lerp(0.3, 0.55, p)}), inset 0 0 0 1px rgba(255,255,255,${0.35 * p})`,
  });
}

// The pointer: where it is at each key time, and when it clicks.
function renderPointer(t) {
  const s = spots;
  const path = [
    [2.3, 1015, 590, 0], [2.55, 1015, 590, 1], [3.62, s.extra.x - 2, s.extra.y + 1, 1], [3.95, s.extra.x - 2, s.extra.y + 1, 1],
    [4.85, s.tile.x + 6, s.tile.y + 4, 1], [5.35, s.tile.x + 6, s.tile.y + 4, 1], [5.7, s.tile.x + 30, s.tile.y + 60, 0],
    [10.0, s.picks[1].x + 70, s.picks[1].y + 90, 0], [10.22, s.picks[1].x + 70, s.picks[1].y + 90, 1], [10.56, s.picks[1].x + 8, s.picks[1].y + 6, 1],
    [10.9, s.picks[1].x + 8, s.picks[1].y + 6, 1], [11.18, s.picks[2].x + 8, s.picks[2].y + 6, 1], [11.8, s.picks[2].x + 8, s.picks[2].y + 6, 1],
    [12.42, s.light.x + 4, s.light.y + 3, 1], [13.8, s.light.x + 4, s.light.y + 3, 1], [14.6, s.toolbar.x + 2, s.toolbar.y + 3, 1],
    [14.85, s.toolbar.x + 2, s.toolbar.y + 3, 1], [15.1, s.toolbar.x + 2, s.toolbar.y + 3, 0],
  ];
  if (t < path[0][0] || t >= path[path.length - 1][0]) { pointer.style.opacity = '0'; return; }
  let i = 0;
  while (i < path.length - 2 && t >= path[i + 1][0]) i++;
  const [t0, x0, y0, o0] = path[i], [t1, x1, y1, o1] = path[i + 1];
  const p = seg(t, t0, t1), m = APPLE(p);
  const clicks = [MENU_CLICK, TILE_CLICK, ...PICKS, LIGHT, TOOLBAR];
  const press = Math.max(0, ...clicks.map(c => t >= c - 0.05 && t < c + 0.15 ? Math.sin(Math.PI * seg(t, c - 0.05, c + 0.15)) : 0));
  style(pointer, { opacity: String(lerp(o0, o1, SMOOTH(p))), transform: `translate(${lerp(x0, x1, m) - 3}px, ${lerp(y0, y1, m) - 2}px) scale(${1 - 0.12 * press})` });
}

function renderPlane(t) {
  const cam = camera(t);
  plane.style.transform = `translate3d(${cam.cx}px, ${cam.cy}px, 0) rotateX(${cam.rx}deg) rotateZ(${cam.rz}deg) scale(${cam.k})`;
  const iconTakeover = t >= ICON[0];
  screen.style.display = iconTakeover ? 'none' : '';
  // The wall: tiles fade in as the camera pulls back and fade out, from the edges in, as it leaves.
  const wallIn = SMOOTH(seg(t, WALL[0] + 0.1, WALL[1] - 0.2));
  const rz = cam.rz * Math.PI / 180, rx = cam.rx * Math.PI / 180;
  for (const tl of tiles) {
    let o = wallIn;
    if (o > 0) {
      const yr = tl.x * Math.sin(rz) + tl.y * Math.cos(rz);
      const depth = -yr * Math.sin(rx) * cam.k;         // how far the tile has tipped away
      o *= clamp(1 - depth / 900) * clamp(1.25 - tl.d * 0.09);
      o *= 1 - SMOOTH(seg(t, RECEDE[0] + (8 - tl.d) * 0.06, RECEDE[0] + 0.4 + (8 - tl.d) * 0.06));
    }
    tl.tile.style.opacity = String(o);
    tl.tile.style.display = o > 0.002 ? '' : 'none';
  }
}

function renderCaptions(t) {
  let shade = 0;
  CAPTIONS.forEach(([, a, b], i) => {
    const p = APPLE(seg(t, a, a + 0.7)), out = IN(seg(t, b - 0.35, b));
    const v = p * (1 - out);
    style(captions.lines[i], { opacity: String(v), filter: `blur(${(1 - p) * 12 + out * 10}px)`, transform: `translateY(${(1 - p) * 16}px)` });
    if (i === 2) shade = v;
  });
  captions.shade.style.opacity = String(shade);
  const themesIn = APPLE(seg(t, THEMES_CAPTION, THEMES_CAPTION + 0.8));
  const themesOut = IN(seg(t, RECEDE[0] - 0.25, RECEDE[0] + 0.15));
  const v = themesIn * (1 - themesOut);
  captions.vignette.style.opacity = String(v);
  style(captions.themes, { opacity: String(v), filter: `blur(${(1 - themesIn) * 16 + themesOut * 12}px)`, transform: `translateY(${(1 - themesIn) * 20}px) scale(${1 + 0.02 * (1 - themesIn)})` });
  captions.themes.firstChild.style.backgroundPosition = `${(t * 18) % 300}% 0`;
}

function renderEnd(t) {
  const cam = camera(Math.min(t, RECEDE[1]));
  // The screen, now a small flat tile in the middle, becomes the app icon.
  const tile = { w: SW * cam.k, h: SH * cam.k };
  const p = APPLE(seg(t, ICON[0], ICON[1] - 0.15));
  const icon = { x: 820, y: 290, w: 280, h: 280 };
  const x = lerp(cam.cx - tile.w / 2, icon.x, p), y = lerp(cam.cy - tile.h / 2, icon.y, p);
  const settle = t >= END ? 1 + 0.018 * Math.exp(-(t - END) * 4) * Math.cos((t - END) * 9) : 1;
  const active = t >= ICON[0];
  end.morph.style.display = active ? '' : 'none';
  end.morphIcon.style.display = active ? '' : 'none';
  if (active) {
    const w = lerp(tile.w, icon.w, p) * settle, h = lerp(tile.h, icon.h, p) * settle;
    const left = x - (w - lerp(tile.w, icon.w, p)) / 2, top = y - (h - lerp(tile.h, icon.h, p)) / 2;
    const iconIn = SMOOTH(seg(p, 0.3, 0.8));
    style(end.morph, {
      opacity: String(1 - SMOOTH(seg(p, 0.55, 0.95))), left: `${left}px`, top: `${top}px`, width: `${w}px`, height: `${h}px`,
      borderRadius: `${lerp(22 * cam.k, 62, p)}px`, boxShadow: `0 ${lerp(12, 30, p)}px ${lerp(30, 70, p)}px rgba(0,0,0,${0.55 * (1 - iconIn)})`,
    });
    const side = Math.min(w, h);
    style(end.morphIcon, {
      opacity: String(iconIn), left: `${left + (w - side) / 2}px`, top: `${top + (h - side) / 2}px`, width: `${side}px`, height: `${side}px`,
      filter: `drop-shadow(0 ${24 * iconIn}px ${40 * iconIn}px rgba(0,0,0,0.5))`,
    });
  }
  const auraOn = SMOOTH(seg(t, ICON[0] + 0.4, END)) * (1 + 0.5 * Math.exp(-Math.max(0, t - END) * 3) * (t >= END ? 1 : 0));
  end.aura.style.opacity = String(0.42 * auraOn);
  end.aura.style.transform = `scale(${1 + 0.04 * Math.sin(t * 1.3)})`;
  const wordIn = APPLE(seg(t, END + 0.25, END + 1.0));
  style(end.word, { opacity: String(wordIn), filter: `blur(${(1 - wordIn) * 14}px)`, transform: `translateY(${(1 - wordIn) * 18}px)` });
  const tagIn = APPLE(seg(t, END + 0.55, END + 1.3));
  style(end.tag, { opacity: String(tagIn), filter: `blur(${(1 - tagIn) * 12}px)`, transform: `translateY(${(1 - tagIn) * 14}px)` });
}

let frameIndex = 0;
window.render = t => {
  frameIndex = Math.round(t * 60);
  renderPlane(t);
  renderDesks(t);
  renderPanel(t);
  renderApp(t);
  renderSwitcher(t);
  renderMorph(t);
  renderPointer(t);
  renderCaptions(t);
  renderEnd(t);
  const r = random(frameIndex + 1);
  grain.style.backgroundPosition = `${Math.floor(r() * 256)}px ${Math.floor(r() * 256)}px`;
  fade.style.opacity = String(SMOOTH(seg(t, FILM - 0.4, FILM)) + (1 - SMOOTH(seg(t, 0, 0.15))));
};

// DesktopPreview for one look and one of its backgrounds, full size.
window.renderThumb = (key, index) => {
  const th = TH[key];
  preview.wall.src = `${ASSET}${th.walls[index]}.jpg`;
  for (const b of preview.list) paint(b, roleColor(key, b.role));
  preview.moon.style.display = th.look === 'light' ? 'none' : '';
  preview.sun.style.display = th.look === 'light' ? '' : 'none';
  return preview.wall.decode();
};

window.ready = (async () => {
  await document.fonts.ready;
  await Promise.all([...document.images].filter(i => i.src).map(i => i.decode().catch(() => { throw new Error(`cannot load ${i.src}`); })));
  const params = new URLSearchParams(location.search);
  if (params.has('t')) window.render(parseFloat(params.get('t')));
  return true;
})();
