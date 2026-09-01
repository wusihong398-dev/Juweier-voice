from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import httpx

VC_WORKER = "http://127.0.0.1:18110"


def run_variant(source: Path, target: Path, out: Path, similarity: float, intelligibility: float) -> dict:
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
                "intelligibility_cfg_rate": f"{intelligibility:.3f}",
                "similarity_cfg_rate": f"{similarity:.3f}",
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
    src = Path(str(body.get("output_path", "")))
    if not src.exists():
        raise RuntimeError(f"VC output missing: {src}")
    dst = out / f"voice_sim{similarity:.2f}_intel{intelligibility:.2f}.wav"
    shutil.copy2(src, dst)
    return {
        "similarity_cfg_rate": similarity,
        "intelligibility_cfg_rate": intelligibility,
        "output": str(dst),
        "processing_seconds": body.get("processing_seconds"),
        "peak_vram_mb": body.get("peak_vram_mb"),
        "task_id": body.get("task_id"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed-VC target timbre tuning matrix")
    parser.add_argument("--source", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    source = Path(args.source)
    target = Path(args.target)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    if not source.exists():
        raise FileNotFoundError(source)
    if not target.exists():
        raise FileNotFoundError(target)

    similarities = [0.70, 0.85, 1.00]
    intelligibilities = [0.60, 0.70, 0.80]

    results = []
    for similarity in similarities:
        for intelligibility in intelligibilities:
            print(f"Running similarity={similarity:.2f}, intelligibility={intelligibility:.2f} ...")
            results.append(run_variant(source, target, out, similarity, intelligibility))

    manifest = {
        "ok": True,
        "mode": "voice_tuning_experiment",
        "source": str(source),
        "target": str(target),
        "variants": results,
        "listening_guidance": (
            "Prefer the variant that matches target age/body/resonance without losing source articulation. "
            "Do not select by similarity_cfg_rate alone; listen for childlike pitch, metallic artifacts, consonant loss, and doubled formants."
        ),
    }
    manifest_path = out / "voice_tuning_result.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    print(f"RESULT_JSON={manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
