'use strict';
// Scene's 20-second product film. window.render(t) draws the frame at t seconds; nothing else moves.
// The cut follows the music: 96 BPM, a beat is 0.625 s and a bar 2.5 s, and 8 bars make 20 s.

const ASSET = '../../build/film/';
const TH = window.FILM_THEMES;
const BEAT = 60 / 96;
const SW = 1440, SH = 900; // the Mac's screen, in its own points

// MARK: - Timeline

const PRESS = [BEAT, 1.5 * BEAT, 2 * BEAT, 3 * BEAT];          // ⌃ ⇧ ⌘ Space
const MORPH = [1.95, 2.55];                                     // Space becomes the switcher's card
const MOVES = [5 * BEAT, 6 * BEAT, 7 * BEAT];                   // → → → in the switcher
const RETURN = 7.5 * BEAT;                                       // ↩
// The new wallpaper starts to bloom under the closing switcher, then each app follows on the beat.
const STEP = { wallpaper: 7.6 * BEAT, menubar: 8 * BEAT, term: 9 * BEAT, editor: 10 * BEAT, accent: 11 * BEAT };
const WORDS = [8.5 * BEAT, 9 * BEAT, 10 * BEAT, 11 * BEAT];
const ALL_AT_ONCE = 13 * BEAT;
// Instant switches that speed up: quarter notes, then eighths, then sixteenths.
const SWITCHES = [
  [14 * BEAT, 'amber:dark'], [15 * BEAT, 'primary:light'], [16 * BEAT, 'rain-bridge:dark'], [17 * BEAT, 'glacier:light'],
  [17.5 * BEAT, 'phosphor:dark'], [18 * BEAT, 'confetti:light'], [18.5 * BEAT, 'deprecated:dark'], [19 * BEAT, 'blueprint:dark'],
  [19.25 * BEAT, 'matcha:light'], [19.5 * BEAT, 'lamplight:dark'], [19.75 * BEAT, 'moss:dark'], [20 * BEAT, 'vaporwave:dark'],
];
// The switcher's layout on a 1440 x 900 screen, and where the camera looks while it is open.
const CARD_Y = 318, INFO_TOP = 560, HINTS_TOP = 782, SWITCHER_CY = 511;
const WALL = [12.5, 13.9];
const THEMES_CAPTION = 21 * BEAT;
const RECEDE = [15.0, 16.3];
const ICON = [16.3, 17.5];
const END = 17.5;
const FILM = 20;
// The fast moves: Space to the switcher's close, the tilt onto the wall, and the wall to the icon.
// render.mjs gives these frames motion blur; the rest move too slowly to need it.
window.BLUR = [[PRESS[3], RETURN + 0.95], [WALL[0] - 0.05, WALL[1] + 0.2], [RECEDE[0] - 0.05, END]];

const START = 'marginalia:light', HERO = 'cold-aisle:dark';
const CAROUSEL = ['deprecated:dark', 'rain-bridge:dark', 'marginalia:light', 'glacier:light', 'amber:dark', 'cold-aisle:dark', 'phosphor:dark', 'primary:dark'];
const CAROUSEL_START = 2;
const LIGHTS = ['amber:dark', 'glacier:light', 'cyberdeck:dark', 'cold-aisle:dark'];

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

function roleColor(theme, role) {
  const th = TH[theme];
  switch (role) {
    case 'menubar': return th.look === 'light' ? 'rgba(0,0,0,0.86)' : 'rgba(255,255,255,0.96)';
    case 'edge': return th.look === 'light' ? 'rgba(0,0,0,0.16)' : 'rgba(255,255,255,0.13)';
    case 'onAccent': return th.onAccent;
  }
  const [group, key, index] = role.split('.');
  if (group === 'ui') return th.ui[key];
  if (group === 'term') return key === 'ansi' ? th.term.ansi[+index] : th.term[key];
  const value = th.syn[key];
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
  e.src = ASSET + src;
  e.decoding = 'sync';
  return e;
}
function svg(markup, parent) {
  const holder = el('span', '', parent);
  holder.innerHTML = markup;
  return holder;
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
};

// Everything a theme colors registers here. group and position decide when it changes in the reveal.
const bindings = [];
function bind(node, prop, role, group, window) {
  bindings.push({ node, prop, role, group, window, y: 0, x: 0 });
}

