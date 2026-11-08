// Bakes the Web version's synthesized sounds into WAV files for Godot.
// Reference: wd-fz/wd-fz.github.io@0bf508a game3d/js/sound-bank.js (recipes), sound-levels.js
// (loudness calibration) and fx/sound-player.js (how a recipe is resolved and played), audio.js
// (the continuous beds). The recipes and the calibration are loaded unchanged from the old files;
// the resolution code below follows sound-player.js line by line; the DSP follows the Web Audio
// spec (exponential ramps, RBJ biquads with Web Audio's Q conventions, equal-power panning).
// Output: assets/audio/sfx/<id>.<take>.ogg, assets/audio/beds/<name>.ogg and assets/audio/index.json.
// Usage: node tools/audio_bake/bake.cjs <old game3d/js dir> [out dir, default assets/audio]
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');

const SRC = process.argv[2] || path.join(__dirname, '../../../wd-fz/wd-fz.github.io/game3d/js');
const OUT = process.argv[3] || path.join(__dirname, '../../assets/audio');
const SR = 22050, VARIANTS = 3;
// Only the cabin crowd event is still pending. The maze's sounds are part of its playable port.
const SKIP = /^(death\.crowd$|event\.liftOverload$|threat\.crowd$)/;
const MAZE = /^(void\.|step\.void$|death\.(void|abyss)$)/;
const ONLY_MAZE = process.argv.includes('--maze-only');

// ---- load the old data unchanged ----
const pub = {};
const ctx = {GameModules: {imports: () => new Proxy({}, {get: (t, k) => pub[k]}), publish: (f, o) => { for (const k in o) pub[k] = o[k].get(); }}, Math, console};
vm.createContext(ctx);
for (const f of ['sound-bank.js', 'sound-levels.js']) vm.runInContext(fs.readFileSync(path.join(SRC, f), 'utf8'), ctx);
const BANK = pub.SOUND_BANK, CATS = pub.SOUND_CATS, LEVELS = pub.SOUND_LEVELS;

