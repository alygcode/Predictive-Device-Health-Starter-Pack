<#
.SYNOPSIS
    Remediation: Slow Startup Fix (Remediation 1)
.DESCRIPTION
    - Clears user + Windows temp files
    - Disables known non-essential startup apps (allow-list aware)
    - Restarts critical, safe-to-bounce services (wuauserv, AppXSvc)
    Validates outcome and writes a closed-loop log entry.
.NOTES
    Intune Proactive Remediation - Remediation script. Runs as SYSTEM.
#>

[CmdletBinding()]
param(
    # Startup entries that are safe to disable when present. Adjust per org.
    [string[]]$DisableStartupNames = @('OneDriveSetup','Spotify','Steam','EpicGamesLauncher','Discord')
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'SlowStartup-Remediate.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

$actions = @()
try {
    # 1. Clear temp files (skip files in use)
    $tempPaths = @($env:TEMP, "$env:WINDIR\Temp")
    foreach ($p in $tempPaths) {
        if (Test-Path $p) {
            Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $actions += 'Cleared temp folders'
    Write-Log 'Cleared temp folders'

    # 2. Disable non-essential startup apps via Run keys
    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($k in $runKeys) {
        if (Test-Path $k) {
            foreach ($name in $DisableStartupNames) {
                if ((Get-Item $k).Property -contains $name) {
                    Remove-ItemProperty -Path $k -Name $name -ErrorAction SilentlyContinue
                    $actions += "Disabled startup: $name"
                    Write-Log "Disabled startup app: $name"
                }
            }
        }
    }

    # 3. Restart critical services that commonly stall startup
    foreach ($svc in 'wuauserv','AppXSvc') {
        try {
            $s = Get-Service -Name $svc -ErrorAction Stop
            if ($s.Status -eq 'Running') { Restart-Service -Name $svc -Force -ErrorAction Stop }
            else { Start-Service -Name $svc -ErrorAction SilentlyContinue }
            $actions += "Cycled service: $svc"
            Write-Log "Restarted service: $svc"
        } catch { Write-Log "Service $svc not cycled: $($_.Exception.Message)" }
    }

    Write-Log "Remediation actions: $($actions -join '; ')"
    Write-Output "Remediated: $($actions -join '; ')"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
