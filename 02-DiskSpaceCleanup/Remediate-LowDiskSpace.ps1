<#
.SYNOPSIS
    Remediation: Disk Space Auto-Cleanup (Remediation 2)
.DESCRIPTION
    - Cleans Windows + user temp folders
    - Purges Windows Update download cache (SoftwareDistribution\Download)
    - Empties the Recycle Bin for all users
    - Runs CleanMgr automated profile (low-risk handlers)
    Validates free space afterward and logs the delta.
.NOTES
    Intune Proactive Remediation - Remediation script. Runs as SYSTEM.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'DiskSpace-Remediate.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }
function Get-FreeBytes {
    (Get-Volume -DriveLetter $env:SystemDrive.TrimEnd(':')).SizeRemaining
}

$actions = @()
try {
    $before = Get-FreeBytes
    Write-Log "Free before: $([math]::Round($before/1GB,2))GB"

    # 1. Temp folders (Windows + all user temps)
    $tempTargets = @("$env:WINDIR\Temp")
    Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $t = Join-Path $_.FullName 'AppData\Local\Temp'
        if (Test-Path $t) { $tempTargets += $t }
    }
    foreach ($t in $tempTargets) {
        Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    $actions += 'Cleared temp folders'

    # 2. Windows Update download cache (stop service, purge, restart)
    try {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        $wuCache = "$env:WINDIR\SoftwareDistribution\Download"
        if (Test-Path $wuCache) {
            Get-ChildItem $wuCache -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        Start-Service wuauserv -ErrorAction SilentlyContinue
        $actions += 'Purged Windows Update cache'
    } catch { Write-Log "WU cache purge issue: $($_.Exception.Message)" }

    # 3. Recycle Bin
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        $actions += 'Emptied Recycle Bin'
    } catch { Write-Log "Recycle Bin: $($_.Exception.Message)" }

    # 4. CleanMgr with a preconfigured sageset (low-risk handlers)
    try {
        $sageId = 64
        $vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
        $handlers = 'Temporary Files','Recycle Bin','Update Cleanup','Delivery Optimization Files','Thumbnail Cache'
        foreach ($h in $handlers) {
            $hp = Join-Path $vc $h
            if (Test-Path $hp) {
                New-ItemProperty -Path $hp -Name "StateFlags00$sageId" -Value 2 -PropertyType DWord -Force | Out-Null
            }
        }
        Start-Process -FilePath cleanmgr.exe -ArgumentList "/sagerun:$sageId" -Wait -WindowStyle Hidden
        $actions += 'Ran CleanMgr'
    } catch { Write-Log "CleanMgr: $($_.Exception.Message)" }

    $after = Get-FreeBytes
    $reclaimed = [math]::Round(($after - $before)/1GB, 2)
    Write-Log "Free after: $([math]::Round($after/1GB,2))GB | Reclaimed ${reclaimed}GB | Actions: $($actions -join '; ')"
    Write-Output "Reclaimed ${reclaimed}GB. Actions: $($actions -join '; ')"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