// ---- sound-player.js resolution ----
const CAT_WET = {ui: 0.04, step: 0.22, foley: 0.3, world: 0.6, distant: 0.6, threat: 0.4, event: 0.5, death: 0.4, scene: 0.35, music: 0.45, void: 0.9};
const LAYER_T = {tone: 1, noise: 1, bell: 1, vowel: 1, fm: 1};
const BELL = [[0.5,0.9,1],[1,0.75,0.8],[1.19,0.5,0.6],[1.5,0.32,0.5],[2,0.42,0.45],[2.51,0.22,0.3],[2.99,0.16,0.25],[4.17,0.09,0.16]];
function mulberry(seed) { let a = seed >>> 0; return function () { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
let rng = mulberry(1);
const pick = (v, o, i) => typeof v === 'function' ? v(o, i, rng) : Array.isArray(v) ? v[0] + (v[1] - v[0]) * rng() : v;
const num = (v, o, i, d) => { const x = pick(v, o, i); return (typeof x === 'number' && isFinite(x)) ? x : d; };
const dB = (x) => Math.pow(10, x / 20);

// ---- DSP ----
class Buf { constructor(len) { this.L = new Float32Array(len); this.R = new Float32Array(len); this.stereo = false; } }
function expAt(t, t0, v0, t1, v1) { if (t <= t0) return v0; if (t >= t1) return v1; return v0 * Math.pow(v1 / v0, (t - t0) / (t1 - t0)); }
// Envelope as in sound-player.js envelope(): 0.0001 → peak (exp, atk) → hold → 0.0001 (exp, at dur).
function envFn(t, atk, hold, dur, peak) {
  peak = Math.max(0.00012, peak); atk = Math.max(0.0008, Math.min(atk, dur * 0.9));
  const holdOn = hold > 0 && atk + hold < dur * 0.95, rs = holdOn ? atk + hold : atk;
  return (s) => { const x = s - t; if (x < 0) return 0; if (x < atk) return expAt(x, 0, 0.0001, atk, peak); if (x < rs) return peak; if (x < dur) return expAt(x, rs, peak, dur, 0.0001); return 0; };
}
function osc(type, ph) { const p = ph - Math.floor(ph);
  if (type === 'square') return p < 0.5 ? 1 : -1;
  if (type === 'sawtooth') return 2 * p - 1;
  if (type === 'triangle') return p < 0.5 ? 4 * p - 1 : 3 - 4 * p;
  return Math.sin(2 * Math.PI * p); }
// RBJ biquad with Web Audio's parameterisation: lowpass/highpass Q in dB, bandpass Q plain.
class Biquad { constructor(type) { this.type = type; this.x1 = this.x2 = this.y1 = this.y2 = 0; this.f = -1; this.q = -1; }
  set(f, q) { if (f === this.f && q === this.q) return; this.f = f; this.q = q;
    const w = 2 * Math.PI * Math.min(Math.max(f, 10), SR * 0.49) / SR, c = Math.cos(w), s = Math.sin(w); let b0, b1, b2, a0, a1, a2, al;
    if (this.type === 'bandpass') { al = s / (2 * Math.max(q, 0.0001)); b0 = al; b1 = 0; b2 = -al; }
    else { al = s / (2 * Math.pow(10, q / 20)); if (this.type === 'highpass') { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; } else { b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; } }
    a0 = 1 + al; a1 = -2 * c; a2 = 1 - al; this.b0 = b0 / a0; this.b1 = b1 / a0; this.b2 = b2 / a0; this.a1 = a1 / a0; this.a2 = a2 / a0; }
  run(x) { const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2; this.x2 = this.x1; this.x1 = x; this.y2 = this.y1; this.y1 = y; return y; } }
function freqFn(f, to, t, glide) { if (!to) return () => f; return (s) => expAt(s, t, f, t + Math.max(0.01, glide), to); }
function addVoice(buf, L, t, peak, fk, pan, o, i) {
  const dur = Math.max(0.01, num(L.dur, o, i, 0.2)), hold = num(L.hold, o, i, 0), nyq = SR * 0.45;
  const gl = pan === null ? 1 : Math.cos((pan + 1) / 2 * Math.PI / 2), gr = pan === null ? 1 : Math.sin((pan + 1) / 2 * Math.PI / 2);
  if (pan !== null) buf.stereo = true;
  const am = L.am ? {rate: num(L.am[0], o, i, 8), depth: Math.max(0, Math.min(1, num(L.am[1], o, i, 0.5))), type: L.am[2] || 'sine'} : null;
  const lp = L.lp ? new Biquad('lowpass') : null, lpf = L.lp ? num(L.lp, o, i, 2000) : 0;
  const vib = L.vib ? {rate: num(L.vib[0], o, i, 5), depth: num(L.vib[1], o, i, 0.01)} : null;
  let src, atk;
  if (L.t === 'tone') {
    const f = Math.min(nyq, num(L.f, o, i, 440) * fk), to = num(L.to, o, i, 0), glide = num(L.glide, o, i, dur);
    const ff = freqFn(f, to ? Math.min(nyq, Math.max(16, to * fk)) : 0, t, glide), type = L.type || 'sine'; let ph = 0;
    src = (s) => { let fr = ff(s); if (vib) fr += f * vib.depth * Math.sin(2 * Math.PI * vib.rate * (s - t)); ph += fr / SR; return osc(type, ph); };
    atk = num(L.atk, o, i, Math.min(0.01, dur * 0.2));
  } else if (L.t === 'noise') {
    const fq = L.p === false ? 1 : fk, f = num(L.f, o, i, 1000) * fq, to = num(L.to, o, i, 0), glide = num(L.glide, o, i, dur), q = num(L.q, o, i, 1);
    const ff = freqFn(Math.min(f, nyq), to ? Math.min(Math.max(20, to * fq), nyq) : 0, t, glide), bq = new Biquad(L.type || 'bandpass'), nr = mulberry(Math.floor(rng() * 1e9));
    src = (s) => { bq.set(ff(s), q); return bq.run(nr() * 2 - 1); };
    atk = num(L.atk, o, i, 0.004);
  } else if (L.t === 'bell') {
    const f = num(L.f, o, i, 220) * fk, parts = L.partials || BELL, a = num(L.atk, o, i, 0.002);
    for (const p of parts) { const pf = f * p[0]; if (pf > nyq) continue;
      const fr = pf * (1 + (rng() - 0.5) * 0.002), pd = Math.max(0.05, dur * p[2]), env = envFn(t, a, 0, pd, peak * p[1]);
      const s0 = Math.floor(t * SR), s1 = Math.min(buf.L.length, Math.ceil((t + pd + 0.06) * SR));
      for (let k = s0; k < s1; k++) { const s = k / SR, v = Math.sin(2 * Math.PI * fr * (s - t)) * env(s); buf.L[k] += v * gl; buf.R[k] += v * gr; } }
    return t + dur;
  } else if (L.t === 'vowel') {
    const f = num(L.f, o, i, 200) * fk, to = num(L.to, o, i, 0), vo = num(L.voice, o, i, 1), br = num(L.breath, o, i, 0);
    const ff = freqFn(f, to ? Math.max(16, to * fk) : 0, t, dur), nr = mulberry(Math.floor(rng() * 1e9)); let ph = 0;
    const forms = [L.f1 || 700, L.f2 || 1150, L.f3].map((x, k) => x ? {bq: new Biquad('bandpass'), f: Math.min(nyq, num(x, o, i, 800)), g: k === 0 ? 1 : (k === 1 ? 0.7 : 0.4)} : null).filter(Boolean);
    const fq = num(L.fq, o, i, 7);
    src = (s) => { let x = 0; if (vo > 0) { let fr = ff(s); if (vib) fr += f * vib.depth * Math.sin(2 * Math.PI * vib.rate * (s - t)); ph += fr / SR; x += vo * osc('sawtooth', ph); }
      if (br > 0) x += br * 2.2 * (nr() * 2 - 1); let y = 0; for (const F of forms) { F.bq.set(F.f, fq); y += F.g * F.bq.run(x); } return y; };
    atk = num(L.atk, o, i, dur * 0.3);
  } else if (L.t === 'fm') {
    const f = Math.min(nyq, num(L.f, o, i, 300) * fk), ratio = num(L.ratio, o, i, 1.4), idx = num(L.index, o, i, 2) * f, idec = num(L.idecay, o, i, 0.6);
    let pc = 0, pm = 0;
    src = (s) => { pm += f * ratio / SR; const mi = expAt(s, t, idx, t + dur * idec, Math.max(1, idx * 0.05)); pc += (f + mi * Math.sin(2 * Math.PI * pm)) / SR; return Math.sin(2 * Math.PI * pc); };
    atk = num(L.atk, o, i, 0.002);
  } else return t;
  if (lp) lp.set(lpf, 1);
  const env = envFn(t, atk, hold, dur, peak), s0 = Math.floor(t * SR), s1 = Math.min(buf.L.length, Math.ceil((t + dur + 0.06) * SR));
  for (let k = s0; k < s1; k++) { const s = k / SR; let v = src(s);
    if (am) v *= (1 - am.depth / 2) + am.depth / 2 * osc(am.type, am.rate * (s - t));
    if (lp) v = lp.run(v);
    v *= env(s); buf.L[k] += v * gl; buf.R[k] += v * gr; }
  return t + dur;
}
// layer() and render() of sound-player.js; plan = true only measures the length.
function layer(buf, L, t0, gk, pk, o, plan, rp) {
  const n = Math.max(1, Math.round(num(L.n, o, 0, 1))), accel = num(L.accel, o, 0, 1), decay = num(L.decay, o, 0, 1), fstep = num(L.fstep, o, 0, 1), at = num(L.at, o, 0, 0);
  let end = t0, dt = 0, g = 1, fm = 1; const own = L.pan !== undefined || L.panTo !== undefined || rp !== null;
  for (let i = 0; i < n; i++) {
    const t = t0 + at + dt + (L.jit ? num(L.jit, o, i, 0) * (rng() * 2 - 1) : 0);
    const peak = num(L.g, o, i, 0.05) * gk * g, fk = (L.p === false ? 1 : pk) * fm;
    if (plan) end = Math.max(end, t + Math.max(0.01, num(L.dur, o, i, 0.2)));
    else { let pan = null;
      if (own) { const p0 = num(L.pan, o, i, 0), p1 = L.panTo !== undefined ? num(L.panTo, o, i, p0) : p0, pp = n > 1 ? p0 + (p1 - p0) * i / (n - 1) : p0;
        pan = Math.max(-1, Math.min(1, (o.pan || 0) * (L.panK === undefined ? 1 : L.panK) + pp + (rp || 0))); }
      end = Math.max(end, addVoice(buf, L, Math.max(t, 0), peak, fk, pan, o, i)); }
    dt += num(L.every, o, i, 0.2) * Math.pow(accel, i); g *= decay; fm *= fstep;
  }
  return end;
}
function render(id, opt, plan, buf) {
  const D = BANK[id], o = Object.assign({}, opt); if (o.len === undefined) o.len = D.len || 1;
  const R = D.rep || {}, rn = Math.max(1, Math.round(num(R.n, o, 0, 1)));
  let end = 0, rdt = 0, rg = 1;
  for (let r = 0; r < rn; r++) {
    const tr = rdt + (R.jit ? num(R.jit, o, r, 0) * (rng() * 2 - 1) : 0);
    const rp = R.pan ? R.pan[0] + (R.pan[1] - R.pan[0]) * (rn > 1 ? r / (rn - 1) : 0) : null;
    for (const L of D.layers) { if (!LAYER_T[L.t]) continue; end = Math.max(end, layer(buf, L, tr, rg, 1, o, plan, rp)); }
    rdt += num(R.every, o, r, 0.3) * Math.pow(num(R.accel, o, 0, 1), r); rg *= num(R.decay, o, 0, 1);
  }
  return end;
}

// ---- WAV → Ogg ----
function writeWav(file, chans, rate) {
  const n = chans[0].length, nc = chans.length, data = Buffer.alloc(44 + n * nc * 2);
  data.write('RIFF', 0); data.writeUInt32LE(36 + n * nc * 2, 4); data.write('WAVE', 8); data.write('fmt ', 12);
  data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(nc, 22); data.writeUInt32LE(rate, 24);
  data.writeUInt32LE(rate * nc * 2, 28); data.writeUInt16LE(nc * 2, 32); data.writeUInt16LE(16, 34); data.write('data', 36); data.writeUInt32LE(n * nc * 2, 40);
  let p = 44; for (let k = 0; k < n; k++) for (const c of chans) { data.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(c[k] * 32767))), p); p += 2; }
  // Encoded to Ogg Vorbis with ffmpeg (needs ffmpeg on PATH); the WAV is only an intermediate.
  const tmp = file + '.tmp.wav'; fs.writeFileSync(tmp, data);
  const ogg = file.replace(/\.wav$/, '.ogg');
  require('child_process').execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '4', ogg]);
  fs.unlinkSync(tmp);
}
// Normalise to peak 0.9 and return the gain (dB) to apply back at runtime.
function normalise(chans) { let pk = 0; for (const c of chans) for (const v of c) pk = Math.max(pk, Math.abs(v)); if (pk <= 0) return 0; const k = 0.9 / pk; for (const c of chans) for (let i = 0; i < c.length; i++) c[i] *= k; return -20 * Math.log10(k); }

