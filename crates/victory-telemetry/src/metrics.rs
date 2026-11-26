//! Lock-free hand-off from the present path to the recorder.
//!
//! The GPU meter calls [`publish`] once per one-second window, on any build,
//! whether or not telemetry or the overlay is enabled. A small ring keeps
//! every window until the recorder drains it, so a scheduling hiccup cannot
//! duplicate or drop a point in the published FPS graph.

use std::sync::atomic::{AtomicU64, Ordering};

/// Windows retained in the ring. At one per second that is over 17 minutes;
/// the recorder drains it every second, so it only matters if that thread is
/// delayed.
const RING: usize = 1024;

static FPS: [AtomicU64; RING] = [const { AtomicU64::new(0) }; RING];
static MS: [AtomicU64; RING] = [const { AtomicU64::new(0) }; RING];
static DRAWS: [AtomicU64; RING] = [const { AtomicU64::new(0) }; RING];
static CPU_MS: [AtomicU64; RING] = [const { AtomicU64::new(0) }; RING];
static GPU_MS: [AtomicU64; RING] = [const { AtomicU64::new(0) }; RING];
/// Publication marker: a slot is readable when its sequence matches.
static SEQ: [AtomicU64; RING] = [const { AtomicU64::new(0) }; RING];
static NEXT: AtomicU64 = AtomicU64::new(1);

/// One second of the game's frame work.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Metrics {
    pub fps: f64,
    pub ms: f64,
    pub draws: f64,
    /// Milliseconds per frame spent preparing submissions on the CPU.
    pub cpu_ms: f64,
    /// Milliseconds per frame the GPU spent, from submission counters.
    pub gpu_ms: f64,
}

fn scaled(value: f64) -> u64 {
    if value.is_finite() && value >= 0.0 {
        (value * 100.0) as u64
    } else {
        0
    }
}

fn unscaled(value: u64) -> f64 {
    value as f64 / 100.0
}

/// Called by the GPU meter after each one-second window. Cheap and non-fatal.
pub fn publish(fps: f64, ms: f64, draws: f64, cpu_ms: f64, gpu_ms: f64) {
    let seq = NEXT.fetch_add(1, Ordering::Relaxed);
    let index = (seq % RING as u64) as usize;
    FPS[index].store(scaled(fps), Ordering::Relaxed);
    MS[index].store(scaled(ms), Ordering::Relaxed);
    DRAWS[index].store(scaled(draws), Ordering::Relaxed);
    CPU_MS[index].store(scaled(cpu_ms), Ordering::Relaxed);
    GPU_MS[index].store(scaled(gpu_ms), Ordering::Relaxed);
    // Release pairs with the reader's Acquire load, publishing all five values.
    SEQ[index].store(seq, Ordering::Release);
}

/// A reader's position in the ring. Start at zero to see everything published
/// so far; keep the same cursor across drains to get each window exactly once.
#[derive(Clone, Copy, Debug, Default)]
pub struct Cursor(u64);

fn read(index: usize) -> Metrics {
    Metrics {
        fps: unscaled(FPS[index].load(Ordering::Relaxed)),
        ms: unscaled(MS[index].load(Ordering::Relaxed)),
        draws: unscaled(DRAWS[index].load(Ordering::Relaxed)),
        cpu_ms: unscaled(CPU_MS[index].load(Ordering::Relaxed)),
        gpu_ms: unscaled(GPU_MS[index].load(Ordering::Relaxed)),
    }
}

/// Highest sequence fully published at this instant.
fn published() -> u64 {
    (0..RING)
        .map(|index| SEQ[index].load(Ordering::Acquire))
        .fold(0u64, u64::max)
}

/// Every window published since `cursor`, in order. Slots overwritten before
/// the reader got to them are skipped rather than read as stale data.
pub fn drain(cursor: &mut Cursor) -> Vec<Metrics> {
    let latest = published();
    let mut out = Vec::new();
    for seq in cursor.0.saturating_add(1)..=latest {
        if seq + RING as u64 <= latest {
            // This slot has already been reused.
            continue;
        }
        let index = (seq % RING as u64) as usize;
        if SEQ[index].load(Ordering::Acquire) == seq {
            out.push(read(index));
        }
    }
    cursor.0 = latest;
    out
}

/// The most recent published window, if the game has presented one.
pub fn snapshot() -> Option<Metrics> {
    let seq = published();
    if seq == 0 {
        return None;
    }
    Some(read((seq % RING as u64) as usize))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // The ring is a process-wide static, so these tests must not run together.
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn drain_returns_each_window_once_in_order() {
        let _guard = TEST_LOCK.lock().unwrap();
        let start = published();
        let mut cursor = Cursor(start);
        publish(60.0, 16.67, 100.0, 3.0, 12.0);
        publish(30.0, 33.33, 200.0, 4.0, 25.0);
        let got = drain(&mut cursor);
        assert_eq!(got.len(), 2);
        assert!((got[0].fps - 60.0).abs() < 1e-9);
        assert!((got[1].fps - 30.0).abs() < 1e-9);
        assert!((got[1].gpu_ms - 25.0).abs() < 1e-9);
        assert!(drain(&mut cursor).is_empty());
    }

    #[test]
    fn scales_to_hundredths_and_drops_bad_values() {
        let _guard = TEST_LOCK.lock().unwrap();
        publish(59.875, 16.687, 1200.5, 3.25, 12.75);
        let value = snapshot().unwrap();
        assert!((value.fps - 59.87).abs() < 1e-9);
        assert!((value.ms - 16.68).abs() < 1e-9);
        assert!((value.draws - 1200.5).abs() < 1e-9);
        publish(f64::NAN, f64::INFINITY, -1.0, 0.0, 0.0);
        let value = snapshot().unwrap();
        assert_eq!(value.fps, 0.0);
        assert_eq!(value.draws, 0.0);
    }

    #[test]
    fn ring_wrap_keeps_the_newest_windows() {
        let _guard = TEST_LOCK.lock().unwrap();
        let start = published();
        for i in 0..(RING + 3) as u64 {
            publish(i as f64, 1.0, 0.0, 0.0, 0.0);
        }
        let mut cursor = Cursor(start);
        let got = drain(&mut cursor);
        assert_eq!(got.len(), RING);
        assert!((got[0].fps - 3.0).abs() < 1e-9);
        assert!((got[RING - 1].fps - (RING + 2) as f64).abs() < 1e-9);
    }
}
