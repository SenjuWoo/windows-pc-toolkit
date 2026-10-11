#requires -version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$label="Toolkit_LauncherAudit_' ! [1] "+[char]0x73A9+[char]0x5BB6+'_'+[guid]::NewGuid().ToString('N')
$fixture=Join-Path $env:TEMP $label
$checks=0
function Check([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "TEST FAILED: $Message" }; $script:checks++ }
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$userSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Get-AuditLaunchers([string]$Directory) {
    $Directory=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    Get-ChildItem -LiteralPath $Directory -Filter '*.bat' -Recurse -File | Where-Object {
        $relative=$_.FullName.Substring($Directory.TrimEnd('\').Length+1)
        $relative -notmatch '^(?:_github_publish|\.git|\.artifacts)[\\/]'
    }
}
$launchers=@(Get-AuditLaunchers $root)
Check ($launchers.Count -eq 12) 'All 12 batch launchers are covered'
[void][IO.Directory]::CreateDirectory($fixture)
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'Local\Temp'))
$markerScript=@'
param([string]$Action,[string]$ExpectedUserSid)
$ErrorActionPreference='Stop'
[IO.File]::WriteAllText($env:TOOLKIT_AUDIT_MARKER,([pscustomobject]@{Path=$PSCommandPath;Action=$Action;ExpectedUserSid=$ExpectedUserSid;Args=@($args)} | ConvertTo-Json -Compress))
exit ([int]$env:TOOLKIT_AUDIT_EXIT)
'@
try {
    foreach ($folder in @('_github_publish','.git','.artifacts')) {
        $decoy=Join-Path $fixture ($folder+'\old.bat')
        [void][IO.Directory]::CreateDirectory((Split-Path $decoy -Parent))
        [IO.File]::WriteAllText($decoy,'@exit /b 99')
    }
    [IO.File]::WriteAllText((Join-Path $fixture 'START_TOOLKIT.bat'),'@exit /b 99')
    Check (@(Get-AuditLaunchers $fixture).Count -eq 1) 'Owned launcher inventory excludes source, packaging and backup staging trees'
    foreach ($launcher in $launchers) {
        $relative=$launcher.FullName.Substring($root.TrimEnd('\').Length).TrimStart('\')
        $destination=Join-Path $fixture $relative
        [void][IO.Directory]::CreateDirectory((Split-Path $destination -Parent))
        $content=[IO.File]::ReadAllText($launcher.FullName)
        $target=[regex]::Match($content,'(?i)-File\s+"%~dp0([^"\r\n]+\.ps1)"')
        Check $target.Success "$relative has an auditable PowerShell file target"
        if ($target.Groups[1].Value -in @('PC_Cleaner.ps1','PC_Fixer.ps1','PC_Optimizer.ps1','Fix_VR_PCVR.ps1','PC_Privacy.ps1')) {
            Check ($content -match '-ExpectedUserSid') "$relative requires the originating account identity for user-scoped actions"
        }
        if (-not $admin) {
            # Fixture-only gate bypass; actual CMD/path/PowerShell target args stay intact.
            $gate='(?m)^"%PS%" -NoProfile -Command "\$p=New-Object Security\.Principal\.WindowsPrincipal[^\r\n]*'
            $matches=@([regex]::Matches($content,$gate))
            Check ($matches.Count -eq $(if ($relative -eq 'START_TOOLKIT.bat') { 0 } else { 1 })) "$relative uses the known principal gate; no UAC is allowed in a fixture"
            $content=[regex]::Replace($content,$gate,'cmd /d /c exit 0')
        }
        [IO.File]::WriteAllText($destination,$content,[Text.Encoding]::ASCII)
        $targetPath=Join-Path (Split-Path $destination -Parent) $target.Groups[1].Value
        [IO.File]::WriteAllText($targetPath,$markerScript,(New-Object Text.UTF8Encoding($true)))
        foreach ($expectedCode in @(0,7)) {
            $marker=Join-Path $fixture ([guid]::NewGuid().ToString('N')+'.json')
            $start=New-Object Diagnostics.ProcessStartInfo
            $start.FileName=$env:ComSpec
            $start.Arguments='/d /v:on /s /c ""'+$destination+'" "'+$userSid+'""'
            $start.UseShellExecute=$false; $start.CreateNoWindow=$true
            $start.RedirectStandardInput=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
            $start.EnvironmentVariables['TOOLKIT_AUDIT_MARKER']=$marker
            $start.EnvironmentVariables['TOOLKIT_AUDIT_EXIT']=[string]$expectedCode
            $start.EnvironmentVariables['LOCALAPPDATA']=(Join-Path $fixture 'Local')
            $process=[Diagnostics.Process]::Start($start)
            try {
                $process.StandardInput.Close()
                $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
                if (-not $process.WaitForExit(20000)) { $process.Kill(); throw "Timed out: $relative" }
                $output=$stdout.Result+$stderr.Result
                Check ($process.ExitCode -eq $expectedCode) "$relative propagates marker exit $expectedCode; actual $($process.ExitCode): $output"
                Check (Test-Path -LiteralPath $marker) "$relative reaches only the harmless marker target"
                $record=Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
                $actualPath=[IO.Path]::GetFullPath($record.Path)
                $expectedPath=[IO.Path]::GetFullPath($targetPath)
                Check ($actualPath -eq $expectedPath) "$relative preserves the exact target file; actual=$actualPath; expected=$expectedPath; raw actual=$($record.Path); raw expected=$targetPath"
                $action=[regex]::Match($content,'-Action\s+(\w+)')
                if ($action.Success) { Check ($record.Action -eq $action.Groups[1].Value) "$relative preserves its action argument" }
                if ($content -match '-ExpectedUserSid') { Check ($record.ExpectedUserSid -eq $userSid) "$relative forwards the originating Windows identity" }
            } finally { $process.Dispose() }
        }
    }
    Write-Host "PASS: $checks launcher checks across $($launchers.Count) real CMD entrypoints (administrator token: $admin)"
    if (-not $admin) { Write-Host 'Fixture principal checks bypassed; interactive UAC was not exercised.' }
} finally {
    if ([IO.Path]::GetFileName($fixture) -like 'Toolkit_LauncherAudit_*') { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
}
