<#
.SYNOPSIS
    Detection: Disk Space Auto-Cleanup (Remediation 2)
.DESCRIPTION
    Flags the device when free space on the system drive falls below threshold.
    Exit 0 = healthy, Exit 1 = low disk space (trigger remediation).
.NOTES
    Intune Proactive Remediation - Detection script.
#>

[CmdletBinding()]
param(
    [int]$MinFreePercent = 15   # remediate below 15% free
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'DiskSpace-Detect.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

try {
    $sysDrive = $env:SystemDrive.TrimEnd(':')
    $vol = Get-Volume -DriveLetter $sysDrive -ErrorAction Stop
    $total = $vol.Size
    $free  = $vol.SizeRemaining
    $pct   = if ($total -gt 0) { [math]::Round(($free / $total) * 100, 1) } else { 100 }

    Write-Log "Drive ${sysDrive}: free ${pct}% ($([math]::Round($free/1GB,1))GB of $([math]::Round($total/1GB,1))GB), threshold ${MinFreePercent}%"

    if ($pct -lt $MinFreePercent) {
        Write-Output "Low disk space: ${pct}% free"
        exit 1
    }
    Write-Output "Disk space OK: ${pct}% free"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0
}
