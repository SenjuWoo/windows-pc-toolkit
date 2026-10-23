#requires -version 5.1
param([switch]$SmokeTest,[string]$RenderPreview,[string]$ExpectedUserSid,[switch]$DebugLog)
$ErrorActionPreference='Stop'
if ($DebugLog) { $env:WINDOWS_PC_TOOLKIT_DEBUG='1' }
trap {
    if ($SmokeTest -or $RenderPreview) { Write-Error $_; exit 1 }
    try { [void][Windows.MessageBox]::Show('Toolkit could not start. Extract the complete toolkit. '+$_.Exception.Message,'Windows PC Toolkit') }
    catch { Write-Error $_ }
    exit 1
}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $ExpectedUserSid) { $ExpectedUserSid=$identity.User.Value }
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $SmokeTest -and -not $RenderPreview -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $escaped=$PSCommandPath.Replace("'","''")
    $command="& '$escaped' -ExpectedUserSid '$ExpectedUserSid'"
    if ($env:WINDOWS_PC_TOOLKIT_DEBUG -eq '1') { $command+=' -DebugLog' }
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments="-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $psi.UseShellExecute=$true; $psi.Verb='runas'
    try { $elevated=[Diagnostics.Process]::Start($psi); $elevated.WaitForExit(); $code=$elevated.ExitCode; $elevated.Dispose(); exit $code }
    catch { [void][Windows.MessageBox]::Show('Administrator launch did not complete. '+$_.Exception.Message,'Windows PC Toolkit'); exit 1 }
    exit 0
}
if (-not $SmokeTest -and -not $RenderPreview -and $identity.User.Value -ne $ExpectedUserSid) { throw 'Start the toolkit with administrator rights for your own account so settings apply to the correct Windows user.' }

Import-Module (Join-Path $PSScriptRoot 'Modules\Toolkit.Core.psm1') -Force -DisableNameChecking
Write-SuiteDiagnostic 'Dashboard startup' "DataRoot=$(Get-SuiteDataRoot); Debug=$($env:WINDOWS_PC_TOOLKIT_DEBUG -eq '1'); SmokeTest=$SmokeTest"
[xml]$markup=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Toolkit.xaml') -Raw -Encoding UTF8
$reader=New-Object Xml.XmlNodeReader($markup)
$script:window=[Windows.Markup.XamlReader]::Load($reader)
$reader.Close()
$script:controls=@{}
foreach ($node in $markup.SelectNodes('//*[@Name]')) { $script:controls[$node.Name]=$script:window.FindName($node.Name) }
$script:catalog=@(Get-SuiteActionCatalog)
$script:optionChecks=@{}
$script:job=$null
$script:requestPath=$null
$script:operation=$null
$script:progressStamp=''
$script:pages=@('OptimizePage','OneDrivePage','StartupPage','AppsPage','DnsPage','RecoveryPage','ToolsPage')
$script:navNames=@('NavOptimize','NavOneDrive','NavStartup','NavApps','NavDns','NavRecovery','NavTools')
$script:oneDriveReport=$null
$script:operationButtons=@('OptimizeButton','PreviewButton','RefreshOneDrive','LockFolders','UninstallOneDrive','RestoreOneDriveFolders','RefreshStartup','DisableStartup','RefreshApps','RemoveApps','ApplyDns','VerifyDns','RestoreDns','DhcpDns','RefreshDns','RefreshHistory','UndoButton','RepairButton','RestorePointButton','HealthButton','OpenFixer','OpenCleaner','OpenPrivacy','OpenGaming','OpenDns')