function buildScreen(parent, withSwitcher) {
  const screen = el('div', '', parent);
  screen.id = 'screen';
  const walls = {};
  for (const key of new Set([START, HERO, ...SWITCHES.map(s => s[1])])) walls[key] = img(TH[key].wallpaper, 'wp', screen);
  const bloomRim = el('div', 'wp', screen);

  // Menu bar.
  const bar = el('div', 'menubar', screen);
  const left = el('div', 'left', bar);
  el('span', 'apple', left, '');
  el('b', '', left, 'Code');
  for (const item of ['File', 'Edit', 'Selection', 'View', 'Go', 'Window', 'Help']) el('span', '', left, item);
  const right = el('div', 'right', bar);
  for (const name of ['palette', 'control', 'wifi', 'battery', 'search']) svg(ICONS[name], right);
  el('span', '', right, 'Tue Sep 29  9:41 AM');
  bind(bar, 'color', 'menubar', 'menubar');

  // Terminal, behind: its window is inactive.
  const term = el('div', 'win term', screen);
  Object.assign(term.style, { left: '92px', top: '118px', width: '668px', height: '436px' });
  const termBar = el('div', 'titlebar', term);
  const termLights = el('div', 'lights', termBar);
  for (let i = 0; i < 3; i++) { const dot = el('i', '', termLights); bind(dot, 'backgroundColor', 'ui.border', 'term', 'term'); }
  const termTitle = el('div', 'title', termBar, 'scene — zsh');
  bind(termTitle, 'color', 'ui.muted', 'term', 'term');
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
      for (let i = line[1]; i < line[1] + 8; i++) bind(el('span', 'swatch', row), 'backgroundColor', `term.ansi.${i}`, 'term', 'term');
      continue;
    }
    for (const [text, ansi] of line) {
      if (text === 'cursor') { bind(el('span', 'cursor-block', row), 'backgroundColor', 'term.cursor', 'term', 'term'); continue; }
      const span = el('span', '', row, text);
      if (ansi === 12) span.style.fontWeight = '600';
      bind(span, 'color', ansi == null ? 'term.foreground' : `term.ansi.${ansi}`, 'term', 'term');
    }
  }
  bind(term, 'backgroundColor', 'term.background', 'term', 'term');
  bind(term, '--edge', 'edge', 'term', 'term');

  // Editor, in front.
  const ed = el('div', 'win editor', screen);
  Object.assign(ed.style, { left: '612px', top: '236px', width: '752px', height: '560px' });
  bind(ed, 'backgroundColor', 'ui.surface', 'editor', 'editor');
  bind(ed, '--edge', 'edge', 'editor', 'editor');
  const edBar = el('div', 'titlebar', ed);
  const edLights = el('div', 'lights', edBar);
  for (const c of ['#ff5f57', '#febc2e', '#28c840']) el('i', '', edLights).style.background = c;
  const tabs = el('div', 'tabs', ed);
  const tab1 = el('div', 'tab', tabs, 'Switcher.swift');
  bind(tab1, 'backgroundColor', 'ui.background', 'editor', 'editor');
  bind(tab1, 'color', 'ui.foreground', 'editor', 'editor');
  bind(el('div', 'bar', tab1), 'backgroundColor', 'ui.accent', 'accent');
  const tab2 = el('div', 'tab', tabs, 'Theme.swift');
  bind(tab2, 'color', 'ui.muted', 'editor', 'editor');
  const side = el('div', 'side', ed);
  bind(el('div', 'head', side, 'SCENE'), 'color', 'ui.muted', 'editor', 'editor');
  const tree = [['▾  Sources', 0], ['Engine.swift', 1, 1], ['Switcher.swift', 1, 1, true], ['Theme.swift', 1, 1], ['▾  Themes', 0],
                ['cold-aisle', 1, 4], ['marginalia', 1, 4], ['Package.swift', 0, 1], ['README.md', 0, 5]];
  for (const [name, depth, dot, selected] of tree) {
    const item = el('div', 'item', side);
    item.style.paddingLeft = `${18 + depth * 16}px`;
    if (dot != null) bind(el('i', 'dot', item), 'backgroundColor', `term.ansi.${dot}`, 'editor', 'editor');
    bind(el('span', '', item, name), 'color', selected ? 'ui.foreground' : 'ui.muted', 'editor', 'editor');
    if (selected) bind(item, 'backgroundColor', 'ui.selection', 'accent');
  }
  const code = el('div', 'code', ed);
  bind(code, 'backgroundColor', 'ui.background', 'editor', 'editor');
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
    if (i === 8) {
      const current = el('div', 'current', line);
      bind(current, 'backgroundColor', 'ui.currentLine', 'editor', 'editor');
    }
    bind(el('span', 'num', line, String(i + 1)), 'color', i === 8 ? 'ui.foreground' : 'ui.muted', 'editor', 'editor');
    const text = el('span', '', line);
    text.style.position = 'relative';
    for (const [piece, role] of tokens) {
      const span = el('span', '', text, piece);
      if (['comment', 'parameter'].includes(role)) span.style.fontStyle = 'italic';
      bind(span, 'color', role ? `syn.${role}` : 'ui.foreground', 'editor', 'editor');
    }
    if (i === 8) {
      const caret = el('div', 'caret', line);
      caret.style.left = `${54 + 8.7 * 54}px`;
      bind(caret, 'backgroundColor', 'ui.cursor', 'editor', 'editor');
    }
  });
  const status = el('div', 'status', ed);
  for (const text of ['⎇  main', '✓ 120 tests']) el('span', '', status, text);
  el('span', 'spacer', status);
  for (const text of ['Ln 9, Col 55', 'Spaces: 4', 'Swift']) el('span', '', status, text);
  bind(status, 'backgroundColor', 'ui.accent', 'accent');
  bind(status, 'color', 'onAccent', 'accent');

  const switcher = withSwitcher ? buildSwitcher(screen) : null;
  return { screen, walls, bloomRim, term, ed, switcher };
}

