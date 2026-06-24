<#
.SYNOPSIS
    Detection: High CPU / Memory Stabilization (Remediation 4)
.DESCRIPTION
    Samples CPU and memory pressure over a short window and flags sustained load.
      - CPU > threshold sustained across samples
      - Committed memory pressure (% in use) high
    Exit 0 = healthy, Exit 1 = sustained resource pressure.
.NOTES
    Intune Proactive Remediation - Detection script.
#>

[CmdletBinding()]
param(
    [int]$CpuThreshold    = 85,   # percent
    [int]$MemThreshold    = 90,   # percent committed in use
    [int]$Samples         = 5,
    [int]$IntervalSeconds = 3
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'HighResource-Detect.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

try {
    # CPU: average across samples
    $cpuReadings = for ($i = 0; $i -lt $Samples; $i++) {
        (Get-CimInstance Win32_PercentProcessorTime -ErrorAction SilentlyContinue) | Out-Null
        $c = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction SilentlyContinue |
              Where-Object Name -eq '_Total').PercentProcessorTime
        if ($null -eq $c) {
            $c = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        }
        if ($i -lt ($Samples - 1)) { Start-Sleep -Seconds $IntervalSeconds }
        [int]$c
    }
    $cpuAvg = if ($cpuReadings) { [math]::Round(($cpuReadings | Measure-Object -Average).Average,0) } else { 0 }

    # Memory: percent committed in use
    $os = Get-CimInstance Win32_OperatingSystem
    $memUsedPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 0)

    Write-Log "CPU avg ${cpuAvg}% (threshold ${CpuThreshold}%), Mem ${memUsedPct}% (threshold ${MemThreshold}%)"

    $reasons = @()
    if ($cpuAvg -ge $CpuThreshold) { $reasons += "CPU ${cpuAvg}%" }
    if ($memUsedPct -ge $MemThreshold) { $reasons += "Mem ${memUsedPct}%" }

    if ($reasons.Count -gt 0) {
        # Capture top offenders for the log / remediation context
        $top = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 Name, Id,
               @{n='CPU';e={[math]::Round($_.CPU,1)}}, @{n='WS_MB';e={[math]::Round($_.WS/1MB,0)}}
        Write-Log "Top processes: $($top | ForEach-Object { "$($_.Name)($($_.Id)):CPU$($_.CPU)/$($_.WS_MB)MB" } -join ', ')"
        Write-Output "Resource pressure: $($reasons -join '; ')"
        exit 1
    }
    Write-Output "Resource usage OK (CPU ${cpuAvg}%, Mem ${memUsedPct}%)"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0
}
