# Predictive Device Health – Remediation Implementation

PowerShell implementation of the **7 high-impact remediations** from
`Predictive_Device_Health_Remediation_Starter_Pack.md`, packaged as
**Intune Proactive Remediation** (Endpoint Analytics → Remediations) detection +
remediation script pairs.

Each pair follows the closed-loop model from the starter pack:
**Detect → Remediate → Validate → Improve**.

## Contents

| # | Folder | Detection script | Remediation script |
|---|--------|------------------|--------------------|
| 1 | `01-SlowStartupFix` | `Detect-SlowStartup.ps1` | `Remediate-SlowStartup.ps1` |
| 2 | `02-DiskSpaceCleanup` | `Detect-LowDiskSpace.ps1` | `Remediate-LowDiskSpace.ps1` |
| 3 | `03-WindowsUpdateRepair` | `Detect-UpdateFailure.ps1` | `Remediate-UpdateFailure.ps1` |
| 4 | `04-CpuMemoryStabilization` | `Detect-HighResource.ps1` | `Remediate-HighResource.ps1` |
| 5 | `05-NetworkVpnReset` | `Detect-Connectivity.ps1` | `Remediate-Connectivity.ps1` |
| 6 | `06-PolicyDriftCorrection` | `Detect-PolicyDrift.ps1` | `Remediate-PolicyDrift.ps1` |
| 7 | `07-AppCrashRecovery` | `Detect-AppCrashes.ps1` | `Remediate-AppCrashes.ps1` |

## How the script pairs work

- **Detection script** exits `0` when the device is healthy (no remediation runs)
  and exits `1` when an issue is found (Intune then runs the remediation script).
- Detection scripts are **fail-safe**: on an unexpected error they exit `0` so a
  faulty probe never triggers mass remediation.
- **Remediation scripts** perform the fix, re-validate, and write a closed-loop
  entry to the log. They exit `0` on success, `1` on failure.
- All scripts log to `C:\ProgramData\PredictiveDeviceHealth\Logs\` (one file per
  script) for trend analysis and the "Improve" step.

## Deploy in Intune

1. **Endpoint Manager admin center** → *Reports* → *Endpoint analytics* →
   *Proactive remediations* → **Create script package**.
2. Upload the matching **Detection** and **Remediation** scripts for each row.
3. Settings:
   - **Run this script using the logged-on credentials**: *No* (run as SYSTEM) for
     all packages **except** any you scope to per-user cache cleanup.
   - **Enforce script signature check**: per your org signing policy.
   - **Run script in 64-bit PowerShell**: *Yes*.
4. **Assignment**: target a pilot ring first; set the schedule (e.g., daily, or
   hourly for #4/#5 which are time-sensitive).
5. Review results under each package: *Output* columns surface the `Write-Output`
   summary line from the scripts.

## Tunable parameters (edit before deploying)

| Remediation | Key params to review |
|-------------|----------------------|
| 1 Slow startup | `BootThresholdMs`, `MaxStartupApps`, `DisableStartupNames` allow/deny list |
| 2 Disk space | `MinFreePercent` (default 15%) |
| 3 WU repair | `StaleDays` |
| 4 CPU/Mem | `CpuThreshold`, `MemThreshold`, `WsKillBytes`, `Protected` process list |
| 5 Network/VPN | `CorpEndpoints` (set to your internal hosts), `DnsProbe` |
| 6 Policy drift | `MaxSyncAgeHours`; review which baseline controls are auto-enabled |
| 7 App crash | `MonitoredApps`, `CrashThreshold`, `WindowHours` |

## Safety notes

- **#4 (CPU/Mem)** never terminates protected/system-critical processes and only
  kills user-session apps above a hard working-set threshold; it logs repeat
  offenders to `HighResource-Offenders.json` for the *Improve* loop.
- **#5 (Network)** runs `netsh winsock/ip reset`, which fully applies after the
  next reboot.
- **#6 (Policy drift)** does **not** silently enable BitLocker (key-escrow risk);
  it forces an Intune sync so the disk-encryption policy drives it instead.
- **#7 (App crash)** defers Win32 reinstalls to the assigned Intune app and only
  resets/repairs Store and Click-to-Run Office apps directly.

## Phasing (from the starter pack)

- **Phase 1 (Quick wins):** #2 Disk, #1 Startup, #5 Network
- **Phase 2:** #3 WU repair, #6 Policy reapplication
- **Phase 3 (Advanced):** #4 CPU stabilization, #7 App self-healing

Validate each phase on a pilot ring before broad rollout.