function buildSwitcher(parent) {
  const root = el('div', 'switcher', parent);
  const backs = CAROUSEL.map(key => { const b = el('div', 'back', root); b.style.backgroundImage = `url(${ASSET}${TH[key].wallpaperSmall})`; return b; });
  el('div', 'dim', root);
  const content = el('div', '', root);
  Object.assign(content.style, { position: 'absolute', inset: '0', transformOrigin: '720px 450px' });
  const cards = CAROUSEL.map(key => {
    const card = el('div', 'card', content);
    img(TH[key].thumb, '', card);
    el('div', 'ring', card);
    if (key === START) {
      const badge = el('div', 'badge glass', card);
      svg(ICONS.check, badge);
      el('span', '', badge, 'Current');
    }
    return card;
  });
  const infos = CAROUSEL.map((key, i) => {
    const info = el('div', 'info', content);
    el('div', 'name', info, TH[key].name);
    el('div', 'summary', info, TH[key].summary);
    const meta = el('div', 'meta', info);
    const dots = el('div', 'dots', meta);
    for (let a = 1; a <= 6; a++) el('i', '', dots).style.background = TH[key].term.ansi[a];
    const looks = el('div', 'looks glass', meta);
    for (const look of [...TH[key].looks].reverse()) {
      const chip = el('span', look === TH[key].look ? 'on' : '', looks);
      svg(look === 'dark' ? ICONS.moon : ICONS.sun, chip);
      el('span', '', chip, look === 'dark' ? 'Dark' : 'Light').style.padding = '0';
    }
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

// MARK: - Scenes

function buildKeys() {
  const light = el('div', 'layer', frame);
  light.id = 'keys-light';
  const blobs = [0, 1, 2].map(() => el('i', '', light));
  const layer = el('div', 'layer', frame);
  const keys = [['⌃', 'control', 168], ['⇧', 'shift', 168], ['⌘', 'command', 168], ['', '', 660]];
  let x = 960 - (168 * 3 + 660 + 26 * 3) / 2;
  const nodes = keys.map(([glyph, label, width]) => {
    const key = el('div', 'key', layer);
    Object.assign(key.style, { left: `${x}px`, top: '456px', width: `${width}px` });
    const tint = el('div', 'tint', key);
    const sheen = el('div', 'sheen', key);
    if (glyph) { el('div', 'glyph', key, glyph); el('div', 'label', key, label); }
    const rect = { x, y: 456, w: width, h: 168 };
    x += width + 26;
    return { key, tint, sheen, rect };
  });
  layer.style.transformOrigin = '960px 540px';
  const morph = el('div', '', frame);
  morph.id = 'morph';
  el('div', 'face', morph);
  const morphImg = img(TH[START].thumb, '', morph);
  return { light, blobs, nodes, morph, morphImg };
}

function buildWall(plane) {
  const looks = Object.keys(TH).filter(k => k !== 'vaporwave:dark');
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
      img(TH[key].thumbSmall, '', tile);
      const x = (c - cc) * (SW + 120), y = (r - cr) * (SH + 120);
      tile.style.left = `${(x - SW / 2) / 3}px`;
      tile.style.top = `${(y - SH / 2) / 3}px`;
      tiles.push({ tile, x, y, d: Math.hypot(c - cc, (r - cr) * 1.1) });
    }
  }
  return tiles;
}

function buildCaptions() {
  const layer = el('div', 'layer', frame);
  const line = el('div', 'caption', layer);
  line.style.top = '946px';
  const words = ['Wallpaper.', 'Terminal.', 'Editor.', 'Accent color.'].map(w => el('span', 'w', line, w));
  const all = el('div', 'caption', layer, 'All at once.');
  all.style.top = '946px';
  const vignette = el('div', 'layer', frame);
  vignette.id = 'vignette';
  const themes = el('div', 'caption big', frame);
  themes.style.top = '470px';
  el('span', 'spectrum', themes, '75');
  el('span', '', themes, ' themes.');
  return { words, all, vignette, themes };
}

function buildEnd() {
  const layer = el('div', 'layer', frame);
  layer.id = 'endcard';
  const aura = el('div', 'aura', layer);
  const morph = el('div', '', layer);
  Object.assign(morph.style, { position: 'absolute', overflow: 'hidden', opacity: '0' });
  const morphThumb = img(TH['vaporwave:dark'].thumb, '', morph);
  Object.assign(morphThumb.style, { position: 'absolute', inset: '0', width: '100%', height: '100%', objectFit: 'cover' });
  // The icon keeps its own shape: it is square, unclipped, and fades in over the tile as the tile becomes square.
  const morphIcon = img('assets/icon.png', '', layer);
  Object.assign(morphIcon.style, { position: 'absolute', opacity: '0' });
  const word = el('div', 'word', layer, 'Scene');
  const tag = el('div', 'tag', layer, 'One theme for your whole Mac.');
  return { aura, morph, morphThumb, morphIcon, word, tag };
}

// ?thumbs builds only the screen, to render the theme desktops that the switcher and the wall show.
const THUMBS = new URLSearchParams(location.search).has('thumbs');
const keys = THUMBS ? null : buildKeys();
const stage = el('div', 'layer', frame);
stage.id = 'stage';
const plane = el('div', '', stage);
plane.id = 'plane';
const glows = [el('div', 'screen-glow', plane), el('div', 'screen-glow', plane)];
glows.forEach(g => Object.assign(g.style, { left: `${-SW / 2}px`, top: `${-SH / 2}px`, backgroundSize: 'cover' }));
const tiles = THUMBS ? [] : buildWall(plane);
const S = buildScreen(plane, !THUMBS);
S.screen.style.left = `${-SW / 2}px`;
S.screen.style.top = `${-SH / 2}px`;
const captions = THUMBS ? null : buildCaptions();
const end = THUMBS ? null : buildEnd();
const grain = el('div', 'layer', frame);
grain.id = 'grain';
const fade = el('div', 'layer', frame);
fade.id = 'fade';
if (!THUMBS) {
  // Painting order, back to front.
  [keys.light, keys.nodes[0].key.parentNode, stage, keys.morph, captions.words[0].parentNode.parentNode, captions.vignette,
   captions.themes, document.getElementById('endcard'), grain, fade].forEach((node, i) => { node.style.zIndex = String(i + 1); });
}

// Where each colored element sits in its window, for the top-to-bottom reveal.
for (const b of bindings) {
  if (!b.window) continue;
  const win = b.window === 'term' ? S.term : S.ed;
  const r = b.node.getBoundingClientRect(), w = win.getBoundingClientRect();
  b.top = r.top - w.top;
  b.h = r.height;
  b.y = b.node === win ? 0 : b.top + r.height / 2;
}
const WIN_H = { term: 436, editor: 560 };

// MARK: - Rendering

function style(node, props) {
  for (const k in props) node.style[k] = props[k];
}

function renderKeys(t) {
  const shown = t < MORPH[1] + 0.1;
  keys.light.style.display = shown ? '' : 'none';
  for (const n of keys.nodes) n.key.style.display = shown ? '' : 'none';
  if (!shown) return;
  // The light under the keys takes a new theme's color at each press.
  const stage = PRESS.filter(p => t >= p).length;
  const color = i => {
    const from = TH[LIGHTS[Math.max(0, i - 1)]].ui.accent, to = TH[LIGHTS[Math.min(i, 3)]].ui.accent;
    return mix(from, to, i === 0 ? 1 : SINE(seg(t, PRESS[i - 1], PRESS[i - 1] + 0.3)));
  };
  const c = color(stage), c2 = TH[LIGHTS[Math.min(stage + 1, 3)]].term.ansi[5];
  const intro = SMOOTH(seg(t, 0.05, 1.1));
  const bloom = Math.exp(-Math.max(0, t - PRESS[3]) * 5) * (t >= PRESS[3] ? 1 : 0);
  const out = seg(t, MORPH[0] + 0.05, MORPH[1]);
  keys.light.style.opacity = (0.8 * intro + 0.5 * bloom) * (1 - SMOOTH(out));
  const drift = t * 0.35;
  const blobs = [[960 + Math.sin(drift) * 180, 640, 980, 330, c], [640 + Math.cos(drift * 1.3) * 110, 590, 640, 280, c2], [1300, 610 + Math.sin(drift * 0.8) * 30, 700, 280, c]];
  keys.nodes[0].key.parentNode.style.transform = `scale(${0.955 + 0.045 * SMOOTH(seg(t, 0, 1.9))})`;
  const sweep = SMOOTH(seg(t, 0.35, 1.55));
  blobs.forEach(([x, y, w, h, col], i) => style(keys.blobs[i], {
    left: `${x - w / 2}px`, top: `${y - h / 2}px`, width: `${w}px`, height: `${h}px`, background: col,
    transform: `scale(${1 + bloom * 0.35})`, opacity: i === 1 ? 0.7 : 1,
  }));
  keys.nodes.forEach((n, i) => {
    const appear = APPLE(seg(t, 0.12 + i * 0.07, 0.9 + i * 0.07));
    const press = t >= PRESS[i] ? APPLE(seg(t, PRESS[i], PRESS[i] + 0.09)) : 0;
    let x = 0, y = (1 - appear) * 26 + press * 5, blur = (1 - appear) * 10, opacity = appear;
    if (i < 3) {
      // The other keys fall away before the space bar grows over them.
      const leave = APPLE(seg(t, PRESS[3] + 0.02, PRESS[3] + 0.32));
      x -= (3 - i) * 90 * leave;
      y += 60 * leave;
      blur += 18 * leave;
      opacity *= 1 - SMOOTH(seg(t, PRESS[3] + 0.02, PRESS[3] + 0.22));
    } else if (t >= MORPH[0]) {
      opacity = 0;
    }
    style(n.key, {
      transform: `translate(${x}px, ${y}px)`, filter: blur > 0.05 ? `blur(${blur}px) brightness(${1 - press * 0.08})` : `brightness(${1 - press * 0.08})`,
      opacity,
    });
    n.tint.style.background = `radial-gradient(120% 90% at 50% 120%, ${c} 0%, rgba(0,0,0,0) 70%)`;
    n.tint.style.opacity = 0.3 * intro + 0.35 * press + 0.45 * bloom;
    // A glint that crosses the whole row once, as if a light passed over the keyboard.
    n.sheen.style.backgroundPosition = `${lerp(-1400, 1500, sweep) - (n.rect.x - 339)}px 0`;
    const glow = 0.25 * intro + 0.4 * press + 0.5 * bloom;
    n.key.style.boxShadow = `inset 0 1.5px 0 rgba(255,255,255,0.16), inset 0 -3px 6px rgba(0,0,0,0.45), 0 0 0 1px rgba(255,255,255,0.05), 0 ${5 - press * 3}px 0 #0b0b0c, 0 ${28 - press * 10}px ${56 - press * 16}px rgba(0,0,0,0.75), 0 20px 70px -18px ${mix('rgba(0,0,0,0)', c, glow)}`;
  });
}

// The camera is the plane's transform: the Mac's screen sits in its middle, and the wall of themes around it.
function camera(t) {
  let k, cx = 960, cy, rx = 0, rz = 0;
  if (t < 4.75) { k = 1920 / SW; cy = SWITCHER_CY; }
  else if (t < 5.6) { const p = SMOOTH(seg(t, 4.75, 5.6)); k = lerp(1920 / SW, 1280 / SW, p); cy = lerp(SWITCHER_CY, 472, p); }
  else if (t < WALL[0]) { const p = SINE(seg(t, 5.6, WALL[0])); k = lerp(1280 / SW, 1330 / SW, p); cy = lerp(472, 466, p); }
  else if (t < RECEDE[0]) {
    const p = SMOOTH(seg(t, WALL[0], WALL[1])), drift = seg(t, WALL[1], RECEDE[0]);
    k = lerp(1330 / SW, 0.2, p) * (1 - 0.06 * drift);
    cy = lerp(466, 575, p);
    cx = 960 - 60 * SINE(drift);
    rx = 52 * p;
    rz = -27 * p + 3 * drift;
  } else {
    const p = SMOOTH(seg(t, RECEDE[0], RECEDE[1]));
    k = lerp(0.2 * 0.94, 0.3, p);
    cx = lerp(900, 960, p);
    cy = lerp(575, 430, p);
    rx = 52 * (1 - p);
    rz = -24 * (1 - p);
  }
  return { k, cx, cy, rx, rz };
}

function desktopPair(t) {
  if (t < SWITCHES[0][0]) return { a: START, b: HERO, mode: 'reveal' };
  let i = SWITCHES.length - 1;
  while (i > 0 && t < SWITCHES[i][0]) i--;
  return { a: i === 0 ? HERO : SWITCHES[i - 1][1], b: SWITCHES[i][1], mode: 'cut', p: SINE(seg(t, SWITCHES[i][0], SWITCHES[i][0] + 0.09)) };
}

function wipe(t, start, duration, y, height, feather = 80) {
  const edge = lerp(-feather, height + feather, SMOOTH(seg(t, start, start + duration)));
  return clamp((edge - y) / feather);
}

function progress(b, t, pair) {
  if (pair.mode === 'cut') return pair.p;
  switch (b.group) {
    case 'menubar': return SMOOTH(seg(t, STEP.menubar, STEP.menubar + 0.45));
    case 'term': return wipe(t, STEP.term, 0.62, b.y, WIN_H.term);
    case 'editor': return wipe(t, STEP.editor, 0.66, b.y, WIN_H.editor);
    case 'accent': return SMOOTH(seg(t, STEP.accent, STEP.accent + 0.4));
  }
  return 1;
}

function renderScreen(t) {
  const pair = desktopPair(t);
  // Until ↩, the switcher covers the desktop: keep it hidden so the switcher fades in from black.
  const desktopOn = t >= RETURN;
  for (const node of [S.term, S.ed, S.screen.querySelector('.menubar'), ...Object.values(S.walls)]) node.style.visibility = desktopOn ? '' : 'hidden';
  // Wallpapers: in the reveal the new one blooms out from the middle; in a cut it cross-fades in 90 ms.
  const reveal = pair.mode === 'reveal' ? APPLE(seg(t, STEP.wallpaper, STEP.wallpaper + 1.25)) : 1;
  for (const [key, node] of Object.entries(S.walls)) {
    let opacity = 0, z = 0, mask = 'none';
    if (key === pair.a) { opacity = 1; z = 1; }
    if (key === pair.b) {
      z = 2;
      if (pair.mode === 'reveal') {
        const r = reveal * 980;
        opacity = reveal > 0 ? 1 : 0;
        mask = reveal >= 1 ? 'none' : `radial-gradient(circle at 50% 56%, #000 ${Math.max(0, r - 170)}px, transparent ${r}px)`;
      } else {
        opacity = pair.p;
      }
    }
    style(node, { opacity, zIndex: z, webkitMaskImage: mask, maskImage: mask });
  }
  const rim = pair.mode === 'reveal' && reveal > 0 && reveal < 1;
  S.bloomRim.style.opacity = rim ? (1 - reveal) * 0.9 : 0;
  if (rim) {
    const r = reveal * 980;
    S.bloomRim.style.background = `radial-gradient(circle at 50% 56%, rgba(255,255,255,0) ${Math.max(0, r - 150)}px, rgba(255,246,220,0.22) ${r - 60}px, rgba(255,255,255,0) ${r + 10}px)`;
  }
  S.bloomRim.style.zIndex = 3;
  for (const b of bindings) {
    const A = roleColor(pair.a, b.role), B = roleColor(pair.b, b.role);
    if (pair.mode === 'reveal' && b.prop === 'backgroundColor' && b.window && b.h > 60) {
      // A tall background wipes from top to bottom, level with the text that changes over it.
      const [start, duration] = b.window === 'term' ? [STEP.term, 0.62] : [STEP.editor, 0.66];
      const F = 80, edge = lerp(-F, WIN_H[b.window] + F, SMOOTH(seg(t, start, start + duration))) - b.top;
      if (edge <= 0) paint(b, A);
      else if (edge - F >= b.h) paint(b, B);
      else b.node.style.background = `linear-gradient(180deg, ${B} 0px, ${B} ${edge - F}px, ${A} ${edge}px, ${A} ${b.h}px)`;
      continue;
    }
    paint(b, mix(A, B, progress(b, t, pair)));
  }
  // The light the screen throws on the dark around it.
  const glowOn = SMOOTH(seg(t, 5.0, 6.2)) * (1 - SMOOTH(seg(t, WALL[0], WALL[0] + 0.6)));
  const g = pair.mode === 'reveal' ? reveal : pair.p;
  glows[0].style.backgroundImage = `url(${ASSET}${TH[pair.a].wallpaperSmall})`;
  glows[1].style.backgroundImage = `url(${ASSET}${TH[pair.b].wallpaperSmall})`;
  glows[0].style.opacity = 0.34 * glowOn * (1 - g);
  glows[1].style.opacity = 0.34 * glowOn * g;
  renderSwitcher(t);
}

function paint(b, value) {
  if (b.prop[0] === '-') b.node.style.setProperty(b.prop, value);
  else if (b.prop === 'backgroundColor') b.node.style.background = value;
  else b.node.style[b.prop] = value;
}

function renderSwitcher(t) {
  const sw = S.switcher;
  // On ↩ the cards and text leave first, then the blurred backdrop, over the desktop that is already changing.
  const open = SMOOTH(seg(t, MORPH[0], MORPH[0] + 0.45));
  const leave = IN(seg(t, RETURN, RETURN + 0.2));
  const clear = SMOOTH(seg(t, RETURN + 0.05, RETURN + 0.5));
  const visible = open * (1 - clear);
  sw.root.style.display = visible > 0 ? '' : 'none';
  if (visible <= 0) return;
  sw.root.style.opacity = visible;
  style(sw.content, { opacity: 1 - leave, transform: `scale(${1 - 0.04 * leave})`, filter: leave > 0 ? `blur(${leave * 10}px)` : 'none' });
  const s = CAROUSEL_START + MOVES.reduce((sum, m) => sum + spring(t - m), 0);
  sw.backs.forEach((b, i) => { b.style.opacity = clamp(1 - Math.abs(i - s) * 1.4); });
  const width = SW * 0.44, height = width * 10 / 16, step = width * 0.7 + 24;
  const enter = spring(t - (MORPH[0] + 0.18), 0.5, 0.9);
  sw.cards.forEach((card, i) => {
    const d = i - s, ad = Math.abs(d), near = Math.min(ad, 1);
    const scale = 1 - 0.2 * near;
    const rot = -24 * clamp(d, -1, 1);
    let opacity = ad <= 1 ? 1 - 0.3 * ad : Math.max(0, 0.7 - (ad - 1) * 0.35);
    const x = 720 + d * step * enter, y = CARD_Y;
    if (i === CAROUSEL_START && t < MORPH[1]) opacity = 0;       // the morph stands in for it
    else if (i !== CAROUSEL_START) opacity *= enter;
    const selected = 1 - near;
    style(card, {
      transform: `translate(${x - width / 2}px, ${y - height / 2}px) perspective(1100px) rotateY(${rot}deg) scale(${scale})`,
      opacity, zIndex: String(100 - Math.round(ad * 10)),
      boxShadow: `0 ${lerp(10, 26, selected)}px ${lerp(16, 44, selected)}px rgba(0,0,0,${lerp(0.3, 0.55, selected)})`,
    });
    card.querySelector('.ring').style.boxShadow = `inset 0 0 0 1px rgba(255,255,255,${lerp(0.12, 0.35, selected)})`;
  });
  const infoIn = APPLE(seg(t, MORPH[0] + 0.3, MORPH[0] + 0.9));
  sw.infos.forEach((info, i) => {
    const w = clamp(1 - Math.abs(i - s) * 2.2);
    style(info, { opacity: w * infoIn, filter: w < 1 ? `blur(${(1 - w) * 6}px)` : 'none', transform: `translateY(${(1 - infoIn) * 14}px)` });
  });
  const hintsIn = APPLE(seg(t, MORPH[0] + 0.4, MORPH[0] + 1.0));
  style(sw.hints, { opacity: hintsIn, transform: `translateX(-50%) translateY(${(1 - hintsIn) * 12}px)` });
  const pressed = (times, key) => {
    const hit = Math.max(0, ...times.map(m => t >= m - 0.02 ? Math.exp(-(t - m + 0.02) * 7) : 0));
    style(sw.caps[key], { background: `rgba(255,255,255,${0.1 + 0.75 * hit})`, color: hit > 0.5 ? '#111' : '#f5f5f7', transform: `scale(${1 - 0.1 * hit})` });
  };
  pressed(MOVES, '→');
  pressed([RETURN], '↩');
}

function renderPlane(t) {
  const cam = camera(t);
  plane.style.transform = `translate3d(${cam.cx}px, ${cam.cy}px, 0) rotateX(${cam.rx}deg) rotateZ(${cam.rz}deg) scale(${cam.k})`;
  const screenOn = SMOOTH(seg(t, MORPH[0], MORPH[0] + 0.4));
  const iconTakeover = t >= ICON[0];
  S.screen.style.opacity = iconTakeover ? 0 : screenOn;
  S.screen.style.display = screenOn > 0 && !iconTakeover ? '' : 'none';
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
    tl.tile.style.opacity = o;
    tl.tile.style.display = o > 0.002 ? '' : 'none';
  }
}

