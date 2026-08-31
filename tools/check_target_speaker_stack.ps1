$ErrorActionPreference = 'Stop'

$Python = 'F:\NOVRIA-Voice-Server\.venv-vc\Scripts\python.exe'

if (-not (Test-Path $Python)) {
    throw "Python not found: $Python"
}

Write-Host '===== Python / Torch / CUDA ====='
& $Python -c @'
import torch
print('Torch:', torch.__version__)
print('CUDA:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('GPU:', torch.cuda.get_device_name(0))
'@

Write-Host "`n===== ModelScope version and relevant Tasks ====="
& $Python -c @'
import modelscope
print('ModelScope:', modelscope.__version__)
from modelscope.utils.constant import Tasks
for name in sorted(dir(Tasks)):
    low = name.lower()
    if any(k in low for k in ['speaker', 'diar', 'speech_separation', 'voice']):
        try:
            print(name, '=', getattr(Tasks, name))
        except Exception:
            pass
'@

Write-Host "`n===== Installed packages relevant to target-speaker processing ====="
& $Python -m pip list |
    Select-String 'modelscope|funasr|speechbrain|pyannote|wesep|mossformer|campplus|eres2net|speaker|onnx|torch|torchaudio'

Write-Host "`n===== Search cached/local speaker-related model directories ====="
$Roots = @(
    'C:\Users\Administrator\.cache',
    'C:\Users\Administrator\.cache\modelscope',
    'F:\NOVRIA-Voice-Server\models',
    'F:\NOVRIA-Voice-Server\seed-vc'
) | Where-Object { Test-Path $_ }

foreach ($Root in $Roots) {
    Write-Host "--- $Root"
    Get-ChildItem $Root -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match '(?i)diar|speaker|campplus|eres2net|mossformer|speech.?separ|wesep|voiceprint|sv'
        } |
        Select-Object -First 100 FullName
}

Write-Host "`n===== Import probes ====="
& $Python -c @'
mods = [
    'modelscope',
    'modelscope.pipelines',
    'modelscope.models.audio',
    'torchaudio',
]
for m in mods:
    try:
        __import__(m)
        print(m, 'OK')
    except Exception as e:
        print(m, 'FAIL', repr(e))
'@

Write-Host "`nDONE"
