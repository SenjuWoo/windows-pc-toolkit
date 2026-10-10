# PC Cleaner audit, 2026-10-10

Scope: all four `pc-cleaner` source/launcher/documentation files; callers in the shared Toolkit module; registry journal and undo dependencies; the existing toolkit regression coverage. No new debloat features were added.

## Confirmed defects and repairs

| Defect and mechanism | Repair and evidence |
| --- | --- |
| Windows.old was a Strict category whose executor took ownership, rewrote ACLs and recursively deleted the previous installation. This contradicted the documented report-only promise and removed upgrade rollback data. | Windows.old is report-only. Removed ownership/deletion branches. The executor refuses every protected report-only category by ID, including old descriptors with Strict/Special fields. |
| The deletion guard checked only the leaf reparse bit. A normal file or directory below a junction could therefore reach outside the cache location. | Check every existing ancestor before deleting or enumerating a root. Native junction fixtures prove normal leaves below links survive direct, category and Temp cleanup. Common local model-store names are protected too. |
| Temp scan counted recent/protected files while actual cleanup accepted only aged files. A file refreshed after enumeration was not rechecked by the console. | Scan and cleanup use the same candidate enumeration; cleanup rechecks write/access ages immediately before removal. Native aged, accessed, refreshed and protected files exercise this boundary. |
| Report-only rows in the main table were omitted entirely from scan output and kept totals; backup review counted only files with a surviving original. | Render all report-only categories and include both backup candidate groups. No backup file is offered to deletion by the executor. |
| Wildcard profile paths interpreted literal brackets in parent directory names. | Escape literal path metacharacters while retaining the intended star wildcard. Real bracket/apostrophe filesystem fixtures cover directories and files. |
| Delivery Optimization assumed all pre-existing files were removed on any successful call and swallowed exceptions as successful-looking results. | Measure the reduction after the official cmdlet, preserve a Failed status and cause on error, show failures in console summaries and persist CompletedWithErrors in run reports. Native cache deletion is faked in these tests. |
| Registry care validated the scanned startup command but removed the current registry value, so a replacement made during review could be removed. Failure after a partial registry write lacked immediate rollback. | Read the current command before deciding; use existing typed Suite journals; roll back entries added by a failed individual repair. Native owned HKCU tests preserve a new valid executable, remove a missing target and undo exactly. |
| Unquoted executable paths with spaces could be interpreted as one missing path despite Windows trying multiple candidates. Prefix filtering also hid legitimate value names starting with PS. | Retain ambiguous commands for review; skip only known provider metadata names. [Microsoft's CreateProcess contract](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw) documents the ambiguity. |
| Legacy backup restore overwrote existing replacement shortcut files and imported entire registry snapshots without disclosing that newer edits could be replaced. | Preserve existing destination files; require explicit confirmation before importing whole legacy registry keys. |
| Logs used second-resolution filenames, overwriting evidence from rapid repeated runs. | Append a GUID; native repeated-run tests verify both reports remain. Add optional bounded diagnostics, quiet on library import. |
| Launcher elevation interpolated the batch path into single-quoted PowerShell, failing on apostrophes; `net session` required the Server service; a timed flag could falsely report UAC failure. Alternate administrator credentials could target another account's files and HKCU. | Pass the launch path through an environment variable, check the Windows principal directly, wait for the elevated child, propagate its actual exit code and validate the originating user SID before bootstrap/action. The launcher audit tests native path/argument boundaries separately. |
| Custom category ranges could allocate an enormous integer range or throw on integer overflow. | Parse and bound both endpoints before creating the range; oversized native console input test reaches no cleanup call. |

## Verification

`powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests\Test_AuditCleaner.ps1` passes **53 checks** on native Windows PowerShell 5.1. It uses real disposable files, real directory junctions, an exclusively locked file, an owned HKCU key, typed Suite journal undo and an injected interruption after actual test-key removal. Delivery Optimization and console inputs are faked. The original cleaner self-test and parser gate also pass.

Fixtures clean up their own files, links and registry key. The restricted sandbox cannot create junctions; the native fixture run used the ordinary user process outside that sandbox, without requiring real cleanup or system repair.

## Remaining limits

Cleanup is not atomic with another process renaming filesystem directories between checks and deletion. Permission-denied and locked paths are skipped; scans are estimates for accessible files, and a cache may change during measurement. A partially failed recursive removal can delete some ordinary disposable children before it encounters a locked child. File/cache deletion has no undo. Legacy whole-key registry imports cannot detect every intervening edit, hence their explicit confirmation. No real user cache, Windows.old, app package, service or Windows Update data was cleaned during this audit; no live performance benefit is claimed.