function renderCaptions(t) {
  const words = captions.words;
  const times = WORDS;
  words.forEach((w, i) => {
    const p = APPLE(seg(t, times[i] + 0.04, times[i] + 0.74));
    const later = i < 3 ? SMOOTH(seg(t, times[i + 1], times[i + 1] + 0.4)) : 0;
    const out = IN(seg(t, ALL_AT_ONCE - 0.05, ALL_AT_ONCE + 0.3));
    style(w, {
      opacity: p * (1 - out), color: mix('#f5f5f7', '#5f5f64', later),
      filter: `blur(${(1 - p) * 12 + out * 10}px)`, transform: `translateY(${(1 - p) * 16}px)`,
    });
  });
  const allIn = APPLE(seg(t, ALL_AT_ONCE + 0.2, ALL_AT_ONCE + 0.9));
  const allOut = IN(seg(t, 10.9, 11.25));
  style(captions.all, { opacity: allIn * (1 - allOut), filter: `blur(${(1 - allIn) * 12 + allOut * 10}px)`, transform: `translateY(${(1 - allIn) * 16}px)` });
  const themesIn = APPLE(seg(t, THEMES_CAPTION, THEMES_CAPTION + 0.8));
  const themesOut = IN(seg(t, 14.75, 15.15));
  const v = themesIn * (1 - themesOut);
  captions.vignette.style.opacity = v;
  style(captions.themes, { opacity: v, filter: `blur(${(1 - themesIn) * 16 + themesOut * 12}px)`, transform: `translateY(${(1 - themesIn) * 20}px) scale(${1 + 0.02 * (1 - themesIn)})` });
  captions.themes.firstChild.style.backgroundPosition = `${(t * 18) % 300}% 0`;
}

