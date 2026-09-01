$ErrorActionPreference = 'Stop'

$Python = 'F:\NOVRIA-Voice-Server\.venv-tse\Scripts\python.exe'
$Script = 'F:\NOVRIA-Voice-Server\Juweier-voice\ai-workers\residual_reconstruction_experiment.py'
$Exp = 'D:\test\target-speaker-exp'

if (-not (Test-Path $Python)) { throw "Python not found: $Python" }
if (-not (Test-Path $Script)) { throw "Script not found: $Script" }
if (-not (Test-Path "$Exp\actor_extracted_44100.wav")) { throw "Run target speaker experiment first" }
if (-not (Test-Path "$Exp\actor_new.wav")) { throw "Run target speaker experiment first" }

& $Python $Script `
  --media 'D:\test\source.mp4' `
  --actor-original "$Exp\actor_extracted_44100.wav" `
  --actor-new "$Exp\actor_new.wav" `
  --start 27.5 `
  --end 31.5 `
  --output-dir $Exp `
  --suppression 0.82 `
  --new-voice-gain 0.92
