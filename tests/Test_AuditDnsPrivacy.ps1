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
        function Get-PrivacyServiceTargets { 'FixtureService' }
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
        $safeSnapshot=$snapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $safeSnapshot.Services=@(); $safeSnapshot.Tasks=@()
        foreach ($bad in @(
            [pscustomobject]@{Path=$key;Name='Outside';Exists=$false;Kind=$null;Value=$null},
            [pscustomobject]@{Path=$key;Name='Fixture';Exists='false';Kind=$null;Value=$null},
            [pscustomobject]@{Path=$key;Name='Fixture';Exists=$true;Kind=@('String');Value='text'},
            [pscustomobject]@{Path=$key;Name='Fixture';Exists=$true;Kind='DWord';Value=1.5},
            [pscustomobject]@{Path=$key;Name='Fixture';Exists=$true;Kind='Binary';Value=@(256)},
            [pscustomobject]@{Path=$key;Name='Fixture';Exists=$true;Kind='MultiString';Value=@(1)}
        )) {
            $invalid=$safeSnapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            $invalid.Registry=@($invalid.Registry)+@($bad)
            $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            Set-RegExact $key 'Fixture' 'preflight-marker' String
            Expect-Failure { Restore-LatestSnapshot } '*privacy registry*' 'Invalid later privacy registry records fail full preflight'
            Check ((Get-RegState $key 'Fixture').Value -eq 'preflight-marker') 'Registry preflight leaves earlier valid records unchanged'
        }
        foreach ($bad in @(
            [pscustomobject]@{Name='wuauserv';StartMode='Disabled';State='Stopped'},
            [pscustomobject]@{Name='FixtureService';StartMode=@('Auto');State='Stopped'},
            [pscustomobject]@{Name='FixtureService';StartMode='Auto';State='Stopped';DelayedAutoStart=[pscustomobject]@{Path=$key;Name='Fixture';Exists=$false;Kind=$null;Value=$null}}
        )) {
            $invalid=$safeSnapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $invalid.Services=@($bad)
            $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            Expect-Failure { Restore-LatestSnapshot } '*privacy*' 'Out-of-scope privacy service and delayed-start targets fail preflight'
            Check ((Get-RegState $key 'Fixture').Value -eq 'preflight-marker') 'Service preflight precedes every registry restore'
        }
        $invalid=$safeSnapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $invalid.Tasks=@([pscustomobject]@{Path='\Fixture\';Name='FixtureTask';Enabled='false'})
        $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        Expect-Failure { Restore-LatestSnapshot } '*privacy task*' 'String task flags cannot become truthy restore requests'
        $invalid.Tasks=@([pscustomobject]@{Path='\Fixture\';Name='OutsideTask';Enabled=$false})
        $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        Expect-Failure { Restore-LatestSnapshot } '*privacy task*' 'Out-of-scope privacy tasks fail before registry mutation'
        Check ((Get-RegState $key 'Fixture').Value -eq 'preflight-marker') 'Task preflight leaves earlier registry records unchanged'
        $invalid=$safeSnapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $invalid | Add-Member -NotePropertyName Schema -NotePropertyValue '1' -Force
        $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        Expect-Failure { Restore-LatestSnapshot } '*privacy backup schema*' 'Privacy schema must be an integer instead of a coercible string'
        & {
            $service=[pscustomobject]@{Name='FixtureService';StartMode='Disabled';State='Stopped'}
            $script:RestoreOrder=New-Object 'Collections.Generic.List[string]'
            function Get-CimInstance { $service }
            function Set-Service { param($Name,$StartupType) $script:RestoreOrder.Add($StartupType); $service.StartMode=$StartupType }
            function Start-Service { param($Name) if ($service.StartMode -eq 'Disabled') { throw 'SCM 1058' };$script:RestoreOrder.Add('Start');$service.State='Running' }
            $valid=$safeSnapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $valid.Registry=@();$valid.Services=@([pscustomobject]@{Name='FixtureService';StartMode='Disabled';State='Running'})
            $valid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            Restore-LatestSnapshot
            Check (($script:RestoreOrder -join ',') -eq 'Manual,Start,Disabled' -and $service.StartMode -eq 'Disabled' -and $service.State -eq 'Running') 'Disabled-but-running service restores via temporary Manual startup'
            $service.State='Stopped'
            function Start-Service { throw 'Injected start failure' }
            Expect-Failure { Restore-LatestSnapshot } '*Injected start failure*' 'Disabled-running restore propagates start failure'
            Check ($service.StartMode -eq 'Disabled') 'Failed temporary service start still restores disabled startup mode'
            $valid.Services[0] | Add-Member -NotePropertyName DelayedAutoStart -NotePropertyValue ([pscustomobject]@{Path='HKLM:\SYSTEM\CurrentControlSet\Services\FixtureService';Name='DelayedAutoStart';Exists=$false;Kind=$null;Value=$null})
            $valid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            function Restore-RegState { throw 'Injected delayed-start restore failure' }
            Expect-Failure { Restore-LatestSnapshot } '*Injected delayed-start restore failure*' 'Disabled-running restore propagates delayed-start failure'
            Check ($service.StartMode -eq 'Disabled') 'Failed delayed-start restore still restores disabled startup mode'
        }
        & {
            $writes=New-Object 'Collections.Generic.List[string]'
            function Ensure-Snapshot { }
            function Set-RegExact { param($Path,$Name,$Value,$Kind) $writes.Add("$Path|$Name|$Value") }
            Apply-BrowserTelemetryPolicies
            Check (@($writes | Where-Object { $_ -eq 'HKCU:\Software\Policies\Microsoft\Edge|DiagnosticData|0' }).Count -eq 1) 'Browser profile applies supported Edge DiagnosticData policy'
            Check (-not @($writes | Where-Object { $_ -like 'HKCU:\Software\Policies\Microsoft\Edge|MetricsReportingEnabled|*' -or $_ -like '*\Windows\DataCollection|*' }).Count) 'Browser profile avoids obsolete Edge metrics and preserves Windows diagnostic level'
        }
        $outside=Join-Path $fixture 'outside-privacy.json'; '{}' | Set-Content -LiteralPath $outside -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $outside -Encoding UTF8
        Expect-Failure { Get-LatestSnapshot } '*outside its snapshot folder*' 'Privacy pointer cannot select a foreign file'
        Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding UTF8
        $outsideRoot=Join-Path $fixture 'outside-privacy';[IO.Directory]::CreateDirectory($outsideRoot)|Out-Null
        '{}' | Set-Content -LiteralPath (Join-Path $outsideRoot 'snapshot.json') -Encoding UTF8
        $link=Join-Path $SnapshotRoot 'linked';New-Item -ItemType Junction -Path $link -Target $outsideRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value (Join-Path $link 'snapshot.json') -Encoding UTF8
        try { Expect-Failure { Get-LatestSnapshot } '*Linked privacy state path*' 'Privacy pointer rejects a real junction inside its snapshot folder' }
        finally { [IO.Directory]::Delete($link);Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding UTF8 }
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
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
    $v4Key=Join-Path $key 'NativeDnsV4';$v6Key=Join-Path $key 'NativeDnsV6'
    foreach($entry in @(@{Path=$v4Key;Value='192.0.2.1,192.0.2.2'},@{Path=$v6Key;Value='2001:db8::1,2001:db8::2'})) {
        New-Item -Path $entry.Path -Force|Out-Null
        New-ItemProperty -LiteralPath $entry.Path -Name NameServer -PropertyType String -Value ($entry.Value+([string][char]0*23)) -Force|Out-Null
    }
    & $network {
        param($v4Key,$v6Key)
        $script:NativeV4Key=$v4Key;$script:NativeV6Key=$v6Key
        function script:Test-Path {param($LiteralPath) $true}
        function script:Get-Item {param($LiteralPath) $path=if($LiteralPath -like '*\Tcpip6\*'){$script:NativeV6Key}else{$script:NativeV4Key};Microsoft.PowerShell.Management\Get-Item -LiteralPath $path -ErrorAction Stop}
    } $v4Key $v6Key
    try {
        $captured=Get-AdapterStaticDnsServers -Adapter ([pscustomobject]@{InterfaceGuid=[guid]::NewGuid()})
        Check (($captured.IPv4 -join ',') -ceq '192.0.2.1,192.0.2.2') 'Native REG_SZ IPv4 capture removes trailing NUL padding before splitting addresses'
        Check (($captured.IPv6 -join ',') -ceq '2001:db8::1,2001:db8::2') 'Native REG_SZ IPv6 capture removes trailing NUL padding before splitting addresses'
    } finally { & $network {Remove-Item Function:script:Test-Path,Function:script:Get-Item} }
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
        $valid=$snapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $valid.Adapters[0].StaticIPv4=@('9.9.9.9')
        foreach ($case in @('MissingAutomatic','WrongFamily','BadFlags','OutsideScope','DuplicateAdapter','StringSchema','StringTouched','ArrayComputer')) {
            $invalid=$valid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            switch($case) {
                'MissingAutomatic' { $invalid.Adapters[0].PSObject.Properties.Remove('Automatic') }
                'WrongFamily' { $invalid.Adapters[0].StaticIPv4=@('2001:db8::1') }
                'BadFlags' { $invalid.TouchedServers=@('192.0.2.1');$invalid.Encryption=@([pscustomobject]@{ServerAddress='192.0.2.1';DohTemplate='https://fixture.invalid/dns-query';AllowFallbackToUdp='false';AutoUpgrade=$true}) }
                'OutsideScope' { $invalid.Encryption=@([pscustomobject]@{ServerAddress='192.0.2.1';DohTemplate='https://fixture.invalid/dns-query';AllowFallbackToUdp=$false;AutoUpgrade=$true}) }
                'DuplicateAdapter' { $invalid.Adapters=@($invalid.Adapters[0],$invalid.Adapters[0]) }
                'StringSchema' { $invalid.Schema='4' }
                'StringTouched' { $invalid.TouchedServers='192.0.2.1' }
                'ArrayComputer' { $invalid.Computer=@($env:COMPUTERNAME) }
            }
            $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            $script:Writes=0
            Expect-Failure { Restore-Snapshot -Path $path } '*DNS*' "DNS $case backup fails preflight"
            Check ($script:Writes -eq 0) "DNS $case cannot modify encryption or adapters"
        }
        & {
            $otherGuid=[guid]::NewGuid()
            $invalid=$valid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            $other=$invalid.Adapters[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            $other.InterfaceGuid=$otherGuid.ToString(); $other.InterfaceIndex=8; $other.StaticIPv6=@('2001:db8::1')
            $invalid.Adapters=@($invalid.Adapters[0],$other)
            $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            function Get-NetAdapter { Get-Adapters; [pscustomobject]@{Name='Other NIC';ifIndex=8;InterfaceGuid=$otherGuid} }
            function Get-DnsClientServerAddress { param($InterfaceIndex) [pscustomobject]@{AddressFamily=2;ServerAddresses=@()}; if($InterfaceIndex -eq 7){[pscustomobject]@{AddressFamily=23;ServerAddresses=@()}} }
            $script:Writes=0
            Expect-Failure { Restore-Snapshot -Path $path } '*no longer exposes IPv6*' 'Later adapter family failure is preflighted before any DNS write'
            Check ($script:Writes -eq 0) 'Later adapter preflight preserves earlier adapters and global encryption entries'
        }
        $outside=Join-Path $fixture 'outside-dns.json'; '{}' | Set-Content -LiteralPath $outside -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $outside -Encoding UTF8
        Expect-Failure { Get-LatestSnapshot } '*outside its snapshot folder*' 'DNS pointer cannot select a foreign file'
        Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding UTF8
        $outsideRoot=Join-Path $fixture 'outside-dns';[IO.Directory]::CreateDirectory($outsideRoot)|Out-Null
        '{}' | Set-Content -LiteralPath (Join-Path $outsideRoot 'snapshot.json') -Encoding UTF8
        $link=Join-Path $SnapshotRoot 'linked';New-Item -ItemType Junction -Path $link -Target $outsideRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value (Join-Path $link 'snapshot.json') -Encoding UTF8
        try { Expect-Failure { Get-LatestSnapshot } '*Linked DNS state path*' 'DNS pointer rejects a real junction inside its snapshot folder' }
        finally { [IO.Directory]::Delete($link);Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding UTF8 }
        $padded=$valid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $padded.Adapters[0].StaticIPv4=@('9.9.9.9'+([string][char]0*23))
        $padded | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        $script:Writes=0;Restore-Snapshot -Path $path
        Check ($script:Writes -gt 0) 'Modern DNS backups with native trailing NUL padding remain recoverable'
        & {
            $legacy=$valid | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            $legacy.Schema=2;$legacy.PSObject.Properties.Remove('TouchedServers');$legacy.Adapters[0].PSObject.Properties.Remove('Automatic');$legacy.Adapters[0].PSObject.Properties.Remove('StaticIPv4');$legacy.Adapters[0].PSObject.Properties.Remove('StaticIPv6')
            $legacy.Adapters[0] | Add-Member -NotePropertyName IPv4 -NotePropertyValue @('194.242.2.2');$legacy.Adapters[0] | Add-Member -NotePropertyName IPv6 -NotePropertyValue @()
            $legacy.Encryption=@([pscustomobject]@{ServerAddress='194.242.2.2';DohTemplate='https://dns.mullvad.net/dns-query';AllowFallbackToUdp=$false;AutoUpgrade=$true})
            $legacy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            $script:LegacyAdded=@();$script:LegacyRemoved=@()
            function Add-DohEntry { param($Server,$Template,$Fallback,$Upgrade) $script:LegacyAdded+=@($Server) }
            function Remove-DohEntry { param($Server) $script:LegacyRemoved+=@($Server) }
            function Get-DohStateForServer { $legacy.Encryption[0] }
            function Get-StaticDnsServers { [pscustomobject]@{IPv4=@('194.242.2.2');IPv6=@()} }
            Restore-Snapshot -Path $path
            Check (($script:LegacyAdded -join ',') -eq '194.242.2.2' -and $script:LegacyRemoved.Count -eq 0) 'Schema2 Mullvad undo preserves captured entries without inferred global deletions'
            $legacy.Adapters[0].IPv4=@('194.242.2.2'+([string][char]0*23))
            $legacy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            Restore-Snapshot -Path $path
            Check ($script:LegacyAdded.Count -eq 2) 'Legacy DNS backups with native trailing NUL padding remain recoverable'
            $legacy.Adapters[0].IPv4=@('194.242.'+[char]0+'2.2')
            $legacy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
            Expect-Failure { Restore-Snapshot -Path $path } '*DNS*' 'Embedded NUL addresses remain invalid instead of being silently joined'
            Check ($script:LegacyAdded.Count -eq 2) 'Embedded NUL preflight prevents encryption mutations'
        }
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
