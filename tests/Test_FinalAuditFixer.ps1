#requires -version 5.1
param([string]$FixerPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if (-not $FixerPath) {
    $FixerPath=Join-Path $root 'pc-corruption-fixer\PC_Fixer.ps1'
    if (-not (Test-Path -LiteralPath $FixerPath)) { $FixerPath=Join-Path $root 'Pc Corruption Fixer\PC_Fixer.ps1' }
}
$fixture=Join-Path $env:TEMP ('ToolkitFinalFixer_'+[guid]::NewGuid().ToString('N'))
$checks=0
function Check([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "FAIL: $Message" }; $script:checks++ }
function Load-FixerFunctions([string[]]$Names) {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($FixerPath,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Fixer parser failed.' }
    $definitions=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $Names},$false))
    if ($definitions.Count -ne $Names.Count) { throw 'Requested audit functions are missing.' }
    $text=($definitions | ForEach-Object { $_.Extent.Text }) -join "`n"
    [Management.Automation.Language.Parser]::ParseInput($text,$FixerPath,[ref]$tokens,[ref]$errors).GetScriptBlock()
}
[void][IO.Directory]::CreateDirectory($fixture)
try {
    function Write-Host {}
    & {
        . (Load-FixerFunctions @('Invoke-CacheCleanup','Invoke-IconCacheRebuild','Assert-FixerUnlinkedPath'))
        $script:Results=[ordered]@{};$script:Messages=New-Object Collections.ArrayList
        $script:ShellRunning=$true;$script:ShellStops=0;$script:FailRestart=$false;$script:FailDelivery=$false
        function Write-StepHeader {}
        function Write-Status { param($Type,$Text) [void]$script:Messages.Add("$Type $Text") }
        function Get-Elapsed { 'fixture' }
        function Invoke-Native-Quiet { [pscustomobject]@{ExitCode=0;Output='intercepted DNS flush'} }
        function Import-Module {}
        function Invoke-SuiteTempCleanup { 'intercepted temp cleanup' }
        function Delete-DeliveryOptimizationCache { [CmdletBinding()]param([switch]$Force) if($script:FailDelivery){throw 'Injected DO denial'} }
        function Read-Host { 'y' }
        function Get-Process { [CmdletBinding()]param($Name) if($script:ShellRunning){[pscustomobject]@{SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId}} }
        function Stop-Process { [CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject,[switch]$Force) process { if($null -ne $InputObject){$script:ShellRunning=$false;$script:ShellStops++} } }
        function Start-Process { [CmdletBinding()]param($FilePath) if($script:FailRestart){throw 'Injected Explorer restart denial'};$script:ShellRunning=$true }
        function Start-Sleep {}
        $oldLocal=$env:LOCALAPPDATA;$link=$null
        try {
            $env:LOCALAPPDATA=Join-Path $fixture "Local [1] ' literal"
            $outside=Join-Path $fixture 'UnrelatedOwnedFiles'
            [void][IO.Directory]::CreateDirectory($outside)
            [void][IO.Directory]::CreateDirectory((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows'))
            $link=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
            New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop | Out-Null
            $thumb=Join-Path $outside 'thumbcache_fixture.db';$icon=Join-Path $outside 'iconcache_fixture.db'
            [IO.File]::WriteAllText($thumb,'unrelated thumbnail-named data');[IO.File]::WriteAllText($icon,'unrelated icon-named data')
            Invoke-CacheCleanup
            Check (Test-Path -LiteralPath $thumb) 'Safe repair cleanup preserves thumbnail-named files behind a junction'
            Check ($script:Results['Caches'] -like 'WARN*') 'Refused linked thumbnail cleanup remains a warning'
            Invoke-IconCacheRebuild
            Check ((Test-Path -LiteralPath $icon) -and (Test-Path -LiteralPath $thumb)) 'Icon rebuild preserves all files behind a linked cache root'
            Check ($script:ShellStops -eq 0 -and $script:Results['IconCache'] -like 'WARN*') 'Linked icon cache is refused before Explorer is stopped'
            [IO.Directory]::Delete($link,$false);$link=$null
            $cache=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
            [void][IO.Directory]::CreateDirectory($cache)
            $ordinary=Join-Path $cache 'thumbcache_ordinary.db';[IO.File]::WriteAllText($ordinary,'owned cache')
            Invoke-CacheCleanup
            Check (-not(Test-Path -LiteralPath $ordinary)) 'Unlinked cache cleanup works in a literal bracket/apostrophe path'
            Check ($script:Results['Caches'] -like 'PASS*') 'Successful guarded cleanup has a successful result'
            $script:FailDelivery=$true
            Invoke-CacheCleanup
            Check ($script:Results['Caches'] -like 'WARN*') 'Failed Delivery Optimization request cannot become cache success'
            $script:FailDelivery=$false
            $ordinary=Join-Path $cache 'iconcache_ordinary.db';[IO.File]::WriteAllText($ordinary,'owned cache')
            Invoke-IconCacheRebuild
            Check (-not(Test-Path -LiteralPath $ordinary)) 'Icon rebuild uses literal parent paths and removes ordinary cache files'
            Check ($script:Results['IconCache'] -like 'PASS*' -and $script:ShellRunning) 'Icon rebuild verifies Explorer is running before success'
            $script:FailRestart=$true
            Invoke-IconCacheRebuild
            Check ($script:Results['IconCache'] -like 'WARN*' -and -not $script:ShellRunning) 'Failed Explorer restart is reported instead of a successful rebuild'
        } finally {
            $env:LOCALAPPDATA=$oldLocal
            if ($link -and (Test-Path -LiteralPath $link)) { [IO.Directory]::Delete($link,$false) }
        }
    }
    & {
        . (Load-FixerFunctions @('Invoke-CreateRestorePoint'))
        $script:Results=[ordered]@{};$script:Version='test';$script:HasFailure=$false;$script:Created=$false;$script:CheckpointMode='Warn';$script:Description=$null
        function Write-StepHeader {};function Write-Status {};function Get-Elapsed { 'fixture' }
        function Enable-ComputerRestore { [CmdletBinding()]param($Drive) }
        function Get-ComputerRestorePoint { [CmdletBinding()]param() [pscustomobject]@{SequenceNumber=1;Description='Previous'};if($script:Created){[pscustomobject]@{SequenceNumber=2;Description=$script:Description}} }
        function Checkpoint-Computer { [CmdletBinding()]param($Description,$RestorePointType) $script:Description=$Description;switch($script:CheckpointMode){'Warn'{Write-Warning 'Restore point frequency limit'}'Success'{$script:Created=$true}} }
        Invoke-CreateRestorePoint
        Check ($script:Results['RestorePt'] -like 'FAIL*') 'Restore-point throttle warning cannot claim success'
        $script:CheckpointMode='NoOp'
        Invoke-CreateRestorePoint
        Check ($script:Results['RestorePt'] -like 'FAIL*') 'Silent restore-point no-op fails when sequence inventory is unchanged'
        $script:CheckpointMode='Success'
        Invoke-CreateRestorePoint
        Check ($script:Results['RestorePt'] -like 'PASS*' -and $script:Created) 'A newly inventoried matching restore point is accepted'
    }
    & {
        . (Load-FixerFunctions @('New-AiFeatureSnapshot','Set-AiFeaturePrivacyProfile','Save-FixerSnapshot','Assert-FixerUnlinkedPath'))
        $script:Results=[ordered]@{};$script:PolicyWrites=0;$script:HasFailure=$false
        $oldProgramData=$env:ProgramData
        try {
            $env:ProgramData=Join-Path $fixture 'PolicyState'
            function Write-Status {}
            function Get-AiFeaturePolicyDefinitions { [pscustomobject]@{Path='HKCU:\Software\WindowsPCToolkitTests\MockedOnly';Name='Fixture';Type='DWord';Value=1;Label='mocked'} }
            function Get-AiRegistryEntryState {param($Path,$Name) [pscustomobject]@{Path=$Path;Name=$Name;PathExisted=$false;ValueExisted=$false;Value=$null;Kind=$null} }
            function New-ItemProperty { [CmdletBinding()]param($Path,$Name,$PropertyType,$Value,[switch]$Force) $script:PolicyWrites++ }
            function Get-ItemPropertyValue { [CmdletBinding()]param($LiteralPath,$Name) 1 }
            $first=New-AiFeatureSnapshot;$second=New-AiFeatureSnapshot
            Check ($first -cne $second -and (Test-Path -LiteralPath $first) -and (Test-Path -LiteralPath $second)) 'Rapid AI snapshots retain distinct verified JSON files'
            Check ((Get-Content -LiteralPath $first -Raw | ConvertFrom-Json).Entries.Count -eq 1) 'Saved AI recovery snapshot contains captured registry state'
            function Set-Content { [CmdletBinding()]param([Parameter(ValueFromPipeline)]$Value,$LiteralPath,$Encoding) process { Write-Error 'Injected nonterminating backup denial' -ErrorId FinalAuditBackupDenied } }
            $ErrorActionPreference='Continue'
            $success=Set-AiFeaturePrivacyProfile
            Check (-not $success -and $script:PolicyWrites -eq 0) 'AI backup write failure blocks all policy mutations under default Continue preference'
            Check (@(Get-ChildItem -LiteralPath (Split-Path $first -Parent) -Filter '*.tmp').Count -eq 0) 'Failed snapshot write exposes no partial recovery file'
        } finally { $env:ProgramData=$oldProgramData }
    }
    & {
        . (Load-FixerFunctions @('Backup-NetworkDnsState','Invoke-NetworkReset','Save-FixerSnapshot','Assert-FixerUnlinkedPath'))
        $script:Results=[ordered]@{};$script:NativeCalls=New-Object Collections.ArrayList
        $oldProgramData=$env:ProgramData
        try {
            $env:ProgramData=Join-Path $fixture 'NetworkState'
            function Write-StepHeader {};function Write-Status {};function Get-Elapsed { 'fixture' }
            function Get-NetAdapter { [CmdletBinding()]param() [pscustomobject]@{Name='Mock NIC';ifIndex=42;InterfaceGuid=[guid]'11111111-1111-1111-1111-111111111111'} }
            function Get-DnsClientServerAddress { [CmdletBinding()]param($InterfaceIndex) [pscustomobject]@{AddressFamily=2;ServerAddresses=@('9.9.9.9')} }
            function Get-StaticNetworkDnsServers {param($Adapter) [pscustomobject]@{IPv4=@('9.9.9.9');IPv6=@()} }
            function Get-DnsClientDohServerAddress { [CmdletBinding()]param() }
            function Invoke-Native-Quiet {param($FilePath,$ArgumentList) [void]$script:NativeCalls.Add($FilePath);throw 'Native mutation must not run after backup failure' }
            $first=Backup-NetworkDnsState;$second=Backup-NetworkDnsState
            Check ($first -cne $second -and (Test-Path -LiteralPath $first) -and (Test-Path -LiteralPath $second)) 'Rapid DNS snapshots retain distinct verified JSON files'
            $saved=Get-Content -LiteralPath $first -Raw | ConvertFrom-Json
            Check ($saved.Adapters[0].StaticIPv4[0] -eq '9.9.9.9' -and @($saved.DoH).Count -eq 0) 'DNS backup round-trips static family state and empty DoH inventory'
            function Set-Content { [CmdletBinding()]param([Parameter(ValueFromPipeline)]$Value,$LiteralPath,$Encoding) process { Write-Error 'Injected nonterminating backup denial' -ErrorId FinalAuditBackupDenied } }
            $ErrorActionPreference='Continue'
            Invoke-NetworkReset
            Check ($script:NativeCalls.Count -eq 0) 'DNS backup write failure blocks flush/Winsock/TCP-IP/firewall mutations'
            Check ($script:Results['Network'] -like 'FAIL - Backup failed*') 'Failed DNS backup is an explicit aborted reset result'
        } finally { $env:ProgramData=$oldProgramData }
    }
    & {
        . (Load-FixerFunctions @('Restore-AiFeatureSnapshot','Get-AiRegistryEntryState','Get-LatestAiFeatureSnapshot','Assert-FixerUnlinkedPath'))
        $script:Results=[ordered]@{};$script:HasFailure=$false
        $script:AllowedKey='HKCU:\Software\WindowsPCToolkitTests\'+[guid]::NewGuid().ToString('N')
        $oldProgramData=$env:ProgramData;$link=$null
        try {
            $env:ProgramData=Join-Path $fixture 'RestoreState'
            function Write-Status {}
            function Get-AiFeaturePolicyDefinitions { foreach($name in @('First','Second')){[pscustomobject]@{Path=$script:AllowedKey;Name=$name}} }
            New-Item -Path $script:AllowedKey -Force | Out-Null
            $snapshot=[pscustomobject]@{Schema=1;Computer=$env:COMPUTERNAME;User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Entries=@(
                [pscustomobject]@{Path=$script:AllowedKey;Name='First';PathExisted=$true;ValueExisted=$true;Value='original';Kind='String'},
                [pscustomobject]@{Path=$script:AllowedKey;Name='Second';PathExisted=$true;ValueExisted=$true;Value=1;Kind='DWord'}
            )}
            $baseline=$snapshot|ConvertTo-Json -Depth 8
            $path=Join-Path $fixture 'AI-restore.json'
            foreach($case in @('BadNumeric','BadArray','Duplicate','MissingValue','InconsistentExistence')){
                $snapshot=$baseline|ConvertFrom-Json
                switch($case){
                    BadNumeric {$snapshot.Entries[1].Value='not an integer'}
                    BadArray {$snapshot.Entries[1].Kind='Binary';$snapshot.Entries[1].Value=@(256)}
                    Duplicate {$snapshot.Entries=@($snapshot.Entries[0],$snapshot.Entries[0])}
                    MissingValue {$snapshot.Entries[1].PSObject.Properties.Remove('Value')}
                    InconsistentExistence {$snapshot.Entries[1].PathExisted=$false}
                }
                $snapshot|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
                New-ItemProperty -LiteralPath $script:AllowedKey -Name First -PropertyType String -Value newer -Force|Out-Null
                $blocked=$false;try{Restore-AiFeatureSnapshot $path|Out-Null}catch{$blocked=$true}
                Check $blocked "$case AI restore state is rejected"
                Check ((Get-ItemPropertyValue -LiteralPath $script:AllowedKey -Name First) -ceq 'newer') "$case is rejected before the first policy write"
            }
            $baseline|Set-Content -LiteralPath $path -Encoding UTF8
            Check (Restore-AiFeatureSnapshot $path) 'Valid AI snapshot still restores after full preflight'
            $outside=Join-Path $fixture 'LinkedAiFiles';[void][IO.Directory]::CreateDirectory($outside)
            $root=Join-Path $env:ProgramData 'WindowsPCToolkit\PCFixer\AIFeatureSnapshots'
            [void][IO.Directory]::CreateDirectory((Split-Path $root -Parent))
            $link=$root;New-Item -ItemType Junction -Path $link -Target $outside|Out-Null
            $linkedPath=Join-Path $outside 'ai_features_fixture.json';[IO.File]::WriteAllText($linkedPath,$baseline)
            $blocked=$false;try{Get-LatestAiFeatureSnapshot|Out-Null}catch{$blocked=$true}
            Check $blocked 'Latest AI snapshot lookup rejects a linked snapshot root'
            New-ItemProperty -LiteralPath $script:AllowedKey -Name First -PropertyType String -Value newer -Force|Out-Null
            $blocked=$false;try{Restore-AiFeatureSnapshot (Join-Path $link 'ai_features_fixture.json')|Out-Null}catch{$blocked=$true}
            Check ($blocked -and (Get-ItemPropertyValue -LiteralPath $script:AllowedKey -Name First) -ceq 'newer') 'Explicit linked AI snapshot restore fails before policy writes'
        } finally {
            $env:ProgramData=$oldProgramData
            Remove-Item -LiteralPath $script:AllowedKey -Recurse -Force -ErrorAction SilentlyContinue
            if($link -and (Test-Path -LiteralPath $link)){[IO.Directory]::Delete($link,$false)}
        }
    }
    & {
        . (Load-FixerFunctions @('Invoke-OrphanServiceScan','Assert-FixerUnlinkedPath'))
        $script:Results=[ordered]@{};$script:NativeCalls=0
        $oldProgramData=$env:ProgramData;$link=$null
        try {
            $env:ProgramData=Join-Path $fixture 'ServiceState'
            function Write-StepHeader {};function Write-Status {};function Get-Elapsed {'fixture'};function Import-Module {};function Read-Host {'y'}
            function Get-CimInstance { [CmdletBinding()]param($ClassName,$Filter) [pscustomobject]@{Name='MockService';DisplayName='Mock service';PathName='C:\MissingMockService.exe';State='Stopped';StartMode='Manual'} }
            function Get-ServiceExePath {param($Path) $Path}
            function Test-SuiteMissingExecutable {$true}
            function Invoke-Native-Quiet {param($FilePath,$ArgumentList) $script:NativeCalls++;if($FilePath -eq 'reg.exe'){[IO.File]::WriteAllText($ArgumentList[2],'owned mock export')};[pscustomobject]@{ExitCode=0} }
            $outside=Join-Path $fixture 'ServiceOutside';[void][IO.Directory]::CreateDirectory($outside)
            $link=Join-Path $env:ProgramData 'WindowsPCToolkit\PCFixer\ServiceBackups'
            [void][IO.Directory]::CreateDirectory((Split-Path $link -Parent))
            New-Item -ItemType Junction -Path $link -Target $outside|Out-Null
            $blocked=$false;try{Invoke-OrphanServiceScan}catch{$blocked=$true}
            Check ($blocked -and $script:NativeCalls -eq 0) 'Linked orphan-service backup directory blocks export and deletion'
            Check (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'Orphan-service backup does not write through a junction'
        } finally {$env:ProgramData=$oldProgramData;if($link -and(Test-Path -LiteralPath $link)){[IO.Directory]::Delete($link,$false)}}
    }
    & {
        . (Load-FixerFunctions @('Restore-NetworkDnsState','Assert-FixerUnlinkedPath'))
        $oldProgramData=$env:ProgramData;$link=$null
        try {
            $env:ProgramData=Join-Path $fixture 'DnsRestoreState'
            $stateRoot=Join-Path $env:ProgramData 'WindowsPCToolkit\PCFixer\NetworkSnapshots';[void][IO.Directory]::CreateDirectory($stateRoot)
            $path=Join-Path $stateRoot 'network_dns_fixture.json'
            $guid1=[guid]::NewGuid().ToString();$guid2=[guid]::NewGuid().ToString()
            $script:MockAdapters=@([pscustomobject]@{Name='First';InterfaceGuid=[guid]$guid1;ifIndex=41},[pscustomobject]@{Name='Second';InterfaceGuid=[guid]$guid2;ifIndex=42})
            $script:NetworkWrites=0;$script:Restored=@{};$script:MockDoH=@()
            function Write-Status {};function Import-Module {}
            function Get-NetAdapter { [CmdletBinding()]param() $script:MockAdapters }
            function Get-DnsClientServerAddress { [CmdletBinding()]param($InterfaceIndex) @([pscustomobject]@{AddressFamily=2},[pscustomobject]@{AddressFamily=23}) }
            function Set-AdapterDnsFamilies {param($Index,$IPv4,$IPv6) $script:NetworkWrites++;$script:Restored[$Index]=[pscustomobject]@{IPv4=@($IPv4);IPv6=@($IPv6)} }
            function Get-StaticNetworkDnsServers {param($Adapter) $script:Restored[[int]$Adapter.ifIndex] }
            function Get-DnsClientDohServerAddress { [CmdletBinding()]param() $script:MockDoH }
            function Add-DnsClientDohServerAddress { [CmdletBinding()]param($ServerAddress,$DohTemplate,$AllowFallbackToUdp,$AutoUpgrade) $script:NetworkWrites++;$script:MockDoH+=@([pscustomobject]@{ServerAddress=$ServerAddress;DohTemplate=$DohTemplate;AllowFallbackToUdp=$AllowFallbackToUdp;AutoUpgrade=$AutoUpgrade}) }
            function Set-DnsClientDohServerAddress { [CmdletBinding()]param($ServerAddress,$DohTemplate,$AllowFallbackToUdp,$AutoUpgrade) $script:NetworkWrites++;throw 'Unexpected existing DoH fixture' }
            $snapshot=[pscustomobject]@{Schema=2;Adapters=@(
                [pscustomobject]@{Name='First';InterfaceGuid=$guid1;Automatic=$false;StaticIPv4=@('9.9.9.9');StaticIPv6=@()},
                [pscustomobject]@{Name='Second';InterfaceGuid=$guid2;Automatic=$true;StaticIPv4=@();StaticIPv6=@()}
            );DoH=@([pscustomobject]@{ServerAddress='9.9.9.9';DohTemplate='https://dns.quad9.net/dns-query';AllowFallbackToUdp=$false;AutoUpgrade=$true})}
            $baseline=$snapshot|ConvertTo-Json -Depth 8
            foreach($case in @('Schema','MissingAdapter','BadFamily','EmbeddedNul','ScalarAddress','BadMode','BadDoHFlag','BadTemplate','DuplicateAdapter','DuplicateDoH')){
                $snapshot=$baseline|ConvertFrom-Json
                switch($case){
                    Schema {$snapshot.Schema='2'}
                    MissingAdapter {$snapshot.Adapters[1].InterfaceGuid=[guid]::NewGuid().ToString()}
                    BadFamily {$snapshot.Adapters[1].StaticIPv4=@('::1');$snapshot.Adapters[1].Automatic=$false}
                    EmbeddedNul {$snapshot.Adapters[0].StaticIPv4=@("9.9.9.9`0invalid")}
                    ScalarAddress {$snapshot.Adapters[0].StaticIPv4="9.9.9.9`0"}
                    BadMode {$snapshot.Adapters[1].Automatic='false'}
                    BadDoHFlag {$snapshot.DoH[0].AutoUpgrade='false'}
                    BadTemplate {$snapshot.DoH[0].DohTemplate='http://dns.quad9.net/dns-query'}
                    DuplicateAdapter {$snapshot.Adapters=@($snapshot.Adapters[0],$snapshot.Adapters[0])}
                    DuplicateDoH {$snapshot.DoH=@($snapshot.DoH[0],$snapshot.DoH[0])}
                }
                $snapshot|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
                $script:NetworkWrites=0
                Check (-not(Restore-NetworkDnsState $path)) "$case DNS recovery snapshot is rejected"
                Check ($script:NetworkWrites -eq 0) "$case DNS recovery rejects all records before any adapter or DoH write"
            }
            $baseline|Set-Content -LiteralPath $path -Encoding UTF8
            Check (Restore-NetworkDnsState $path) 'Valid modern DNS recovery snapshot still restores and verifies'
            Check ($script:Restored[41].IPv4[0] -eq '9.9.9.9' -and @($script:Restored[42].IPv4).Count -eq 0) 'DNS recovery preserves static and automatic adapter modes'
            $snapshot=$baseline|ConvertFrom-Json;$snapshot.DoH=@()
            $snapshot.Adapters[0].StaticIPv4=@('9.9.9.9'+([string][char]0)*23)
            $snapshot|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
            Check (Restore-NetworkDnsState $path) 'Old modern DNS snapshot with Windows REG_SZ padding still restores'
            Check ($script:Restored[41].IPv4[0] -ceq '9.9.9.9') 'Modern DNS recovery removes only the trailing NUL padding before writes'
            $snapshot=$baseline|ConvertFrom-Json;$snapshot.Schema=1;$snapshot.DoH=@()
            foreach($adapter in $snapshot.Adapters){
                $adapter|Add-Member -NotePropertyName IPv4 -NotePropertyValue @($adapter.StaticIPv4)
                $adapter|Add-Member -NotePropertyName IPv6 -NotePropertyValue @($adapter.StaticIPv6)
                foreach($name in @('Automatic','StaticIPv4','StaticIPv6')){$adapter.PSObject.Properties.Remove($name)}
            }
            $snapshot|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
            Check (Restore-NetworkDnsState $path) 'Legacy family arrays still restore with explicit mode warning'
            $snapshot.Adapters[0].IPv4=@("9.9.9.9`0`0");$snapshot.Adapters[0].IPv6=@("2620:fe::fe`0`0")
            $snapshot|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
            Check (Restore-NetworkDnsState $path) 'Old legacy DNS family arrays with trailing NUL padding still restore'
            Check ($script:Restored[41].IPv4[0] -ceq '9.9.9.9' -and $script:Restored[41].IPv6[0] -ceq '2620:fe::fe') 'Legacy DNS recovery normalizes both address families without changing IPs'
            $outsidePath=Join-Path $fixture 'outside-network-snapshot.json';[IO.File]::WriteAllText($outsidePath,$baseline);$script:NetworkWrites=0
            Check (-not(Restore-NetworkDnsState $outsidePath) -and $script:NetworkWrites -eq 0) 'DNS recovery rejects a file outside its backup folder'
            $outside=Join-Path $fixture 'LinkedDnsRecovery';[void][IO.Directory]::CreateDirectory($outside)
            $link=Join-Path $stateRoot 'Linked';New-Item -ItemType Junction -Path $link -Target $outside|Out-Null
            [IO.File]::WriteAllText((Join-Path $outside 'snapshot.json'),$baseline);$script:NetworkWrites=0
            Check (-not(Restore-NetworkDnsState (Join-Path $link 'snapshot.json')) -and $script:NetworkWrites -eq 0) 'Linked DNS recovery snapshot is refused before writes'
        } finally {$env:ProgramData=$oldProgramData;if($link -and(Test-Path -LiteralPath $link)){[IO.Directory]::Delete($link,$false)}}
    }
    Microsoft.PowerShell.Utility\Write-Host "PASS: $checks final Fixer audit checks. Only disposable HKCU/files and intercepted service/native mutations were used." -ForegroundColor Green
} finally {
    if (-not [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped TEMP.' }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Stop }
}
