#!/usr/bin/env python3
"""Import Novabolt's sound effects from Sam's licensed sound library.

Picked by ear on Nov 21, 2026 (audition page). Each source is converted to
16-bit mono 44.1 kHz, leading silence trimmed, cut to a game-friendly length
with a fade-out, and loudness-matched (RMS) so the per-sound volumes in
lib/audio/sfx.dart stay meaningful. The kill sound is written as five combo
pitches (kill_0 … kill_4).

Output file names are what the game loads, so no code changes are needed.
Needs: macOS `afconvert`, numpy, and the library at LIB.

    python3 scripts/import_sfx.py

Licences (all allow use inside a commercial game; none require credit; raw
files must not be redistributed on their own): see scripts/sfx_sources.md.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

LIB = "/Users/sammorrison/Documents/Coc Boys/Sound Effects"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")

OV = "Ovani"
SCIFI = OV + "/Science Fiction Sound FX Pack Vol. 2-1705735579386/Science Fiction SFX 2"
CYBER = OV + "/Cyberpunk Sound FX Pack Vol. 1-1705725658282/Cyberpunk SFX"
UI = OV + "/UI & Menus Sound FX Pack Vol. 2-1705773661447/UI&Menu SFX 2"
CAS = OV + "/Casual & Mobile Sound FX Pack Vol. 1-1705710022155/Casual Mobile SFX"
JIN = OV + "/Jingles & Stingers Sound FX Pack Vol. 2-1705730742505/Jingles & Stingers SFX 2"
TWU = "Games & Films/userinterfacesoundfxscifitech"
TWE = "Games & Films/explosionsoundfxvolume1"

# game file: (library path, max seconds)
PICKS = {
    "shoot": (SCIFI + "/Weapons/Light/Lazgun Single A.wav", 0.35),
    "hit": (CAS + "/Interactions/Enemies and Allies/Casual Enemy Damage A.wav", 0.3),
    "kill": (TWU + "/TomWinandySFX_UI_ScifiTech_Deflect_01.wav", 0.45),
    "explode": (TWE + "/TomWinandySFX_Explosions Volume I_MediumExplosion_02.wav", 1.3),
    "boss_death": (TWE + "/TomWinandySFX_Explosions Volume I_CloseExplosion_08.wav", 3.0),
    "player_hit": (CYBER + "/Lazers and Tazers/Impact and Fry.wav", 0.7),
    "shield_hit": (SCIFI + "/Misc/Shields and Impacts/Shield Impact B.wav", 0.7),
    "pickup": (UI + "/Signals/Positive/Signal Positive Space A.wav", 0.9),
    "coin": (UI + "/Signals/Positive/Signal Positive Bells A.wav", 1.0),
    "levelup": (TWU + "/TomWinandySFX_UI_ScifiTech_Upgrade-Boost_04.wav", 2.0),
    "nova": (SCIFI + "/Weapons/Charge/Power Charge A.wav", 1.6),
    "warning": (TWU + "/TomWinandySFX_UI_ScifiTech_Alarm-Loop_01.wav", 2.0),
    "stage": (CYBER + "/Pulse and Surge/Cyber Pulse A.wav", 1.6),
    "click": (TWU + "/TomWinandySFX_UI_ScifiTech_Button-Select_01.wav", 0.25),
    "relic": (JIN + "/Bells/Bells Discover.wav", 2.4),
    "zap": (SCIFI + "/Weapons/Misc/Laser Beam A.wav", 0.6),
    "dash": (TWU + "/TomWinandySFX_UI_ScifiTech_Swipe 1.wav", 0.4),
    # Added Nov 22, 2026 (picked from the names, not by ear; swap freely):
    "overdrive": (CYBER + "/Pulse and Surge/Cyber Surge A.wav", 1.8),
    "graze": (TWU + "/TomWinandySFX_UI_ScifiTech_Swipe 8.wav", 0.24),
}

# Kill pops rise with the combo (see Sfx.killForCombo). Subtle steps: a real
# recording sounds chipmunky if pushed as far as the old synth was.
KILL_PITCHES = (1.0, 1.06, 1.12, 1.19, 1.26)

SR = 44100
TARGET_RMS = 0.12  # ~-18 dBFS over the audible part
PEAK_CEIL = 0.95


def load(path):
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, "x.wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{SR}", "-c", "1", path, tmp],
                       check=True, capture_output=True)
        with wave.open(tmp) as w:
            return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768


def shape(x, max_s):
    thr = 0.02 * (np.max(np.abs(x)) or 1)
    nz = np.nonzero(np.abs(x) > thr)[0]
    if len(nz):
        x = x[max(0, nz[0] - int(SR * 0.003)):]
    n = min(len(x), int(SR * max_s))
    cut = n < len(x)
    x = x[:n].copy()
    # Fade-in a hair (no click), fade-out longer when we cut a tail off.
    fi = min(n // 8, int(SR * 0.002))
    if fi:
        x[:fi] *= np.linspace(0, 1, fi)
    fo = min(n // 3, int(SR * (0.08 if cut else 0.01)))
    if fo:
        x[-fo:] *= np.linspace(1, 0, fo) ** (2 if cut else 1)
    return x


def loudness_match(x):
    audible = x[np.abs(x) > 0.01 * (np.max(np.abs(x)) or 1)]
    rms = np.sqrt(np.mean(audible ** 2)) if len(audible) else 1
    x = x * (TARGET_RMS / (rms or 1))
    peak = np.max(np.abs(x)) or 1
    if peak > PEAK_CEIL:
        x *= PEAK_CEIL / peak
    return x


def pitch(x, factor):
    """Resample to raise pitch by [factor] (also shortens it, like tape)."""
    if factor == 1.0:
        return x
    idx = np.arange(0, len(x) - 1, factor)
    return np.interp(idx, np.arange(len(x)), x)


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{name:12s} {len(x) / SR:5.2f}s")


def main():
    for name, (rel, max_s) in PICKS.items():
        x = loudness_match(shape(load(os.path.join(LIB, rel)), max_s))
        if name == "kill":
            for i, f in enumerate(KILL_PITCHES):
                write(f"kill_{i}", pitch(x, f))
        else:
            write(name, x)


if __name__ == "__main__":
    main()
