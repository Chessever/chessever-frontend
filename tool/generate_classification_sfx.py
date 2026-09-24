#!/usr/bin/env python3
"""Generate the move-classification sounds with the ElevenLabs Sound Generation API.

Writes one file per class to ``assets/sfx/nag_<name>.mp3``. ``assets/sfx/`` is
already a registered asset directory, so no pubspec change is needed.

Only CLASSIFIED moves get these sounds (the report verdicts and the move-quality
glyphs ``!!`` ``!`` ``!?`` ``?!`` ``?`` ``??``, plus best / missed win / book).
Ordinary moves keep the board's own ``piece_*.wav`` sounds untouched.

Key handling: the key is read from ``ELEVENLABS_API_KEY`` or, with
``--key-file``, from a JSON/JSONC file containing an ``"ELEVENLABS_API_KEY"``
entry (the git-ignored ``opencode.jsonc``). It is never taken from argv, never
printed, and scrubbed from any error body before that is shown.

    python3 tool/generate_classification_sfx.py --key-file opencode.jsonc
    python3 tool/generate_classification_sfx.py --key-file opencode.jsonc \\
        --only blunder --variants 3 --raw-dir build/sfx_takes
    python3 tool/generate_classification_sfx.py --finish blunder \\
        build/sfx_takes/nag_blunder_v2.mp3

With ``--variants 1`` (default) each take is finished straight into
``assets/sfx``. With more, raw takes land in ``--raw-dir`` to audition, and the
chosen one is finished with ``--finish <name> <take>``.

Finishing (needs ffmpeg for decode/encode; the rest is plain Python):
  * trims the API's leading and trailing silence — a class sound has to start
    the instant the piece lands — or, for sounds whose body arrives late (the
    page flick), starts a few ms before the loudest transient;
  * for ``great`` and ``interesting``, composes the two-note gesture from the
    single generated note (at these lengths the model renders one note however
    the prompt asks for two): the second note is the same take re-pitched, and
    ``interesting``'s second note bends upward like a question;
  * caps the length, fades the tail, levels the take against the board sounds
    and encodes 44.1 kHz / 128 kbps mp3.
"""

from __future__ import annotations

import argparse
import array
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import wave
from dataclasses import dataclass, field
from pathlib import Path

API_URL = "https://api.elevenlabs.io/v1/sound-generation"
OUTPUT_FORMAT = "mp3_44100_128"
REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "assets" / "sfx"
SAMPLE_RATE = 44100

# Shared tail for every prompt: one instrument family (felt mallets, warm
# bells, glass) so the nine read as a set, and away from the game-show /
# cartoon register the model drifts into by default.
_STYLE = (
    "Premium minimal UI sound for a chess app, felt mallet and warm glass "
    "timbre, dry close studio recording, clean, no voice, no music bed, no "
    "whoosh, not cartoonish, starts instantly, short tight ending"
)


@dataclass(frozen=True)
class Note:
    """One voice of a composed gesture, cut from the generated take."""

    start: float  # seconds into the output
    ratio: float = 1.0  # pitch ratio (1.5 = a fifth up); shortens the note
    gain: float = 1.0
    # Fade the note out between these times (seconds from its start), so a
    # first note makes room for the second instead of ringing under it.
    release: tuple[float, float] | None = None
    # Upward bend: (from, to, ratio) — the pitch glides by `ratio` between
    # `from` and `to` seconds after the note starts.
    bend: tuple[float, float, float] | None = None


@dataclass(frozen=True)
class Sound:
    prompt: str
    duration: float  # asked of the API (it accepts 0.5 s and up)
    influence: float
    max_seconds: float  # hard cap after finishing
    # Target RMS level. The board sounds sit between -19 and -31 dB RMS; the
    # frequent classes (book, best) sit at the quiet end, the rare ones
    # (brilliant, blunder) at the loud end.
    rms_db: float
    # Start this many ms before the loudest transient instead of at the
    # first audible sample (for takes whose body arrives late).
    align_to_peak_ms: float | None = None
    compose: tuple[Note, ...] = field(default_factory=tuple)


