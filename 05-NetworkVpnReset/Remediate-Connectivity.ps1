<#
.SYNOPSIS
    Remediation: Network / VPN Reset (Remediation 5)
.DESCRIPTION
    - Flushes DNS cache
    - Releases / renews DHCP lease
    - Resets Winsock and TCP/IP stack (winsock reset, int ip reset)
    - Restarts active physical adapters
    - Re-triggers the Intune-delivered VPN profile (best-effort sync)
    Validates connectivity afterward.
.NOTES
    Intune Proactive Remediation - Remediation script. Runs as SYSTEM.
    Note: winsock/ip reset benefits from a reboot to fully apply.
#>

[CmdletBinding()]
param(
    [string[]]$DnsProbe = @('login.microsoftonline.com')
)

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile = Join-Path $LogDir 'Connectivity-Remediate.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

$actions = @()
try {
    # 1. DNS flush
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    ipconfig /flushdns | Out-Null
    $actions += 'Flushed DNS'

    # 2. DHCP release/renew
    ipconfig /release | Out-Null
    ipconfig /renew   | Out-Null
    $actions += 'Renewed DHCP'

    # 3. Winsock + TCP/IP reset
    netsh winsock reset | Out-Null
    netsh int ip reset  | Out-Null
    $actions += 'Reset Winsock/TCPIP (reboot recommended)'

    # 4. Bounce active physical adapters
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object Status -eq 'Up' | ForEach-Object {
            try {
                Restart-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction Stop
                $actions += "Restarted adapter $($_.Name)"
                Write-Log "Restarted adapter: $($_.Name)"
            } catch { Write-Log "Adapter $($_.Name): $($_.Exception.Message)" }
        }

    # 5. Re-trigger VPN/config profile delivery via Intune MDM sync
    try {
        Start-Process -FilePath "$env:WINDIR\System32\deviceenroller.exe" -ArgumentList '/o','/c' -WindowStyle Hidden -ErrorAction SilentlyContinue
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskName -match 'Schedule.*created.*OMA' } | Select-Object -First 1
        if ($task) { Start-ScheduledTask -InputObject $task; $actions += 'Triggered MDM/VPN profile sync' }
    } catch { Write-Log "VPN profile sync: $($_.Exception.Message)" }

    # Validate
    Start-Sleep -Seconds 5
    $dnsOk = $false
    foreach ($h in $DnsProbe) {
        try { Resolve-DnsName $h -QuickTimeout -ErrorAction Stop | Out-Null; $dnsOk = $true } catch {}
    }
    Write-Log "Post-reset DNS resolve OK: $dnsOk | Actions: $($actions -join '; ')"
    Write-Output "Network reset done (DNS OK: $dnsOk). Actions: $($actions -join '; ')"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
