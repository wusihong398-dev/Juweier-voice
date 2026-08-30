from __future__ import annotations

import json
import mimetypes
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

APP_NAME = "橘味儿配音 Audio Service"
APP_VERSION = "0.3.0"
DEFAULT_VC_WORKER = os.getenv("JUWEIER_VC_WORKER", "http://127.0.0.1:18110").rstrip("/")
DEFAULT_FFMPEG = os.getenv("JUWEIER_FFMPEG", r"F:\NOVRIA-Voice-Server\tools\ffmpeg\bin\ffmpeg.exe")
DEFAULT_FFPROBE = os.getenv("JUWEIER_FFPROBE", r"F:\NOVRIA-Voice-Server\tools\ffmpeg\bin\ffprobe.exe")
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


def _run(command: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode != 0:
        raise HTTPException(status_code=500, detail=result.stderr[-4000:] or "media command failed")
    return result


def _run_json(command: list[str]) -> dict[str, Any]:
    result = _run(command)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"invalid ffprobe json: {exc}") from exc


async def _save_upload(upload: UploadFile, folder: Path, stem: str = "input") -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    suffix = Path(upload.filename or "upload.bin").suffix
    target = folder / f"{stem}{suffix}"
    with target.open("wb") as f:
        while chunk := await upload.read(1024 * 1024):
            f.write(chunk)
    await upload.close()
    return target


def _probe(path: Path) -> dict[str, Any]:
    ffprobe = _require_binary(DEFAULT_FFPROBE, "ffprobe")
    payload = _run_json([
        ffprobe, "-v", "error", "-show_format", "-show_streams", "-of", "json", str(path)
    ])
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


def _extract_audio(source: Path, output: Path) -> Path:
    ffmpeg = _require_binary(DEFAULT_FFMPEG, "ffmpeg")
    _run([
        ffmpeg, "-y", "-i", str(source), "-vn", "-ac", "1", "-ar", "22050",
        "-c:a", "pcm_s16le", str(output)
    ])
    return output


async def _vc_convert_paths(source_path: Path, target_path: Path, *, diffusion_steps: int = 20,
                            length_adjust: float = 1.0, intelligibility_cfg_rate: float = 0.7,
                            similarity_cfg_rate: float = 0.7, top_p: float = 0.9,
                            temperature: float = 1.0, repetition_penalty: float = 1.0,
                            convert_style: bool = False) -> dict[str, Any]:
    files = {
        "source": (source_path.name, source_path.read_bytes(), "application/octet-stream"),
        "target": (target_path.name, target_path.read_bytes(), "application/octet-stream"),
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
        async with httpx.AsyncClient(timeout=900) as client:
            response = await client.post(f"{DEFAULT_VC_WORKER}/api/v1/vc/convert", files=files, data=data)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"VC worker unavailable: {exc}") from exc
    try:
        body: Any = response.json()
    except ValueError:
        body = {"raw": response.text}
    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=body)
    if not isinstance(body, dict) or not body.get("ok"):
        raise HTTPException(status_code=502, detail={"vc_worker": body})
    return body


def _mux_video_with_audio(video: Path, audio: Path, output: Path) -> Path:
    ffmpeg = _require_binary(DEFAULT_FFMPEG, "ffmpeg")
    _run([
        ffmpeg, "-y", "-i", str(video), "-i", str(audio),
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-shortest", str(output)
    ])
    return output


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
        "vc_worker": {"url": DEFAULT_VC_WORKER, "online": vc_ok, "data": vc_data},
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
    output = _extract_audio(source, job_dir / "audio.wav")
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
    job_dir = Path(tempfile.mkdtemp(prefix="vc-", dir=DATA_ROOT))
    source_path = await _save_upload(source, job_dir, "source")
    target_path = await _save_upload(target, job_dir, "target")
    source_audio = _extract_audio(source_path, job_dir / "source.wav")
    target_audio = _extract_audio(target_path, job_dir / "target.wav")
    return await _vc_convert_paths(
        source_audio, target_audio,
        diffusion_steps=diffusion_steps,
        length_adjust=length_adjust,
        intelligibility_cfg_rate=intelligibility_cfg_rate,
        similarity_cfg_rate=similarity_cfg_rate,
        top_p=top_p,
        temperature=temperature,
        repetition_penalty=repetition_penalty,
        convert_style=convert_style,
    )


@app.post("/api/v1/dubbing/simple")
async def simple_dubbing(
    media: UploadFile = File(...),
    target: UploadFile = File(...),
    diffusion_steps: int = Form(20),
    intelligibility_cfg_rate: float = Form(0.7),
    similarity_cfg_rate: float = Form(0.7),
) -> dict[str, Any]:
    """One-click simple dubbing: media -> audio -> Seed-VC -> mux back to video when possible.

    This endpoint intentionally does not claim dialogue/background separation yet. It is the stable
    first production step while the Roformer multi-stem pipeline is being wrapped into the service.
    """
    task_id = str(uuid.uuid4())
    job_dir = DATA_ROOT / "dubbing" / task_id
    job_dir.mkdir(parents=True, exist_ok=True)

    media_path = await _save_upload(media, job_dir, "media")
    target_path = await _save_upload(target, job_dir, "target")
    media_info = _probe(media_path)
    if not media_info["has_audio"]:
        raise HTTPException(status_code=400, detail="input media has no audio stream")

    source_wav = _extract_audio(media_path, job_dir / "source.wav")
    target_wav = _extract_audio(target_path, job_dir / "target.wav")
    vc = await _vc_convert_paths(
        source_wav,
        target_wav,
        diffusion_steps=diffusion_steps,
        intelligibility_cfg_rate=intelligibility_cfg_rate,
        similarity_cfg_rate=similarity_cfg_rate,
    )
    vc_output = Path(str(vc.get("output_path", "")))
    if not vc_output.exists():
        raise HTTPException(status_code=502, detail=f"VC output not found: {vc_output}")

    if media_info["has_video"]:
        final_output = _mux_video_with_audio(media_path, vc_output, job_dir / "final.mp4")
        output_kind = "video"
    else:
        final_output = job_dir / "final.wav"
        shutil.copy2(vc_output, final_output)
        output_kind = "audio"

    return {
        "ok": True,
        "task_id": task_id,
        "mode": "simple_dubbing",
        "output_kind": output_kind,
        "output_path": str(final_output),
        "media": media_info,
        "vc": vc,
        "note": "当前为稳定的一键换声回写链路；Roformer对白/环境声分离混回将在后续接口接入。",
    }


@app.get("/api/v1/dubbing/result/{task_id}")
async def dubbing_result(task_id: str) -> FileResponse:
    job_dir = DATA_ROOT / "dubbing" / task_id
    video = job_dir / "final.mp4"
    audio = job_dir / "final.wav"
    if video.exists():
        return FileResponse(video, media_type="video/mp4", filename=f"{task_id}.mp4")
    if audio.exists():
        return FileResponse(audio, media_type="audio/wav", filename=f"{task_id}.wav")
    raise HTTPException(status_code=404, detail="dubbing result not found")


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
