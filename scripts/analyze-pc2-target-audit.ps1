param(
    [Parameter(Mandatory)][string]$Log,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$events = @{}
foreach ($line in Get-Content -LiteralPath $Log) {
    if ($line -notmatch 'victory_gpu::target_audit: render target lifetime') { continue }
    $fields = @{}
    foreach ($match in [regex]::Matches($line, '(?<key>[a-z_]+)=(?:"(?<quoted>[^"]*)"|(?<bare>[^\s]+))')) {
        $fields[$match.Groups['key'].Value] = if ($match.Groups['quoted'].Success) { $match.Groups['quoted'].Value } else { $match.Groups['bare'].Value }
    }
    if (-not $fields.ContainsKey('serial') -or -not $fields.ContainsKey('event')) { continue }
    $id = [string]$fields.serial
    if (-not $events.ContainsKey($id)) { $events[$id] = [ordered]@{ Serial=$id; Start=0L; Bytes=0L; HostBytes=0L; Created=0L; End=[long]::MaxValue; Destroyed=$false; Resource=''; Format=0; Width=0L; Height=0; Flags=0; Pooled=$false; Reused=$false } }
    $entry = $events[$id]
    foreach ($key in @('guest_start','guest_bytes','host_bytes','created_frame','resource','format','width','height','flags','pooled','reused')) {
        if ($fields.ContainsKey($key)) {
            $property = switch ($key) { guest_start {'Start'} guest_bytes {'Bytes'} host_bytes {'HostBytes'} created_frame {'Created'} resource {'Resource'} default {$key.Substring(0,1).ToUpperInvariant()+$key.Substring(1)} }
            $entry[$property] = if ($property -eq 'Resource') { [string]$fields[$key] } elseif ($property -in @('Pooled','Reused')) { [bool]::Parse([string]$fields[$key]) } else { [long]$fields[$key] }
        }
    }
    if ($fields.event -eq 'host_destroy') { $entry.End=[long]$fields.frame; $entry.Destroyed=$true }
}
$live = @($events.Values | Where-Object { $_.Bytes -gt 0 })
$overlaps = [System.Collections.Generic.List[object]]::new()
for ($i=0; $i -lt $live.Count; $i++) {
    for ($j=$i+1; $j -lt $live.Count; $j++) {
        $a=$live[$i]; $b=$live[$j]
        $addressOverlap=($a.Start -lt ($b.Start+$b.Bytes)) -and ($b.Start -lt ($a.Start+$a.Bytes))
        $lifeOverlap=($a.Created -le $b.End) -and ($b.Created -le $a.End)
        if ($addressOverlap -and $lifeOverlap) {
            $overlaps.Add([pscustomobject]@{SerialA=$a.Serial;SerialB=$b.Serial;ResourceA=$a.Resource;ResourceB=$b.Resource;GuestStartA=('0x{0:X}' -f $a.Start);GuestBytesA=$a.Bytes;GuestStartB=('0x{0:X}' -f $b.Start);GuestBytesB=$b.Bytes;OverlapBytes=([Math]::Min($a.Start+$a.Bytes,$b.Start+$b.Bytes)-[Math]::Max($a.Start,$b.Start));FrameA="$($a.Created)-$($a.End)";FrameB="$($b.Created)-$($b.End)";HostBytesA=$a.HostBytes;HostBytesB=$b.HostBytes})
        }
    }
}
$summary=[pscustomobject]@{AuditRows=$events.Count;TargetsWithGuestRanges=$live.Count;StillHostAlive=@($live|Where-Object {-not $_.Destroyed}).Count;PooledTargets=@($events.Values|Where-Object {$_.Pooled}).Count;ReusedTargetRanges=@($events.Values|Where-Object {$_.Reused}).Count;ConfirmedOverlappingAddressAndLifetimePairs=$overlaps.Count;PotentialHostBytes=[long](($overlaps|ForEach-Object {[Math]::Min($_.HostBytesA,$_.HostBytesB)}|Measure-Object -Sum).Sum)}
$summary | Format-List | Out-String | Write-Output
if ($OutputPath) { $overlaps | Export-Csv -LiteralPath $OutputPath -NoTypeInformation; Write-Output "Overlap report: $OutputPath" }
if ($overlaps.Count) { $overlaps | Format-Table -AutoSize | Out-String | Write-Output }
