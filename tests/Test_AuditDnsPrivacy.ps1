#requires -version 5.1
param([string]$Root=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
$script:Checks=0
function Check([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:Checks++; Write-Host "PASS: $Message"
}
function Expect-Failure([scriptblock]$Action,[string]$Pattern,[string]$Message) {
    $failure=$null; try { & $Action | Out-Null } catch { $failure=$_.Exception.Message }
    Check ($null -ne $failure -and $failure -like $Pattern) $Message
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('Toolkit-DnsPrivacy-'+[guid]::NewGuid().ToString('N'))
$key='HKCU:\Software\WindowsPCToolkitAudit\'+[guid]::NewGuid().ToString('N')
[IO.Directory]::CreateDirectory($fixture)|Out-Null
try {
    & {
        $privacy=Join-Path $Root 'pc-privacy-guard\PC_Privacy.ps1'
        if (-not (Test-Path -LiteralPath $privacy)) { $privacy=Join-Path $Root 'Pc Privacy Guard\PC_Privacy.ps1' }
        $ast=[Management.Automation.Language.Parser]::ParseFile($privacy,[ref]$null,[ref]$null)
        Invoke-Expression ((@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) | ForEach-Object { $_.Extent.Text }) -join "`n")
        $Version='2.1.1'; $StateRoot=Join-Path $fixture 'Privacy'; $SnapshotRoot=Join-Path $StateRoot 'Snapshots'
        $PrivacyLog=Join-Path $fixture 'Logs\Privacy.log'; $PrivacyDebug=$false
        Write-PrivacyDiagnostic 'INFO' 'quiet-event'
        Check (-not (Test-Path -LiteralPath $PrivacyLog)) 'Privacy detailed events stay quiet by default'
        Write-PrivacyDiagnostic 'FAIL' ('f'*5000)
        $entry=Get-Content -LiteralPath $PrivacyLog -Raw -Encoding UTF8 | ConvertFrom-Json
        Check ($entry.Version -eq $Version -and $entry.Kind -eq 'FAIL' -and $entry.Message.Length -eq 4096) 'Privacy failures retain version and bounded cause while detailed logging is off'
        $PrivacyDebug=$true; Write-PrivacyDiagnostic 'DEBUG' 'debug-event'; $PrivacyDebug=$false
        Check (@(Get-Content -LiteralPath $PrivacyLog -Encoding UTF8).Count -eq 2) 'Privacy debug logging can be toggled on'
        $script:CurrentSnapshot=$null
        function Assert-Admin { }
        function Write-Status { param($Kind,$Message) if ($Kind -eq 'OK') { $script:SuccessMessages++ } }
        function Get-PrivacyTargets { @{P=$key;N='Fixture'} }
        function Get-TaskTargets { @{Path='\Fixture\';Name='FixtureTask'} }
        function Get-CimInstance { param($ClassName,$Filter) if ($script:FailInventory) { throw 'Injected service inventory failure' }; @() }
        function Get-ScheduledTask { param($TaskPath,$TaskName) if ($script:FailTasks) { throw 'Injected task inventory failure' }; @() }
        function Stop-Service { param($Name,[switch]$Force) throw 'Injected denied service stop' }
        function Start-Service { throw 'Unexpected service mutation' }
        function Set-Service { throw 'Unexpected service mutation' }
        function Disable-ScheduledTask { throw 'Injected denied task disable' }
        function Enable-ScheduledTask { throw 'Unexpected task mutation' }
        function Read-Host { 'n' }
        Check ((Get-Command Stop-Service).CommandType -eq 'Function' -and (Get-Command Set-Service).CommandType -eq 'Function') 'All privacy service mutations are intercepted before testing'
        Set-RegExact $key 'Fixture' '%TEMP%\literal' ExpandString
        foreach ($typedCase in @(@{Kind='Binary';Value=[byte[]]@(42)},@{Kind='Binary';Value=[byte[]]@()},@{Kind='MultiString';Value=[string[]]@('one')},@{Kind='MultiString';Value=[string[]]@()})) {
            Set-RegExact $key 'TypedFixture' $typedCase.Value $typedCase.Kind
            $before=Get-RegState $key 'TypedFixture'
            Set-RegExact $key 'TypedFixture' 'changed' String
            Restore-RegState ($before | ConvertTo-Json | ConvertFrom-Json)
            $actual=Get-RegState $key 'TypedFixture'
            Check ($actual.Kind -eq $typedCase.Kind -and (ConvertTo-Json -InputObject $actual.Value -Compress) -eq (ConvertTo-Json -InputObject $typedCase.Value -Compress)) "Privacy typed restore preserves $($typedCase.Kind) arrays of length $($typedCase.Value.Count)"
        }
        $path=New-PrivacySnapshot 'Disposable registry round-trip'
        $snapshot=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        Check ($snapshot.Computer -eq $env:COMPUTERNAME -and $snapshot.User -eq [Security.Principal.WindowsIdentity]::GetCurrent().Name -and $snapshot.UserSid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) 'Fresh privacy backup records the identity required by undo'
        Set-RegExact $key 'Fixture' 'changed' String
        Restore-LatestSnapshot
        $actual=Get-RegState $key 'Fixture'
        Check ($actual.Kind -eq 'ExpandString' -and $actual.Value -eq '%TEMP%\literal') 'Fresh privacy snapshot restores exact disposable HKCU type and literal value'
        $script:FailInventory=$true
        Expect-Failure { New-PrivacySnapshot } '*Injected service inventory failure*' 'Service inventory failures abort privacy backups'
        $script:FailInventory=$false; $script:FailTasks=$true
        Expect-Failure { New-PrivacySnapshot } '*Injected task inventory failure*' 'Task inventory failures abort privacy backups'
        $script:FailTasks=$false
        function Get-CimInstance { param($ClassName,$Filter) [pscustomobject]@{Name='FixtureService';StartMode='Auto';State='Stopped'} }
        function Get-ScheduledTask { param($TaskPath,$TaskName) [pscustomobject]@{TaskPath='\Fixture\';TaskName='FixtureTask';State='Ready';Settings=[pscustomobject]@{Enabled=$false}} }
        $capturedPath=New-PrivacySnapshot 'Capture service and task flags'
        $captured=Get-Content -LiteralPath $capturedPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Check ($captured.Services[0].DelayedAutoStart.Name -eq 'DelayedAutoStart' -and -not $captured.Tasks[0].Enabled) 'Service backup includes delayed startup and task backup uses Settings.Enabled'
        function Get-CimInstance { param($ClassName,$Filter) [pscustomobject]@{Name='FixtureService';StartMode='Auto';State='Start Pending'} }
        Expect-Failure { New-PrivacySnapshot } '*not in a restorable state*' 'Transient service state aborts snapshots before privacy changes'
        Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding UTF8
        $snapshot.UserSid='S-1-5-21-0-0-0-99999'; $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        Set-RegExact $key 'Fixture' 'foreign-guard' String
        Expect-Failure { Restore-LatestSnapshot } '*another computer or user*' 'Foreign-user backups fail before registry mutation'
        Check ((Get-RegState $key 'Fixture').Value -eq 'foreign-guard') 'Foreign-user preflight preserves registry state'
        $snapshot.PSObject.Properties.Remove('Computer'); $snapshot.PSObject.Properties.Remove('User'); $snapshot.PSObject.Properties.Remove('UserSid')
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        Expect-Failure { Restore-LatestSnapshot } '*Legacy privacy restore cancelled*' 'Legacy identity-less backup requires explicit confirmation'
        function Read-Host { 'y' }
        Restore-LatestSnapshot
        Check ((Get-RegState $key 'Fixture').Value -eq '%TEMP%\literal') 'Confirmed legacy backup remains recoverable'
        $snapshot.Services=@([pscustomobject]@{Name='FixtureService';StartMode='Auto';State='Running'})
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        $script:CurrentSnapshot=$path; $script:SuccessMessages=0
        Expect-Failure { Apply-StrictTelemetryServiceProfile } '*Injected denied service stop*' 'Strict privacy service failures propagate'
        Check ($script:SuccessMessages -eq 0) 'Strict privacy does not print success after denied service mutation'
        $snapshot.Services=@(); $snapshot.Tasks=@([pscustomobject]@{Path='\Fixture\';Name='FixtureTask';Enabled=$true})
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        Expect-Failure { Apply-StrictTelemetryServiceProfile } '*Injected denied task disable*' 'Strict privacy task failures propagate'
        Expect-Failure { Set-RegExact $key 'Fixture' 'bad' 'UnknownType' } '*Unsupported registry value type*' 'Unsupported registry kinds cannot silently become strings'
        Set-RegExact $key 'Fixture' 'CaseOnly' String
        function New-ItemProperty { }
        Expect-Failure { Set-RegExact $key 'Fixture' 'unwritten' String } '*Registry write read-back failed*' 'Ignored registry writes cannot claim success'
        Expect-Failure { Set-RegExact $key 'Fixture' 'caseonly' String } '*Registry write read-back failed*' 'Registry read-back preserves exact string case'
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$privacy+'" -ExpectedUserSid S-1-5-21-0-0-0-99999'
        $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
        $foreignState=Join-Path $fixture 'ForeignProgramData'
        $psi.EnvironmentVariables['ProgramData']=$foreignState
        $psi.EnvironmentVariables['LOCALAPPDATA']=Join-Path $fixture 'ForeignLocalAppData'
        $psi.EnvironmentVariables['WINDOWS_PC_TOOLKIT_DEBUG']='0'
        $process=New-Object Diagnostics.Process; $process.StartInfo=$psi
        try {
            [void]$process.Start()
            $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(15000)) { $process.Kill(); throw 'Foreign-user entrypoint test did not exit.' }
            $text=$stdout.Result+$stderr.Result
            Check ($process.ExitCode -ne 0 -and $text -match 'elevated as a different Windows user' -and -not (Test-Path -LiteralPath $foreignState)) 'Native Privacy entrypoint rejects another user SID before state initialization'
        } finally { $process.Dispose() }
    }

    Import-Module (Join-Path $Root 'Modules\Network.State.psm1') -Force
    $network=Get-Module Network.State
    & $network {
        $script:Writes=0
        function script:Get-DnsClientServerAddress { param($InterfaceIndex) [pscustomobject]@{AddressFamily=2} }
        function script:Set-DnsClientServerAddress { param($InputObject,$ServerAddresses,[switch]$ResetServerAddresses) $script:Writes++ }
    }
    Check (& $network { (Get-Command Set-DnsClientServerAddress).CommandType -eq 'Function' }) 'Network writes are intercepted before testing'
    Expect-Failure { Set-AdapterDnsFamilies -Index 7 -IPv4 @('9.9.9.9') -IPv6 @('2620:fe::fe') } '*does not expose address family 23*' 'Missing IPv6 family is rejected during preflight'
    Check ((& $network { $script:Writes }) -eq 0) 'Missing IPv6 family cannot partially overwrite IPv4'
    & $network { function script:Get-DnsClientServerAddress { @() } }
    Expect-Failure { Set-AdapterDnsFamilies -Index 7 } '*exposes no DNS address families*' 'Missing adapter DNS inventory cannot report a successful reset'

    & {
        $dns=Join-Path $Root 'dns-encrypted-doh\DNS_Manager.ps1'
        if (-not (Test-Path -LiteralPath $dns)) { $dns=Join-Path $Root 'Pc Privacy Guard\Optional DNS\DNS_Manager.ps1' }
        . $dns -Action Library
        $DnsLog=Join-Path $fixture 'Logs\DNS.log'; $DnsDebug=$false
        Write-DnsDiagnostic 'INFO' 'quiet-event'
        Check (-not (Test-Path -LiteralPath $DnsLog)) 'DNS detailed events stay quiet by default'
        Write-DnsDiagnostic 'FAIL' ('f'*5000)
        $entry=Get-Content -LiteralPath $DnsLog -Raw -Encoding UTF8 | ConvertFrom-Json
        Check ($entry.Version -eq $Version -and $entry.Kind -eq 'FAIL' -and $entry.Message.Length -eq 4096) 'DNS failures retain version and bounded cause while detailed logging is off'
        $DnsDebug=$true; Write-DnsDiagnostic 'DEBUG' 'debug-event'; $DnsDebug=$false
        Check (@(Get-Content -LiteralPath $DnsLog -Encoding UTF8).Count -eq 2) 'DNS debug logging can be toggled on'
        Check (($Providers.Quad9.V6 -join ',') -eq '2620:fe::fe,2620:fe::9') 'Quad9 IPv6 addresses match the official Secure service table'
        $StateRoot=Join-Path $fixture 'DNS'; $SnapshotRoot=Join-Path $StateRoot 'Snapshots'
        $script:Entries=@{}; $script:Writes=0; $script:Rollback=0
        function Assert-Admin { }
        function Write-Status { }
        function Get-DnsClientDohServerAddress { @($script:Entries.Values) }
        function Set-DnsClientDohServerAddress { param($ServerAddress,$DohTemplate,$AllowFallbackToUdp,$AutoUpgrade) $script:Writes++ }
        function Add-DnsClientDohServerAddress { param($ServerAddress,$DohTemplate,$AllowFallbackToUdp,$AutoUpgrade) $script:Writes++ }
        function Remove-DnsClientDohServerAddress { param($ServerAddress) $script:Writes++ }
        function Set-AdapterDnsFamilies { param($Index,$IPv4,$IPv6) $script:Writes++ }
        function Clear-DnsClientCache { }
        $guid=[guid]::NewGuid()
        function Get-Adapters { [pscustomobject]@{Name='Fixture NIC';ifIndex=7;InterfaceGuid=$guid} }
        function Get-NetAdapter { Get-Adapters }
        function Get-StaticDnsServers { param($Adapter) [pscustomobject]@{IPv4=@('9.9.9.9');IPv6=@()} }
        function Get-DnsClientServerAddress { param($InterfaceIndex) [pscustomobject]@{AddressFamily=2;ServerAddresses=@('9.9.9.9')}; [pscustomobject]@{AddressFamily=23;ServerAddresses=@()} }
        Check ((Get-Command Add-DnsClientDohServerAddress).CommandType -eq 'Function' -and (Get-Command Set-AdapterDnsFamilies).CommandType -eq 'Function') 'All DNS mutations are intercepted before testing'
        Expect-Failure { Add-DohEntry '192.0.2.1' 'https://fixture.invalid/dns-query' } '*DoH write read-back failed*' 'Ignored DoH writes fail verification'
        $script:Entries['192.0.2.1']=[pscustomobject]@{ServerAddress='192.0.2.1';DohTemplate='https://fixture.invalid/dns-query';AllowFallbackToUdp=$false;AutoUpgrade=$true}
        Expect-Failure { Remove-DohEntry '192.0.2.1' } '*DoH removal read-back failed*' 'Ignored DoH removals fail verification'
        $path=New-DnsSnapshot -TouchedServers @()
        $snapshot=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $snapshot.Adapters[0].StaticIPv4=@(); $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        $script:Writes=0
        Expect-Failure { Restore-Snapshot -Path $path } '*inconsistent address modes*' 'Malformed static DNS backup fails preflight'
        Check ($script:Writes -eq 0) 'Malformed backup cannot modify encryption or adapters'
        function Restore-Snapshot { param($Path) $script:Rollback++ }
        Expect-Failure { Reset-Dhcp } '*Automatic DNS read-back failed*' 'DHCP reset cannot claim success when static DNS remains'
        Check ($script:Rollback -eq 1) 'DHCP reset verification failure attempts prior-state rollback'
        Set-Content -LiteralPath (Join-Path $StateRoot 'current_provider.json') -Value '{broken' -Encoding UTF8
        Expect-Failure { New-DnsSnapshot } '*' 'Unreadable current-provider state aborts the DNS snapshot'
    }
    Write-Host "DNS/privacy audit checks passed: $script:Checks"
} finally {
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
    Remove-Module Network.State -ErrorAction SilentlyContinue
}
