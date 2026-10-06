#Requires -Version 7.5
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$source=Join-Path $repo 'fpga/custom_project/sc520-osd-demo'
$destination=Join-Path $repo 'fpga/custom_project/sc520-learning-ui-audio'
if(Test-Path -LiteralPath $destination){throw 'Destination already exists; never overwrite the previous candidate'}
$manifest=Get-Content -LiteralPath (Join-Path $repo 'evidence/sc520-osd-demo/candidate-manifest.json') -Raw | ConvertFrom-Json
$baseline=$manifest
if((Get-FileHash -LiteralPath $baseline.SourceSnapshot).Hash -ne $baseline.SourceSnapshotSHA256){throw 'Source manifest changed'}
if((Get-FileHash -LiteralPath $baseline.Candidate).Hash -ne $baseline.SHA256){throw 'Rollback bit changed'}
$inputs=Get-Content -LiteralPath $baseline.SourceSnapshot -Raw | ConvertFrom-Json -AsHashtable
foreach($relative in $inputs.Keys){
    $original=Join-Path $source $relative
    if((Get-FileHash -LiteralPath $original).Hash -ne $inputs[$relative]){throw "Changed source: $relative"}
}
foreach($relative in $inputs.Keys){
    $target=Join-Path $destination $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $source $relative) -Destination $target
    if((Get-FileHash -LiteralPath $target).Hash -ne $inputs[$relative]){throw 'Copy verification failed'}
}
$evidence=Join-Path $repo 'evidence/sc520-learning-ui-audio'
[IO.Directory]::CreateDirectory($evidence) | Out-Null
@{Source=$source;SourceInputs=$inputs;Rollback=$baseline.Candidate;RollbackSHA256=$baseline.SHA256;Destination=$destination} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'origin.json') -Encoding utf8
Write-Output "PREPARED inputs=$($inputs.Count) destination=$destination"
