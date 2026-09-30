// Renders the film with headless Chrome, one frame at a time, and encodes it with ffmpeg.
//
//   node render.mjs thumbs                       theme desktops for the switcher's cards and the wall
//   node render.mjs stills 0.5,3.2,7.9           PNG frames at these times, for review
//   node render.mjs film [--fps 60] [--workers 6] [--shutter 32] [--scale 2] [--out scene-film-master.mov]
//   node render.mjs deliver                      the master with score.wav, as ProRes, HEVC, and H.264
//   node render.mjs readme                       frames of the film for the README, into .github/assets/
//
// Output goes to build/film/. The film is ProRes 422 HQ, 3840 x 2160; see README.md for the deliverables.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, '..', '..', 'build', 'film');
const PAGE = 'file://' + path.join(HERE, 'film.html');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const DURATION = 20;

const args = process.argv.slice(2);
const option = (name, fallback) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : fallback; };

async function open(query = '', width = 1920, height = 1080, scale = 2) {
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: 'new',
    args: ['--force-color-profile=srgb', '--hide-scrollbars', '--allow-file-access-from-files', '--disable-lcd-text', '--font-render-hinting=none'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width, height, deviceScaleFactor: scale });
  page.on('pageerror', e => console.error('page error:', e.message));
  await page.goto(PAGE + query, { waitUntil: 'load' });
  await page.evaluate(() => window.ready);
  return { browser, page };
}

// Draws the frame at t and waits for Chrome to paint it.
async function frame(page, t) {
  await page.evaluate(t => new Promise(done => { window.render(t); requestAnimationFrame(() => requestAnimationFrame(done)); }), t);
  return page.screenshot({ type: 'png', optimizeForSpeed: true });
}

async function thumbs() {
  const { browser, page } = await open('?thumbs', 1440, 900, 4 / 3);
  const keys = await page.evaluate(() => Object.keys(window.FILM_THEMES));
  fs.mkdirSync(path.join(OUT, 'assets', 'thumb'), { recursive: true });
  for (const key of keys) {
    const [folder, look] = key.split(':');
    await page.evaluate(k => window.renderThumb(k), key);
    await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
    const file = path.join(OUT, 'assets', 'thumb', `${folder}-${look}.jpg`);
    fs.writeFileSync(file, await page.screenshot({ type: 'jpeg', quality: 93 }));
    await run('sips', ['-Z', '768', file, '--out', file.replace('.jpg', '-small.jpg')]);
  }
  await browser.close();
  console.log(`${keys.length} theme desktops in ${path.relative(process.cwd(), path.join(OUT, 'assets', 'thumb'))}`);
}

async function stills(times) {
  const { browser, page } = await open();
  const dir = path.join(OUT, 'stills');
  fs.mkdirSync(dir, { recursive: true });
  for (const t of times) {
    fs.writeFileSync(path.join(dir, `t${t.toFixed(3).padStart(6, '0')}.png`), await frame(page, t));
  }
  await browser.close();
  console.log(`${times.length} stills in ${path.relative(process.cwd(), dir)}`);
}

function run(command, list, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, list, { stdio: [input ? 'pipe' : 'ignore', 'ignore', 'pipe'] });
    let err = '';
    child.stderr.on('data', d => { err += d; });
    child.on('close', code => code === 0 ? resolve() : reject(new Error(`${command} exited ${code}: ${err.slice(-800)}`)));
    if (input) input(child.stdin);
  });
}

// ProRes 422 HQ in BT.709, from sRGB frames. FFmpeg 8 takes the frames' color tags from setparams;
// TAGS writes them into the container when a file is copied without encoding.
const TAGS = ['-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-color_range', 'tv'];
const ENCODE = ['-c:v', 'prores_ks', '-profile:v', '3', '-vendor', 'apl0', '-pix_fmt', 'yuv422p10le',
  '-vf', 'scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv',
  ...TAGS];

// Frames in the film's fast moves (window.BLUR) average --shutter moments across half a frame, like a 180° camera
// shutter; the other frames take one moment. tmix mixes a frame with the n - 1 before it, so select keeps the last
// moment of each frame. Two tmix stages of at most 8 keep the cost down, so the shutter is 1 to 8 or a multiple of 8.
function blur(samples, fps) {
  if (samples === 1) return [];
  const first = Math.min(samples, 8), second = samples / first;
  const stage = n => [`tmix=frames=${n}`, `select=eq(mod(n\\,${n})\\,${n - 1})`];
  return ['format=gbrp16le', ...stage(first), ...(second > 1 ? stage(second) : []), `setpts=N/${fps}/TB`];
}

// Renders one job, a run of frames with the same number of moments, into its own ProRes file.
async function chunk(page, job, fps) {
  const encode = [...ENCODE];
  encode[encode.indexOf('-vf') + 1] = [...blur(job.samples, fps), encode[encode.indexOf('-vf') + 1]].join(',');
  await run('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-c:v', 'png', '-framerate', String(fps * job.samples), '-i', '-',
    ...encode, '-r', String(fps), job.file], async stdin => {
    for (let f = job.first; f < job.last; f++) {
      for (let s = 0; s < job.samples; s++) {
        const t = (f + (job.samples > 1 ? ((s + 0.5) / job.samples - 0.5) * 0.5 : 0)) / fps;
        const png = await frame(page, Math.max(0, Math.min(DURATION - 1e-4, t)));
        if (!stdin.write(png)) await new Promise(r => stdin.once('drain', r));
      }
    }
    stdin.end();
  });
}

