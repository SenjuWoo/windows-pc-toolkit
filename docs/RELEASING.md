# Releasing

The steps used for 3.1.2, in the order they must run. Nothing here changes a Windows setting: the builder reads Git objects and writes an archive, and the tests use disposable fixtures.

## 1. Version and notes

- Bump `$script:SuiteVersion` in `Modules/Toolkit.Core.psm1` and the `vX.Y.Z` label in `Toolkit.xaml` (top bar).
- Add the top `## Toolkit X.Y.Z (date)` entry in `CHANGELOG.md`.
- Add `docs/releases/vX.Y.Z.md` and point the README download links at the new tag.

`Validate_All.ps1` fails when the module version, the dashboard label and the changelog top entry disagree, so run it before anything else.

## 2. Local proof

Windows PowerShell 5.1 only, from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Validate_All.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test_All.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Toolkit.ps1 -SmokeTest
```

The suite must report every assertion passing with no `FAIL` line. Record the counts in `STATE.md`.

## 3. Push, then prove the SHA

Push the release commit and wait for every check on that exact SHA to finish successfully. Re-query Dependabot, code-scanning and secret-scanning alerts; unavailable Code Quality stays off. A green run on a different SHA proves nothing.

## 4. Build the payload

```powershell
python tests\tools\build_release.py build dist\Windows-PC-Toolkit-X.Y.Z.zip <release-sha> --report dist\build.json
```

The builder refuses to overwrite an existing archive, disables the local CRLF conversion for that one `git archive` call, drops repository/test/validator/spec paths, and fails if any shipped file differs from the raw blob at the commit. Do not hand-zip the folder: `git archive` alone ships CRLF variants that break the byte claim.

## 5. Tag and publish

```powershell
git tag -a vX.Y.Z <release-sha> -m "Windows PC Toolkit X.Y.Z: <summary>"
git push origin refs/tags/vX.Y.Z
gh release create vX.Y.Z dist\Windows-PC-Toolkit-X.Y.Z.zip dist\release-provenance.json dist\SHA256SUMS.txt
```

Release notes come from `docs/releases/vX.Y.Z.md`. GitHub renders release bodies as page markdown, so links must be absolute and commit- or tag-pinned; a relative `../docs/...` link 404s.

## 6. Verify the published assets

```powershell
gh release download vX.Y.Z --dir dist\downloaded
python tests\tools\build_release.py verify dist\downloaded\Windows-PC-Toolkit-X.Y.Z.zip <release-sha> --report dist\verify.json
Get-FileHash dist\downloaded\* -Algorithm SHA256
```

Compare all three hashes with `SHA256SUMS.txt` and with GitHub's recorded asset digests, extract the ZIP into a new versioned folder, run `Toolkit.ps1 -SmokeTest` there, and record the paths and hashes in `STATE.md`.
