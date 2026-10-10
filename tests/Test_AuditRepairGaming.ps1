#requires -version 5.1
param([string]$Root=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
$checks=0
function Check([bool]$Condition,[string]$Message) { if(-not $Condition){throw "TEST FAILED: $Message"}; $script:checks++ }
function Load-Functions([string]$Path,[string[]]$Names) {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors.Message -join '; ')}
    $text=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $Names},$false) | ForEach-Object {$_.Extent.Text}) -join "`n"
    [scriptblock]::Create($text)
}
function Find-Source([string[]]$Candidates) { foreach($p in $Candidates){$path=Join-Path $Root $p;if(Test-Path -LiteralPath $path){return $path}};throw 'Component source missing.' }
$gaming=Find-Source @('pc-gaming-optimizer\Modules\Optimizer.Core.psm1','Pc Gaming Optimizer\Modules\Optimizer.Core.psm1')
$fixer=Find-Source @('pc-corruption-fixer\PC_Fixer.ps1','Pc Corruption Fixer\PC_Fixer.ps1')
$fixture=Join-Path $env:TEMP ("Toolkit audit O'Brien 玩家 "+[guid]::NewGuid().ToString('N'))
$key='HKCU:\Software\WindowsPCToolkitTests\'+[guid]::NewGuid().ToString('N')
[void][IO.Directory]::CreateDirectory($fixture)
try {
    $module=Import-Module $gaming -Force -DisableNameChecking -PassThru
    & $module {
        param($fixture,$key)
        $script:StateRoot=Join-Path $fixture 'GamingState'
        $script:SnapshotRoot=Join-Path $script:StateRoot 'Snapshots'
        $script:LogRoot=Join-Path $script:StateRoot 'Logs'
        $script:DiagnosticPath=Join-Path $fixture 'Gaming.log'
        $script:DebugLog=$false
        $script:FixtureKey=$key
        function script:Assert-Administrator {}
        function script:Get-GamingRegistryTargets { @(@{Path=$script:FixtureKey;Name='Text'}) }
        function script:Get-BcdOverrideStates { throw 'Unrequested BCD access' }
        function script:Get-NetworkAdapterStates { throw 'Unrequested network access' }
        function script:Read-Host { 'y' }
    } $fixture $key
    New-Item -Path $key -Force | Out-Null
    foreach($item in @(
        @{Name='Byte';Value=([byte[]]@(255));Kind='Binary'},
        @{Name='Multi';Value=([string[]]@('only'));Kind='MultiString'},
        @{Name='DWord';Value=-1;Kind='DWord'},@{Name='QWord';Value=([long]-1);Kind='QWord'},
        @{Name='Text';Value='CaseSensitive';Kind='String'})) {
        Set-RegistryValueExact $key $item.Name $item.Value $item.Kind
        $actual=Get-RegistryValueState $key $item.Name
        Check ($actual.Kind -eq $item.Kind -and (ConvertTo-Json -InputObject $actual.Value -Compress) -ceq (ConvertTo-Json -InputObject $item.Value -Compress)) "Real registry round-trip: $($item.Kind)"
    }
    $path=New-GamingSnapshot -Reason 'isolated fixture' -RegistryTargets @(@{Path=$key;Name='Text'})
    $snapshot=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Check ($snapshot.Schema -eq 3 -and $snapshot.Registry.Count -eq 1 -and $snapshot.Services.Count -eq 0 -and $snapshot.BcdOverrides.Count -eq 0 -and $snapshot.NetworkAdapters.Count -eq 0 -and $null -eq $snapshot.PowerScheme) 'New console snapshots capture only requested scope'
    Check ($snapshot.UserSid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -and $snapshot.Computer -eq $env:COMPUTERNAME) 'Snapshots identify their originating computer/user'
    Check ((Get-LatestGamingSnapshotPath) -ceq $path) 'UTF-8 snapshot pointer preserves Unicode/apostrophe path'
    Set-RegistryValueExact $key 'Text' 'changed' String
    Restore-LatestGamingSnapshot
    Check ((Get-RegistryValueState $key 'Text').Value -ceq 'CaseSensitive') 'Confirmed console undo restores exact original case'
    $snapshot.Computer='another-computer'
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    $blocked=$false;try{Restore-LatestGamingSnapshot}catch{$blocked=$true}
    Check $blocked 'Foreign computer snapshot is rejected'
    $snapshot.Computer=$env:COMPUTERNAME;$snapshot.Registry[0].Path='HKLM:\SOFTWARE\FixtureOutsideAllowlist'
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    $blocked=$false;try{Restore-LatestGamingSnapshot}catch{$blocked=$true}
    Check $blocked 'Unrecognized registry target rejected before mutation'
    $emptyPath=New-GamingSnapshot -Reason 'no registry changes' -RegistryTargets @()
    $empty=Get-Content -LiteralPath $emptyPath -Raw | ConvertFrom-Json
    Check ($empty.Registry.Count -eq 0 -and $empty.Services.Count -eq 0) 'Empty snapshots contain empty collections instead of null entries'
    $empty.Services=@([pscustomobject]@{Name='SysMain';StartMode='Auto';State='Running'})
    $empty | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $emptyPath -Encoding UTF8
    & $module { function script:Set-Service { throw 'Injected service access denial' } }
    $blocked=$false;try{Restore-LatestGamingSnapshot}catch{$blocked=$_.Exception.Message -like '*Injected service access denial*'}
    Check $blocked 'Service restore errors propagate instead of claiming an exact successful restore'

    # Use real directories and a real junction; outside target must survive.
    $oldLocal=$env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA=Join-Path $fixture 'Local'
        $outside=Join-Path $fixture 'PersonalData'
        [void][IO.Directory]::CreateDirectory($env:LOCALAPPDATA);[void][IO.Directory]::CreateDirectory($outside)
        [IO.File]::WriteAllText((Join-Path $outside 'keep.bin'),'personal')
        New-Item -ItemType Junction -Path (Join-Path $env:LOCALAPPDATA 'D3DSCache') -Target $outside | Out-Null
        $ordinary=Join-Path $env:LOCALAPPDATA 'AMD\DxCache'
        [void][IO.Directory]::CreateDirectory($ordinary);[IO.File]::WriteAllText((Join-Path $ordinary 'remove.bin'),'cache')
        Invoke-ShaderCacheCleanup
        Check (Test-Path -LiteralPath (Join-Path $outside 'keep.bin')) 'Shader cleanup preserves data behind a cache-root junction'
        Check (-not (Test-Path -LiteralPath (Join-Path $ordinary 'remove.bin'))) 'Shader cleanup removes real ordinary cache files'
        [IO.Directory]::Delete((Join-Path $env:LOCALAPPDATA 'D3DSCache'))
    } finally { $env:LOCALAPPDATA=$oldLocal }

    & {
        . (Load-Functions $gaming @('Invoke-SafeRetrim'))
        $script:trimmed=@()
        function Assert-Administrator {}
        function Write-ToolStatus {}
        function Get-PhysicalDisk { [pscustomobject]@{MediaType='SSD';SerialNumber='ssd1'};[pscustomobject]@{MediaType='HDD';SerialNumber='hdd1'} }
        function Get-Disk { [pscustomobject]@{Number=1;SerialNumber='ssd1'};[pscustomobject]@{Number=2;SerialNumber='hdd1'};[pscustomobject]@{Number=3;SerialNumber='unknown'} }
        function Get-Partition { param($DiskNumber) [pscustomobject]@{DiskNumber=$DiskNumber} }
        function Get-Volume { process { [pscustomobject]@{DriveLetter=([string]$_.DiskNumber);DriveType='Fixed';FileSystem='NTFS'} } }
        function Optimize-Volume { param($DriveLetter,[switch]$ReTrim,[switch]$Verbose,$ErrorAction) $script:trimmed+=@($DriveLetter) }
        Invoke-SafeRetrim
        Check ($script:trimmed.Count -eq 1 -and $script:trimmed[0] -eq '1') 'Console ReTrim excludes HDD/unknown media'
    }
    & {
        . (Load-Functions $fixer @('Get-AiRegistryEntryState','Restore-AiFeatureSnapshot','Write-FixerDiagnostic'))
        $script:Results=[ordered]@{};$script:HasFailure=$false;$script:Version='7.2.1'
        $script:DebugLog=$false;$script:LogDir=Join-Path $fixture 'FixerLogs'
        $script:AllowedKey=$key
        function Get-AiFeaturePolicyDefinitions { foreach($name in @('Byte','Multi','DWord','QWord','Text')){[pscustomobject]@{Path=$script:AllowedKey;Name=$name}} }
        function Write-Status {}
        $entries=@(foreach($name in @('Byte','Multi','DWord','QWord','Text')){Get-AiRegistryEntryState $key $name})
        $snapshot=[pscustomobject]@{Schema=1;Computer=$env:COMPUTERNAME;User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Entries=$entries}
        $path=Join-Path $fixture 'AI.json'
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        foreach($name in @('Byte','Multi','DWord','QWord','Text')) { New-ItemProperty -LiteralPath $key -Name $name -PropertyType String -Value 'changed' -Force | Out-Null }
        Check (Restore-AiFeatureSnapshot $path) 'AI snapshot restores signed numeric and singleton array registry types'
        foreach($entry in $entries) {
            $actual=Get-AiRegistryEntryState $key $entry.Name
            Check ($actual.Kind -eq $entry.Kind -and (ConvertTo-Json -InputObject $actual.Value -Compress) -ceq (ConvertTo-Json -InputObject $entry.Value -Compress)) "AI exact restoration: $($entry.Kind)"
        }
        $snapshot.Entries[0].Path='HKLM:\SOFTWARE\OutsideAllowedFixture'
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        $blocked=$false;try{Restore-AiFeatureSnapshot $path}catch{$blocked=$true}
        Check $blocked 'AI snapshot rejects unsupported registry destinations'
        [void][IO.Directory]::CreateDirectory($script:LogDir)
        Write-FixerDiagnostic Info 'quiet fixture'
        Check (-not (Test-Path -LiteralPath (Join-Path $script:LogDir 'PCFixer.log'))) 'Fixer diagnostics are quiet by default'
        Write-FixerDiagnostic Fail 'injected failure cause'
        $diagnostic=Get-Content -LiteralPath (Join-Path $script:LogDir 'PCFixer.log') -Raw | ConvertFrom-Json
        Check ($diagnostic.Version -eq '7.2.1' -and $diagnostic.Message -eq 'injected failure cause') 'Fixer error diagnostics record version and cause without debug enabled'
    }

    # Harmless compiled argv fixture exercises the actual Win32 argument boundary.
    $argvExe=Join-Path $fixture 'argv fixture.exe'
    Add-Type -TypeDefinition @'
