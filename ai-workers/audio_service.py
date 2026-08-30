from __future__ import annotations

import json
import mimetypes
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

APP_NAME = "橘味儿配音 Audio Service"
APP_VERSION = "0.2.0"
DEFAULT_VC_WORKER = os.getenv("JUWEIER_VC_WORKER", "http://127.0.0.1:18110").rstrip("/")
DEFAULT_FFMPEG = os.getenv(
    "JUWEIER_FFMPEG",
    r"F:\NOVRIA-Voice-Server\tools\ffmpeg\bin\ffmpeg.exe",
)
DEFAULT_FFPROBE = os.getenv(
    "JUWEIER_FFPROBE",
    r"F:\NOVRIA-Voice-Server\tools\ffmpeg\bin\ffprobe.exe",
)
DATA_ROOT = Path(os.getenv("JUWEIER_AUDIO_DATA", r"E:\NOVRIA-Voice-Data\audio-service"))
DATA_ROOT.mkdir(parents=True, exist_ok=True)

app = FastAPI(title=APP_NAME, version=APP_VERSION)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _require_binary(path: str, name: str) -> str:
    if Path(path).exists():
        return path
    resolved = shutil.which(name)
    if resolved:
        return resolved
    raise HTTPException(status_code=503, detail=f"{name} not found: {path}")


def _run_json(command: list[str]) -> dict[str, Any]:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail=result.stderr.strip() or "media command failed",
        )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"invalid ffprobe json: {exc}") from exc


async def _save_upload(upload: UploadFile, folder: Path) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    suffix = Path(upload.filename or "upload.bin").suffix
    target = folder / f"input{suffix}"
    with target.open("wb") as f:
        while chunk := await upload.read(1024 * 1024):
            f.write(chunk)
    await upload.close()
    return target


def _probe(path: Path) -> dict[str, Any]:
    ffprobe = _require_binary(DEFAULT_FFPROBE, "ffprobe")
    payload = _run_json(
        [
            ffprobe,
            "-v",
            "error",
            "-show_format",
            "-show_streams",
            "-of",
            "json",
            str(path),
        ]
    )
    streams = payload.get("streams", [])
    format_info = payload.get("format", {})
    audio_streams = [s for s in streams if s.get("codec_type") == "audio"]
    video_streams = [s for s in streams if s.get("codec_type") == "video"]
    return {
        "filename": path.name,
        "size_bytes": path.stat().st_size,
        "duration": float(format_info.get("duration", 0) or 0),
        "format_name": format_info.get("format_name"),
        "has_audio": bool(audio_streams),
        "has_video": bool(video_streams),
        "audio_streams": audio_streams,
        "video_streams": video_streams,
    }


@app.get("/health")
async def health() -> dict[str, Any]:
    vc_ok = False
    vc_data: dict[str, Any] | None = None
    try:
        async with httpx.AsyncClient(timeout=3) as client:
            response = await client.get(f"{DEFAULT_VC_WORKER}/health")
            vc_ok = response.status_code == 200
            if vc_ok:
                vc_data = response.json()
    except Exception:
        vc_ok = False

    return {
        "ok": True,
        "service": "juweier-audio",
        "version": APP_VERSION,
        "audio_first": True,
        "video_generation": {
            "enabled": True,
            "stage": "development_testing",
            "message": "AI视频生成功能正在开发测试阶段，前期以音频处理和短剧配音为主。",
        },
        "vc_worker": {
            "url": DEFAULT_VC_WORKER,
            "online": vc_ok,
            "data": vc_data,
        },
        "ffmpeg": Path(DEFAULT_FFMPEG).exists() or bool(shutil.which("ffmpeg")),
        "ffprobe": Path(DEFAULT_FFPROBE).exists() or bool(shutil.which("ffprobe")),
    }


@app.post("/api/v1/media/analyze")
async def analyze_media(file: UploadFile = File(...)) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="juweier-analyze-") as tmp:
        path = await _save_upload(file, Path(tmp))
        info = _probe(path)
        info["mime_type"] = mimetypes.guess_type(file.filename or "")[0]
        info["supported_for_voice"] = info["has_audio"]
        return {"ok": True, "media": info}


@app.post("/api/v1/media/extract-audio")
async def extract_audio(file: UploadFile = File(...)) -> FileResponse:
    job_dir = Path(tempfile.mkdtemp(prefix="extract-", dir=DATA_ROOT))
    source = await _save_upload(file, job_dir)
    output = job_dir / "audio.wav"
    ffmpeg = _require_binary(DEFAULT_FFMPEG, "ffmpeg")
    result = subprocess.run(
        [
            ffmpeg,
            "-y",
            "-i",
            str(source),
            "-vn",
            "-ac",
            "1",
            "-ar",
            "22050",
            "-c:a",
            "pcm_s16le",
            str(output),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode != 0 or not output.exists():
        raise HTTPException(status_code=500, detail=result.stderr[-4000:])
    return FileResponse(output, media_type="audio/wav", filename="audio.wav")


@app.post("/api/v1/vc/convert")
async def vc_convert(
    source: UploadFile = File(...),
    target: UploadFile = File(...),
    diffusion_steps: int = Form(20),
    length_adjust: float = Form(1.0),
    intelligibility_cfg_rate: float = Form(0.7),
    similarity_cfg_rate: float = Form(0.7),
    top_p: float = Form(0.9),
    temperature: float = Form(1.0),
    repetition_penalty: float = Form(1.0),
    convert_style: bool = Form(False),
) -> Any:
    source_bytes = await source.read()
    target_bytes = await target.read()
    files = {
        "source": (source.filename or "source.bin", source_bytes, source.content_type or "application/octet-stream"),
        "target": (target.filename or "target.bin", target_bytes, target.content_type or "application/octet-stream"),
    }
    data = {
        "diffusion_steps": str(diffusion_steps),
        "length_adjust": str(length_adjust),
        "intelligibility_cfg_rate": str(intelligibility_cfg_rate),
        "similarity_cfg_rate": str(similarity_cfg_rate),
        "top_p": str(top_p),
        "temperature": str(temperature),
        "repetition_penalty": str(repetition_penalty),
        "convert_style": "true" if convert_style else "false",
    }
    try:
        async with httpx.AsyncClient(timeout=600) as client:
            response = await client.post(
                f"{DEFAULT_VC_WORKER}/api/v1/vc/convert",
                files=files,
                data=data,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"VC worker unavailable: {exc}") from exc

    try:
        body: Any = response.json()
    except ValueError:
        body = {"raw": response.text}
    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=body)
    return body


@app.get("/api/v1/video/status")
async def video_status() -> dict[str, Any]:
    return {
        "ok": True,
        "enabled": True,
        "stage": "development_testing",
        "primary_product_focus": "audio",
        "message": "AI视频功能已保留，当前处于开发测试阶段。正式版本前期重点为短剧配音、音视频换声、对白分离、环境声还原和AI演员库。",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("JUWEIER_AUDIO_PORT", "18115")))
