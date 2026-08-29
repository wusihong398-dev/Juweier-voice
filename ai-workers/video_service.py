import os
import shutil
import subprocess
import time
import uuid
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

ROOT = Path(r"F:\NOVRIA-Voice-Server")
LTX_ROOT = ROOT / "LTX-Video"
PYTHON = ROOT / ".venv-video" / "Scripts" / "python.exe"
MODEL_ROOT = ROOT / "video-models" / "ltx"
DATA_ROOT = Path(r"E:\NOVRIA-Voice-Data\video")
INPUT_ROOT = DATA_ROOT / "input"
OUTPUT_ROOT = DATA_ROOT / "output"
TEMP_ROOT = DATA_ROOT / "temp"

for p in (INPUT_ROOT, OUTPUT_ROOT, TEMP_ROOT):
    p.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Juweier Local Video Worker", version="0.1.0")


def _model_file(name: str) -> Path:
    return MODEL_ROOT / name


def _ready() -> dict:
    return {
        "python": PYTHON.exists(),
        "repo": LTX_ROOT.exists(),
        "model": _model_file("ltxv-2b-0.9.8-distilled.safetensors").exists(),
        "upscaler": _model_file("ltxv-spatial-upscaler-0.9.8.safetensors").exists(),
    }


@app.get("/health")
def health():
    state = _ready()
    return {
        "ok": all(state.values()),
        "service": "juweier-local-video",
        "engine": "LTX-Video",
        "model": "2B Distilled 0.9.8",
        "state": state,
    }


def _write_runtime_config(task_dir: Path) -> Path:
    source = LTX_ROOT / "configs" / "ltxv-2b-0.9.8-distilled.yaml"
    if not source.exists():
        raise HTTPException(500, f"Missing config: {source}")
    text = source.read_text(encoding="utf-8")
    text = text.replace('checkpoint_path: "ltxv-2b-0.9.8-distilled.safetensors"', f'checkpoint_path: "{_model_file("ltxv-2b-0.9.8-distilled.safetensors").as_posix()}"')
    text = text.replace('spatial_upscaler_model_path: "ltxv-spatial-upscaler-0.9.8.safetensors"', f'spatial_upscaler_model_path: "{_model_file("ltxv-spatial-upscaler-0.9.8.safetensors").as_posix()}"')
    config = task_dir / "ltx_runtime.yaml"
    config.write_text(text, encoding="utf-8")
    return config


@app.post("/api/v1/video/generate")
async def generate(
    prompt: str = Form(...),
    negative_prompt: str = Form("worst quality, inconsistent motion, blurry, jittery, distorted"),
    width: int = Form(768),
    height: int = Form(448),
    num_frames: int = Form(81),
    fps: int = Form(24),
    seed: int = Form(171198),
    reference: Optional[UploadFile] = File(None),
):
    state = _ready()
    if not all(state.values()):
        raise HTTPException(503, {"message": "video worker not ready", "state": state})

    width = max(320, min(width, 1024))
    height = max(320, min(height, 1024))
    num_frames = max(9, min(num_frames, 121))
    fps = max(8, min(fps, 30))

    task_id = str(uuid.uuid4())
    task_dir = TEMP_ROOT / task_id
    task_dir.mkdir(parents=True, exist_ok=True)
    output_dir = OUTPUT_ROOT / task_id
    output_dir.mkdir(parents=True, exist_ok=True)
    config = _write_runtime_config(task_dir)

    cmd = [
        str(PYTHON),
        str(LTX_ROOT / "inference.py"),
        "--prompt", prompt,
        "--negative_prompt", negative_prompt,
        "--height", str(height),
        "--width", str(width),
        "--num_frames", str(num_frames),
        "--frame_rate", str(fps),
        "--seed", str(seed),
        "--pipeline_config", str(config),
        "--output_path", str(output_dir),
        "--offload_to_cpu", "true",
    ]

    if reference is not None:
        suffix = Path(reference.filename or "reference.png").suffix or ".png"
        ref_path = task_dir / f"reference{suffix}"
        with ref_path.open("wb") as f:
            shutil.copyfileobj(reference.file, f)
        cmd += ["--conditioning_media_paths", str(ref_path), "--conditioning_start_frames", "0"]

    started = time.time()
    process = subprocess.run(
        cmd,
        cwd=str(LTX_ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    seconds = round(time.time() - started, 2)

    if process.returncode != 0:
        raise HTTPException(500, {
            "message": "LTX generation failed",
            "task_id": task_id,
            "stderr": process.stderr[-6000:],
            "stdout": process.stdout[-3000:],
        })

    videos = sorted(output_dir.rglob("*.mp4"), key=lambda p: p.stat().st_mtime)
    if not videos:
        raise HTTPException(500, {"message": "Generation completed but no MP4 found", "task_id": task_id})

    output = videos[-1]
    return {
        "ok": True,
        "task_id": task_id,
        "engine": "LTX-Video 2B Distilled 0.9.8",
        "processing_seconds": seconds,
        "width": width,
        "height": height,
        "num_frames": num_frames,
        "fps": fps,
        "seed": seed,
        "output_path": str(output),
        "download_url": f"/api/v1/video/result/{task_id}",
    }


@app.get("/api/v1/video/result/{task_id}")
def result(task_id: str):
    output_dir = OUTPUT_ROOT / task_id
    if not output_dir.exists():
        raise HTTPException(404, "Task not found")
    videos = sorted(output_dir.rglob("*.mp4"), key=lambda p: p.stat().st_mtime)
    if not videos:
        raise HTTPException(404, "Video not ready")
    return FileResponse(videos[-1], media_type="video/mp4", filename=f"juweier_{task_id}.mp4")
