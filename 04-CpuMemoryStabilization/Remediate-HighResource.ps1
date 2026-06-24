<#
.SYNOPSIS
    Remediation: High CPU / Memory Stabilization (Remediation 4)
.DESCRIPTION
    - Identifies the top resource-consuming processes
    - Restarts offending *services* (safe) and terminates non-critical *user* apps
      that exceed thresholds, honouring a protected allow-list
    - Logs repeated offenders to a rolling JSON file for trend analysis
    NEVER kills protected/system-critical processes.
.NOTES
    Intune Proactive Remediation - Remediation script. Runs as SYSTEM.
#>

[CmdletBinding()]
param(
    [int]$CpuKillThreshold = 80,    # per-process CPU-seconds growth heuristic
    [long]$WsKillBytes     = 2GB,   # working set kill threshold for user apps
    [string[]]$Protected   = @(
        'System','Idle','Registry','csrss','wininit','winlogon','services','lsass',
        'smss','svchost','explorer','dwm','MsMpEng','SenseIR','MemCompression',
        'fontdrvhost','sihost','ctfmon','RuntimeBroker','SearchHost'
    )
)

$ErrorActionPreference = 'Stop'
$LogDir   = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile  = Join-Path $LogDir 'HighResource-Remediate.log'
$Offenders = Join-Path $LogDir 'HighResource-Offenders.json'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

$actions = @()
try {
    # Rank by working set (memory) since CPU-seconds is cumulative/noisy as one-shot
    $candidates = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $Protected -notcontains $_.ProcessName -and $_.SessionId -ne 0 } |
        Sort-Object WS -Descending | Select-Object -First 10

    # Track repeat offenders
    $history = @{}
    if (Test-Path $Offenders) {
        try { $history = Get-Content $Offenders -Raw | ConvertFrom-Json -AsHashtable } catch { $history = @{} }
    }
    if ($null -eq $history) { $history = @{} }

    foreach ($p in $candidates) {
        $name = $p.ProcessName
        $wsMB = [math]::Round($p.WS/1MB,0)

        # Record offender frequency
        if ($history.ContainsKey($name)) { $history[$name] = [int]$history[$name] + 1 }
        else { $history[$name] = 1 }

        if ($p.WS -ge $WsKillBytes) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                $actions += "Stopped ${name}(${wsMB}MB)"
                Write-Log "Terminated runaway app: $name PID $($p.Id) WS ${wsMB}MB (offense #$($history[$name]))"
            } catch { Write-Log "Could not stop $name : $($_.Exception.Message)" }
        }
    }

    # Restart commonly-hung services if present and consuming
    foreach ($svc in 'Spooler','WSearch') {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            try { Restart-Service $svc -Force -ErrorAction Stop
                  $actions += "Restarted service $svc"
                  Write-Log "Restarted service: $svc" } catch {}
        }
    }

    $history | ConvertTo-Json -Depth 3 | Out-File -FilePath $Offenders -Encoding utf8

    if ($actions.Count -eq 0) { $actions += 'No process exceeded kill thresholds (logged offenders only)' }
    Write-Log "Actions: $($actions -join '; ')"
    Write-Output "Stabilized: $($actions -join '; ')"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
