param(
    [Parameter(Mandatory)][string]$Exe,
    [ValidateSet('diag','release')][string]$Build = 'release',
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runner = Join-Path $root "target\$Build\victory.exe"
$exePath = (Resolve-Path -LiteralPath $Exe).Path
foreach ($path in @($runner,$exePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $path" }
}
$profile = @{
    VICTORY_CONSOLE='series-s'; VICTORY_CARD_WINDOWS_MB='256'; VICTORY_CARD_BUFFERS_MB='768'
    VICTORY_WINDOW_KB='512'; VICTORY_WINDOW_TAILS='1'; VICTORY_CARD_BUFFERS_MIN_KB='64'
    VICTORY_LEVELS_ON_DEMAND='1'; VICTORY_TEXTURE_DROP_MIPS='1'; VICTORY_HELD_LEVELS='1'
    VICTORY_STAGING_CACHE_MB='0'
    VICTORY_TEXTURE_NO_WAIT='1'; VICTORY_RELAY='2'; VICTORY_WIDE_BACK='1'
}
if ($Check) {
    Write-Output "runner=$runner"
    foreach ($key in $profile.Keys) { Write-Output "$key=$($profile[$key])" }
    Write-Output 'mode=check; no game started'
    return
}
$old = @{}
try {
    foreach ($key in $profile.Keys) {
        $old[$key] = [Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$profile[$key],'Process')
    }
    Push-Location $root
    try { & $runner run $exePath --console series-s --execute; $result=$LASTEXITCODE }
    finally { Pop-Location }
} finally {
    foreach ($key in $profile.Keys) { [Environment]::SetEnvironmentVariable($key,$old[$key],'Process') }
}
exit $result
