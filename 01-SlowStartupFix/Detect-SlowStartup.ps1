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

$logBuffer = [System.Collections.Generic.List[string]]::new()
function Add-Log { param([string]$m) $script:logBuffer.Add("$(Get-Date -Format o) $m") }
function Flush-Log {
    if ($script:logBuffer.Count -gt 0) {
        $script:logBuffer | Out-File -FilePath $LogFile -Append -Encoding utf8
        $script:logBuffer.Clear()
    }
}

function Get-TempBytesUpToThreshold {
    param(
        [Parameter(Mandatory=$true)][string[]]$Paths,
        [Parameter(Mandatory=$true)][long]$Threshold
    )

    [long]$sum = 0
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }

        Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($null -ne $_.Length) {
                    $sum += [long]$_.Length
                    if ($sum -gt $Threshold) {
                        Add-Log "Temp threshold exceeded while scanning $p"
                        return $sum
                    }
                }
            }

        if ($sum -gt $Threshold) { return $sum }
    }

    return $sum
}

try {
    $reasons = [System.Collections.Generic.List[string]]::new()

    # 1. Boot duration from the Diagnostics-Performance operational log.
    # Validate the event schema and property indexing on the Windows versions
    # in your environment before relying on this signal broadly.
    try {
        $evt = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100
        } -MaxEvents 1 -ErrorAction Stop

        if ($evt -and $evt.Properties.Count -gt 8) {
            $bootMs = [int]($evt.Properties[8].Value)
            Add-Log "Last boot duration: ${bootMs}ms (threshold ${BootThresholdMs}ms)"
            if ($bootMs -gt $BootThresholdMs) { [void]$reasons.Add("BootTime ${bootMs}ms") }
        }
        else {
            Add-Log 'Boot event did not include expected BootTime property index.'
        }
    }
    catch {
        Add-Log "Boot event unavailable: $($_.Exception.Message)"
    }

    # 2. Temp clutter (short-circuit once threshold exceeded)
    $tempPaths = @($env:TEMP, "$env:WINDIR\Temp")
    [long]$tempBytes = Get-TempBytesUpToThreshold -Paths $tempPaths -Threshold $TempBytesThreshold
    Add-Log "Temp bytes: $tempBytes (threshold $TempBytesThreshold)"
    if ($tempBytes -gt $TempBytesThreshold) {
        [void]$reasons.Add("Temp $([math]::Round($tempBytes / 1GB, 2))GB")
    }

    # 3. Enabled startup app count from Run keys
    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )

    $startupCount = 0
    foreach ($k in $runKeys) {
        if (Test-Path $k) {
            $key = Get-Item -Path $k -ErrorAction SilentlyContinue
            if ($null -ne $key -and $null -ne $key.Property) {
                $startupCount += $key.Property.Count
            }
        }
    }

    Add-Log "Enabled Run-key startup apps: $startupCount (threshold $MaxStartupApps)"
    if ($startupCount -gt $MaxStartupApps) { [void]$reasons.Add("$startupCount startup apps") }

    if ($reasons.Count -gt 0) {
        $reasonText = ($reasons -join '; ')
        Add-Log "DETECTED issue(s): $reasonText"
        Flush-Log
        Write-Output "Slow startup detected: $reasonText"
        exit 1
    }

    Add-Log 'Healthy - no slow-startup signals.'
    Flush-Log
    Write-Output 'Startup health OK'
    exit 0
}
catch {
    Add-Log "ERROR: $($_.Exception.Message)"
    Flush-Log
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0  # fail-safe: do not trigger remediation on detection error
}
