param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$RunPrefix,
    [Parameter(Mandatory)][string]$Exe,
    [ValidateSet('series-s','series-x')][string]$Console = 'series-x',
    [ValidateRange(0,4)][int]$DropMips = 2,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$bench = Join-Path $PSScriptRoot 'pc2-memory-benchmark.ps1'
$runs = @(
    [pscustomobject]@{ Id = "${RunPrefix}_mipdrop"; Mode = 'MipDrop'; DropMips = $DropMips },
    [pscustomobject]@{ Id = "${RunPrefix}_sparse"; Mode = 'Sparse'; DropMips = 0 },
    [pscustomobject]@{ Id = "${RunPrefix}_sparse_mipdrop"; Mode = 'Sparse'; DropMips = $DropMips }
)
foreach ($run in $runs) {
    if ($Check) {
        Write-Output "run_id=$($run.Id); mode=$($run.Mode); console=$Console; drop_mips=$($run.DropMips)"
        continue
    }
    Write-Output "Run $($run.Mode): use the same checkpoint and camera, stand still for 600 seconds, then close the game before the next run."
    & $bench -RunId $run.Id -Exe $Exe -Mode $run.Mode -Console $Console -DropMips $run.DropMips
    if ($LASTEXITCODE -ne 0) { throw "Benchmark $($run.Id) exited $LASTEXITCODE" }
}
if ($Check) { Write-Output 'mode=check; no game started'; return }
Write-Output 'Analyze each memory.csv with analyze-pc2-memory-benchmark.ps1 and the measured scene-start offset; this harness makes no FPS claim.'
