<#
.SYNOPSIS
    Remediation: Network / VPN Reset (Remediation 5)
.DESCRIPTION
    - Flushes DNS cache
    - Releases / renews DHCP lease
    - Resets Winsock and TCP/IP stack (winsock reset, int ip reset)
    - Restarts active physical adapters
    - Attempts a best-effort device management sync that may help refresh
      Intune-delivered VPN or connectivity-related configuration
    Validates connectivity afterward.
.NOTES
    Intune remediation script. Runs as SYSTEM.
    Winsock/IP reset behavior, scheduled task naming, and MDM sync behavior can
    vary by Windows version and enrollment state. Validate before broad rollout.
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
    $actions += 'Reset Winsock/TCPIP (reboot may be required on some systems)'

    # 4. Bounce active physical adapters
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object Status -eq 'Up' | ForEach-Object {
            try {
                Restart-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction Stop
                $actions += "Restarted adapter $($_.Name)"
                Write-Log "Restarted adapter: $($_.Name)"
            } catch { Write-Log "Adapter $($_.Name): $($_.Exception.Message)" }
        }

    # 5. Attempt device management sync that may refresh VPN/config profile delivery
    try {
        if (Test-Path "$env:WINDIR\System32\deviceenroller.exe") {
            Start-Process -FilePath "$env:WINDIR\System32\deviceenroller.exe" -ArgumentList '/o','/c' -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-Log 'Invoked deviceenroller.exe for best-effort sync trigger.'
        } else {
            Write-Log 'deviceenroller.exe not present; skipping enrollment-based sync trigger.'
        }

        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskName -match 'Schedule.*created.*OMA' } | Select-Object -First 1
        if ($task) {
            Start-ScheduledTask -InputObject $task
            $actions += 'Triggered MDM/VPN profile sync'
        } else {
            Write-Log 'No matching EnterpriseMgmt scheduled task found for OMA sync trigger.'
        }
    } catch { Write-Log "VPN/profile sync: $($_.Exception.Message)" }

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