function renderMorph(t) {
  const m = keys.morph;
  const p = APPLE(seg(t, MORPH[0], MORPH[1]));
  const active = t >= MORPH[0] - 0.001 && t < MORPH[1];
  m.style.display = active ? '' : 'none';
  if (!active) return;
  const from = keys.nodes[3].rect;
  const press = 5;
  const k = 1920 / SW;
  const w = SW * 0.44 * k, h = w * 10 / 16;
  const to = { x: 960 - w / 2, y: SWITCHER_CY + (CARD_Y - 450) * k - h / 2, w, h };
  const x = lerp(from.x, to.x, p), y = lerp(from.y + press, to.y, p), ww = lerp(from.w, to.w, p), hh = lerp(from.h, to.h, p);
  style(m, {
    opacity: 1, left: `${x}px`, top: `${y}px`, width: `${ww}px`, height: `${hh}px`, borderRadius: `${lerp(28, 14 * k, p)}px`,
    boxShadow: `0 ${lerp(24, 34, p)}px ${lerp(48, 60, p)}px rgba(0,0,0,${lerp(0.75, 0.55, p)}), inset 0 0 0 1px rgba(255,255,255,${lerp(0.06, 0.3, p)})`,
  });
  m.querySelector('.face').style.opacity = 1 - SMOOTH(seg(p, 0.25, 0.7));
  keys.morphImg.style.opacity = SMOOTH(seg(p, 0.3, 0.8));
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
  if (active) {
    const w = lerp(tile.w, icon.w, p) * settle, h = lerp(tile.h, icon.h, p) * settle;
    const left = x - (w - lerp(tile.w, icon.w, p)) / 2, top = y - (h - lerp(tile.h, icon.h, p)) / 2;
    const iconIn = SMOOTH(seg(p, 0.3, 0.8));
    style(end.morph, {
      opacity: 1 - SMOOTH(seg(p, 0.55, 0.95)), left: `${left}px`, top: `${top}px`, width: `${w}px`, height: `${h}px`,
      borderRadius: `${lerp(22 * cam.k, 62, p)}px`,
      boxShadow: `0 ${lerp(12, 30, p)}px ${lerp(30, 70, p)}px rgba(0,0,0,${0.55 * (1 - iconIn)})`,
    });
    const side = Math.min(w, h);
    style(end.morphIcon, {
      opacity: iconIn, left: `${left + (w - side) / 2}px`, top: `${top + (h - side) / 2}px`, width: `${side}px`, height: `${side}px`,
      filter: `drop-shadow(0 ${24 * iconIn}px ${40 * iconIn}px rgba(0,0,0,0.5))`,
    });
  }
  end.morphIcon.style.display = active ? '' : 'none';
  const auraOn = SMOOTH(seg(t, ICON[0] + 0.4, END)) * (1 + 0.5 * Math.exp(-Math.max(0, t - END) * 3) * (t >= END ? 1 : 0));
  end.aura.style.opacity = 0.42 * auraOn;
  end.aura.style.transform = `scale(${1 + 0.04 * Math.sin(t * 1.3)})`;
  const wordIn = APPLE(seg(t, END + 0.25, END + 1.0));
  style(end.word, { opacity: wordIn, filter: `blur(${(1 - wordIn) * 14}px)`, transform: `translateY(${(1 - wordIn) * 18}px)` });
  const tagIn = APPLE(seg(t, END + 0.55, END + 1.3));
  style(end.tag, { opacity: tagIn, filter: `blur(${(1 - tagIn) * 12}px)`, transform: `translateY(${(1 - tagIn) * 14}px)` });
}

