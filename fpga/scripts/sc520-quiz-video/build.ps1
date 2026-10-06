#Requires -Version 7.5
[CmdletBinding()]
param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$project = Join-Path $repo 'fpga/custom_project/sc520-quiz-video'
$tool = 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
if (-not (Test-Path -LiteralPath $tool)) { throw 'Required existing TD 6.2.1 executable missing' }
& $Python (Join-Path $PSScriptRoot 'verify-build.py') --preflight
if ($LASTEXITCODE -ne 0) { throw 'Build input preflight failed; refresh manifests after source freeze' }
$runId = [guid]::NewGuid().ToString('N').Substring(0,8)
$evidence = Join-Path $repo "evidence/sc520-quiz-video/b/$runId"
if (Test-Path -LiteralPath $evidence) { throw 'Refuse a duplicate isolated build ID' }
# TD 6.2.1 rejects unnormalized cwd/../../../file paths longer than 259
# characters. Keep the independent snapshot root short; timestamps are in JSON.
$snapshot = $evidence
[IO.Directory]::CreateDirectory($snapshot) | Out-Null
$startedUtc = [datetime]::UtcNow
$files = @(Get-ChildItem -LiteralPath (Join-Path $project 'user_source') -File -Recurse)
$files += @(Get-ChildItem -LiteralPath (Join-Path $project 'td_project/al_ip') -File -Recurse)
$files += @(Get-ChildItem -LiteralPath (Join-Path $project 'td_project') -File | Where-Object { $_.Extension -in @('.al','.sdc') })
foreach ($stage in @('syn_1','phy_1')) {
    $files += @(Get-ChildItem -LiteralPath (Join-Path $project "td_project/camera_to_dsi_display_Runs/$stage") -File | Where-Object { $_.Name -in @('camera_to_dsi_display.prj','camera_to_dsi_display.tcl','settings.cfg') })
}
$hashes = [ordered]@{}
foreach ($sourceFile in ($files | Sort-Object FullName)) {
    $relative = [IO.Path]::GetRelativePath($project,$sourceFile.FullName).Replace('\','/')
    $target = Join-Path $snapshot $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
    $digest = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
    Copy-Item -LiteralPath $sourceFile.FullName -Destination $target
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $digest) { throw "Input changed while copying: $relative" }
    $hashes[$relative] = $digest
}
$sourceSnapshot = Join-Path $evidence 'source-inputs.json'
$hashes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sourceSnapshot -Encoding utf8
$builderHashes = [ordered]@{}
$toolSnapshot = Join-Path $evidence 'tools'
[IO.Directory]::CreateDirectory($toolSnapshot) | Out-Null
foreach ($name in @('build.ps1','archive-build.py','verify-build.py','prepare.py')) {
    $sourceFile = Join-Path $PSScriptRoot $name
    $builderHashes[$name] = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
    Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $toolSnapshot $name)
}
$before = [ordered]@{Variant='quiz-video';Owner='01a11124-e100-75e2-9e85-9f9686e23c73 /root/audio';StartedAtUtc=$startedUtc.ToString('o');SourceProject=$project;BuildProject=$snapshot;Tool=$tool;ToolSHA256=(Get-FileHash -LiteralPath $tool).Hash;SourceSnapshot=$sourceSnapshot;SourceSnapshotSHA256=(Get-FileHash -LiteralPath $sourceSnapshot).Hash;BuilderHashes=$builderHashes;ProtectionSnapshot=(Join-Path $repo 'evidence/sc520-quiz-video/protected-before.json');ProtectionSnapshotSHA256=(Get-FileHash -LiteralPath (Join-Path $repo 'evidence/sc520-quiz-video/protected-before.json')).Hash}
$before | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'started.json') -Encoding utf8
$results = [Collections.Generic.List[object]]::new()
try {
    foreach ($stage in @('syn_1','phy_1')) {
        $runDir = Join-Path $snapshot "td_project/camera_to_dsi_display_Runs/$stage"
        $stdout = Join-Path $evidence "$stage.stdout.log"
        $stderr = Join-Path $evidence "$stage.stderr.log"
        $launcher = Join-Path $evidence "$stage.launch.tcl"
        $launchText = @'
if {[catch {source camera_to_dsi_display.tcl} message]} {
    puts stderr $message
    exit 1
}
puts "SC520_QUIZ_VIDEO_STAGE_OK STAGE_TOKEN"
exit 0
'@
        $launchText.Replace('STAGE_TOKEN',$stage) | Set-Content -LiteralPath $launcher -Encoding utf8
        $stageStart = [datetime]::UtcNow
        $terminal = if ($stage -eq 'syn_1') { '.opt_gate.end.f' } else { '.bitgen.end.f' }
        $marker = Join-Path $runDir $terminal
        if (Test-Path -LiteralPath $marker) { throw 'A new isolated build unexpectedly contains an old marker' }
        $arguments = '"{0}"' -f $launcher.Replace('\','/')
        $process = Start-Process -FilePath $tool -ArgumentList $arguments -WorkingDirectory $runDir -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        Write-Output "TD quiz-video $stage PID=$($process.Id) evidence=$evidence"
        $process.WaitForExit()
        $process.Refresh()
        $stageEnd = [datetime]::UtcNow
        $exitCode = $process.ExitCode
        $stageResult = [ordered]@{Stage=$stage;PID=$process.Id;StartedAtUtc=$stageStart.ToString('o');FinishedAtUtc=$stageEnd.ToString('o');ExitCode=$exitCode;Stdout=$stdout;Stderr=$stderr;Launcher=$launcher;WorkingDirectory=$runDir;Marker=$marker;MarkerFresh=$false}
        if (Test-Path -LiteralPath $marker) {
            $stamp = (Get-Item -LiteralPath $marker).LastWriteTimeUtc
            $stageResult.MarkerFresh = ($stamp -ge $stageStart -and $stamp -le $stageEnd)
            $stageResult.MarkerModifiedUtc = $stamp.ToString('o')
        }
        $results.Add($stageResult)
        $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'stages.json') -Encoding utf8
        if ($exitCode -ne 0 -or -not $stageResult.MarkerFresh) { throw "TD $stage failed or stale marker; inspect $evidence" }
        if (-not (Select-String -LiteralPath $stdout -SimpleMatch "SC520_QUIZ_VIDEO_STAGE_OK $stage" -Quiet)) { throw "Missing launcher success token for $stage" }
    }
    $changed = @()
    foreach ($relative in $hashes.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $project $relative)).Hash -ne $hashes[$relative] -or
            (Get-FileHash -LiteralPath (Join-Path $snapshot $relative)).Hash -ne $hashes[$relative]) { $changed += $relative }
    }
    foreach ($name in $builderHashes.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash -ne $builderHashes[$name]) { $changed += "builder/$name" }
    }
    $bit = Join-Path $snapshot 'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit'
    if (-not (Test-Path -LiteralPath $bit)) { throw 'No new bit generated' }
    $result = [ordered]@{Variant='quiz-video';StartedAtUtc=$startedUtc.ToString('o');FinishedAtUtc=[datetime]::UtcNow.ToString('o');SourceProject=$project;BuildProject=$snapshot;Bit=$bit;SHA256=(Get-FileHash -LiteralPath $bit).Hash;Bytes=(Get-Item -LiteralPath $bit).Length;HardwareValidated=$false;PhysicalAudioImplemented=$false;SourceSnapshot=$sourceSnapshot;SourceSnapshotSHA256=(Get-FileHash -LiteralPath $sourceSnapshot).Hash;Stages=$results;ChangedInputs=$changed;BuilderHashes=$builderHashes;StartedManifestSHA256=(Get-FileHash -LiteralPath (Join-Path $evidence 'started.json')).Hash}
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'result.json') -Encoding utf8
    if ($changed.Count -ne 0) { throw "Build inputs changed; completed outputs cannot be qualified: $($changed -join ',')" }
    & $Python (Join-Path $toolSnapshot 'archive-build.py') --build-directory $evidence
    if ($LASTEXITCODE -ne 0) { throw 'Build archival failed' }
    & $Python (Join-Path $toolSnapshot 'verify-build.py') --build-directory $evidence
    if ($LASTEXITCODE -ne 0) { throw 'Build verification failed' }
    Write-Output "BUILD_FINISHED $evidence"
} catch {
    [ordered]@{FailedAtUtc=[datetime]::UtcNow.ToString('o');Message=$_.Exception.Message;Stages=$results} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'failure.json') -Encoding utf8
    throw
}