# OneDrive stays first among the recommended actions so the folder lock is visible without scrolling.
foreach ($choice in ($script:catalog | Sort-Object @{Expression='Default';Descending=$true}, @{Expression={ if ($_.Category -eq 'OneDrive') { '0' } else { $_.Category } }})) {
    $row=New-Object Windows.Controls.StackPanel
    $row.Margin=New-Object Windows.Thickness(0,0,12,14)
    $check=New-Object Windows.Controls.CheckBox
    $check.Content=$choice.Name; $check.IsChecked=$choice.Default; $check.Tag=$choice.Id
    $check.ToolTip=$choice.Detail
    $description=New-Object Windows.Controls.TextBlock
    $description.Text=$choice.Detail; $description.Foreground='#9BADCA'; $description.FontSize=12
    $description.TextWrapping='Wrap'; $description.Margin=New-Object Windows.Thickness(23,0,0,0)
    [void]$row.Children.Add($check); [void]$row.Children.Add($description)
    [void]$script:controls.OptionsPanel.Children.Add($row)
    $script:optionChecks[$choice.Id]=$check
}
$script:controls.ProviderCombo.ItemsSource=@(
    [pscustomobject]@{Key='Quad9';Name='Quad9 Secure - malware blocking'},
    [pscustomobject]@{Key='AdGuard';Name='AdGuard DNS - ads and trackers'})
$script:controls.ProviderCombo.SelectedIndex=0

