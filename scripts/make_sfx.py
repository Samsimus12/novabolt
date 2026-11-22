#!/usr/bin/env python3
"""Synthesise Novabolt's original placeholder sound effects.

The game now ships sounds imported from Sam's licensed library
(scripts/import_sfx.py). This script writes to scripts/synth_sfx/ so it can't
overwrite them; copy a file into assets/sfx/ by hand if you want one back.

Everything is generated from oscillators, noise and envelopes (no samples,
no third-party audio), in the same spirit as the code-drawn visuals.
Re-run after tweaking a recipe:  python3 scripts/make_sfx.py
Needs numpy only.
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "synth_sfx")
rng = np.random.default_rng(7)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack=0.005, release=None, curve=3.0):
    """Fast attack, exponential-ish decay to zero at the end."""
    a = max(1, int(SR * attack))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    rest = n - a
    if rest > 0:
        e[a:] = (1 - np.linspace(0, 1, rest)) ** curve
    return e


def sweep(f0, f1, dur, shape="sine"):
    t = t_axis(dur)
    f = np.geomspace(f0, f1, len(t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "square":
        return np.sign(np.sin(ph)) * 0.6
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if shape == "tri":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1.0) - 1) - 1
    raise ValueError(shape)


def tone(f, dur, shape="sine"):
    return sweep(f, f * 1.0001, dur, shape)


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be a scalar or a per-sample array."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def pad(x, n):
    return np.pad(x, (0, max(0, n - len(x))))


def mix(*parts):
    n = max(len(p) for p in parts)
    return sum(pad(p, n) for p in parts)


def seq(*parts, gap=0.0):
    g = np.zeros(int(SR * gap))
    out = []
    for p in parts:
        out += [p, g]
    return np.concatenate(out[:-1]) if out else np.zeros(1)


def write(name, x, gain=0.8):
    x = np.asarray(x, dtype=float)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * gain
    # 3 ms fade at both ends so nothing clicks.
    f = min(len(x) // 4, int(SR * 0.003))
    if f > 0:
        x[:f] *= np.linspace(0, 1, f)
        x[-f:] *= np.linspace(1, 0, f)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{name:14s} {len(x) / SR * 1000:6.0f} ms")


# ── Recipes ──────────────────────────────────────────────────────────────────

def shoot():
    d = 0.07
    s = sweep(1500, 620, d, "tri") * env(int(SR * d), 0.002, curve=2.2)
    s += 0.25 * highpass(noise(d), 3000) * env(int(SR * d), 0.001, curve=6)
    return s


def hit():
    d = 0.045
    n = highpass(noise(d), 1800) * env(int(SR * d), 0.001, curve=4)
    return n + 0.5 * sweep(900, 400, d) * env(int(SR * d), 0.001, curve=4)


def kill(pitch):
    d = 0.16
    n = int(SR * d)
    body = sweep(520 * pitch, 140 * pitch, d) * env(n, 0.002, curve=2.5)
    sparkle = sweep(2400 * pitch, 1600 * pitch, d * 0.6, "tri") * env(int(n * 0.6), 0.001, curve=3)
    crack = lowpass(noise(d), np.geomspace(6000, 600, n)) * env(n, 0.001, curve=5)
    return mix(body, 0.35 * sparkle, 0.6 * crack)


def explode(dur=0.55):
    n = int(SR * dur)
    rumble = lowpass(noise(dur), np.geomspace(2600, 120, n)) * env(n, 0.003, curve=2.2)
    thump = sweep(140, 38, dur) * env(n, 0.002, curve=3)
    return mix(1.6 * rumble, thump)


def boss_death():
    d = 1.6
    n = int(SR * d)
    boom = explode(1.2) * 1.2
    rise = sweep(300, 1800, d, "saw")
    rise = lowpass(rise, 2500) * np.linspace(0, 1, n) ** 2 * env(n, 0.6, curve=1.2) * 0.35
    chord = mix(*(tone(f, 1.1) for f in (523, 659, 784, 1047))) * env(int(SR * 1.1), 0.05, curve=2)
    chord = np.concatenate([np.zeros(int(SR * 0.45)), chord * 0.22])
    return mix(boom, rise, chord)


def player_hit():
    d = 0.2
    n = int(SR * d)
    thud = sweep(220, 55, d, "square") * env(n, 0.002, curve=3)
    crunch = lowpass(noise(d), 2200) * env(n, 0.001, curve=4)
    return mix(lowpass(thud, 1200), 0.8 * crunch)


def shield_hit():
    d = 0.18
    n = int(SR * d)
    ping = mix(tone(1320, d), 0.6 * tone(1980, d), 0.3 * tone(2970, d)) * env(n, 0.001, curve=4)
    fizz = highpass(noise(d), 4000) * env(n, 0.001, curve=8) * 0.4
    return mix(ping, fizz)


def pickup():
    a = tone(880, 0.07, "tri") * env(int(SR * 0.07), 0.002, curve=1.5)
    b = tone(1320, 0.11, "tri") * env(int(SR * 0.11), 0.002, curve=2.5)
    return seq(a, b)


def coin():
    d = 0.32
    n = int(SR * d)
    return mix(tone(1975, d), 0.5 * tone(2637, d)) * env(n, 0.001, curve=3.5)


def levelup():
    notes = (523, 659, 784, 1047)
    parts = [tone(f, 0.11, "tri") * env(int(SR * 0.11), 0.003, curve=1.6) for f in notes]
    tail = mix(tone(1047, 0.45, "tri"), 0.5 * tone(1568, 0.45)) * env(int(SR * 0.45), 0.003, curve=2.5)
    return seq(*parts, tail, gap=0.005)


def nova():
    d = 0.8
    n = int(SR * d)
    whoosh = lowpass(noise(d), np.geomspace(300, 7000, n)) * np.linspace(0.2, 1, n) * env(n, 0.3, curve=1.0)
    charge = sweep(180, 1400, d, "saw")
    charge = lowpass(charge, 3000) * np.linspace(0.1, 1, n) * env(n, 0.5, curve=0.8) * 0.5
    return mix(whoosh, charge)


def warning():
    seg = []
    for i in range(4):
        f = 660 if i % 2 == 0 else 495
        s = tone(f, 0.3, "square")
        s = lowpass(s, 2200) * env(int(SR * 0.3), 0.01, curve=0.6)
        seg.append(s)
    return seq(*seg, gap=0.06)


def stage():
    d = 0.75
    n = int(SR * d)
    t = t_axis(d)
    vib = 1 + 0.04 * np.sin(2 * np.pi * 7 * t)
    f = np.geomspace(90, 60, n) * vib
    ph = 2 * np.pi * np.cumsum(f) / SR
    growl = (2 * ((ph / (2 * np.pi)) % 1.0) - 1)
    growl = lowpass(growl, 900) * env(n, 0.06, curve=1.5)
    grit = lowpass(noise(d), 1400) * env(n, 0.02, curve=2) * 0.6
    return mix(growl, grit, 0.6 * explode(0.4))


def click():
    d = 0.03
    return tone(2200, d) * env(int(SR * d), 0.0005, curve=6)


def relic():
    d = 1.0
    n = int(SR * d)
    chord = mix(*(tone(f, d, "sine") for f in (392, 587, 784, 1175))) * env(n, 0.02, curve=2)
    shimmer = mix(*(tone(f, d) * (0.5 + 0.5 * np.sin(2 * np.pi * (6 + k) * t_axis(d)))
                    for k, f in enumerate((2349, 2637, 3136)))) * env(n, 0.1, curve=2) * 0.25
    return mix(chord, shimmer)


def zap():
    d = 0.12
    n = int(SR * d)
    buzz = sweep(1800, 300, d, "saw") * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 90 * t_axis(d))))
    return lowpass(buzz, 5000) * env(n, 0.001, curve=2.5)


if __name__ == "__main__":
    write("shoot", shoot(), 0.45)
    write("hit", hit(), 0.5)
    for i, p in enumerate((1.0, 1.12, 1.26, 1.41, 1.59)):
        write(f"kill_{i}", kill(p), 0.7)
    write("explode", explode(), 0.9)
    write("boss_death", boss_death(), 0.95)
    write("player_hit", player_hit(), 0.85)
    write("shield_hit", shield_hit(), 0.6)
    write("pickup", pickup(), 0.6)
    write("coin", coin(), 0.55)
    write("levelup", levelup(), 0.7)
    write("nova", nova(), 0.85)
    write("warning", warning(), 0.7)
    write("stage", stage(), 0.9)
    write("click", click(), 0.4)
    write("relic", relic(), 0.7)
    write("zap", zap(), 0.55)
