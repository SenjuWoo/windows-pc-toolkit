# PC Gaming Optimizer 5.0

Gaming controls, diagnostics and maintenance integrated with the [dashboard](../README.md). Keep the full toolkit extracted together.

Root `START_TOOLKIT.bat` launches one-click optimization/debloat. `Run_All_Optimizations.ps1` runs the same recommended profile; `-Preview` gives a read-only plan. `Run_As_Admin.bat` opens the detailed console; **A** opens the dashboard.

- Game Mode and optional capture disable.
- HAGS manager and optional mouse acceleration settings.
- Above Normal process priority/stay-awake during a game session, restored in `finally`.
- GPU/driver, network, memory, storage, timer/BCD, MSI, display and PCVR audits.
- Official SSD ReTrim and shader troubleshooting cleanup.
- JSON benchmark snapshots, privacy/DNS/repair launchers and legacy v3 tweak cleanup.

Automatic optimization preserves power/sleep, SysMain, drivers, HAGS, GPU interrupt mode, timers/BCD, TCP/NIC offloads and shaders. Test HAGS/power changes against the actual game.

Dashboard recovery uses conflict-aware journals in `%ProgramData%\WindowsPCToolkit\Suite\Runs`. Console actions use `GamingOptimizer\Snapshots` and **U** restores the latest gaming snapshot. Legacy snapshots capture a wider settings set: review later manual changes before restoring. Shader deletion cannot be undone.

Parser/registry checks do not prove performance gains. Compare game frame times and benchmark evidence.
