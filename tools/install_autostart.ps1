$ErrorActionPreference = 'Stop'

$RepoRoot = 'F:\NOVRIA-Voice-Server\Juweier-voice'
$VcWatchdog = Join-Path $RepoRoot 'tools\autostart\run_vc_watchdog.ps1'
$AudioWatchdog = Join-Path $RepoRoot 'tools\autostart\run_audio_watchdog.ps1'
$LogDir = 'F:\NOVRIA-Voice-Server\logs'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principalCheck = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Please run PowerShell as Administrator.'
}

foreach ($path in @($VcWatchdog, $AudioWatchdog)) {
    if (-not (Test-Path $path)) {
        throw "Missing startup script: $path"
    }
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1)

$vcAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$VcWatchdog`""
$audioAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$AudioWatchdog`""

$tasks = @(
    @{ Name = 'NOVRIA-SeedVC-18110'; Action = $vcAction; Description = 'NOVRIA Seed-VC worker watchdog on TCP 18110.' },
    @{ Name = 'Juweier-Audio-18115'; Action = $audioAction; Description = 'Juweier Audio Service watchdog on TCP 18115.' }
)

foreach ($task in $tasks) {
    $existing = Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false
    }

    Register-ScheduledTask `
        -TaskName $task.Name `
        -Action $task.Action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description $task.Description | Out-Null
}

Write-Host 'Autostart tasks installed:' -ForegroundColor Green
Get-ScheduledTask -TaskName 'NOVRIA-SeedVC-18110','Juweier-Audio-18115' |
    Select-Object TaskName, State |
    Format-Table -AutoSize

Write-Host ''
Write-Host 'Starting tasks now...'
Start-ScheduledTask -TaskName 'NOVRIA-SeedVC-18110'
Start-Sleep -Seconds 5
Start-ScheduledTask -TaskName 'Juweier-Audio-18115'

Write-Host ''
Write-Host 'Startup setup complete. Logs:' -ForegroundColor Green
Write-Host (Join-Path $LogDir 'novria-vc-autostart.log')
Write-Host (Join-Path $LogDir 'juweier-audio-autostart.log')
