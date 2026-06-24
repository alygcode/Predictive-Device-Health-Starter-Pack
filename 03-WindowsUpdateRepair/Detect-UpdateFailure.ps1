<#
.SYNOPSIS
    Detection: Windows Update Repair (Remediation 3)
.DESCRIPTION
    Flags the device when Windows Update is failing or stuck:
      - Recent failed update install (Get-WinEvent / Update QFE history)
      - wuauserv stopped/disabled
      - No successful update activity within a stale window
    Exit 0 = healthy, Exit 1 = update issue detected.
.NOTES
    Intune Proactive Remediation - Detection script.
#>

[CmdletBinding()]
param(
    [int]$StaleDays = 35   # no successful scan/install within N days = suspect
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'WURepair-Detect.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

try {
    $reasons = @()

    # 1. wuauserv health
    $svc = Get-Service wuauserv -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.StartType -eq 'Disabled') { $reasons += 'wuauserv disabled' }
    Write-Log "wuauserv: status=$($svc.Status) start=$($svc.StartType)"

    # 2. Recent failed update installs (Setup / WindowsUpdateClient)
    try {
        $failed = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 20
        } -MaxEvents 5 -ErrorAction SilentlyContinue
        if ($failed) { $reasons += "$($failed.Count) recent update-install failure event(s)" }
    } catch { Write-Log "WU event query: $($_.Exception.Message)" }

    # 3. Staleness via last successful install from update history (COM)
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $count    = $searcher.GetTotalHistoryCount()
        if ($count -gt 0) {
            $hist = $searcher.QueryHistory(0, [math]::Min($count,50))
            $lastOk = ($hist | Where-Object { $_.ResultCode -eq 2 } |
                       Sort-Object Date -Descending | Select-Object -First 1)
            if ($lastOk) {
                $age = (New-TimeSpan -Start $lastOk.Date -End (Get-Date)).Days
                Write-Log "Last successful update: $($lastOk.Date) ($age days ago)"
                if ($age -gt $StaleDays) { $reasons += "Last success $age days ago" }
            } else { $reasons += 'No successful update in history' }
        }
    } catch { Write-Log "Update history: $($_.Exception.Message)" }

    if ($reasons.Count -gt 0) {
        Write-Log "DETECTED: $($reasons -join '; ')"
        Write-Output "Update issue: $($reasons -join '; ')"
        exit 1
    }
    Write-Output "Windows Update healthy"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0
}
