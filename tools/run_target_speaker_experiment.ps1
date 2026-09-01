$ErrorActionPreference = 'Stop'

$Python = 'F:\NOVRIA-Voice-Server\.venv-tse\Scripts\python.exe'
$Script = 'F:\NOVRIA-Voice-Server\Juweier-voice\ai-workers\target_speaker_experiment.py'
$Output = 'D:\test\target-speaker-exp'

if (-not (Test-Path $Python)) { throw "Python not found: $Python" }
if (-not (Test-Path $Script)) { throw "Script not found: $Script" }

New-Item -ItemType Directory -Force $Output | Out-Null

& $Python $Script `
  --media 'D:\test\source.mp4' `
  --actor-ref 'D:\test\source_actor_A_ref.wav' `
  --target 'D:\test\target.mp4' `
  --start 27.5 `
  --end 31.5 `
  --output-dir $Output