SOUNDS: dict[str, Sound] = {
    # !! — the rarest, most special verdict.
    "brilliant": Sound(
        "Crystalline ascending shimmer: three quick glass bell notes rising "
        "in a bright major arpeggio, ending on one sparkling high accent, "
        "delicate and precious",
        1.2,
        0.65,
        1.2,
        -19.0,
    ),
    # ! — confident, warm, positive: a rising fifth, ding-DING.
    "great": Sound(
        "Two separate warm bell notes played one after the other, a low note "
        "then a higher note a fifth above, confident and positive, soft felt "
        "mallet, clean",
        0.7,
        0.65,
        0.75,
        -21.0,
        compose=(
            Note(0.0, 1.0, gain=0.8, release=(0.09, 0.30)),
            Note(0.105, 1.5),
        ),
    ),
    # Engine's top move — frequent, so neutral and light.
    "best": Sound(
        "One clean soft tick-chime, a single short warm glass tap with a "
        "gentle bright resonance, neutral and positive, subtle",
        0.5,
        0.65,
        0.5,
        -24.0,
    ),
    # !? — speculative: a note, then a higher one that lifts like a question.
    "interesting": Sound(
        "A single soft wooden marimba note whose pitch slides upward at the "
        "end like a curious question, playful and light",
        0.8,
        0.65,
        0.7,
        -22.0,
        compose=(
            Note(0.0, 1.0, gain=0.85, release=(0.10, 0.26)),
            Note(0.13, 1.26, bend=(0.06, 0.30, 1.12)),
        ),
    ),
    # ?! — doubtful, not alarming.
    "inaccuracy": Sound(
        "Soft doubtful descending wobble: one muted felt mallet note gently "
        "bending downward with a slight slow vibrato, hesitant and quiet",
        0.7,
        0.65,
        0.7,
        -24.0,
    ),
    # ? — a clear "uh-oh".
    "mistake": Sound(
        "Clear falling two-note uh-oh, warm muted bell, the second note a "
        "minor third lower, short and slightly disappointed",
        0.7,
        0.65,
        0.45,
        -21.0,
    ),
    # ?? — the most severe. Low-mid rather than sub-bass so it still lands on
    # a phone speaker.
    "blunder": Sound(
        "Dramatic dissonant low-mid piano cluster stab, two clashing notes a "
        "tritone apart struck hard with a dark brass edge, severe and tense, "
        "short decay",
        1.0,
        0.65,
        0.9,
        -19.0,
    ),
    # A winning line was missed — regret, not alarm.
    "missed_win": Sound(
        "Sighing falling glissando, a soft warm synth tone sliding down "
        "slowly like a sigh, regretful and gentle, fading out",
        1.2,
        0.6,
        1.1,
        -22.0,
    ),
    # Opening theory — the most frequent class, so the quietest and shortest.
    "book": Sound(
        "One single crisp paper page flick, very short, sharp attack, quiet, "
        "dry close-up",
        0.5,
        0.7,
        0.32,
        -27.0,
        align_to_peak_ms=35,
    ),
}

_PEAK_CEILING_DB = -3.0
_SILENCE_DB = -50.0  # below the take's peak
_PRE_ROLL_S = 0.005
_FADE_S = 0.06

# ---------------------------------------------------------------------------
# ElevenLabs.


def _read_key(key_file: str | None) -> str:
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if key or not key_file:
        return key
    text = Path(key_file).read_text(encoding="utf-8")
    match = re.search(r'"ELEVENLABS_API_KEY"\s*:\s*"([^"]+)"', text)
    return match.group(1).strip() if match else ""