using System;
using System.Text;
public static class ToolkitAuditArgv { public static int Main(string[] args) { if (args.Length>0 && args[0]=="/enum") return 5; foreach (string a in args) Console.WriteLine("arg:"+Convert.ToBase64String(Encoding.UTF8.GetBytes(a))); return 0; } }
'@ -OutputAssembly $argvExe -OutputType ConsoleApplication
    & {
        . (Load-Functions $fixer @('Invoke-NativeProcessSafe'))
        $script:ArgvExe=$argvExe
        function Resolve-SystemTool { $script:ArgvExe }
        $arguments=@('','two words','C:\Space Dir\','say"hello','four\\\"end','Grüße 玩家')
        $result=Invoke-NativeProcessSafe 'fixture.exe' $arguments -Quiet
        $actual=@($result.Output -split "`r?`n")
        Check ($result.ExitCode -eq 0 -and $actual.Count -eq $arguments.Count) 'Native fallback launches real argv fixture and preserves empty arguments'
        for($i=0;$i -lt $arguments.Count;$i++){Check ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($actual[$i].Substring(4))) -ceq $arguments[$i]) "Win32 quoting round-trip argument $i"}
    }
    & {
        . (Load-Functions $gaming @('Get-BcdOverrideStates'))
        $oldWindows=$env:SystemRoot
        try {
            $env:SystemRoot=Join-Path $fixture 'FakeWindows'
            [void][IO.Directory]::CreateDirectory((Join-Path $env:SystemRoot 'System32'))
            Copy-Item -LiteralPath $argvExe -Destination (Join-Path $env:SystemRoot 'System32\bcdedit.exe')
            $blocked=$false;try{Get-BcdOverrideStates}catch{$blocked=$_.Exception.Message -like '*exit 5*'}
            Check $blocked 'Real native BCD query failure cannot create an all-absent boot snapshot'
        } finally { $env:SystemRoot=$oldWindows }
    }

    & {
        . (Load-Functions $fixer @('Show-Summary','Invoke-PerfCounterRepair','Invoke-QuickHealthScan','Invoke-StoreReset','Invoke-SfcScan','Invoke-DismRepair','Invoke-DeepCleanup','Invoke-TimeSyncRepair','Invoke-EventLogScan','Get-FixerEvents','Export-HealthReport','ConvertTo-HtmlSafe','Invoke-ServiceHealthCheck','Invoke-FullRepair'))
        $script:Results=[ordered]@{};$script:HasFailure=$false;$script:RestartRequired=$false;$script:StartTime=Get-Date
        $script:LogPath=Join-Path $fixture 'fixture.log';$script:Version='7.2.1';$script:Sys32=Join-Path $env:SystemRoot 'System32'
        $B=@{TL='+';TR='+';BL='+';BR='+';H='-';V='|';LT='+';RT='+';MH='-'}
        $script:Messages=New-Object Collections.ArrayList
        function Write-Status { param($Type,$Text) [void]$script:Messages.Add("$Type $Text") }
        function Write-StepHeader {}
        function Get-Elapsed { 'fixture' }
        function Enable-StayAwake {}
        function Disable-StayAwake {}
        function Start-Sleep {}
        function Read-Host { 'n' }
        function Test-PendingReboot { [pscustomobject]@{Pending=$false;Reasons=@()} }
        $script:Results['SFC']='COMPLETED - Review SFC output'
        Show-Summary
        Check $true 'Summary accepts actual OrderedDictionary results without ContainsKey crash'
        function Invoke-Native-Quiet { param($FilePath,$ArgumentList,$BaseDir) [pscustomobject]@{ExitCode=if($FilePath -eq 'winmgmt.exe'){5}else{0};Output='Native localized fixture verdict'} }
        Invoke-PerfCounterRepair
        Check ($script:Results['PerfCounters'] -like 'WARN*') 'WMI resync failure cannot produce a successful performance-counter report'
        function Get-CimInstance { param($ClassName,$Filter) switch($ClassName){'Win32_LogicalDisk'{[pscustomobject]@{FreeSpace=80GB;Size=100GB;DeviceID='C:'}}} }
        function Get-Service { param($Name) [pscustomobject]@{Name=$Name;DisplayName=$Name;Status=if($Name -eq 'wuauserv'){'Stopped'}else{'Running'};StartType=if($Name -eq 'wuauserv'){'Manual'}else{'Automatic'}} }
        function Get-MpComputerStatus { [pscustomobject]@{AMServiceEnabled=$true;AntivirusSignatureLastUpdated=(Get-Date);QuickScanEndTime=(Get-Date)} }
        function Get-PhysicalDisk { [pscustomobject]@{DeviceId='1';FriendlyName='Fixture';HealthStatus='Healthy'} }
        Invoke-QuickHealthScan
        Check ($script:Results['QuickScan'] -like 'COMPLETED*') 'Idle trigger-start Windows Update service is healthy; no false SFC integrity claim'
        Check (-not @($script:Messages | Where-Object {$_ -match 'System file integrity OK|wuauserv.*NOT running|HEALTH SCAN COMPLETE - No issues found'}).Count) 'Quick scan avoids guessed native verdicts and false Windows Update failures'
        $script:appxAllUsers=$false;$script:registered=0
        function Start-Process { [pscustomobject]@{ExitCode=0} }
        function Get-AppxPackage { param([switch]$AllUsers) $script:appxAllUsers=[bool]$AllUsers;[pscustomobject]@{InstallLocation=$fixture} }
        function Add-AppxPackage { $script:registered++ }
        [IO.File]::WriteAllText((Join-Path $fixture 'AppxManifest.xml'),'<Package/>')
        Invoke-StoreReset
        Check (-not $script:appxAllUsers -and $script:registered -eq 1) 'Store repair scopes registration to the current user'
        $script:nativeCalled=$false
        function Test-PendingReboot { [pscustomobject]@{Pending=$true;Reasons=@('Windows Update')} }
        function Invoke-Native { $script:nativeCalled=$true;throw 'Servicing must not run' }
        Invoke-SfcScan;Invoke-DeepCleanup
        Check (-not $script:nativeCalled -and $script:Results['SFC'] -like 'SKIP*' -and $script:Results['DeepClean'] -like 'SKIP*') 'Pending servicing restart blocks SFC and deep cleanup'
        function Test-PendingReboot { [pscustomobject]@{Pending=$false;Reasons=@()} }
        $script:timeArguments=@()
        function Start-ServiceSafely { $true }
        function Invoke-Native-Quiet { param($FilePath,$ArgumentList) $script:timeArguments+=($ArgumentList -join ' ');[pscustomobject]@{ExitCode=5;Output='No time data available'} }
        Invoke-TimeSyncRepair
        Check (-not @($script:timeArguments | Where-Object {$_ -match '/unregister|/register'}).Count -and $script:Results['TimeSync'] -like 'FAIL*') 'Failed time resync preserves existing NTP/domain configuration'
        function Get-WinEvent { [CmdletBinding()]param($FilterHashtable,$MaxEvents) Write-Error 'Access denied to fixture log' -ErrorId FixtureAccessDenied }
        Invoke-EventLogScan
        Check ($script:Results['EventLog'] -like 'WARN*') 'Unreadable event logs cannot become a clean-health verdict'
        $script:LogDir=Join-Path $fixture 'Reports';[void][IO.Directory]::CreateDirectory($script:LogDir)
        function Invoke-Item {}
        Export-HealthReport
        $html=Get-Content -LiteralPath (Get-ChildItem -LiteralPath $script:LogDir -Filter '*.html' | Select-Object -First 1).FullName -Raw
        Check ($html -match 'Unavailable; event log could not be read' -and $html -notmatch '>0 critical/error events') 'HTML report shares event-log failure handling and cannot invent zero errors'
        function Get-Service { param($Name) [pscustomobject]@{Name=$Name;DisplayName=$Name;Status='Stopped';StartType='Disabled'} }
        Invoke-ServiceHealthCheck
        Check ($script:Results['Services'] -like 'WARN*') 'Disabled critical services do not produce a successful service-health verdict'
    }
    foreach ($entry in @($fixer,(Find-Source @('pc-gaming-optimizer\PC_Optimizer.ps1','Pc Gaming Optimizer\PC_Optimizer.ps1')),(Find-Source @('pc-gaming-optimizer\Fix_VR_PCVR.ps1','Pc Gaming Optimizer\Fix_VR_PCVR.ps1')))) {
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
        $guard=$ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text -match 'ExpectedUserSid' } | Select-Object -First 1
        Check ($null -ne $guard -and $guard.Extent.StartOffset -lt ($ast.EndBlock.Statements | Where-Object { $_.Extent.Text -match '^Import-Module|^\$ProgressPreference|^\$ErrorActionPreference' } | Select-Object -First 1).Extent.StartOffset) 'Expected-user guard runs before console bootstrap'
        $fixtureScript=Join-Path $fixture 'identity.ps1'
        [IO.File]::WriteAllText($fixtureScript,"param([string]`$ExpectedUserSid)`r`n"+$guard.Extent.Text+"`r`nthrow 'Wrong-user guard did not stop execution'",(New-Object Text.UTF8Encoding($true)))
        $previousPreference=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            $output=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $fixtureScript -ExpectedUserSid 'S-1-5-18' 2>&1
            $code=$LASTEXITCODE
        } finally { $ErrorActionPreference=$previousPreference }
        Check ($code -eq 1 -and ($output -join ' ') -notmatch 'Wrong-user guard did not stop execution') 'Actual user guard rejects another Windows account before bootstrap'
    }
    Write-Host "PASS: $checks repair/gaming audit checks. No live repair, optimization, service or network mutation was performed." -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module Optimizer.Core -Force -ErrorAction SilentlyContinue
    if (-not [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup path escaped TEMP.' }
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
