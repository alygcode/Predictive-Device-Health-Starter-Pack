<#
.SYNOPSIS
    Detection: Slow Startup Fix (Remediation 1)
.DESCRIPTION
    Flags the device for remediation when boot/login performance is degraded.
    Signals used:
      - Last boot duration from Diagnostics-Performance event log (Event ID 100)
      - Excess temp-file accumulation
      - Excess enabled startup apps from Run keys
    Exit 0 = healthy (no action), Exit 1 = issue detected (trigger remediation).
.NOTES
    Intune remediation detection script. Run in 64-bit PowerShell.
    Threshold defaults in this script are examples and should be tuned for your
    hardware profile, Windows build mix, and operational baseline.
#>

[CmdletBinding()]
param(
    [int]$BootThresholdMs   = 60000,   # Example threshold: 60s boot considered slow
    [int]$MaxStartupApps    = 12,      # Example threshold: high Run-key startup count
    [long]$TempBytesThreshold = 1GB    # Example threshold: temp clutter threshold
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'SlowStartup-Detect.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

try {
    $reasons = @()

    # 1. Boot duration from the Diagnostics-Performance operational log.
    # Validate the event schema and property indexing on the Windows versions
    # in your environment before relying on this signal broadly.
    try {
        $evt = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100
        } -MaxEvents 1 -ErrorAction Stop
        if ($evt -and $evt.Properties.Count -gt 8) {
            $bootMs = [int]($evt.Properties[8].Value)
            Write-Log "Last boot duration: ${bootMs}ms (threshold ${BootThresholdMs}ms)"
            if ($bootMs -gt $BootThresholdMs) { $reasons += "BootTime ${bootMs}ms" }
        } else {
            Write-Log 'Boot event did not include expected BootTime property index.'
        }
    } catch { Write-Log "Boot event unavailable: $($_.Exception.Message)" }

    # 2. Temp clutter
    $tempPaths = @($env:TEMP, "$env:WINDIR\Temp")
    $tempBytes = 0
    foreach ($p in $tempPaths) {
        if (Test-Path $p) {
            $tempBytes += (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        }
    }
    Write-Log "Temp bytes: $tempBytes (threshold $TempBytesThreshold)"
    if ($tempBytes -gt $TempBytesThreshold) { $reasons += "Temp $([math]::Round($tempBytes/1GB,2))GB" }

    # 3. Enabled startup app count from Run keys
    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )
    $startupCount = 0
    foreach ($k in $runKeys) {
        if (Test-Path $k) {
            $startupCount += (Get-Item $k).Property.Count
        }
    }
    Write-Log "Enabled Run-key startup apps: $startupCount (threshold $MaxStartupApps)"
    if ($startupCount -gt $MaxStartupApps) { $reasons += "$startupCount startup apps" }

    if ($reasons.Count -gt 0) {
        Write-Log "DETECTED issue(s): $($reasons -join '; ')"
        Write-Output "Slow startup detected: $($reasons -join '; ')"
        exit 1
    }

    Write-Log 'Healthy - no slow-startup signals.'
    Write-Output 'Startup health OK'
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0  # fail-safe: do not trigger remediation on detection error
}
