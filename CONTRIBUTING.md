# Contributing

Thanks for taking the time to contribute! This is a personal, hobby-maintained project, so please be patient with response times.

## Ground rules

- Open an issue first for anything non-trivial — a feature, a refactor, or a bug you plan to fix — so we can agree on the approach before you write a lot of code.
- Keep changes small and focused. One logical change per pull request makes review much easier.
- Match the existing style of the code around you (formatting, naming, structure).

## Bugs and features

1. Search the issues to make sure it hasn't already been reported.
2. Open an issue describing the problem or idea clearly, including how to reproduce bugs.
3. If you want to implement it, say so in the issue and link your pull request to it.

## Pull requests

1. Fork the repo (or push a branch if you have write access).
2. Make your change.
3. If the project has tests or CI, make sure they pass.
4. Open a pull request with a clear title and a description of what and why.
5. Keep the PR scoped; reviewers will ask for changes if something is unclear.

## Local validation

Use built-in Windows PowerShell 5.1 on Windows, with STA for the WPF tests:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Validate_All.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test_Toolkit.ps1
```

Tests create disposable registry/filesystem fixtures and use simulated mutation commands for DNS, AppX, optional features and update repair. They exercise native WPF/jobs, stay-awake and read-only inventories; they do not optimize or repair the host. CI runs the same suite in both supported folder layouts. See [validation details](VALIDATION_REPORT.md).

## Security issues

Do **not** report security problems in a public issue. See `SECURITY.md` for how to report privately.

By contributing, you agree that your contributions are licensed under the same license as this project.
