#requires -version 5.1
param([Parameter(Mandatory)][string]$RequestPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules\Toolkit.Core.psm1') -Force -DisableNameChecking
$request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$resultPath=$RequestPath+'.result.json'
$progressPath=$RequestPath+'.progress.json'
$progress={param($run) Save-SuiteJson -Path $progressPath -Value $run}
try {
    $data=$null; $report=$null; $message='Completed'; $status='Completed'
    switch ($request.Operation) {
        'Preview' { $data=@(Get-SuitePreview -ActionIds @($request.Ids)); $message='Preview only. No Windows settings changed.' }
        'Optimize' { $report=Invoke-SuiteRun -ActionIds @($request.Ids) -StartupIds @($request.StartupIds) -AppIds @($request.AppIds) -Progress $progress }
        'Startup' { $data=@(Get-SuiteStartupItems); $message="$($data.Count) startup entries and third-party startup tasks found." }
        'DisableStartup' { $report=Invoke-SuiteStartupDisable -Ids @($request.Ids) }
        'Apps' { $data=@(Get-SuiteAppCatalog); $message="$($data.Count) optional consumer apps found." }
        'RemoveApps' { $report=Invoke-SuiteAppRemoval -Ids @($request.Ids) }
        'Health' { $data=Get-SuiteHealth; $message='Hardware and Windows service status read.' }
        'History' { $data=@(Get-SuiteHistory); $message="$($data.Count) saved operations found." }
        'Undo' { $report=Invoke-SuiteUndo -Path $request.Path }
        'Repair' { $report=Invoke-SuiteRepair -Progress $progress }
        'RestorePoint' { Checkpoint-Computer -Description 'Windows PC Toolkit' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; $message='Windows restore point created.' }
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
    if ($report) { $report.Status='Failed'; $report.Message=$_.Exception.Message; Save-SuiteJson $report.Path $report }
    Save-SuiteJson $resultPath ([pscustomobject]@{Status='Failed';Message=$_.Exception.Message;Data=$null;Report=$null})
    throw
}
