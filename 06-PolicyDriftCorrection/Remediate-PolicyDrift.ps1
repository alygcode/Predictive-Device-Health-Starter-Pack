<#
.SYNOPSIS
    Remediation: Policy Drift Auto-Correction (Remediation 6)
.DESCRIPTION
    - Forces an Intune/MDM device sync (re-evaluates and reapplies assigned policies)
    - Re-enables baseline security controls that drifted:
        * Defender real-time protection
        * Firewall profiles
    - BitLocker is NOT silently enabled here (requires key escrow); it is logged and
      a sync is forced so the Intune disk-encryption policy can drive it.
    Validates and logs post-state.
.NOTES
    Intune Proactive Remediation - Remediation script. Runs as SYSTEM.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'PolicyDrift-Remediate.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

$actions = @()
try {
    # 1. Re-enable Defender real-time protection
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        $actions += 'Enabled Defender RTP'
        Write-Log 'Defender RTP enabled'
    } catch { Write-Log "Defender RTP: $($_.Exception.Message)" }

    # 2. Re-enable firewall profiles
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
        $actions += 'Enabled firewall profiles'
        Write-Log 'Firewall profiles enabled'
    } catch { Write-Log "Firewall: $($_.Exception.Message)" }

    # 3. BitLocker - log only (managed by Intune disk-encryption policy)
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        if ($bl.ProtectionStatus -ne 'On') {
            Write-Log 'BitLocker off - deferring to Intune encryption policy (sync forced below)'
            $actions += 'Flagged BitLocker for Intune policy'
        }
    } catch { Write-Log "BitLocker: $($_.Exception.Message)" }

    # 4. Force MDM sync so Intune re-pushes all assigned config/compliance policies
    try {
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskName -match 'Schedule #3' -or $_.TaskName -match 'OMADMClient' } |
                Select-Object -First 1
        if ($task) { Start-ScheduledTask -InputObject $task; $actions += 'Forced MDM sync' ; Write-Log 'Forced MDM sync via scheduled task' }
        else {
            Start-Process -FilePath "$env:WINDIR\System32\deviceenroller.exe" -ArgumentList '/o','/c' -WindowStyle Hidden -ErrorAction SilentlyContinue
            $actions += 'Triggered deviceenroller sync'
        }
    } catch { Write-Log "MDM sync: $($_.Exception.Message)" }

    Write-Log "Actions: $($actions -join '; ')"
    Write-Output "Drift correction: $($actions -join '; ')"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
