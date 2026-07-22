"""Generate placeholder SFX into assets/sfx/.

AudioManager (autoload/audio_manager.gd) looks for place/rotate/invalid/send
.wav files and no-ops while they are missing. These are soft sine-based
stand-ins tuned to be cozy rather than arcade-y; swapping in real audio is the
same drop-a-file-at-the-same-path pipeline as the item art.

Run:  python tools/make_sfx.py
Stdlib only (wave + math), so it needs neither numpy nor Godot.
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
ASSETS = Path(__file__).resolve().parent.parent / "assets" / "sfx"


def render(duration, voice):
    """voice(t) -> sample in [-1, 1]; returns int16 frames."""
    count = int(duration * RATE)
    frames = bytearray()
    for i in range(count):
        t = i / RATE
        sample = max(-1.0, min(1.0, voice(t)))
        frames += struct.pack("<h", int(sample * 32767))
    return bytes(frames)


def write_wav(name, frames):
    with wave.open(str(ASSETS / name), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)
    print(f"{name}  {len(frames) // 2} samples")


def tone(t, freq, amp, decay):
    return amp * math.sin(math.tau * freq * t) * math.exp(-t * decay)


def place(t):
    # A soft thump: a low sine dropping in pitch, over fast.
    freq = 200.0 - 60.0 * min(t / 0.09, 1.0)
    return tone(t, freq, 0.5, 28.0)


def rotate(t):
    # A small dry tick.
    return tone(t, 780.0, 0.28, 90.0)


def invalid(t):
    # Two gentle low buzzes — "nope", not a game-over sting.
    burst = 0.09
    if t < burst:
        local = t
    elif 0.12 <= t < 0.12 + burst:
        local = t - 0.12
    else:
        return 0.0
    wobble = 1.0 + 0.02 * math.sin(math.tau * 31.0 * local)
    return tone(local, 155.0 * wobble, 0.32, 26.0)


def send(t):
    # A rising three-note chime (C5 E5 G5) with ringing tails.
    out = 0.0
    for start, freq in ((0.0, 523.25), (0.11, 659.25), (0.22, 783.99)):
        if t >= start:
            out += tone(t - start, freq, 0.22, 7.0)
    return out


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    write_wav("place.wav", render(0.14, place))
    write_wav("rotate.wav", render(0.07, rotate))
    write_wav("invalid.wav", render(0.30, invalid))
    write_wav("send.wav", render(0.85, send))


if __name__ == "__main__":
    main()