async function film() {
  const fps = Number(option('fps', 60)), workers = Number(option('workers', 6)), shutter = Number(option('shutter', 32));
  const scale = Number(option('scale', 2)), name = option('out', 'scene-film-master.mov');
  const total = Math.round(DURATION * fps);
  fs.rmSync(path.join(OUT, 'chunks'), { recursive: true, force: true });
  fs.mkdirSync(path.join(OUT, 'chunks'), { recursive: true });
  const started = Date.now();
  const pages = await Promise.all(Array.from({ length: workers }, () => open('', 1920, 1080, scale)));
  const ranges = await pages[0].page.evaluate(() => window.BLUR);
  const samples = f => ranges.some(([a, b]) => f / fps >= a && f / fps < b) ? shutter : 1;
  // Jobs of about the same cost, about 400 moments each.
  const jobs = [];
  for (let f = 0; f < total; f++) {
    const job = jobs[jobs.length - 1], n = samples(f);
    if (job && job.samples === n && (job.last - job.first) * n < 400) job.last++;
    else jobs.push({ first: f, last: f + 1, samples: n, file: path.join(OUT, 'chunks', `chunk-${String(jobs.length).padStart(3, '0')}.mov`) });
  }
  const queue = [...jobs];
  let done = 0;
  await Promise.all(pages.map(async ({ browser, page }) => {
    for (let job; (job = queue.shift());) {
      await chunk(page, job, fps);
      process.stdout.write(`\r  ${++done}/${jobs.length} chunks`);
    }
    await browser.close();
  }));
  const list = path.join(OUT, 'chunks', 'list.txt');
  fs.writeFileSync(list, jobs.map(job => `file '${job.file}'`).join('\n'));
  const master = path.join(OUT, name);
  await run('ffmpeg', ['-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', ...TAGS, master]);
  fs.rmSync(path.join(OUT, 'chunks'), { recursive: true, force: true });
  const blurred = jobs.filter(job => job.samples > 1).reduce((sum, job) => sum + job.last - job.first, 0);
  console.log(`\n${total} frames, ${blurred} with motion blur, in ${((Date.now() - started) / 1000).toFixed(0)} s -> ${path.relative(process.cwd(), master)}`);
}

// The README's pictures: frames of the film as [time, crop], where a crop is [top, height] in the 1920 x 1080 frame.
// Each is drawn at 2x and scaled down, so small text stays sharp. JPEG with full-resolution color keeps text clean.
const README = { switcher: [4.6], shortcut: [1.2, [200, 800]], desktop: [7.9], themes: [14.2] };

async function readme() {
  const { browser, page } = await open();
  const dir = path.join(HERE, '..', '..', '.github', 'assets');
  for (const [name, [t, crop]] of Object.entries(README)) {
    const png = await frame(page, t);
    const filters = ['scale=1920:1080:flags=lanczos', ...(crop ? [`crop=1920:${crop[1]}:0:${crop[0]}`] : []), 'format=yuvj444p'];
    await run('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-c:v', 'png', '-i', '-', '-vf', filters.join(','), '-q:v', '3',
      path.join(dir, `${name}.jpg`)], stdin => stdin.end(png));
    console.log(path.relative(process.cwd(), path.join(dir, `${name}.jpg`)));
  }
  await browser.close();
}

// Adds score.wav to the master and encodes the copies people watch.
async function deliver() {
  const input = ['-y', '-v', 'error', '-i', path.join(OUT, 'scene-film-master.mov'), '-i', path.join(OUT, 'score.wav'), '-map', '0:v', '-map', '1:a'];
  const aac = ['-c:a', 'aac_at', '-b:a', '256k', '-movflags', '+faststart'];
  const outputs = {
    // For editing: the master's ProRes, untouched, with 24-bit PCM.
    'scene-film-4k-prores.mov': ['-c:v', 'copy', '-c:a', 'pcm_s24le'],
    // For YouTube, Apple devices, and the web. 10-bit keeps the dark gradients from banding.
    'scene-film-4k.mp4': ['-c:v', 'libx265', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p10le', '-tag:v', 'hvc1', '-x265-params', 'log-level=error', ...aac],
    // For social posts, which take H.264 at 1080p most reliably.
    'scene-film-1080p.mp4': ['-vf', 'scale=1920:1080:flags=lanczos', '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-profile:v', 'high', '-pix_fmt', 'yuv420p', ...aac],
  };
  for (const [name, codec] of Object.entries(outputs)) {
    await run('ffmpeg', [...input, ...codec, ...TAGS, '-shortest', path.join(OUT, name)]);
    console.log(path.relative(process.cwd(), path.join(OUT, name)));
  }
}

const command = args[0];
if (command === 'thumbs') await thumbs();
else if (command === 'stills') await stills(args[1].split(',').map(Number));
else if (command === 'film') await film();
else if (command === 'deliver') await deliver();
else if (command === 'readme') await readme();
else console.log('usage: node render.mjs thumbs | stills 1.0,2.5 | film [--fps 60] [--workers 6] [--shutter 32] [--scale 2] [--out name.mov] | deliver | readme');