// ---- loudness check (sound-player.js loudness(): K-weighting ≈ 60 Hz highpass + 1.5 kHz high shelf
// +4 dB, then the loudest 100 ms RMS window). After calibration each sound should land near its
// category target + lv, as in the Web version; the deviation is printed per category. ----
function shelf(x, st) { // RBJ high shelf, f 1500 Hz, +4 dB, S = 1 (Web Audio highshelf)
  if (!st.b0) { const A = Math.pow(10, 4 / 40), w = 2 * Math.PI * 1500 / SR, c = Math.cos(w), s = Math.sin(w), al = s / 2 * Math.sqrt(2), sq = 2 * Math.sqrt(A) * al;
    const a0 = (A + 1) - (A - 1) * c + sq; st.b0 = A * ((A + 1) + (A - 1) * c + sq) / a0; st.b1 = -2 * A * ((A - 1) + (A + 1) * c) / a0; st.b2 = A * ((A + 1) + (A - 1) * c - sq) / a0;
    st.a1 = 2 * ((A - 1) - (A + 1) * c) / a0; st.a2 = ((A + 1) - (A - 1) * c - sq) / a0; st.x1 = st.x2 = st.y1 = st.y2 = 0; }
  const y = st.b0 * x + st.b1 * st.x1 + st.b2 * st.x2 - st.a1 * st.y1 - st.a2 * st.y2; st.x2 = st.x1; st.x1 = x; st.y2 = st.y1; st.y1 = y; return y; }
