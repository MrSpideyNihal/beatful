/**
 * Generates the game audio into app/assets/audio.
 *
 * The app ships with sound, so the sounds have to exist. Rather than pull in
 * licensed audio files, these are synthesised: short soft tones for the cues and
 * a calm eight second loop for the background music. Mono 22050 Hz 16 bit WAV,
 * which every Android device plays and which keeps the whole set under a
 * megabyte.
 *
 * Run from the repo root: node tools/make-audio.js
 */

'use strict';

const fs = require('fs');
const path = require('path');

const RATE = 22050;
const OUT = path.join(__dirname, '..', 'app', 'assets', 'audio');

/** Write mono 16 bit PCM samples in [-1, 1] as a WAV file. */
function writeWav(name, samples) {
  const bytes = samples.length * 2;
  const buffer = Buffer.alloc(44 + bytes);
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + bytes, 4);
  buffer.write('WAVE', 8);
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16); // fmt chunk size
  buffer.writeUInt16LE(1, 20); // PCM
  buffer.writeUInt16LE(1, 22); // mono
  buffer.writeUInt32LE(RATE, 24);
  buffer.writeUInt32LE(RATE * 2, 28); // byte rate
  buffer.writeUInt16LE(2, 32); // block align
  buffer.writeUInt16LE(16, 34); // bits per sample
  buffer.write('data', 36);
  buffer.writeUInt32LE(bytes, 40);

  for (let i = 0; i < samples.length; i += 1) {
    const clamped = Math.max(-1, Math.min(1, samples[i]));
    buffer.writeInt16LE(Math.round(clamped * 32000), 44 + i * 2);
  }

  const file = path.join(OUT, name);
  fs.writeFileSync(file, buffer);
  const kb = (buffer.length / 1024).toFixed(0);
  console.log(`${name.padEnd(18)} ${kb} KB`);
}

const seconds = (n) => Math.round(n * RATE);

/** Smooth attack and release, so nothing clicks at the edges. */
function envelope(i, total, attack = 0.01, release = 0.25) {
  const t = i / total;
  const up = Math.min(1, t / attack);
  const down = Math.min(1, (1 - t) / release);
  return up * down;
}

function tone(buffer, { freq, from, duration, gain = 0.3, attack = 0.01, release = 0.4, harmonic = 0.25 }) {
  const total = seconds(duration);
  const start = seconds(from);
  for (let i = 0; i < total; i += 1) {
    const index = start + i;
    if (index >= buffer.length) break;
    const t = i / RATE;
    const body =
      Math.sin(2 * Math.PI * freq * t) +
      harmonic * Math.sin(4 * Math.PI * freq * t);
    buffer[index] += body * gain * envelope(i, total, attack, release);
  }
}

/** Filtered noise, for the soft thump of a card meeting the table. */
function noise(buffer, { from, duration, gain = 0.3, cut = 0.25 }) {
  const total = seconds(duration);
  const start = seconds(from);
  let last = 0;
  let state = 22222;
  const random = () => {
    // Small deterministic generator so every build produces the same file.
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return (state / 0x7fffffff) * 2 - 1;
  };
  for (let i = 0; i < total; i += 1) {
    const index = start + i;
    if (index >= buffer.length) break;
    last += (random() - last) * cut;
    buffer[index] += last * gain * envelope(i, total, 0.005, 0.6);
  }
}

const note = (semitonesFromA4) => 440 * Math.pow(2, semitonesFromA4 / 12);

function make(duration) {
  return new Float64Array(seconds(duration));
}

// A card landing: a low soft thump with a short wooden ring.
{
  const buffer = make(0.22);
  noise(buffer, { from: 0, duration: 0.09, gain: 0.5, cut: 0.35 });
  tone(buffer, { freq: note(-17), from: 0, duration: 0.2, gain: 0.22, release: 0.7 });
  writeWav('card_place.wav', buffer);
}

// Pass: a short breathy sweep, no pitch, so it reads as "nothing played".
{
  const buffer = make(0.3);
  noise(buffer, { from: 0, duration: 0.28, gain: 0.3, cut: 0.12 });
  writeWav('pass.wav', buffer);
}

// Your turn: two rising notes, friendly and quiet.
{
  const buffer = make(0.42);
  tone(buffer, { freq: note(4), from: 0, duration: 0.16, gain: 0.26 });
  tone(buffer, { freq: note(11), from: 0.12, duration: 0.28, gain: 0.26 });
  writeWav('turn.wav', buffer);
}

// Timer warning: one clear beep. Meant to be noticed, not to startle.
{
  const buffer = make(0.26);
  tone(buffer, { freq: note(9), from: 0, duration: 0.22, gain: 0.3, harmonic: 0.1 });
  writeWav('warn.wav', buffer);
}

// A refused tap: a short low buzz.
{
  const buffer = make(0.2);
  tone(buffer, { freq: note(-14), from: 0, duration: 0.16, gain: 0.24, harmonic: 0.7 });
  writeWav('deny.wav', buffer);
}

// Win: a major arpeggio that keeps rising.
{
  const buffer = make(1.3);
  const steps = [0, 4, 7, 12, 16];
  steps.forEach((semi, index) => {
    tone(buffer, {
      freq: note(semi),
      from: index * 0.11,
      duration: 0.75,
      gain: 0.2,
      release: 0.55,
    });
  });
  writeWav('win.wav', buffer);
}

// Round over without a win: two settling notes, not a punishment.
{
  const buffer = make(0.8);
  tone(buffer, { freq: note(2), from: 0, duration: 0.4, gain: 0.22 });
  tone(buffer, { freq: note(-3), from: 0.26, duration: 0.5, gain: 0.22 });
  writeWav('lose.wav', buffer);
}

// A coin arriving, for the shop and for match payouts.
{
  const buffer = make(0.4);
  tone(buffer, { freq: note(16), from: 0, duration: 0.1, gain: 0.2, harmonic: 0.5 });
  tone(buffer, { freq: note(23), from: 0.06, duration: 0.3, gain: 0.18, harmonic: 0.5 });
  writeWav('coin.wav', buffer);
}

// The background loop: eight seconds of a slow chord pattern, quiet and without
// percussion, so it can sit under a game for a long time without wearing thin.
// The last note fades before the end and the first starts from silence, so the
// seam is inaudible when it repeats.
{
  const length = 8;
  const buffer = make(length);
  // Two bars of I, vi, IV, V in A, one chord every two seconds.
  const chords = [
    [-12, -5, 0], // A
    [-15, -8, -3], // F sharp minor
    [-17, -10, -5], // D
    [-19, -12, -7], // E
  ];
  chords.forEach((chord, bar) => {
    chord.forEach((semi, voice) => {
      tone(buffer, {
        freq: note(semi),
        from: bar * 2 + voice * 0.06,
        duration: 2.1,
        gain: 0.1,
        attack: 0.15,
        release: 0.45,
        harmonic: 0.12,
      });
    });
    // A single higher note per bar, so the loop has a shape to follow.
    tone(buffer, {
      freq: note(chord[2] + 12 + (bar % 2 === 0 ? 4 : 7)),
      from: bar * 2 + 0.5,
      duration: 1.2,
      gain: 0.06,
      attack: 0.2,
      release: 0.6,
      harmonic: 0.05,
    });
  });
  // Guarantee silence at both ends of the loop.
  const fade = seconds(0.12);
  for (let i = 0; i < fade; i += 1) {
    const ramp = i / fade;
    buffer[i] *= ramp;
    buffer[buffer.length - 1 - i] *= ramp;
  }
  writeWav('music_loop.wav', buffer);
}
