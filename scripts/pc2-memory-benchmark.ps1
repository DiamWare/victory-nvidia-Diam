param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$RunId,
    [Parameter(Mandatory)][string]$Exe,
    [ValidateSet('MipDrop','Sparse')][string]$Mode = 'MipDrop',
    [ValidateSet('series-s','series-x')][string]$Console = 'series-x',
    [ValidateRange(0,4)][int]$DropMips = 2,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runner = Join-Path $root 'target\release\victory.exe'
$launcher = Join-Path $root 'Play-VIctory.cmd'
$exePath = (Resolve-Path -LiteralPath $Exe).Path
foreach ($path in @($runner,$launcher,$exePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $path" }
}
if ($Check) {
    Write-Output "runner=$runner"
    Write-Output "title=$exePath"
    Write-Output "mode=$Mode; console=$Console; drop_mips=$DropMips"
    Write-Output 'mode=check; no game started'
    return
}
$out = Join-Path $root "benchmarks\$RunId"
if (Test-Path -LiteralPath $out) { throw "Run ID already exists: $out" }
New-Item -ItemType Directory -Path $out -Force | Out-Null
$cache = Join-Path $env:LOCALAPPDATA 'VIctory\cache-pareto'
$data = Join-Path $env:LOCALAPPDATA "VIctory\pc2-benchmark\$RunId"
New-Item -ItemType Directory -Path $data -Force | Out-Null
$csv = Join-Path $out 'memory.csv'
$log = Join-Path $out 'victory.log'
$manifest = Join-Path $out 'run.txt'
@(
    "run_id=$RunId"
    "mode=$Mode"
    "console=$Console"
    "drop_mips=$DropMips"
    'staging_cache_mb=0'
    'target_audit=1'
    "started_utc=$([DateTime]::UtcNow.ToString('o'))"
    "runner_sha256=$((Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash)"
    "title_sha256=$((Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash)"
    "shader_cache=$cache"
    "data_dir=$data"
    'scene_protocol=load the same checkpoint, keep the same camera and position, mark scene start, remain still for 600 seconds'
) | Set-Content -LiteralPath $manifest -Encoding UTF8
$settings = @{
    VICTORY_MEMORY_BENCH_CSV = $csv
    VICTORY_LOG = 'info'
    VICTORY_GAME_DIR = (Split-Path -Parent $exePath)
    VICTORY_TITLE_EXE = $exePath
    VICTORY_RUNNER = $runner
    VICTORY_CONSOLE = $Console
    VICTORY_CACHE_DIR = $cache
    VICTORY_DATA_DIR = $data
    VICTORY_LEVELS_ON_DEMAND = $(if ($Mode -eq 'Sparse') { '1' } else { '0' })
    VICTORY_TEXTURE_DROP_MIPS = [string]$DropMips
    VICTORY_STAGING_CACHE_MB = '0'
    VICTORY_TARGET_AUDIT = '1'
    VICTORY_HELD_LEVELS = '1'
}
$old = @{}
try {
    foreach ($key in $settings.Keys) {
        $old[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, [string]$settings[$key], 'Process')
    }
    # Windows PowerShell promotes native stderr to ErrorRecord objects. With
    # ErrorActionPreference=Stop, ordinary tracing lines would abort the
    # pipeline before the game starts. Merge streams in cmd.exe instead.
    $batch = 'call "{0}" pareto-residency' -f $launcher
    $redirected = '(' + $batch + ') > "' + $log + '" 2>&1'
    & $env:ComSpec /d /s /c $redirected
    $result = $LASTEXITCODE
} finally {
    foreach ($key in $settings.Keys) {
        [Environment]::SetEnvironmentVariable($key, $old[$key], 'Process')
    }
}
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 40 | Write-Output }
"exit_status=$result" | Add-Content -LiteralPath $manifest
Write-Output "Capture=$out"
Write-Output "After closing the game: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'analyze-pc2-memory-benchmark.ps1')`" -Csv `"$csv`" -SceneStartSeconds <offset>"
exit $result
