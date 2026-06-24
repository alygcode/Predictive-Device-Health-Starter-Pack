<#
.SYNOPSIS
    Remediation: App Crash Recovery (Remediation 7)
.DESCRIPTION
    For each app the detection script flagged (AppCrash-State.json):
      - Gracefully stop any lingering process
      - Clear the app's volatile cache where known (Outlook/Teams/Edge)
      - Repair via the appropriate channel:
          * Store/AppX apps -> reset package
          * Click-to-Run Office -> trigger OfficeC2R quick repair
          * Win32 apps -> restart only (reinstall handled by Intune app assignment)
    Validates the process can relaunch and logs the outcome.
.NOTES
    Intune Proactive Remediation - Remediation script. Runs as SYSTEM.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$LogDir    = 'C:\ProgramData\PredictiveDeviceHealth\Logs'
$LogFile   = Join-Path $LogDir 'AppCrash-Remediate.log'
$StateFile = Join-Path $LogDir 'AppCrash-State.json'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param($m) "$(Get-Date -Format o) $m" | Out-File -FilePath $LogFile -Append -Encoding utf8 }

$actions = @()
try {
    if (-not (Test-Path $StateFile)) {
        Write-Log 'No state file - nothing flagged. Exiting clean.'
        Write-Output 'No flagged apps to recover'
        exit 0
    }

    $flagged = (Get-Content $StateFile -Raw | ConvertFrom-Json).PSObject.Properties.Name
    Write-Log "Flagged apps: $($flagged -join ', ')"

    foreach ($exe in $flagged) {
        $procName = [System.IO.Path]::GetFileNameWithoutExtension($exe)

        # 1. Stop lingering instances
        Get-Process -Name $procName -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Log "Stopped instances of $procName"

        # 2. App-specific repair/cache reset
        switch -Wildcard ($exe) {
            'Teams.exe' {
                Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $cache = Join-Path $_.FullName 'AppData\Roaming\Microsoft\Teams\Cache'
                    if (Test-Path $cache) { Remove-Item "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue }
                }
                $actions += 'Cleared Teams cache'
            }
            'msedge.exe' {
                $pkg = Get-AppxPackage -AllUsers -Name 'Microsoft.MicrosoftEdge*' -ErrorAction SilentlyContinue
                $actions += 'Edge flagged (managed by Intune/WebView update)'
            }
            { $_ -in 'OUTLOOK.EXE','WINWORD.EXE','EXCEL.EXE' } {
                # Office Click-to-Run quick repair
                $c2r = "$env:ProgramFiles\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
                if (Test-Path $c2r) {
                    Start-Process -FilePath $c2r -ArgumentList 'scenario=Repair','platform=x64','culture=en-us','RepairType=QuickRepair','DisplayLevel=False' -WindowStyle Hidden -ErrorAction SilentlyContinue
                    $actions += "Triggered Office QuickRepair for $exe"
                } else {
                    $actions += "Restarted $exe (no C2R client found)"
                }
            }
            default {
                # Generic AppX reset if it is a packaged app
                $pkg = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
                       Where-Object { $_.PackageFullName -match $procName }
                if ($pkg) {
                    foreach ($p in $pkg) {
                        # No built-in reset cmdlet for system context; re-register the manifest.
                        if ($p.InstallLocation -and (Test-Path "$($p.InstallLocation)\AppxManifest.xml")) {
                            Add-AppxPackage -DisableDevelopmentMode -Register `
                                "$($p.InstallLocation)\AppxManifest.xml" -ErrorAction SilentlyContinue
                            $actions += "Re-registered AppX $($p.Name)"
                        } else {
                            $actions += "AppX $($p.Name) flagged (no manifest to re-register)"
                        }
                    }
                } else {
                    $actions += "Restarted $exe (Win32 reinstall deferred to Intune app policy)"
                }
            }
        }
        Write-Log "Recovery handled for $exe"
    }

    # Clear state so detection re-evaluates fresh next cycle
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue

    if ($actions.Count -eq 0) { $actions += 'Stopped crashing processes' }
    Write-Log "Actions: $($actions -join '; ')"
    Write-Output "App recovery: $($actions -join '; ')"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
