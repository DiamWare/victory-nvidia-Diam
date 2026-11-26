param(
    [Parameter(Mandatory)][string]$Csv,
    [ValidateRange(0, 86400)][double]$SceneStartSeconds = 0,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
function Num([object]$value) { [double]::Parse([string]$value, $culture) }
function Median([double[]]$values) {
    $sorted = @($values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 0) { return ($sorted[$middle - 1] + $sorted[$middle]) / 2 }
    return $sorted[$middle]
}
$rows = @(Import-Csv -LiteralPath $Csv)
if ($rows.Count -eq 0) { throw "No memory samples in $Csv" }
$needed = @('elapsed_ms','fps','frame_ms','private_commit_bytes','working_set_bytes','local_budget_bytes','local_used_bytes','shared_used_bytes','queued_textures','due_textures','waiting_memory_textures','partial_textures')
foreach ($field in $needed) {
    if (-not $rows[0].PSObject.Properties[$field]) { throw "Missing CSV column: $field" }
}
$summary = foreach ($milestone in @(0, 60, 180, 600)) {
    $target = ($SceneStartSeconds + $milestone) * 1000
    $nearest = $null
    $difference = [double]::PositiveInfinity
    foreach ($row in $rows) {
        $distance = [Math]::Abs((Num $row.elapsed_ms) - $target)
        if ($distance -lt $difference) { $nearest = $row; $difference = $distance }
    }
    if ($difference -gt 5000) {
        [pscustomobject]@{ MilestoneSeconds=$milestone; Status='missing'; SampleSeconds=$null; PrivateCommitMiB=$null; WorkingSetMiB=$null; DedicatedMiB=$null; SharedMiB=$null; LocalBudgetMiB=$null; QueuedTextures=$null; DueTextures=$null; WaitingMemoryTextures=$null; PartialTextures=$null; MedianFPS=$null; MedianFrameMs=$null; P95FrameMs=$null; WindowSamples=0 }
        continue
    }
    $window = @($rows | Where-Object { [Math]::Abs((Num $_.elapsed_ms) - $target) -le 5000 })
    $fps = @($window | ForEach-Object { Num $_.fps })
    $times = @($window | ForEach-Object { Num $_.frame_ms } | Sort-Object)
    $p95 = $times[[Math]::Max(0, [int][Math]::Ceiling($times.Count * 0.95) - 1)]
    [pscustomobject]@{
        MilestoneSeconds = $milestone
        Status = 'measured'
        SampleSeconds = [Math]::Round((Num $nearest.elapsed_ms) / 1000, 1)
        PrivateCommitMiB = [Math]::Round((Num $nearest.private_commit_bytes) / 1MB, 1)
        WorkingSetMiB = [Math]::Round((Num $nearest.working_set_bytes) / 1MB, 1)
        DedicatedMiB = [Math]::Round((Num $nearest.local_used_bytes) / 1MB, 1)
        SharedMiB = [Math]::Round((Num $nearest.shared_used_bytes) / 1MB, 1)
        LocalBudgetMiB = [Math]::Round((Num $nearest.local_budget_bytes) / 1MB, 1)
        QueuedTextures = [int](Num $nearest.queued_textures)
        DueTextures = [int](Num $nearest.due_textures)
        WaitingMemoryTextures = [int](Num $nearest.waiting_memory_textures)
        PartialTextures = [int](Num $nearest.partial_textures)
        MedianFPS = [Math]::Round((Median $fps), 2)
        MedianFrameMs = [Math]::Round((Median $times), 2)
        P95FrameMs = [Math]::Round($p95, 2)
        WindowSamples = $window.Count
    }
}
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $Csv).Path) 'milestones.csv' }
$summary | Export-Csv -LiteralPath $OutputPath -NoTypeInformation
$summary | Format-Table -AutoSize | Out-String | Write-Output
Write-Output "Saved: $OutputPath"
