$ErrorActionPreference = 'Stop'

$Root = 'F:\NOVRIA-Voice-Server'
$Repo = Join-Path $Root 'LTX-Video'
$Venv = Join-Path $Root '.venv-video'
$Models = Join-Path $Root 'video-models\ltx'
$Data = 'E:\NOVRIA-Voice-Data\video'

Write-Host '===== 橘味儿配音 本地视频模型安装 ====='
Write-Host '模型：LTX-Video 2B Distilled 0.9.8'
Write-Host '用途：RTX 3060 12GB 本地文生视频 / 图生视频'

New-Item -ItemType Directory -Force $Root,$Models,$Data | Out-Null

if (-not (Test-Path $Repo)) {
    git clone https://github.com/Lightricks/LTX-Video.git $Repo
} else {
    Set-Location $Repo
    git pull
}

if (-not (Test-Path $Venv)) {
    C:\Python310\python.exe -m venv $Venv
}

$Py = Join-Path $Venv 'Scripts\python.exe'
& $Py -m pip install --upgrade pip wheel setuptools
Set-Location $Repo
& $Py -m pip install -e '.[inference]'
& $Py -m pip install fastapi uvicorn python-multipart huggingface_hub

Write-Host '===== 下载本地模型 ====='
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
        local_dir_use_symlinks=False,
    )
print('Models:', root)
"@ | & $Py -

Write-Host '===== CUDA 检查 ====='
& $Py -c "import torch; print('Torch:',torch.__version__); print('CUDA:',torch.cuda.is_available()); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else None); print('VRAM GB:', round(torch.cuda.get_device_properties(0).total_memory/1024**3,2) if torch.cuda.is_available() else 0)"

Write-Host ''
Write-Host '安装完成。'
Write-Host "LTX-Video: $Repo"
Write-Host "模型目录: $Models"
Write-Host "Python: $Py"
Write-Host "输出目录: $Data"
