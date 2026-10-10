# PC Gaming Optimizer 5.0.1

Gaming controls, diagnostics and maintenance integrated with the [dashboard](../README.md). Keep the full toolkit extracted together.

Root `START_TOOLKIT.bat` launches one-click optimization/debloat. `Run_All_Optimizations.ps1` runs the same recommended profile; `-Preview` gives a read-only plan. `Run_As_Admin.bat` opens the detailed console; **A** opens the dashboard.

- Game Mode and optional capture disable.
- HAGS manager and optional mouse acceleration settings.
- Above Normal process priority/stay-awake during a game session, restored in `finally`.
- GPU/driver, network, memory, storage, timer/BCD, MSI, display and PCVR audits.
- Official SSD ReTrim and shader troubleshooting cleanup.
- JSON benchmark snapshots, privacy/DNS/repair launchers and legacy v3 tweak cleanup.

Automatic optimization preserves power/sleep, SysMain, drivers, HAGS, GPU interrupt mode, timers/BCD, TCP/NIC offloads and shaders. Test HAGS/power changes against the actual game.

Dashboard recovery uses conflict-aware journals in `%ProgramData%\WindowsPCToolkit\Suite\Runs`. Console actions use `GamingOptimizer\Snapshots` and **U** restores the latest gaming snapshot after confirmation. New snapshots record the computer/user and capture only that action's registry, service, network or boot settings. Restore checks typed registry values and reports service/NIC/native-tool failures. Legacy snapshots lack identity metadata and can capture a wider settings set: restore only your own local backup and review later manual changes. Console restore can replace later manual edits; use dashboard journals for conflict-aware undo. Shader deletion cannot be undone, and linked cache folders are skipped.

Console ReTrim requires a positive SSD serial-number match; HDD and unidentified storage are preserved. Boot-configuration query failures stop legacy timer cleanup rather than being interpreted as no overrides.

Warnings/errors are logged to `%LOCALAPPDATA%\WindowsPCToolkit\Logs\GamingOptimizer.log`, with version and cause. Run `PC_Optimizer.ps1 -DebugLog` or set `WINDOWS_PC_TOOLKIT_DEBUG=1` for detailed startup/configuration/state diagnostics. Debug logging is off by default; diagnostics rotate at 2 MB.

Parser/registry checks do not prove performance gains. Compare game frame times and benchmark evidence.