let frameIndex = 0;
window.render = t => {
  frameIndex = Math.round(t * 60);
  renderKeys(t);
  renderMorph(t);
  renderPlane(t);
  renderScreen(t);
  renderCaptions(t);
  renderEnd(t);
  const r = random(frameIndex + 1);
  grain.style.backgroundPosition = `${Math.floor(r() * 256)}px ${Math.floor(r() * 256)}px`;
  fade.style.opacity = SMOOTH(seg(t, FILM - 0.4, FILM)) + (1 - SMOOTH(seg(t, 0, 0.12)));
};

// A theme's desktop alone, full size, for the switcher's cards and the wall's tiles.
window.renderThumb = key => {
  for (const node of frame.children) node.style.display = 'none';
  stage.style.display = '';
  tiles.forEach(tl => { tl.tile.style.display = 'none'; });
  glows.forEach(g => { g.style.display = 'none'; });
  plane.style.transform = `translate3d(${SW / 2}px, ${SH / 2}px, 0)`;
  style(S.screen, { display: '', opacity: 1, borderRadius: '0', boxShadow: 'none' });
  for (const n of Object.values(S.walls)) n.style.opacity = 0;
  let node = S.walls[key];
  if (!node) { node = img(TH[key].wallpaper, 'wp', S.screen); S.screen.insertBefore(node, S.screen.firstChild); S.walls[key] = node; }
  style(node, { opacity: 1, zIndex: 1, webkitMaskImage: 'none', maskImage: 'none' });
  S.bloomRim.style.opacity = 0;
  for (const b of bindings) paint(b, roleColor(key, b.role));
  return node.decode();
};

window.ready = (async () => {
  await document.fonts.ready;
  await Promise.all([...document.images].map(i => i.decode().catch(() => { throw new Error(`cannot load ${i.src}`); })));
  const params = new URLSearchParams(location.search);
  if (params.has('t')) window.render(parseFloat(params.get('t')));
  return true;
})();
