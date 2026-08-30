$ErrorActionPreference = 'Stop'

$Root = 'F:\NOVRIA-Voice-Server\Juweier-voice'
$Python = 'F:\NOVRIA-Voice-Server\.venv-video\Scripts\python.exe'
$Service = Join-Path $Root 'ai-workers\audio_service.py'

if (-not (Test-Path $Python)) {
    throw "Python not found: $Python"
}
if (-not (Test-Path $Service)) {
    throw "Audio service not found: $Service"
}

$env:JUWEIER_VC_WORKER = 'http://127.0.0.1:18110'
$env:JUWEIER_AUDIO_PORT = '18115'
$env:JUWEIER_AUDIO_DATA = 'E:\NOVRIA-Voice-Data\audio-service'
$env:JUWEIER_FFMPEG = 'F:\NOVRIA-Voice-Server\tools\ffmpeg\bin\ffmpeg.exe'
$env:JUWEIER_FFPROBE = 'F:\NOVRIA-Voice-Server\tools\ffmpeg\bin\ffprobe.exe'

Set-Location $Root
& $Python $Service
