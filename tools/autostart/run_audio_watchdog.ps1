$ErrorActionPreference = 'Continue'

$Root = 'F:\NOVRIA-Voice-Server\Juweier-voice'
$ServiceScript = Join-Path $Root 'tools\start_audio_service.ps1'
$LogDir = 'F:\NOVRIA-Voice-Server\logs'
$LogFile = Join-Path $LogDir 'juweier-audio-autostart.log'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log([string]$Message) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$stamp] $Message" -Encoding UTF8
}

Write-Log 'Audio watchdog started.'
Start-Sleep -Seconds 35

while ($true) {
    try {
        $health = $null
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:18115/health' -TimeoutSec 3
        } catch {}

        if ($health -and $health.ok) {
            Start-Sleep -Seconds 15
            continue
        }

        $vcReady = $false
        try {
            $vc = Invoke-RestMethod -Uri 'http://127.0.0.1:18110/health' -TimeoutSec 3
            $vcReady = [bool]$vc.ok
        } catch {}

        if (-not $vcReady) {
            Write-Log '18110 is not ready yet; waiting before starting 18115.'
            Start-Sleep -Seconds 10
            continue
        }

        if (-not (Test-Path $ServiceScript)) {
            Write-Log "Service script not found: $ServiceScript"
            Start-Sleep -Seconds 30
            continue
        }

        Write-Log 'Starting Juweier Audio Service on 18115.'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ServiceScript *>> $LogFile
        Write-Log 'Audio service process exited; retrying in 10 seconds.'
    } catch {
        Write-Log ("Audio watchdog error: " + $_.Exception.Message)
    }

    Start-Sleep -Seconds 10
}
