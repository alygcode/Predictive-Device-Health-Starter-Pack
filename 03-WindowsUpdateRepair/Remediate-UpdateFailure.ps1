<#
.SYNOPSIS
    Remediation: Windows Update Repair (Remediation 3)
.DESCRIPTION
    Standard Windows Update component reset:
      - Stop wuauserv, bits, cryptsvc, msiserver
      - Rename SoftwareDistribution and catroot2
      - Restart services
      - Trigger an update detection re-scan using a best-effort method
    Validates services are running afterward.
.NOTES
    Intune remediation script. Runs as SYSTEM.
    Some service defaults, scan triggers, and post-reset behavior can vary by
    Windows version. Validate in your supported build matrix before broad rollout.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'WURepair-Remediate.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

$svcs = 'wuauserv','bits','cryptsvc','msiserver'
try {
    # 1. Stop services
    foreach ($s in $svcs) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
    Write-Log "Stopped: $($svcs -join ', ')"

    # 2. Rename component caches (forces a clean rebuild)
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    foreach ($folder in "$env:WINDIR\SoftwareDistribution","$env:WINDIR\System32\catroot2") {
        if (Test-Path $folder) {
            $bak = "$folder.bak.$stamp"
            try {
                Rename-Item -Path $folder -NewName (Split-Path $bak -Leaf) -ErrorAction Stop
                Write-Log "Renamed $folder -> $bak"
            }
            catch { Write-Log "Could not rename $folder : $($_.Exception.Message)" }
        }
    }

    # 3. Restart services
    foreach ($s in $svcs) {
        try {
            Set-Service $s -StartupType Manual -ErrorAction SilentlyContinue
            Start-Service $s -ErrorAction Stop
            Write-Log "Started: $s"
        } catch { Write-Log "Start $s failed: $($_.Exception.Message)" }
    }

    # Service startup expectations can vary by Windows build and policy.
    Set-Service wuauserv -StartupType Automatic -ErrorAction SilentlyContinue

    # 4. Trigger detection re-scan
    try {
        if (Test-Path "$env:WINDIR\System32\UsoClient.exe") {
            Start-Process -FilePath "$env:WINDIR\System32\UsoClient.exe" -ArgumentList 'StartScan' -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-Log 'Triggered UsoClient StartScan (best effort). Validate support on current Windows builds.'
        } else {
            Write-Log 'UsoClient.exe not present; no re-scan trigger executed.'
        }
    } catch { Write-Log "Re-scan trigger: $($_.Exception.Message)" }

    # 5. Validate
    $running = $svcs | ForEach-Object { Get-Service $_ -ErrorAction SilentlyContinue } |
               Where-Object { $_.Status -eq 'Running' }
    Write-Log "Running after repair: $($running.Name -join ', ')"
    Write-Output "WU components reset; running: $($running.Name -join ', ')"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
