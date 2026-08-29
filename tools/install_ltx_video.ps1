$ErrorActionPreference = 'Stop'

$Root = 'F:\NOVRIA-Voice-Server'
$Repo = Join-Path $Root 'LTX-Video'
$Venv = Join-Path $Root '.venv-video'
$Models = Join-Path $Root 'video-models\ltx'
$Data = 'E:\NOVRIA-Voice-Data\video'

Write-Host '===== Juweier Local Video Model Installer ====='
Write-Host 'Model: LTX-Video 2B Distilled 0.9.8'
Write-Host 'Target GPU: NVIDIA RTX 3060 12GB'

New-Item -ItemType Directory -Force $Root,$Models,$Data | Out-Null

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git.exe was not found in PATH.'
}

if (-not (Test-Path $Repo)) {
    git clone https://github.com/Lightricks/LTX-Video.git $Repo
} else {
    Set-Location $Repo
    git pull
}

$BasePython = 'C:\Python310\python.exe'
if (-not (Test-Path $BasePython)) {
    throw "Python 3.10 was not found at $BasePython"
}

if (-not (Test-Path $Venv)) {
    & $BasePython -m venv $Venv
}

$Py = Join-Path $Venv 'Scripts\python.exe'
& $Py -m pip install --upgrade pip wheel setuptools

Set-Location $Repo
& $Py -m pip install -e '.[inference]'
& $Py -m pip install fastapi uvicorn python-multipart huggingface_hub

Write-Host '===== Downloading local model files ====='
@"
from huggingface_hub import hf_hub_download
from pathlib import Path
root = Path(r'$Models')
root.mkdir(parents=True, exist_ok=True)
for name in [
    'ltxv-2b-0.9.8-distilled.safetensors',
    'ltxv-spatial-upscaler-0.9.8.safetensors',
]:
    print('Downloading', name)
    hf_hub_download(
        repo_id='Lightricks/LTX-Video',
        filename=name,
        local_dir=str(root),
    )
print('Models:', root)
"@ | & $Py -

Write-Host '===== CUDA Check ====='
& $Py -c "import torch; print('Torch:', torch.__version__); print('CUDA:', torch.cuda.is_available()); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else None); print('VRAM GB:', round(torch.cuda.get_device_properties(0).total_memory/1024**3, 2) if torch.cuda.is_available() else 0)"

Write-Host ''
Write-Host 'Installation completed.'
Write-Host "LTX-Video repo: $Repo"
Write-Host "Model directory: $Models"
Write-Host "Python: $Py"
Write-Host "Output directory: $Data"
