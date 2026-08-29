$ErrorActionPreference = 'Stop'

$Root = 'F:\NOVRIA-Voice-Server'
$Repo = Join-Path $Root 'LTX-Video'
$Venv = Join-Path $Root '.venv-video'
$Data = 'E:\NOVRIA-Voice-Data\video'

Write-Host '===== 橘味儿配音 本地视频模型安装 ====='
Write-Host '模型：LTX-Video 2B Distilled 0.9.8'
Write-Host '目标显卡：RTX 3060 12GB'

New-Item -ItemType Directory -Force $Root,$Data | Out-Null

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
& $Py -m pip install -e '.[inference-script]'

Write-Host ''
Write-Host '===== CUDA 检查 ====='
& $Py -c "import torch; print('Torch:',torch.__version__); print('CUDA:',torch.cuda.is_available()); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else None)"

Write-Host ''
Write-Host '安装完成。'
Write-Host "LTX-Video: $Repo"
Write-Host "Python: $Py"
Write-Host "输出目录: $Data"
Write-Host '下一步启动 video_service.py 后从橘味儿配音 App 调用。'
