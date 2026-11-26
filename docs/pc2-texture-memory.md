# Texture and render-target memory work

This change set adds instrumentation and opt-in controls; it does not claim an
FPS improvement without comparable gameplay captures.

## Staging cache

Per-texture upload staging is not retained between uses by default:
`VICTORY_STAGING_CACHE_MB` defaults to `0`. Set it to a nonzero value to opt in
to a bounded warm cache (maximum 8192 MiB). In-flight command lists keep their
`Arc` reference, so cache eviction cannot free an upload buffer still used by
recorded work. Memory pressure always forces the cache budget to zero.

## Mip reduction and sparse residency

`VICTORY_TEXTURE_DROP_MIPS` selects a coarser base mip from 0 through 4. The
existing `VICTORY_LEVELS_ON_DEMAND=1` path uses tiled sparse residency; when
that is off, the host copy can begin at a coarser mip where views permit it.
Run the same scene with `scripts/compare-pc2-residency.ps1` to produce separate
captures; the harness does not synthesize or promise a performance result.

## Memory benchmark and target audit

Set `VICTORY_MEMORY_BENCH_CSV` to write one CSV sample per second. Private
commit, working set, local/shared DXGI budget and use, queue state and frame
timings are recorded as separate columns. `scripts/analyze-pc2-memory-benchmark.ps1`
summarizes the 0/60/180/600-second milestones relative to an explicit scene
start offset.

Set `VICTORY_TARGET_AUDIT=1` to log target/depth host-resource create/destroy
events with guest address ranges, lifetimes, and whether an allocation was
pooled or reused. Run
`scripts/analyze-pc2-target-audit.ps1` on the resulting log. Address/lifetime
overlap is a candidate signal, not proof that two targets can be safely aliased.
The RT/DS pool places single-sample 2D color render targets and depth-only
targets; UAV, combined depth/UAV, multisample, and non-2D resources continue to
use committed allocations. It is **disabled by default** because the prior
MipDrop run ended in GPU device removal before a comparable stability run.
Set `VICTORY_TARGET_POOL=1` to opt in for an A/B test only. Each placed
resource (including one on a fresh heap) is activated in the
submission-ordered prelude with a D3D12 aliasing barrier, transitioned to
render-target or depth-write state, discarded for initialization, then
transitioned to the first requested state. This follows
the
[D3D12 placed-resource activation and initialization requirements](https://learn.microsoft.com/en-us/windows/desktop/api/d3d12/nf-d3d12-id3d12device-createplacedresource).
Diagnostics builds add DRED breadcrumb labels for alias activation, RT/DS
transitions, discard, and first-use state restoration.

## Series S profile

`scripts/play-series-s-low-memory.ps1` applies a reversible process-local
profile and restores the caller's environment when the runner exits. Use
`-Check` to inspect settings without launching the game.
