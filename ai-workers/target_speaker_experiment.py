from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import httpx
import numpy as np
import soundfile as sf
from speechbrain.inference.separation import SepformerSeparation

FFMPEG = Path(r"F:\NOVRIA-Voice-Server\tools\ffmpeg\bin\ffmpeg.exe")
VC_PYTHON = Path(r"F:\NOVRIA-Voice-Server\.venv-vc\Scripts\python.exe")
VC_WORKER = "http://127.0.0.1:18110"
SEPFORMER_DIR = Path(r"F:\NOVRIA-Voice-Server\models\sepformer-whamr")


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


def ffmpeg_convert(source: Path, output: Path, *, sample_rate: int, channels: int = 1) -> Path:
    run([
        str(FFMPEG), "-y", "-i", str(source), "-vn",
        "-ac", str(channels), "-ar", str(sample_rate),
        "-c:a", "pcm_s16le", str(output),
    ])
    return output


def extract_segment(media: Path, output: Path, *, start: float, end: float) -> Path:
    duration = max(0.10, end - start)
    run([
        str(FFMPEG), "-y",
        "-ss", f"{start:.3f}", "-t", f"{duration:.3f}",
        "-i", str(media), "-vn",
        "-ac", "1", "-ar", "8000", "-c:a", "pcm_s16le",
        str(output),
    ])
    return output


def campplus_score(reference: Path, candidate: Path) -> dict:
    code = r'''
import json, sys
from modelscope.pipelines import pipeline
from modelscope.utils.constant import Tasks
sv = pipeline(task=Tasks.speaker_verification, model='iic/speech_campplus_sv_zh-cn_16k-common')
r = sv([sys.argv[1], sys.argv[2]])
print('NOVRIA_JSON=' + json.dumps(r, ensure_ascii=False))
'''
    result = run([str(VC_PYTHON), "-c", code, str(reference), str(candidate)])
    marker = "NOVRIA_JSON="
    line = next((x for x in result.stdout.splitlines() if x.startswith(marker)), None)
    if not line:
        raise RuntimeError("CAMPPlus did not return JSON")
    return json.loads(line[len(marker):])


def seed_vc(source: Path, target: Path, output_dir: Path) -> dict:
    with source.open("rb") as fs, target.open("rb") as ft:
        response = httpx.post(
            f"{VC_WORKER}/api/v1/vc/convert",
            files={
                "source": (source.name, fs, "audio/wav"),
                "target": (target.name, ft, "application/octet-stream"),
            },
            data={
                "diffusion_steps": "20",
                "length_adjust": "1.0",
                "intelligibility_cfg_rate": "0.7",
                "similarity_cfg_rate": "0.7",
                "top_p": "0.9",
                "temperature": "1.0",
                "repetition_penalty": "1.0",
                "convert_style": "false",
            },
            timeout=1800,
        )
    response.raise_for_status()
    body = response.json()
    if not body.get("ok"):
        raise RuntimeError(f"Seed-VC failed: {body}")
    vc_path = Path(str(body.get("output_path", "")))
    if not vc_path.exists():
        raise RuntimeError(f"Seed-VC output missing: {vc_path}")
    local = output_dir / "actor_new.wav"
    ffmpeg_convert(vc_path, local, sample_rate=44100, channels=1)
    body["local_output"] = str(local)
    return body


def save_preview(non_actor: Path, actor_new: Path, output: Path) -> Path:
    # Dialogue-only diagnostic preview. This deliberately does NOT replace the original mix.
    run([
        str(FFMPEG), "-y",
        "-i", str(non_actor), "-i", str(actor_new),
        "-filter_complex",
        "[0:a]aresample=44100,volume=1.0[a];"
        "[1:a]aresample=44100,volume=0.92[b];"
        "[a][b]amix=inputs=2:duration=longest:normalize=0,"
        "alimiter=limit=0.891251[out]",
        "-map", "[out]", "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le",
        str(output),
    ])
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="NOVRIA target-speaker overlap experiment")
    parser.add_argument("--media", required=True)
    parser.add_argument("--actor-ref", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--start", type=float, required=True)
    parser.add_argument("--end", type=float, required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    media = Path(args.media)
    actor_ref = Path(args.actor_ref)
    target = Path(args.target)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    for p in (media, actor_ref, target, FFMPEG, VC_PYTHON, SEPFORMER_DIR / "hyperparams.yaml"):
        if not p.exists():
            raise FileNotFoundError(p)

    segment_8k = extract_segment(media, out / "overlap_8k.wav", start=args.start, end=args.end)

    print("Loading local SepFormer...")
    model = SepformerSeparation.from_hparams(
        source=str(SEPFORMER_DIR),
        savedir=str(SEPFORMER_DIR),
    )
    sources = model.separate_file(path=str(segment_8k))
    if sources.ndim != 3 or sources.shape[-1] < 2:
        raise RuntimeError(f"Unexpected SepFormer output shape: {tuple(sources.shape)}")

    ref16 = ffmpeg_convert(actor_ref, out / "actor_ref_16k.wav", sample_rate=16000)
    candidates: list[dict] = []

    for idx in range(sources.shape[-1]):
        audio = sources[0, :, idx].detach().cpu().numpy().astype(np.float32)
        peak = float(np.max(np.abs(audio))) if audio.size else 0.0
        if peak > 0:
            audio = audio / peak * 0.95
        raw = out / f"speaker_{idx + 1}_8k.wav"
        sf.write(raw, audio, 8000, subtype="PCM_16")
        wav16 = ffmpeg_convert(raw, out / f"speaker_{idx + 1}_16k.wav", sample_rate=16000)
        score = campplus_score(ref16, wav16)
        candidates.append({
            "speaker": idx + 1,
            "path_8k": str(raw),
            "path_16k": str(wav16),
            "score": float(score.get("score", 0.0)),
            "verdict": score.get("text"),
        })

    candidates.sort(key=lambda x: x["score"], reverse=True)
    actor = candidates[0]
    actor_8k = Path(actor["path_8k"])
    actor_441 = ffmpeg_convert(actor_8k, out / "actor_extracted_44100.wav", sample_rate=44100)

    non_actor = candidates[1] if len(candidates) > 1 else None
    non_actor_441 = None
    if non_actor:
        non_actor_441 = ffmpeg_convert(
            Path(non_actor["path_8k"]), out / "non_actor_44100.wav", sample_rate=44100
        )

    vc = seed_vc(actor_441, target, out)
    actor_new = Path(vc["local_output"])

    preview = None
    if non_actor_441 is not None:
        preview = save_preview(non_actor_441, actor_new, out / "dialogue_only_preview.wav")

    result = {
        "ok": True,
        "mode": "target_speaker_experiment",
        "window": {"start": args.start, "end": args.end},
        "selected_actor_speaker": actor["speaker"],
        "selected_actor_score": actor["score"],
        "candidates": candidates,
        "actor_extracted": str(actor_441),
        "actor_new": str(actor_new),
        "dialogue_only_preview": str(preview) if preview else None,
        "vc": vc,
        "warning": (
            "This preview is dialogue-only. Do not use it as final soundtrack. "
            "Original BGM/effects preservation requires the next residual-reconstruction stage."
        ),
    }
    result_path = out / "result.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"RESULT_JSON={result_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