function Update-OneDriveActions {
    $idle=(-not $script:job)
    $script:controls.LockFolders.IsEnabled=$idle
    $script:controls.RefreshOneDrive.IsEnabled=$idle
    $report=$script:oneDriveReport
    $script:controls.UninstallOneDrive.IsEnabled=$idle -and $report -and [bool]$report.UninstallAllowed
    $script:controls.RestoreOneDriveFolders.IsEnabled=$idle -and $report -and [bool]$report.RestoreAllowed
}
function Set-ToolkitBusy {
    param([bool]$Busy)
    foreach ($name in $script:operationButtons) { $script:controls[$name].IsEnabled=(-not $Busy) }
    $script:controls.RecommendedButton.IsEnabled=(-not $Busy)
    $script:controls.IncludeReviewed.IsEnabled=(-not $Busy)
    foreach ($check in $script:optionChecks.Values) { $check.IsEnabled=(-not $Busy) }
    $script:controls.BusyBar.Visibility=if ($Busy) { 'Visible' } else { 'Collapsed' }
    Update-OneDriveActions
}
function Show-ToolkitPage {
    param([int]$Index)
    for ($i=0; $i -lt $script:pages.Count; $i++) {
        $script:controls[$script:pages[$i]].Visibility=if ($i -eq $Index) { 'Visible' } else { 'Collapsed' }
        $script:controls[$script:navNames[$i]].Background=if ($i -eq $Index) { '#315FA0' } else { '#17202D' }
    }
    if (-not $script:job) {
        switch ($Index) {
            1 { Start-ToolkitOperation 'OneDrive' }
            2 { Start-ToolkitOperation 'Startup' }
            3 { Start-ToolkitOperation 'Apps' }
            4 { Start-ToolkitOperation 'DnsInfo' }
            5 { Start-ToolkitOperation 'History' }
        }
    }
}
function Start-ToolkitOperation {
    param([string]$Operation,[string[]]$Ids=@(),[string]$Path,[string]$DnsAction,[string[]]$ConsumerAppIds=@())
    if ($script:job) { return }
    try {
        Initialize-SuiteState
        $script:requestPath=Join-Path (Get-SuiteDataRoot) ('Requests\'+[guid]::NewGuid().ToString('N')+'.json')
        $startupIds=@(); $appIds=@($ConsumerAppIds)
        if ($Operation -in @('Optimize','Preview') -and $script:controls.IncludeReviewed.IsChecked) {
            $startupIds=@($script:controls.StartupGrid.SelectedItems | ForEach-Object Id)
            $appIds+=@($script:controls.AppsGrid.SelectedItems | ForEach-Object Id)
        }
        $request=[pscustomobject]@{Operation=$Operation;Ids=@($Ids);Path=$Path;DnsAction=$DnsAction;StartupIds=$startupIds;AppIds=$appIds}
        Save-SuiteJson $script:requestPath $request
        Write-SuiteDiagnostic 'Dashboard operation' "$Operation; profile=$($Ids -join ','); startup=$($startupIds.Count); apps=$($appIds.Count)"
        $script:operation=$Operation; $script:progressStamp=''
        $script:controls.StatusText.Text="Running: $Operation"
        $script:controls.ResultText.Text=''; $script:controls.ResultText.Visibility='Visible'
        Set-ToolkitBusy $true
        $script:job=Start-Job -ScriptBlock { param($worker,$request) & $worker -RequestPath $request } -ArgumentList (Join-Path $PSScriptRoot 'Toolkit.Worker.ps1'),$script:requestPath
    } catch { Write-SuiteDiagnostic 'Dashboard operation' $_.Exception.Message 'Error'; Set-ToolkitBusy $false; $script:controls.StatusText.Text='Failed: '+$_.Exception.Message }
}
function Open-ToolkitConsole {
    param([string[]]$Candidates)
    $path=Resolve-SuitePath $Candidates
    $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$path+'"'
    if ([IO.Path]::GetFileName($path) -ne 'DNS_Manager.ps1') { $arguments+=' -ExpectedUserSid "'+(Get-SuiteIdentity)+'"' }
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -WindowStyle Normal
}
function Invoke-ToolkitButton {
    param($sender,$eventArgs)
    try {
        switch ($sender.Name) {
            'OptimizeButton' {
                $ids=@($script:catalog | Where-Object { $script:optionChecks[$_.Id].IsChecked } | ForEach-Object Id)
                if (-not $ids.Count -and -not ($script:controls.IncludeReviewed.IsChecked -and ($script:controls.StartupGrid.SelectedItems.Count -or $script:controls.AppsGrid.SelectedItems.Count))) { $script:controls.StatusText.Text='Choose an action or reviewed startup/app selections.'; return }
                $apps=@()
                if ($ids -contains 'Debloat') { $apps+=@(Get-SuiteAppCatalog) }
                if ($script:controls.IncludeReviewed.IsChecked) { $apps+=@($script:controls.AppsGrid.SelectedItems) }
                $apps=@($apps | Sort-Object Id -Unique)
                if ($apps.Count) {
                    $names=@($apps.Name) -join "`n"
                    if ([Windows.MessageBox]::Show("Optimize with these consumer app removals? Their app data may be deleted. Verified package reinstall backups are saved first.`n`n$names",'Optimize and debloat','YesNo','Question','No') -ne 'Yes') { return }
                }
                Start-ToolkitOperation 'Optimize' $ids -ConsumerAppIds @($apps | ForEach-Object Id)
            }
            'PreviewButton' { Start-ToolkitOperation 'Preview' @($script:catalog | Where-Object { $script:optionChecks[$_.Id].IsChecked } | ForEach-Object Id) }
            'RecommendedButton' { foreach ($choice in $script:catalog) { $script:optionChecks[$choice.Id].IsChecked=$choice.Default } }
            'RefreshOneDrive' { Start-ToolkitOperation 'OneDrive' }
            'OpenWindowsBackup' { Start-Process 'ms-settings:backup' }
            'OpenOneDriveApp' {
                $oneDrive=Get-SuiteOneDriveExecutable
                if ($oneDrive) { Start-Process -FilePath $oneDrive }
                else { $script:controls.StatusText.Text='OneDrive is not installed. Sign-in is required only while the app is still there. If folders still point at OneDrive, use Restore local locations.' }
            }
            'LockFolders' {
                $gate=Get-SuiteOneDriveReport
                $script:oneDriveReport=$gate
                $script:controls.OneDriveBanner.Text=$gate.Summary
                Update-OneDriveActions
                if (-not $gate.PolicyAllowed) { $script:controls.StatusText.Text=$gate.PolicyBlock; return }
                $answer=[Windows.MessageBox]::Show('Lock Desktop, Documents and Pictures so OneDrive cannot take them over? Files are not moved or deleted. Do this only after every folder says it is on this PC.','Keep folders on this PC','YesNo','Question','No')
                if ($answer -eq 'Yes') { Start-ToolkitOperation 'Optimize' @('KeepLocalFolders') }
            }
            'UninstallOneDrive' {
                $gate=if ($script:oneDriveReport) { $script:oneDriveReport } else { Get-SuiteOneDriveReport }
                if (-not $gate.UninstallAllowed) { $script:controls.StatusText.Text=$gate.UninstallBlock; return }
                $answer=[Windows.MessageBox]::Show("Folders are on this PC. Open Installed apps and uninstall Microsoft OneDrive there.`n`nThe toolkit does not delete your files and does not run the uninstaller itself.",'Uninstall OneDrive','YesNo','Question','No')
                if ($answer -eq 'Yes') { Start-Process 'ms-settings:appsfeatures' }
            }
            'RestoreOneDriveFolders' {
                $gate=Get-SuiteOneDriveReport
                if (-not $gate.RestoreAllowed) { $script:controls.StatusText.Text=$gate.RestoreBlock; return }
                $answer=[Windows.MessageBox]::Show("OneDrive is already gone and at least one folder still points at it. Point those folders back at this PC?`n`nFiles stay where they are. Nothing is deleted. Sign out afterwards, then move leftover files out of the old OneDrive folder yourself.",'Restore local folder locations','YesNo','Question','No')
                if ($answer -eq 'Yes') { Start-ToolkitOperation 'RestoreOneDriveFolders' }
            }
            'RefreshStartup' { Start-ToolkitOperation 'Startup' }
            'DisableStartup' { Start-ToolkitOperation 'DisableStartup' @($script:controls.StartupGrid.SelectedItems | ForEach-Object Id) }
            'RefreshApps' { Start-ToolkitOperation 'Apps' }
            'RemoveApps' {
                $items=@($script:controls.AppsGrid.SelectedItems)
                if (-not $items.Count) { $script:controls.StatusText.Text='Select apps to remove.'; return }
                $answer=[Windows.MessageBox]::Show("Remove these optional apps for your account? Package reinstall backups are saved; app data is not backed up.`n`n"+(@($items.Name) -join "`n"),'Remove selected apps','YesNo','Question','No')
                if ($answer -eq 'Yes') { Start-ToolkitOperation 'RemoveApps' @($items | ForEach-Object Id) }
            }
            'RefreshDns' { Start-ToolkitOperation 'DnsInfo' }
            { $_ -in @('ApplyDns','VerifyDns','RestoreDns','DhcpDns') } {
                if (-not $script:controls.AdapterCombo.SelectedItem -and $sender.Name -ne 'RestoreDns') { $script:controls.StatusText.Text='Refresh and select a physical adapter first.'; return }
                $dnsAction=switch ($sender.Name) { 'ApplyDns' { $script:controls.ProviderCombo.SelectedItem.Key } 'VerifyDns' { 'Verify' } 'RestoreDns' { 'Restore' } 'DhcpDns' { 'DHCP' } }
                $ids=@(); if ($script:controls.AdapterCombo.SelectedItem) { $ids=@([string]$script:controls.AdapterCombo.SelectedItem.ifIndex) }
                Start-ToolkitOperation -Operation 'Dns' -Ids $ids -DnsAction $dnsAction
            }
            'RefreshHistory' { Start-ToolkitOperation 'History' }
            'UndoButton' { if ($script:controls.HistoryGrid.SelectedItem) { Start-ToolkitOperation -Operation 'Undo' -Path $script:controls.HistoryGrid.SelectedItem.Path } else { $script:controls.StatusText.Text='Select an operation to restore.' } }
            'OpenReport' { if ($script:controls.HistoryGrid.SelectedItem) { Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList ('"'+$script:controls.HistoryGrid.SelectedItem.Path+'"') } }
            'OpenBackups' { Initialize-SuiteState; Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"'+(Get-SuiteDataRoot)+'"') }
            'RepairButton' { Start-ToolkitOperation 'Repair' }
            'RestorePointButton' { Start-ToolkitOperation 'RestorePoint' }
            'HealthButton' { Start-ToolkitOperation 'Health' }
            'OpenFixer' { Open-ToolkitConsole @('pc-corruption-fixer\PC_Fixer.ps1','Pc Corruption Fixer\PC_Fixer.ps1') }
            'OpenCleaner' { Open-ToolkitConsole @('pc-cleaner\PC_Cleaner.ps1','Pc Cleaner\PC_Cleaner.ps1') }
            'OpenPrivacy' { Open-ToolkitConsole @('pc-privacy-guard\PC_Privacy.ps1','Pc Privacy Guard\PC_Privacy.ps1') }
            'OpenGaming' { Open-ToolkitConsole @('pc-gaming-optimizer\PC_Optimizer.ps1','Pc Gaming Optimizer\PC_Optimizer.ps1') }
            'OpenDns' { Open-ToolkitConsole @('dns-encrypted-doh\DNS_Manager.ps1','Pc Privacy Guard\Optional DNS\DNS_Manager.ps1') }
            'SettingsUpdates' { Start-Process 'ms-settings:windowsupdate' }
            'SettingsDisplay' { Start-Process 'ms-settings:display-advanced' }
            'SettingsPower' { Start-Process 'ms-settings:powersleep' }
            'SettingsStorage' { Start-Process 'ms-settings:storagesense' }
            'SettingsApps' { Start-Process 'ms-settings:appsfeatures' }
            'DuckLink' { Start-Process 'https://github.com/itsfatduck/optimizerDuck' }
            'SourceLink' { Start-Process 'https://github.com/SenjuWoo/windows-pc-toolkit' }
        }
    } catch { Write-SuiteDiagnostic 'Dashboard button' $_.Exception.Message 'Error'; $script:controls.StatusText.Text='Failed: '+$_.Exception.Message }
}
for ($i=0; $i -lt $script:navNames.Count; $i++) {
    $button=$script:controls[$script:navNames[$i]]; $button.Tag=$i
    $button.Add_Click({param($sender,$eventArgs) Show-ToolkitPage ([int]$sender.Tag)})
}
foreach ($control in $script:controls.Values) {
    if ($control -is [Windows.Controls.Button] -and $script:navNames -notcontains $control.Name) { $control.Add_Click({param($sender,$eventArgs) Invoke-ToolkitButton $sender $eventArgs}) }
}
$script:timer=New-Object Windows.Threading.DispatcherTimer
$script:timer.Interval=[TimeSpan]::FromMilliseconds(400)
$script:timer.Add_Tick({
    if (-not $script:job) { return }
    try {
        $progressPath=$script:requestPath+'.progress.json'
        if (Test-Path -LiteralPath $progressPath) {
            $progress=Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($progress.Message -ne $script:progressStamp) {
                $script:progressStamp=$progress.Message; $script:controls.StatusText.Text=$progress.Message
                $script:controls.ResultText.Text=(@($progress.Steps | ForEach-Object { "[$($_.Status)] $($_.Action): $($_.Message)" }) -join "`r`n")
            }
        }
        if ($script:job.State -notin @('Completed','Failed','Stopped')) { return }
        $null=Receive-Job $script:job -ErrorAction SilentlyContinue
        $resultPath=$script:requestPath+'.result.json'
        if (-not (Test-Path -LiteralPath $resultPath)) { throw 'The worker stopped before saving a result. Check Recovery for an interrupted operation.' }
        $result=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:controls.StatusText.Text=$result.Message
        if ($result.Report) {
            $script:controls.ResultText.Text=(@($result.Report.Steps | ForEach-Object { "[$($_.Status)] $($_.Action): $($_.Message)" }) -join "`r`n")+"`r`nReport: "+$result.Report.Path
        } elseif ($result.Status -eq 'Completed' -and $script:operation -in @('Startup','Apps','History','DnsInfo','OneDrive')) {
            switch ($script:operation) {
                'OneDrive' {
                    $script:oneDriveReport=$result.Data
                    $script:controls.OneDriveGrid.ItemsSource=@($result.Data.Folders)
                    $script:controls.OneDriveSummary.Text=[string]$result.Data.Summary
                    $script:controls.OneDriveBanner.Text=[string]$result.Data.Summary
                }
                'Startup' { $script:controls.StartupGrid.ItemsSource=@($result.Data) }
                'Apps' { $script:controls.AppsGrid.ItemsSource=@($result.Data) }
                'History' { $script:controls.HistoryGrid.ItemsSource=@($result.Data) }
                'DnsInfo' { $script:controls.AdapterCombo.ItemsSource=@($result.Data); $script:controls.AdapterCombo.SelectedIndex=0 }
            }
        } elseif ($result.Data) {
            switch ($script:operation) {
                'Health' {
                    $health=$result.Data
                    $script:controls.HardwareText.Text="$($health.OS) | $($health.CPU) | $($health.RAMGB) GB RAM"
                    $script:controls.ServicesGrid.ItemsSource=@($health.Services)
                    if ($health.UpdatesDisabled) { $script:controls.StatusText.Text='Windows Update services were already disabled. Review system health in the repair console.' }
                }
                'Preview' { $script:controls.ResultText.Text=(@($result.Data | ForEach-Object { "$($_.Action): $($_.Details)" }) -join "`r`n") }
            }
        } else { $script:controls.ResultText.Text=$result.Message }
        Remove-Job $script:job -Force; $script:job=$null; Set-ToolkitBusy $false
    } catch {
        Write-SuiteDiagnostic 'Dashboard result' $_.Exception.Message 'Error'
        $script:controls.StatusText.Text='Failed: '+$_.Exception.Message
        if ($script:job -and $script:job.State -in @('Completed','Failed','Stopped')) { Remove-Job $script:job -Force; $script:job=$null; Set-ToolkitBusy $false }
    }
})
$script:window.Add_Closing({param($sender,$eventArgs)
    if ($script:job) { $eventArgs.Cancel=$true; [void][Windows.MessageBox]::Show('An operation is still running. Keep the toolkit open until its result is saved.','Windows PC Toolkit') }
    else { $script:timer.Stop() }
})

if ($RenderPreview) {
    $script:controls.OneDriveBanner.Text='Check Desktop, Documents, Pictures, Music and Videos before uninstalling OneDrive.'
    $script:window.Width=1200; $script:window.Height=860
    $content=$script:window.Content
    $content.Measure((New-Object Windows.Size(1200,860)))
    $content.Arrange((New-Object Windows.Rect(0,0,1200,860)))
    $content.UpdateLayout()
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1200,860,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($content)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create([IO.Path]::GetFullPath($RenderPreview))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    Write-Output "Rendered dashboard: $RenderPreview"
}
if (-not $RenderPreview) {
    try {
        $script:oneDriveReport=Get-SuiteOneDriveReport
        $script:controls.OneDriveBanner.Text=$script:oneDriveReport.Summary
        Update-OneDriveActions
    } catch {
        $script:controls.OneDriveBanner.Text='OneDrive folder check failed: '+$_.Exception.Message
    }
}
if ($SmokeTest -or $RenderPreview) { Write-Output "Dashboard loaded: $($script:controls.Count) controls, $($script:optionChecks.Count) optimization choices."; return }
$script:window.Add_Loaded({$script:timer.Start(); Start-ToolkitOperation 'Health'})
[void]$script:window.ShowDialog()
