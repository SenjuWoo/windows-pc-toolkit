# PC Gaming Optimizer v4.0

A conservative Windows 10/11 gaming toolkit built around **measurement, exact rollback, and supported Windows controls**.

## What changed

v4.0 removes the tweak pile that could make a fast PC slower or less stable: forced 0.5 ms timers, BCD clock overrides, Nagle edits on every interface, `NetworkThrottlingIndex`, `SystemResponsiveness=0`, global RSC/offload disabling, SysMain disabling, standby-list purges, undocumented NVIDIA PowerMizer keys, unsafe GPU MSI writes, NTFS cache hacks, AHCI/NVMe power-registry hacks, permanent no-sleep power plans, and guessed-default undo logic.

Every write now creates an exact JSON snapshot under:

`%ProgramData%\WindowsPCToolkit\GamingOptimizer\Snapshots`

**Undo restores the values that were actually present**, including missing values, service state, and active power plan.

## Recommended use

1. Run `Run_As_Admin.bat`.
2. Use **Safe Gaming Profile** to enable Game Mode. Background recording is separately optional.
3. Run **Benchmark Snapshot** before and after a change.
4. Test HAGS enabled and disabled for the specific game or VR runtime.
5. Use **Repair v3.x Tweaks** once if an older release was previously applied.

## Safe by default

The default profile preserves:

- Current power plan and sleep policy
- SysMain and Windows services
- HAGS state
- DNS and encrypted DNS configuration
- TCP autotuning, RSS, RSC, interrupt moderation, and hardware offloads
- NTFS internals and storage power management
- GPU interrupt mode and undocumented driver keys
- Windows timer and CPU scheduler defaults

## Tools

The numbered scripts remain for compatibility, but now call a shared audited module in `Modules\Optimizer.Core.psm1`.

- HAGS manager
- Shader-cache troubleshooting cleanup
- GPU/driver audit
- Safe Game Mode profile
- Privacy Guard launcher
- Network audit and opt-in legacy cleanup
- Windows Update repair launcher
- Memory audit, without fake “free RAM” purges
- Exact snapshot restore
- Storage health and official ReTrim
- Read-only GPU MSI audit
- Timer/BCD audit
- JSON benchmark snapshots
- Session booster using only Above Normal process priority and stay-awake
- Optional mouse acceleration change
- Display and PCVR audits

## Notes

Shader caches should not be cleared routinely. The first launch after clearing them can stutter while compilation data is rebuilt.

The toolkit does not promise universal FPS gains. On a modern system, firmware, drivers, game settings, thermals, shader compilation, and frame-time evidence matter more than bulk registry edits.