function loudness(ch) { const hp = new Biquad('highpass'); hp.set(60, 0.5); const st = {}, kw = new Float32Array(ch.length);
  for (let i = 0; i < ch.length; i++) kw[i] = shelf(hp.run(ch[i]), st);
  const win = Math.round(SR * 0.1), hop = Math.round(SR * 0.025); let best = 0;
  for (let i = 0; i + win <= kw.length; i += hop) { let a = 0; for (let j = i; j < i + win; j++) a += kw[j] * kw[j]; best = Math.max(best, Math.sqrt(a / win)); }
  return best > 0 ? 20 * Math.log10(best) : -120; }
const check = {};

// ---- one-shots ----
fs.mkdirSync(path.join(OUT, 'sfx'), {recursive: true});
const index = ONLY_MAZE ? JSON.parse(fs.readFileSync(path.join(OUT, 'index.json'), 'utf8')) : {rate: SR, cats: {}, sfx: {}, beds: {}};
for (const c in CATS) index.cats[c] = {target: CATS[c].target, wet: CAT_WET[c] || 0.3};
for (const id of Object.keys(BANK).sort()) {
  if (SKIP.test(id) || (ONLY_MAZE && !MAZE.test(id))) continue;
  const D = BANK[id], vars = []; let stereo = false, len = 0;
  // Every play re-rolls the recipe's ranges in the Web version; here short sounds get three baked
  // takes, middle ones two and long ones (bells, scenes) one, plus pitch and gain variation at play time.
  rng = mulberry(1000); const est = render(id, {}, true, null);
  const takes = est <= 1.5 ? VARIANTS : (est <= 4 ? 2 : 1);
  for (let v = 0; v < takes; v++) {
    rng = mulberry(1000 + v * 17);
    const L = Math.min(20, render(id, {}, true, null) + 0.35); len = Math.max(len, L);
    rng = mulberry(1000 + v * 17);
    const buf = new Buf(Math.max(256, Math.ceil(L * SR)));
    render(id, {}, false, buf);
    stereo = stereo || buf.stereo; vars.push(buf);
  }
  const lv = typeof LEVELS[id] === 'number' ? LEVELS[id] : 0, files = [];
  { const mono = new Float32Array(vars[0].L.length); for (let k = 0; k < mono.length; k++) mono[k] = (vars[0].L[k] + vars[0].R[k]) / 2;
    const want = CATS[D.cat].target + (D.lv || 0), got = loudness(mono) + lv; (check[D.cat] = check[D.cat] || []).push(got - want); }
  vars.forEach((b, v) => { const chans = stereo ? [b.L, b.R] : [b.L]; const db = normalise(chans); const f = `${id}.${v}.ogg`;
    writeWav(path.join(OUT, 'sfx', f.replace(/\.ogg$/, '.wav')), chans, SR); files.push({file: f, db: Math.round((db + lv) * 100) / 100}); });
  index.sfx[id] = {cat: D.cat, len: Math.round(len * 100) / 100, stereo, vary: {p: (D.vary || {}).p || 0, g: (D.vary || {}).g || 0}, wet: D.wet !== undefined ? D.wet : (CAT_WET[D.cat] || 0.3), files};
}

