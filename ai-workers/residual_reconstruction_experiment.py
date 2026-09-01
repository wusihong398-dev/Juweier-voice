from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import correlate, correlation_lags

FFMPEG = Path(r"F:\NOVRIA-Voice-Server\tools\ffmpeg\bin\ffmpeg.exe")


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr[-4000:] or result.stdout[-4000:] or "command failed")
    return result


def ffmpeg_convert(source: Path, output: Path, *, sample_rate: int = 44100, channels: int = 2) -> Path:
    run([
        str(FFMPEG), "-y", "-i", str(source), "-vn",
        "-ac", str(channels), "-ar", str(sample_rate),
        "-c:a", "pcm_s24le", str(output),
    ])
    return output


def extract_original_segment(media: Path, output: Path, *, start: float, end: float) -> Path:
    duration = max(0.1, end - start)
    run([
        str(FFMPEG), "-y",
        "-ss", f"{start:.3f}", "-t", f"{duration:.3f}",
        "-i", str(media), "-vn",
        "-ac", "2", "-ar", "44100", "-c:a", "pcm_s24le",
        str(output),
    ])
    return output


def normalize_shape(audio: np.ndarray) -> np.ndarray:
    if audio.ndim == 1:
        audio = audio[:, None]
    return audio.astype(np.float64, copy=False)


