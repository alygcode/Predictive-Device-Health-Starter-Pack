<#
.SYNOPSIS
    Detection: Network / VPN Reset (Remediation 5)
.DESCRIPTION
    Flags the device when corporate connectivity is failing:
      - No active non-loopback adapter with a gateway
      - DNS resolution failing
      - Corporate endpoint(s) unreachable
    Exit 0 = healthy, Exit 1 = connectivity problem.
.NOTES
    Intune Proactive Remediation - Detection script.
    Set $CorpEndpoints to internal hosts that should always be reachable on-net/VPN.
#>

[CmdletBinding()]
param(
    [string[]]$DnsProbe      = @('login.microsoftonline.com'),
    [string[]]$CorpEndpoints = @(),   # e.g. @('vpn.contoso.com','dc01.contoso.local')
    [int]$TimeoutMs          = 3000
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'Connectivity-Detect.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

try {
    $reasons = @()

    # 1. Active adapter with default gateway?
    $up = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
          Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway }
    if (-not $up) { $reasons += 'No active adapter with gateway' }
    Write-Log "Active gateway adapters: $(($up.InterfaceAlias) -join ', ')"

    # 2. DNS resolution
    foreach ($h in $DnsProbe) {
        try { Resolve-DnsName -Name $h -QuickTimeout -ErrorAction Stop | Out-Null }
        catch { $reasons += "DNS fail: $h" }
    }

    # 3. Corporate endpoint reachability (TCP 443) - only if configured
    foreach ($ep in $CorpEndpoints) {
        $ok = Test-NetConnection -ComputerName $ep -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        if (-not $ok) { $reasons += "Unreachable: $ep" }
    }

    if ($reasons.Count -gt 0) {
        Write-Log "DETECTED: $($reasons -join '; ')"
        Write-Output "Connectivity issue: $($reasons -join '; ')"
        exit 1
    }
    Write-Output "Connectivity OK"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0
}
