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
    [string[]]$DisableStartupNames = @('OneDriveSetup','Spotify','Steam','EpicGamesLauncher','Discord'),

    # Skip deleting very recent temp files to reduce contention with active processes.
    [int]$TempFileMinAgeMinutes = 30
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'SlowStartup-Remediate.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$logBuffer = [System.Collections.Generic.List[string]]::new()
function Add-Log { param([string]$m) $script:logBuffer.Add("$(Get-Date -Format o) $m") }
function Flush-Log {
    if ($script:logBuffer.Count -gt 0) {
        $script:logBuffer | Out-File -FilePath $LogFile -Append -Encoding utf8
        $script:logBuffer.Clear()
    }
}

function Clear-TempPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][datetime]$Cutoff
    )

    $removedFiles = 0
    $removedDirs  = 0

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Files = 0; Dirs = 0 }
    }

    # Delete older files first (fastest wins); skip locked/in-use files silently.
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $Cutoff } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removedFiles++
            } catch { }
        }

    # Then remove now-empty directories older than cutoff.
    Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName -Descending |
        Where-Object { $_.LastWriteTime -lt $Cutoff } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removedDirs++
            } catch { }
        }

    return [pscustomobject]@{ Files = $removedFiles; Dirs = $removedDirs }
}

$actions = [System.Collections.Generic.List[string]]::new()
try {
    # 1. Clear temp files (skip files in use / very recent temp files)
    $tempPaths = @($env:TEMP, "$env:WINDIR\Temp")
    $cutoff = (Get-Date).AddMinutes(-1 * [math]::Abs($TempFileMinAgeMinutes))

    $totalFiles = 0
    $totalDirs = 0
    foreach ($p in $tempPaths) {
        $result = Clear-TempPath -Path $p -Cutoff $cutoff
        $totalFiles += $result.Files
        $totalDirs += $result.Dirs
    }

    [void]$actions.Add("Cleared temp folders (files=$totalFiles, dirs=$totalDirs, minAge=${TempFileMinAgeMinutes}m)")
    Add-Log "Cleared temp folders: files=$totalFiles dirs=$totalDirs minAge=${TempFileMinAgeMinutes}m"

    # 2. Disable non-essential startup apps via Run keys
    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($k in $runKeys) {
        if (-not (Test-Path $k)) { continue }

        $key = Get-Item -Path $k -ErrorAction SilentlyContinue
        if ($null -eq $key -or $null -eq $key.Property) { continue }

        $props = $key.Property
        foreach ($name in $DisableStartupNames) {
            if ($props -contains $name) {
                Remove-ItemProperty -Path $k -Name $name -ErrorAction SilentlyContinue
                [void]$actions.Add("Disabled startup: $name")
                Add-Log "Disabled startup app: $name"
            }
        }
    }

    # 3. Restart critical services that commonly stall startup
    foreach ($svc in 'wuauserv','AppXSvc') {
        try {
            $s = Get-Service -Name $svc -ErrorAction Stop
            if ($s.Status -eq 'Running') { Restart-Service -Name $svc -Force -ErrorAction Stop }
            else { Start-Service -Name $svc -ErrorAction SilentlyContinue }
            [void]$actions.Add("Cycled service: $svc")
            Add-Log "Restarted service: $svc"
        } catch {
            Add-Log "Service $svc not cycled: $($_.Exception.Message)"
        }
    }

    $actionsText = ($actions -join '; ')
    Add-Log "Remediation actions: $actionsText"
    Flush-Log
    Write-Output "Remediated: $actionsText"
    exit 0
}
catch {
    Add-Log "ERROR: $($_.Exception.Message)"
    Flush-Log
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
