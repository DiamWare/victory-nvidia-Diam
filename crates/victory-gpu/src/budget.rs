//! Shared admission policy for host-side GPU allocations.
//!
//! Adapter usage is authoritative for the whole process, including render
//! targets, sparse heaps and uploaded textures. Callers subtract only bytes
//! they can reclaim and pass subsystem reservations to the same policy.

const WITHOUT_BUDGET: u64 = 4 << 30;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Pressure { Normal, Constrained, Critical }

pub(crate) fn pressure(memory: Option<[u64; 4]>) -> Pressure {
    let Some([budget, used, ..]) = memory else { return Pressure::Normal };
    if budget == 0 { return Pressure::Critical; }
    let pct = u128::from(used) * 100 / u128::from(budget);
    if pct >= 95 { Pressure::Critical }
    else if pct >= 85 { Pressure::Constrained }
    else { Pressure::Normal }
}

pub(crate) fn admit_textures(
    memory: Option<[u64; 4]>, filled: u64, floor: u64, reclaimable: u64,
    shadow_reserved: u64, target_reserved: u64, percent: u64,
) -> bool {
    if filled < floor { return true; }
    match memory {
        Some([budget, used, ..]) => {
            let accounted = u128::from(used.saturating_sub(reclaimable))
                + u128::from(shadow_reserved) + u128::from(target_reserved);
            accounted < u128::from(budget) * u128::from(percent.clamp(50, 97)) / 100
        }
        None => filled < WITHOUT_BUDGET,
    }
}

pub(crate) fn admit_pool_growth(memory: Option<[u64; 4]>, allocation: u64) -> bool {
    match memory {
        Some([budget, used, ..]) if budget > 0 =>
            u128::from(used) + u128::from(allocation) <= u128::from(budget) * 90 / 100,
        Some(_) => false,
        None => allocation <= 64 << 20,
    }
}

/// Dedicated uploads have no smaller fallback. When budget information is
/// unavailable, let the existing residency policy decide whether to allocate.
pub(crate) fn admit_staging_allocation(memory: Option<[u64; 4]>, allocation: u64) -> bool {
    memory.is_none() || admit_pool_growth(memory, allocation)
}

#[cfg(test)]
mod tests {
    use super::{Pressure, admit_pool_growth, admit_staging_allocation, admit_textures, pressure};

    #[test]
    fn dedicated_large_upload_can_fall_back_when_budget_is_unknown() {
        let large = 128 << 20;
        assert!(!admit_pool_growth(None, large));
        assert!(admit_staging_allocation(None, large));
        assert!(!admit_staging_allocation(Some([1 << 30, 1 << 30, 0, 0]), large));
    }

    #[test]
    fn adapter_pressure_is_shared_across_texture_and_pool_admission() {
        let memory = Some([8 << 30, (8 << 30) * 96 / 100, 0, 0]);
        assert_eq!(pressure(memory), Pressure::Critical);
        assert!(admit_textures(memory, 2 << 30, 2 << 30, 0, 0, 0, 97));
        assert!(!admit_pool_growth(memory, 64 << 20));
        assert!(admit_pool_growth(Some([8 << 30, 6 << 30, 0, 0]), 64 << 20));
    }

    #[test]
    fn floor_and_no_budget_ceiling_are_preserved() {
        assert!(admit_textures(Some([4 << 30, 4 << 30, 0, 0]), 0, 1 << 30, 0, 0, 0, 90));
        assert!(admit_textures(None, 3 << 30, 0, 0, 0, 0, 90));
        assert!(!admit_textures(None, 4 << 30, 0, 0, 0, 0, 90));
    }
}
