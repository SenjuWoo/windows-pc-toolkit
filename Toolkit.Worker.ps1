#requires -version 5.1
param([Parameter(Mandatory)][string]$RequestPath)
$ErrorActionPreference='Stop'
$resultPath=$RequestPath+'.result.json'
$progressPath=$RequestPath+'.progress.json'
$report=$null
try {
    Import-Module (Join-Path $PSScriptRoot 'Modules\Toolkit.Core.psm1') -Force -DisableNameChecking
    Assert-SuiteUnlinkedPath $RequestPath
    Assert-SuiteStatePermissions (Split-Path ([IO.Path]::GetFullPath($RequestPath)) -Parent)
    Assert-SuiteStatePermissions $RequestPath
    $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $progress={param($run) Save-SuiteJson -Path $progressPath -Value $run}
    Write-SuiteDiagnostic 'Worker startup' "Operation=$($request.Operation); DataRoot=$(Get-SuiteDataRoot); Request=$RequestPath"
    $data=$null; $report=$null; $message='Completed'; $status='Completed'
    switch ($request.Operation) {
        'Preview' { $data=@(Get-SuitePreview -ActionIds @($request.Ids) -StartupIds @($request.StartupIds | Where-Object { $_ }) -AppIds @($request.AppIds | Where-Object { $_ })); $message='Preview only. No Windows settings changed.' }
        'Optimize' { $report=Invoke-SuiteRun -ActionIds @($request.Ids) -StartupIds @($request.StartupIds | Where-Object { $_ }) -AppIds @($request.AppIds | Where-Object { $_ }) -Progress $progress }
        'Startup' { $data=@(Get-SuiteStartupItems); $message="$($data.Count) startup entries and third-party startup tasks found." }
        'DisableStartup' { $report=Invoke-SuiteStartupDisable -Ids @($request.Ids) }
        'Apps' { $data=@(Get-SuiteAppCatalog); $message="$($data.Count) optional consumer apps found." }
        'OneDrive' { $data=Get-SuiteOneDriveReport -CountCloudOnly; $message=$data.Summary }
        'RestoreOneDriveFolders' { $report=Invoke-SuiteOneDriveFolderRestore; $message=$report.Message }
        'RemoveApps' { $report=Invoke-SuiteAppRemoval -Ids @($request.Ids) }
        'Health' { $data=Get-SuiteHealth; $message='Hardware and Windows service status read.' }
        'History' { $data=@(Get-SuiteHistory); $message="$($data.Count) saved operations found." }
        'Undo' { $report=Invoke-SuiteUndo -Path $request.Path }
        'Repair' { $report=Invoke-SuiteRepair -Progress $progress }
        'RestorePoint' {
            $before=@(Get-ComputerRestorePoint -ErrorAction Stop | ForEach-Object SequenceNumber)
            Checkpoint-Computer -Description 'Windows PC Toolkit' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction Stop
            $created=@(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.SequenceNumber -notin $before -and $_.Description -eq 'Windows PC Toolkit' })
            if (-not $created.Count) { throw 'Windows did not create a new toolkit restore point. Check System Protection and the restore-point frequency limit.' }
            $message='Windows restore point created and verified.'
        }
        'DnsInfo' { $data=@(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up' | Select-Object Name,ifIndex,InterfaceDescription); $message='Active physical adapters loaded.' }
        'Dns' {
            . (Resolve-SuitePath @('dns-encrypted-doh\DNS_Manager.ps1','Pc Privacy Guard\Optional DNS\DNS_Manager.ps1')) -Action Library -InterfaceIndex @($request.Ids | ForEach-Object { [int]$_ })
            if ($request.DnsAction -eq 'Verify') {
                if (-not (Test-Configuration)) { throw 'DNS checks did not pass. Open the DNS console for the detailed Windows configuration.' }
                $message='Encrypted DNS configuration and resolution checks passed.'
            } else {
                $mutex=Enter-SuiteOperation
                try {
                    $report=New-SuiteRun 'DNS'
                    switch ($request.DnsAction) {
                        'Restore' { Restore-Snapshot }
                        'DHCP' { Reset-Dhcp }
                        default {
                            if (-not $Providers.Contains($request.DnsAction)) { throw 'Unknown DNS provider.' }
                            Set-Provider $request.DnsAction
                        }
                    }
                    if ($request.DnsAction -ne 'Restore') { $report | Add-Member -NotePropertyName DnsBackup -NotePropertyValue (Get-LatestSnapshot) }
                    $report.Status='Completed'; $report.Message='DNS action completed and checked.'
                    Add-SuiteStep $report 'DNS' 'Applied' $report.Message
                    Save-SuiteJson $report.Path $report
                } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
            }
        }
        default { throw 'Unknown toolkit operation.' }
    }
    if ($report) { $status=$report.Status; $message=$report.Message }
    Save-SuiteJson $resultPath ([pscustomobject]@{Status=$status;Message=$message;Data=$data;Report=$report})
} catch {
    $failure=$_
    if (Get-Command Write-SuiteDiagnostic -ErrorAction SilentlyContinue) { Write-SuiteDiagnostic 'Worker failure' $failure.Exception.Message 'Error' }
    if ($report) {
        $report.Status='Failed'; $report.Message=$failure.Exception.Message
        try { Add-SuiteStep $report $request.Operation 'Failed' $failure.Exception.Message } catch { Write-Warning $_.Exception.Message }
    }
    $result=[pscustomobject]@{Status='Failed';Message=$failure.Exception.Message;Data=$null;Report=$report}
    # Keep startup/import failures visible even when the shared module could not load.
    $json=$result | ConvertTo-Json -Depth 16
    if (Get-Command Assert-SuiteUnlinkedPath -ErrorAction SilentlyContinue) { Assert-SuiteUnlinkedPath $resultPath }
    if (Get-Command Assert-SuiteStatePermissions -ErrorAction SilentlyContinue) {
        Assert-SuiteStatePermissions (Split-Path ([IO.Path]::GetFullPath($resultPath)) -Parent)
        Assert-SuiteStatePermissions $resultPath
    }
    [IO.File]::WriteAllText($resultPath,$json,(New-Object Text.UTF8Encoding($false)))
    throw $failure
}
