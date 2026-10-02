#Requires -Version 7.5
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evidence/team-workflow/runs'))

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('delivery-fixtures-' + [guid]::NewGuid().ToString('N'))
$checker = Join-Path $PSScriptRoot 'check-delivery.ps1'
$shell = (Get-Process -Id $PID).Path
$passed = 0
function Test-Fixture {
    param([string]$Name, [hashtable]$Files, [bool]$Expected)
    $fixture = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    & git -C $fixture init -q
    if ($LASTEXITCODE -ne 0) { throw 'Fixture init failed.' }
    foreach ($relative in $Files.Keys) {
        $path = Join-Path $fixture $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, $Files[$relative])
    }
    & git -C $fixture add -- .
    if ($LASTEXITCODE -ne 0) { throw 'Fixture add failed.' }
    $output = & $shell -NoProfile -File $checker -RepoRoot $fixture 2>&1
    $actual = $LASTEXITCODE -eq 0
    $output | Set-Content -LiteralPath (Join-Path $testRoot "$Name.log") -Encoding utf8
    if ($actual -ne $Expected) { throw "Unexpected delivery result for ${Name}: $output" }
    $script:passed++
    Write-Output "PASS: $Name"
}
Test-Fixture -Name 'valid' -Files @{'README.md'='[data](data.json)';'data.json'='{"ready":false}'} -Expected $true
Test-Fixture -Name 'missing-link' -Files @{'README.md'='[missing](missing.md)'} -Expected $false
Test-Fixture -Name 'outside-link' -Files @{'README.md'='[outside](../README.md)'} -Expected $false
Test-Fixture -Name 'bad-json' -Files @{'data.json'='{'} -Expected $false
Test-Fixture -Name 'private-file' -Files @{'hardware/private/order.txt'='fixture only'} -Expected $false
Test-Fixture -Name 'runtime-file' -Files @{'evidence/demo/runs/raw.log'='fixture only'} -Expected $false
Test-Fixture -Name 'fake-token' -Files @{'data.txt'=('ghp_' + ('a' * 36))} -Expected $false
Test-Fixture -Name 'unicode-name' -Files @{'非ASCII.md'='fixture only'} -Expected $false
Write-Output "PASS: $passed delivery checks; fixtures=$testRoot"