def align_mono_reference(original_stereo: np.ndarray, actor_mono: np.ndarray, max_lag_ms: float, sr: int) -> tuple[np.ndarray, int]:
    original_mono = original_stereo.mean(axis=1)
    actor = actor_mono[:, 0] if actor_mono.ndim == 2 else actor_mono

    n = min(len(original_mono), len(actor))
    original_mono = original_mono[:n]
    actor = actor[:n]

    max_lag = max(1, int(sr * max_lag_ms / 1000.0))
    # Downsample only for correlation speed; keep exact lag in original sample units.
    step = 4
    corr = correlate(original_mono[::step], actor[::step], mode="full", method="fft")
    lags = correlation_lags(len(original_mono[::step]), len(actor[::step]), mode="full")
    allowed = np.abs(lags) <= max(1, max_lag // step)
    best = int(lags[allowed][np.argmax(np.abs(corr[allowed]))]) * step

    aligned = np.zeros(n, dtype=np.float64)
    if best >= 0:
        length = min(n - best, n)
        if length > 0:
            aligned[best:best + length] = actor[:length]
    else:
        shift = -best
        length = min(n - shift, n)
        if length > 0:
            aligned[:length] = actor[shift:shift + length]
    return aligned, best


def estimate_channel_scales(original: np.ndarray, actor_aligned: np.ndarray, max_gain: float) -> np.ndarray:
    denom = float(np.dot(actor_aligned, actor_aligned)) + 1e-12
    scales = []
    for ch in range(original.shape[1]):
        alpha = float(np.dot(original[:, ch], actor_aligned) / denom)
        alpha = max(-max_gain, min(max_gain, alpha))
        scales.append(alpha)
    return np.asarray(scales, dtype=np.float64)


def make_soft_activity(actor: np.ndarray, sr: int, floor_db: float = -42.0, smooth_ms: float = 40.0) -> np.ndarray:
    env = np.abs(actor)
    win = max(1, int(sr * smooth_ms / 1000.0))
    kernel = np.ones(win, dtype=np.float64) / win
    env = np.convolve(env, kernel, mode="same")
    peak = float(np.max(env)) + 1e-12
    threshold = peak * (10.0 ** (floor_db / 20.0))
    gate = np.clip((env - threshold) / max(peak * 0.12, 1e-12), 0.0, 1.0)
    return gate


def fit_length(audio: np.ndarray, n: int) -> np.ndarray:
    if len(audio) == n:
        return audio
    if len(audio) > n:
        return audio[:n]
    pad = np.zeros((n - len(audio), audio.shape[1]), dtype=audio.dtype)
    return np.concatenate([audio, pad], axis=0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Experimental residual reconstruction for target-speaker dubbing")
    parser.add_argument("--media", required=True)
    parser.add_argument("--actor-original", required=True)
    parser.add_argument("--actor-new", required=True)
    parser.add_argument("--start", type=float, required=True)
    parser.add_argument("--end", type=float, required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--suppression", type=float, default=0.82)
    parser.add_argument("--new-voice-gain", type=float, default=0.92)
    parser.add_argument("--max-lag-ms", type=float, default=120.0)
    parser.add_argument("--max-projection-gain", type=float, default=3.0)
    args = parser.parse_args()

    media = Path(args.media)
    actor_original = Path(args.actor_original)
    actor_new = Path(args.actor_new)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    for p in (media, actor_original, actor_new, FFMPEG):
        if not p.exists():
            raise FileNotFoundError(p)

    original_path = extract_original_segment(media, out / "original_segment_44100.wav", start=args.start, end=args.end)
    actor_original_path = ffmpeg_convert(actor_original, out / "actor_original_44100.wav", sample_rate=44100, channels=1)
    actor_new_path = ffmpeg_convert(actor_new, out / "actor_new_44100_stereo.wav", sample_rate=44100, channels=2)

    original, sr = sf.read(original_path, always_2d=True, dtype="float64")
    actor_old, sr_old = sf.read(actor_original_path, always_2d=True, dtype="float64")
    actor_new_audio, sr_new = sf.read(actor_new_path, always_2d=True, dtype="float64")
    if sr != 44100 or sr_old != 44100 or sr_new != 44100:
        raise RuntimeError(f"Unexpected sample rates: {sr}, {sr_old}, {sr_new}")

    original = normalize_shape(original)
    actor_old = normalize_shape(actor_old)
    actor_new_audio = normalize_shape(actor_new_audio)
    n = len(original)
    actor_new_audio = fit_length(actor_new_audio, n)

    actor_aligned, lag = align_mono_reference(original, actor_old, args.max_lag_ms, sr)
    scales = estimate_channel_scales(original, actor_aligned, args.max_projection_gain)
    activity = make_soft_activity(actor_aligned, sr)

    estimated_actor = np.stack([actor_aligned * scales[ch] for ch in range(original.shape[1])], axis=1)
    suppression = float(np.clip(args.suppression, 0.0, 1.2))
    residual = original - estimated_actor * activity[:, None] * suppression

    # Keep original spatial field. New voice is centered but left/right preserving target waveform.
    new_gain = float(np.clip(args.new_voice_gain, 0.0, 2.0))
    mixed = residual + actor_new_audio * activity[:, None] * new_gain

    peak = float(np.max(np.abs(mixed))) + 1e-12
    limiter_gain = 1.0
    target_peak = 10.0 ** (-1.5 / 20.0)
    if peak > target_peak:
        limiter_gain = target_peak / peak
        mixed *= limiter_gain

    sf.write(out / "residual_only.wav", residual.astype(np.float32), sr, subtype="PCM_24")
    sf.write(out / "residual_reconstruction_preview.wav", mixed.astype(np.float32), sr, subtype="PCM_24")
    sf.write(out / "estimated_actor_projection.wav", estimated_actor.astype(np.float32), sr, subtype="PCM_24")

    result = {
        "ok": True,
        "mode": "residual_reconstruction_experiment",
        "window": {"start": args.start, "end": args.end},
        "sample_rate": sr,
        "alignment_lag_samples": lag,
        "alignment_lag_ms": lag * 1000.0 / sr,
        "channel_projection_scales": scales.tolist(),
        "suppression": suppression,
        "new_voice_gain": new_gain,
        "limiter_gain": limiter_gain,
        "outputs": {
            "original": str(original_path),
            "actor_original": str(actor_original_path),
            "actor_new": str(actor_new_path),
            "estimated_actor_projection": str(out / "estimated_actor_projection.wav"),
            "residual_only": str(out / "residual_only.wav"),
            "preview": str(out / "residual_reconstruction_preview.wav"),
        },
        "warning": (
            "Experimental residual reconstruction. It preserves the original mix as the base and only subtracts "
            "the component correlated with the extracted actor before adding the converted actor. Listen for "
            "phase residue, doubled voice, lost effects, or pumping before production use."
        ),
    }
    result_path = out / "residual_result.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"RESULT_JSON={result_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