// ---- continuous beds (audio.js buildLayers), baked as seamless loops ----
fs.mkdirSync(path.join(OUT, 'beds'), {recursive: true});
function loopBake(name, seconds, rate, gen) {
  const fade = Math.min(1.5, seconds * 0.25), n = Math.round(seconds * rate), m = Math.round(fade * rate), raw = new Float32Array(n + m);
  for (let k = 0; k < n + m; k++) raw[k] = gen(k / rate);
  const out = new Float32Array(n);   // the tail crossfades into the head (equal power) so the loop has no seam
  for (let k = 0; k < n; k++) { if (k < m) { const x = k / m; out[k] = raw[k] * Math.sin(x * Math.PI / 2) + raw[n + k] * Math.cos(x * Math.PI / 2); } else out[k] = raw[k]; }
  const db = normalise([out]); writeWav(path.join(OUT, 'beds', name + '.wav'), [out], rate); index.beds[name] = {db: Math.round(db * 100) / 100, len: seconds};
}
function noiseLoop(name, type, f, q, lfo) { const bq = new Biquad(type), nr = mulberry(name.length * 7919);
  const SRb = SR; loopBake(name, lfo ? 1 / lfo.rate * 2 : 6, SRb, (s) => { bq.set(f + (lfo ? lfo.depth * Math.sin(2 * Math.PI * lfo.rate * s) : 0), q); return bq.run(nr() * 2 - 1); }); }
