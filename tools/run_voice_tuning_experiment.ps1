$ErrorActionPreference = 'Stop'

$Python = 'F:\NOVRIA-Voice-Server\.venv-tse\Scripts\python.exe'
$Script = 'F:\NOVRIA-Voice-Server\Juweier-voice\ai-workers\voice_tuning_experiment.py'
$Exp = 'D:\test\target-speaker-exp'
$Out = Join-Path $Exp 'voice-tuning'

if (-not (Test-Path $Python)) { throw "Python not found: $Python" }
if (-not (Test-Path $Script)) { throw "Script not found: $Script" }
if (-not (Test-Path "$Exp\actor_extracted_44100.wav")) { throw "Run target speaker experiment first" }
if (-not (Test-Path 'D:\test\target.mp4')) { throw "Target not found: D:\test\target.mp4" }

New-Item -ItemType Directory -Force $Out | Out-Null

& $Python $Script `
  --source "$Exp\actor_extracted_44100.wav" `
  --target 'D:\test\target.mp4' `
  --output-dir $Out
