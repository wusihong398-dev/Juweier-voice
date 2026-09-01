$ErrorActionPreference = 'Continue'

$Root = 'F:\NOVRIA-Voice-Server'
$ServiceScript = Join-Path $Root 'Start-NOVRIA-Voice.ps1'
$LogDir = Join-Path $Root 'logs'
$LogFile = Join-Path $LogDir 'novria-vc-autostart.log'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log([string]$Message) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$stamp] $Message" -Encoding UTF8
}

Write-Log 'VC watchdog started.'
Start-Sleep -Seconds 20

while ($true) {
    try {
        $health = $null
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:18110/health' -TimeoutSec 3
        } catch {}

        if ($health -and $health.ok) {
            Start-Sleep -Seconds 15
            continue
        }

        if (-not (Test-Path $ServiceScript)) {
            Write-Log "Service script not found: $ServiceScript"
            Start-Sleep -Seconds 30
            continue
        }

        Write-Log 'Starting NOVRIA Seed-VC worker on 18110.'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ServiceScript *>> $LogFile
        Write-Log 'Seed-VC process exited; retrying in 10 seconds.'
    } catch {
        Write-Log ("VC watchdog error: " + $_.Exception.Message)
    }

    Start-Sleep -Seconds 10
}