if (!ONLY_MAZE) {
noiseLoop('wind', 'bandpass', 420, 0.7, {rate: 0.11, depth: 180});
noiseLoop('rain', 'lowpass', 3600, 0.4);
noiseLoop('rain2', 'highpass', 5200, 0.3);
noiseLoop('rumble', 'lowpass', 90, 1.0);
// Lamp hum: 100 Hz sine 0.5, 200 Hz square 0.06, 300 Hz sine 0.15 — periodic in one second.
loopBake('hum', 2, SR, (s) => 0.5 * Math.sin(2 * Math.PI * 100 * s) + 0.06 * osc('square', 200 * s) + 0.15 * Math.sin(2 * Math.PI * 300 * s));
// Tension: minor-second cluster with a 6.5 Hz tremolo (gain 0.5 ± 0.5).
loopBake('tension', 8, SR, (s) => (Math.sin(2 * Math.PI * 880 * s) + Math.sin(2 * Math.PI * 932.3 * s) + Math.sin(2 * Math.PI * 1396.9 * s)) * 0.33 * (0.5 + 0.5 * Math.sin(2 * Math.PI * 6.5 * s)));
// The pad: four detuned oscillators through a resonant lowpass whose cutoff swings ±90 Hz at 0.07 Hz.
function pad(name, root, cutoff, tritone, ss) {
  const cents = (c) => Math.pow(2, c / 1200), bq = new Biquad('lowpass'), rate = 11025;
  const os = [[root, 'sawtooth', 0, 0.33], [root * 1.5 * (tritone ? 0.944 : 1), 'triangle', 4, 0.33], [root * (1.01 + ss * 0.045), 'sawtooth', -6, 0.33], [root * (2 - ss * 0.11), 'sine', 2, 0.5]];
  loopBake(name, 1 / 0.07, rate, (s) => { let x = 0; for (const p of os) x += p[3] * osc(p[1], p[0] * cents(p[2]) * s); bq.set(cutoff + 90 * Math.sin(2 * Math.PI * 0.07 * s), 4); return bq.run(x); });
}
const ROOTS = {in: 46.25, day: 55, night: 49, garage: 41.2};
for (const k in ROOTS) { pad('pad_' + k + '_calm', ROOTS[k], k === 'in' ? 180 + 0.15 * 700 - 40 : 180 + 0.15 * 700, false, 0); pad('pad_' + k + '_tense', ROOTS[k], k === 'in' ? 180 + 0.85 * 700 - 40 : 180 + 0.85 * 700, true, 0.6); }
pad('pad_menu', 43.65, 240, true, 0.27);
}
// void-maze/maze-sound.js: four slow sine voices and very low filtered noise.
const voidTone = new Biquad('lowpass'), voidNoise = new Biquad('lowpass'), voidRng = mulberry(90210);
voidTone.set(150, 0.6);
loopBake('void', 120, SR, s => {
  const voices = [[36,.5],[36.6,.45],[72.4,.09],[108.9,.035]];
  const tone = voices.reduce((a, v) => a + Math.sin(2*Math.PI*v[0]*s)*v[1], 0);
  voidNoise.set(180+70*Math.sin(2*Math.PI*.017*s), .7);
  return voidTone.run(tone*(.7+.28*Math.sin(2*Math.PI*.031*s))) + .32*voidNoise.run(voidRng()*2-1);
});

fs.writeFileSync(path.join(OUT, 'index.json'), JSON.stringify(index, null, 1));
for (const c in check) { const d = check[c], m = d.reduce((a, b) => a + b, 0) / d.length; console.log(`loudness ${c}: mean ${m.toFixed(1)} dB from target, worst ${Math.max(...d.map(Math.abs)).toFixed(1)} (n ${d.length})`); }
console.log('baked', Object.keys(index.sfx).length, 'sounds,', Object.keys(index.beds).length, 'beds');
