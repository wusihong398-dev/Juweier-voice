$ErrorActionPreference = 'Stop'

$Python = 'F:\NOVRIA-Voice-Server\.venv-tse\Scripts\python.exe'
$Script = 'F:\NOVRIA-Voice-Server\Juweier-voice\ai-workers\residual_reconstruction_experiment.py'
$Base = 'D:\test\target-speaker-exp'

if (-not (Test-Path $Python)) { throw "Python not found: $Python" }
if (-not (Test-Path $Script)) { throw "Script not found: $Script" }
if (-not (Test-Path "$Base\actor_extracted_44100.wav")) { throw "Run target speaker experiment first" }
if (-not (Test-Path "$Base\actor_new.wav")) { throw "Run target speaker experiment first" }

$Values = @(0.88, 0.92, 0.96)

foreach ($Suppression in $Values) {
    $Name = ('residual-s{0:0.00}' -f $Suppression).Replace('.', '_')
    $Out = Join-Path $Base $Name
    New-Item -ItemType Directory -Force $Out | Out-Null

    Write-Host "===== suppression=$Suppression ====="

    & $Python $Script `
      --media 'D:\test\source.mp4' `
      --actor-original "$Base\actor_extracted_44100.wav" `
      --actor-new "$Base\actor_new.wav" `
      --start 27.5 `
      --end 31.5 `
      --output-dir $Out `
      --suppression $Suppression `
      --new-voice-gain 0.92
}

Write-Host ""
Write-Host "===== Residual sweep complete ====="
Get-ChildItem $Base -Directory -Filter 'residual-s*' | Select-Object FullName
