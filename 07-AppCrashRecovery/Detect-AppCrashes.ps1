<#
.SYNOPSIS
    Detection: App Crash Recovery (Remediation 7)
.DESCRIPTION
    Scans the Application event log for repeated crashes (Event ID 1000 = app error,
    1002 = app hang) of the SAME monitored application within a rolling window.
    Exit 0 = healthy, Exit 1 = a monitored app crashed >= threshold times.
.NOTES
    Intune Proactive Remediation - Detection script.
    Edit $MonitoredApps to the executables critical to your org.
#>

[CmdletBinding()]
param(
    [string[]]$MonitoredApps = @('OUTLOOK.EXE','WINWORD.EXE','EXCEL.EXE','Teams.exe','msedge.exe'),
    [int]$CrashThreshold     = 3,
    [int]$WindowHours        = 24
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'AppCrash-Detect.log'
$StateFile = Join-Path $LogDir 'AppCrash-State.json'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

try {
    $since = (Get-Date).AddHours(-$WindowHours)
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'; ProviderName = 'Application Error','Application Hang'; StartTime = $since
    } -ErrorAction SilentlyContinue

    $offenders = @{}
    foreach ($e in $events) {
        # Property[0] = faulting application name for both 1000 and 1002
        $app = $e.Properties[0].Value
        if (-not $app) { continue }
        foreach ($m in $MonitoredApps) {
            if ($app -ieq $m) {
                if ($offenders.ContainsKey($m)) { $offenders[$m]++ } else { $offenders[$m] = 1 }
            }
        }
    }

    $breached = $offenders.GetEnumerator() | Where-Object { $_.Value -ge $CrashThreshold }
    Write-Log "Crash counts (${WindowHours}h): $((($offenders.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '))"

    if ($breached) {
        # Persist which apps need recovery for the remediation script
        $payload = @{}
        $breached | ForEach-Object { $payload[$_.Key] = $_.Value }
        $payload | ConvertTo-Json | Out-File -FilePath $StateFile -Encoding utf8
        $summary = ($breached | ForEach-Object { "$($_.Key) x$($_.Value)" }) -join ', '
        Write-Log "DETECTED repeated crashes: $summary"
        Write-Output "Repeated crashes: $summary"
        exit 1
    }
    if (Test-Path $StateFile) { Remove-Item $StateFile -Force -ErrorAction SilentlyContinue }
    Write-Output "No repeated app crashes"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0
}
