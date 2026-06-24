<#
.SYNOPSIS
    Detection: Policy Drift Auto-Correction (Remediation 6)
.DESCRIPTION
    Flags the device when it shows signs of configuration drift / non-compliance:
      - MDM sync stale (last sync older than threshold)
      - Core security posture off (BitLocker off on system drive, Defender RTP off, firewall profile off)
    Exit 0 = compliant, Exit 1 = drift detected.
.NOTES
    Intune Proactive Remediation - Detection script.
#>

[CmdletBinding()]
param(
    [int]$MaxSyncAgeHours = 24
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'PolicyDrift-Detect.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

try {
    $reasons = @()

    # 1. MDM sync staleness via EnterpriseMgmt scheduled task history
    try {
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskName -match 'Schedule #3' -or $_.TaskName -match 'OMADMClient' } |
                Select-Object -First 1
        if ($task) {
            $info = $task | Get-ScheduledTaskInfo
            if ($info.LastRunTime) {
                $age = (New-TimeSpan -Start $info.LastRunTime -End (Get-Date)).TotalHours
                Write-Log "Last MDM sync: $($info.LastRunTime) ($([math]::Round($age,1))h ago)"
                if ($age -gt $MaxSyncAgeHours) { $reasons += "MDM sync $([math]::Round($age,1))h stale" }
            }
        } else { Write-Log 'MDM sync task not found' }
    } catch { Write-Log "MDM task check: $($_.Exception.Message)" }

    # 2. BitLocker on the system drive
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        Write-Log "BitLocker $($env:SystemDrive): $($bl.ProtectionStatus)"
        if ($bl.ProtectionStatus -ne 'On') { $reasons += 'BitLocker off (system drive)' }
    } catch { Write-Log "BitLocker check: $($_.Exception.Message)" }

    # 3. Defender real-time protection
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if (-not $mp.RealTimeProtectionEnabled) { $reasons += 'Defender RTP disabled' }
        Write-Log "Defender RTP: $($mp.RealTimeProtectionEnabled)"
    } catch { Write-Log "Defender check: $($_.Exception.Message)" }

    # 4. Firewall profiles
    try {
        $off = Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled }
        if ($off) { $reasons += "Firewall off: $(($off.Name) -join ',')" }
    } catch { Write-Log "Firewall check: $($_.Exception.Message)" }

    if ($reasons.Count -gt 0) {
        Write-Log "DRIFT: $($reasons -join '; ')"
        Write-Output "Policy drift: $($reasons -join '; ')"
        exit 1
    }
    Write-Output "Compliant - no drift"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0
}