def _generate(key: str, name: str, sound: Sound) -> bytes:
    body = json.dumps({
        "text": f"{sound.prompt}. {_STYLE}.",
        "duration_seconds": sound.duration,
        "prompt_influence": sound.influence,
    }).encode("utf-8")
    request = urllib.request.Request(
        f"{API_URL}?output_format={OUTPUT_FORMAT}",
        data=body,
        method="POST",
        headers={
            "xi-api-key": key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        data = response.read()
        content_type = response.headers.get("Content-Type", "")
    if "audio" not in content_type and not data.startswith((b"ID3", b"\xff")):
        raise ValueError(
            f"{name}: expected audio, got {content_type or 'no content type'}"
        )
    if len(data) < 1024:
        raise ValueError(f"{name}: suspiciously small response ({len(data)} B)")
    return data


# ---------------------------------------------------------------------------
# Finishing. Mono float lists at 44.1 kHz; a second of audio is 44k floats,
# so plain Python is fast enough and needs no numpy.


def _ffmpeg(*args: str) -> str:
    result = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-y", *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stderr


def _decode(path: Path, tmp: Path) -> list[float]:
    wav = tmp / "decoded.wav"
    _ffmpeg(
        "-i", str(path), "-ac", "1", "-ar", str(SAMPLE_RATE),
        "-sample_fmt", "s16", str(wav),
    )
    with wave.open(str(wav)) as reader:
        frames = array.array("h", reader.readframes(reader.getnframes()))
    return [sample / 32768.0 for sample in frames]


def _encode(samples: list[float], target: Path, tmp: Path) -> None:
    wav = tmp / "finished.wav"
    pcm = array.array(
        "h", (max(-32768, min(32767, round(s * 32767))) for s in samples)
    )
    with wave.open(str(wav), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(SAMPLE_RATE)
        writer.writeframes(pcm.tobytes())
    _ffmpeg(
        "-i", str(wav), "-ac", "2", "-codec:a", "libmp3lame", "-b:a", "128k",
        "-ar", str(SAMPLE_RATE), str(target),
    )


def _db(value: float) -> float:
    return 20 * math.log10(max(value, 1e-9))


def _smoothstep(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def _render(source: list[float], note: Note) -> list[float]:
    """[source] re-pitched by [note] (tape-style: pitch and speed together)."""
    out: list[float] = []
    pos = 0.0
    last = len(source) - 1
    while pos < last:
        i = int(pos)
        frac = pos - i
        t = len(out) / SAMPLE_RATE
        sample = source[i] * (1 - frac) + source[i + 1] * frac
        if note.release is not None:
            begin, end = note.release
            sample *= 1 - _smoothstep((t - begin) / max(end - begin, 1e-6))
        out.append(sample * note.gain)
        rate = note.ratio
        if note.bend is not None:
            begin, end, ratio = note.bend
            rate *= 1 + (ratio - 1) * _smoothstep(
                (t - begin) / max(end - begin, 1e-6)
            )
        pos += rate
    return out


def _compose(source: list[float], notes: tuple[Note, ...]) -> list[float]:
    voices = [(round(n.start * SAMPLE_RATE), _render(source, n)) for n in notes]
    length = max(offset + len(voice) for offset, voice in voices)
    mix = [0.0] * length
    for offset, voice in voices:
        for i, sample in enumerate(voice):
            mix[offset + i] += sample
    return mix


def _trim(samples: list[float], sound: Sound, *, cap: bool = True) -> list[float]:
    # Relative to the take's own peak: the API's masters differ by ~25 dB, so
    # an absolute floor would clip a quiet take's decay.
    peak_level = max((abs(s) for s in samples), default=0.0)
    floor = peak_level * 10 ** (_SILENCE_DB / 20)
    audible = [i for i, s in enumerate(samples) if abs(s) > floor]
    if not audible:
        return samples
    if sound.align_to_peak_ms is not None:
        peak = max(range(len(samples)), key=lambda i: abs(samples[i]))
        start = max(0, peak - round(sound.align_to_peak_ms / 1000 * SAMPLE_RATE))
    else:
        start = max(0, audible[0] - round(_PRE_ROLL_S * SAMPLE_RATE))
    end = audible[-1] + 1
    if cap:
        end = min(end, start + round(sound.max_seconds * SAMPLE_RATE))
    return samples[start:end]


def _fade_edges(samples: list[float]) -> list[float]:
    out = list(samples)
    # 2 ms fade-in: a peak-aligned start can land mid-waveform.
    fade_in = min(len(out), round(0.002 * SAMPLE_RATE))
    for i in range(fade_in):
        out[i] *= i / fade_in
    fade_out = min(len(out) // 3, round(_FADE_S * SAMPLE_RATE))
    for i in range(fade_out):
        out[len(out) - fade_out + i] *= 1 - _smoothstep(i / fade_out)
    return out


def _level(samples: list[float], rms_db: float) -> list[float]:
    rms = math.sqrt(sum(s * s for s in samples) / max(len(samples), 1))
    peak = max(abs(s) for s in samples)
    gain_db = min(rms_db - _db(rms), _PEAK_CEILING_DB - _db(peak))
    gain = 10 ** (gain_db / 20)
    return [s * gain for s in samples]


def finish(name: str, raw: Path, target: Path) -> str:
    """Finish [raw] into [target] (see the module docs). Returns a summary."""
    sound = SOUNDS[name]
    if shutil.which("ffmpeg") is None:
        target.write_bytes(raw.read_bytes())
        return "raw (ffmpeg not found)"
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp = Path(tmp_dir)
        samples = _decode(raw, tmp)
        if sound.compose:
            # Compose from the whole note (not its silent lead-in, and not
            # yet capped, so the re-pitched voices keep their full decay).
            samples = _compose(_trim(samples, sound, cap=False), sound.compose)
        samples = _level(_fade_edges(_trim(samples, sound)), sound.rms_db)
        _encode(samples, target, tmp)
    rms = math.sqrt(sum(s * s for s in samples) / len(samples))
    peak = max(abs(s) for s in samples)
    return (
        f"{len(samples) / SAMPLE_RATE:.2f}s, rms {_db(rms):.1f} dB, "
        f"peak {_db(peak):.1f} dB"
    )


# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--only",
        help="comma-separated subset of sound names (without the nag_ prefix)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="regenerate even when assets/sfx/nag_<name>.mp3 already exists",
    )
    parser.add_argument(
        "--key-file",
        help="JSON/JSONC file holding an ELEVENLABS_API_KEY entry",
    )
    parser.add_argument(
        "--variants",
        type=int,
        default=1,
        help="takes per sound; >1 writes raw takes to --raw-dir to choose from",
    )
    parser.add_argument(
        "--raw-dir",
        default=str(REPO_ROOT / "build" / "classification_sfx_takes"),
        help="where raw takes go when --variants > 1",
    )
    parser.add_argument(
        "--finish",
        nargs=2,
        metavar=("NAME", "TAKE"),
        help="finish one chosen raw take into assets/sfx/nag_<NAME>.mp3",
    )
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if args.finish:
        name, take = args.finish
        name = name.removeprefix("nag_")
        if name not in SOUNDS:
            print(f"unknown sound: {name}", file=sys.stderr)
            return 2
        target = OUT_DIR / f"nag_{name}.mp3"
        print(f"ok    nag_{name}.mp3 {finish(name, Path(take), target)}")
        return 0

    key = _read_key(args.key_file)
    if not key:
        print(
            "No ElevenLabs key: set ELEVENLABS_API_KEY or pass --key-file",
            file=sys.stderr,
        )
        return 2

    names = list(SOUNDS)
    if args.only:
        wanted = [n.strip().removeprefix("nag_") for n in args.only.split(",")]
        unknown = [n for n in wanted if n not in SOUNDS]
        if unknown:
            print(f"unknown sound(s): {', '.join(unknown)}", file=sys.stderr)
            return 2
        names = wanted

    raw_dir = Path(args.raw_dir)
    if args.variants > 1:
        raw_dir.mkdir(parents=True, exist_ok=True)

    failures = 0
    for name in names:
        target = OUT_DIR / f"nag_{name}.mp3"
        if args.variants == 1 and target.exists() and not args.force:
            print(f"skip  nag_{name}.mp3 (exists, {target.stat().st_size} B)")
            continue
        sound = SOUNDS[name]
        for take in range(1, args.variants + 1):
            label = f"nag_{name}" + (f"_v{take}" if args.variants > 1 else "")
            try:
                data = _generate(key, name, sound)
            except urllib.error.HTTPError as error:
                failures += 1
                detail = error.read()[:200].decode("utf-8", "replace")
                detail = detail.replace(key, "***")  # never echo the key back
                print(f"FAIL  {label} HTTP {error.code}: {detail}")
                continue
            except (urllib.error.URLError, ValueError, TimeoutError) as error:
                failures += 1
                message = str(error).replace(key, "***")
                print(f"FAIL  {label} {type(error).__name__}: {message}")
                continue
            if args.variants > 1:
                path = raw_dir / f"{label}.mp3"
                path.write_bytes(data)
                print(f"take  {path} {len(data)} B")
            else:
                with tempfile.NamedTemporaryFile(suffix=".mp3") as raw:
                    raw.write(data)
                    raw.flush()
                    summary = finish(name, Path(raw.name), target)
                print(f"ok    nag_{name}.mp3 {summary}")
            time.sleep(0.4)  # stay well under the per-second request limit

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
