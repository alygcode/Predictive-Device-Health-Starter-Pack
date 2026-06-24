# Predictive Device Health – Remediation Implementation

PowerShell implementation of **7 high-impact endpoint remediations** from
`Predictive_Device_Health_Remediation_Starter_Pack.md`, packaged as
**Microsoft Intune Remediations** script pairs.

Each remediation follows a closed-loop model:

**Detect → Remediate → Validate → Improve**

---

## Table of Contents

- [What this repository includes](#what-this-repository-includes)
- [Quick Start (5 minutes)](#quick-start-5-minutes)
- [How script pairs work](#how-script-pairs-work)
- [Remediation catalog](#remediation-catalog)
- [Tunable parameters](#tunable-parameters)
- [Deploy in Intune](#deploy-in-intune)
- [Operational monitoring](#operational-monitoring)
- [Safety notes](#safety-notes)
- [Phased rollout plan](#phased-rollout-plan)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## What this repository includes

| # | Folder | Detection script | Remediation script |
|---|--------|------------------|--------------------|
| 1 | `01-SlowStartupFix` | `Detect-SlowStartup.ps1` | `Remediate-SlowStartup.ps1` |
| 2 | `02-DiskSpaceCleanup` | `Detect-LowDiskSpace.ps1` | `Remediate-LowDiskSpace.ps1` |
| 3 | `03-WindowsUpdateRepair` | `Detect-UpdateFailure.ps1` | `Remediate-UpdateFailure.ps1` |
| 4 | `04-CpuMemoryStabilization` | `Detect-HighResource.ps1` | `Remediate-HighResource.ps1` |
| 5 | `05-NetworkVpnReset` | `Detect-Connectivity.ps1` | `Remediate-Connectivity.ps1` |
| 6 | `06-PolicyDriftCorrection` | `Detect-PolicyDrift.ps1` | `Remediate-PolicyDrift.ps1` |
| 7 | `07-AppCrashRecovery` | `Detect-AppCrashes.ps1` | `Remediate-AppCrashes.ps1` |

---

## Quick Start (5 minutes)

1. Start with one low-risk package, for example `02-DiskSpaceCleanup`.
2. In the Intune admin center, open the current device remediation workflow for your tenant. UI labels and navigation can change over time, so confirm the latest path in your environment before deployment.
3. Upload matching scripts:
   - Detection: `02-DiskSpaceCleanup/Detect-LowDiskSpace.ps1`
   - Remediation: `02-DiskSpaceCleanup/Remediate-LowDiskSpace.ps1`
4. Example settings to validate in your environment:
   - **Run this script using the logged-on credentials:** `No` (SYSTEM)
   - **Enforce script signature check:** per your organization policy
   - **Run script in 64-bit PowerShell:** `Yes`
5. Assign to a pilot group sized for your operational risk tolerance, for example 5–10% of devices, and use a schedule appropriate for the remediation.
6. Validate for an observation window that fits your environment, for example 48–72 hours, before expanding scope.

---

## How script pairs work

### Execution semantics

| Script type | Exit code | Meaning | Expected Intune behavior |
|---|---:|---|---|
| Detection | `0` | Healthy / no issue detected | Remediation should not run |
| Detection | `1` | Issue detected | Remediation should run |
| Detection | `0` on unexpected error | Fail-safe probe behavior | Helps prevent accidental broad remediation |
| Remediation | `0` | Fix successful | Expected to be reported as successful |
| Remediation | `1` | Fix failed / follow-up needed | Expected to be reported as failed |

> Verify reporting and execution behavior against current Intune documentation and tenant behavior, as platform UX and reporting details can evolve.

### Logging

All scripts write logs to:

`C:\ProgramData\PredictiveDeviceHealth\Logs\`

One log file per script supports auditing, trend analysis, and continuous improvement.

---

## Remediation catalog

| # | Name | Primary objective | Typical user impact | Reboot likely? | Example schedule |
|---|------|-------------------|---------------------|----------------|------------------|
| 1 | Slow Startup Fix | Reduce boot/login delay | Low | No | Daily |
| 2 | Disk Space Cleanup | Recover free space and prevent update failures | Low–Medium (cache/temp cleanup) | No | Daily |
| 3 | Windows Update Repair | Recover stuck/failed updates | Medium | Sometimes | Off-hours preferred |
| 4 | CPU/Memory Stabilization | Mitigate sustained resource pressure | Medium–High (process intervention) | No | Higher-frequency only after validation |
| 5 | Network/VPN Reset | Restore network or VPN connectivity | Medium | Often effective after reboot | Higher-frequency only after validation |
| 6 | Policy Drift Correction | Re-apply compliance/security state | Low | No | Daily |
| 7 | App Crash Recovery | Recover repeatedly crashing business apps | Medium | Depends on repair path | Daily |

> Scheduling should be tuned per remediation type, device class, user impact, and tenant risk tolerance.

---

## Tunable parameters

Review and tune before broad rollout. Parameter defaults in this repository are examples and should be validated against your device fleet, hardware profile, Windows build mix, and operational baselines.

| Remediation | Key parameters |
|-------------|----------------|
| 1 Slow startup | `BootThresholdMs`, `MaxStartupApps`, `DisableStartupNames` allow/deny list |
| 2 Disk space | `MinFreePercent` (default 15%) |
| 3 WU repair | `StaleDays` |
| 4 CPU/Mem | `CpuThreshold`, `MemThreshold`, `WsKillBytes`, `Protected` process list |
| 5 Network/VPN | `CorpEndpoints` (set to internal hosts), `DnsProbe` |
| 6 Policy drift | `MaxSyncAgeHours`; confirm baseline controls to auto-remediate |
| 7 App crash | `MonitoredApps`, `CrashThreshold`, `WindowHours` |

---

## Deploy in Intune

1. **Create one script package per remediation pair**.
2. Upload matching detection + remediation scripts from the same numbered folder.
3. Use **SYSTEM** context by default unless a remediation explicitly requires user context.
4. Start with pilot ring assignments that fit your change-management model, for example:
   - Ring 0: IT/engineering devices
   - Ring 1: 5–10% of production
   - Ring 2: 25–50%
   - Ring 3: broad rollout
5. Confirm health metrics before each ring expansion:
   - Remediation success rate target (example: >95%)
   - No high-severity incident increase
   - No sustained performance regressions

> Treat the ring sizes and success targets above as examples, not universal defaults.

---

## Operational monitoring

### Recommended weekly checks

- Top recurring detections by remediation
- Devices with repeated failures (`exit 1` remediation outcomes)
- Time-to-recovery trend per remediation
- High-resource repeat offenders (`HighResource-Offenders.json`)

### Suggested KPIs

- Endpoint performance complaint volume
- Update compliance improvement
- VPN/network helpdesk ticket reduction
- Mean time to remediate common endpoint faults

---

## Safety notes

- **CPU/Memory stabilization (#4)**:
  - Never terminate protected/system-critical processes.
  - Keep an explicit protected process list.
  - Prefer intervention only above hard thresholds.
- **Network/VPN reset (#5)**:
  - Includes `netsh winsock reset` / TCP-IP reset flows that may require reboot to fully apply on some systems.
  - Validate adapter reset and MDM/VPN sync behavior on your current Windows builds before broad rollout.
- **Policy drift correction (#6)**:
  - Does **not** silently force BitLocker enablement.
  - Triggers management sync so policy controls desired state.
  - Confirm current compliance, encryption, and remediation expectations in your tenant before enabling automatic correction.
- **App crash recovery (#7)**:
  - Prioritize repair/reset paths first.
  - Defer Win32 reinstall to assigned Intune app lifecycle when possible.

---

## Phased rollout plan

- **Phase 1 (Quick wins):** #2 Disk, #1 Startup, #5 Network
- **Phase 2:** #3 Windows Update repair, #6 Policy reapplication
- **Phase 3 (Advanced):** #4 CPU stabilization, #7 App self-healing

Validate each phase in pilot before broader deployment.

---

## Troubleshooting

- **Detection never triggers remediation**
  - Verify detection script returns `1` when condition is present.
- **Remediation runs but device stays unhealthy**
  - Check remediation log in `C:\ProgramData\PredictiveDeviceHealth\Logs\`.
  - Confirm thresholds are realistic for device class.
  - Revalidate any Windows-version-specific or tenant-specific assumptions in the script.
- **Unexpected user impact**
  - Move package back to pilot scope.
  - Tighten allow/protect lists and increase thresholds.
- **No output visible in Intune**
  - Ensure scripts emit a final `Write-Output` summary line.
  - Confirm current reporting behavior in your Intune tenant.

---

## Contributing

Contributions are welcome. Recommended standards:

- Keep detection scripts fail-safe.
- Keep remediation scripts idempotent where possible.
- Log every critical action and validation result.
- Include clear output summaries for Intune reporting.
- Flag Windows-build-specific, tenant-specific, or Intune-UX-specific assumptions in comments and documentation.

---

## Source reference

Implementation is based on:

- `Predictive_Device_Health_Remediation_Starter_Pack.md`

This repository operationalizes those remediation patterns into deployable Intune script pairs.