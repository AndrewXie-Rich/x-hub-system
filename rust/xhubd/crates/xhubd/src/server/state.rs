use std::collections::{BTreeMap, VecDeque};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Mutex;

use xhub_core::{now_ms, HubConfig};
use xhub_memory::MemoryIndexSnapshot;
use xhub_skills::SkillCatalog;

use crate::config::{env_u128_in_range, env_usize_in_range};

pub(crate) struct HubState {
    pub(crate) config: HubConfig,
    pub(crate) http_in_flight: AtomicUsize,
    pub(crate) http_max_in_flight: usize,
    pub(crate) http_slow_ms: u128,
    pub(crate) http_read_timeout_ms: u64,
    pub(crate) http_write_timeout_ms: u64,
    pub(crate) http_metrics_recent_limit: usize,
    pub(crate) http_metrics: Mutex<HttpMetrics>,
    pub(crate) readiness_cache: Mutex<ReadinessCache>,
    pub(crate) readiness_cache_ttl_ms: u128,
    pub(crate) product_kernel_readiness_refresh_in_flight: AtomicBool,
    pub(crate) memory_snapshot_cache: Mutex<MemorySnapshotCache>,
    pub(crate) memory_snapshot_cache_ttl_ms: u128,
    pub(crate) skills_catalog_cache: Mutex<SkillsCatalogCache>,
    pub(crate) skills_catalog_cache_ttl_ms: u128,
}

#[derive(Debug, Clone)]
pub(crate) struct HttpMetrics {
    pub(crate) started_at_ms: u128,
    pub(crate) total_requests: u64,
    pub(crate) slow_requests: u64,
    pub(crate) max_elapsed_ms: u128,
    pub(crate) routes: BTreeMap<String, HttpRouteMetrics>,
    pub(crate) recent_samples: VecDeque<HttpMetricSample>,
    pub(crate) recent_dropped_samples: u64,
}

impl Default for HttpMetrics {
    fn default() -> Self {
        Self {
            started_at_ms: now_ms(),
            total_requests: 0,
            slow_requests: 0,
            max_elapsed_ms: 0,
            routes: BTreeMap::new(),
            recent_samples: VecDeque::new(),
            recent_dropped_samples: 0,
        }
    }
}

#[derive(Debug, Clone)]
pub(crate) struct HttpMetricSample {
    pub(crate) completed_at_ms: u128,
    pub(crate) route: String,
    pub(crate) status: String,
    pub(crate) elapsed_ms: u128,
    pub(crate) slow: bool,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct HttpRouteMetrics {
    pub(crate) count: u64,
    pub(crate) slow_count: u64,
    pub(crate) total_elapsed_ms: u128,
    pub(crate) max_elapsed_ms: u128,
    pub(crate) last_elapsed_ms: u128,
    pub(crate) last_status: String,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct ReadinessCache {
    pub(crate) body: String,
    pub(crate) refreshed_at_ms: u128,
    pub(crate) expires_at_ms: u128,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct MemorySnapshotCache {
    pub(crate) memory_dir: PathBuf,
    pub(crate) snapshot: Option<MemoryIndexSnapshot>,
    pub(crate) expires_at_ms: u128,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct SkillsCatalogCache {
    pub(crate) skills_dir: PathBuf,
    pub(crate) catalog: Option<SkillCatalog>,
    pub(crate) expires_at_ms: u128,
}

pub(crate) struct HttpInflightGuard<'a> {
    pub(crate) state: &'a HubState,
}

impl Drop for HttpInflightGuard<'_> {
    fn drop(&mut self) {
        self.state.http_in_flight.fetch_sub(1, Ordering::AcqRel);
    }
}

impl HubState {
    pub(crate) fn new(config: HubConfig) -> Self {
        Self {
            config,
            http_in_flight: AtomicUsize::new(0),
            http_max_in_flight: env_usize_in_range("XHUB_RUST_HTTP_MAX_IN_FLIGHT", 128, 1, 10_000),
            http_slow_ms: env_u128_in_range("XHUB_RUST_HTTP_SLOW_MS", 2_000, 1, 300_000),
            http_read_timeout_ms: env_u128_in_range(
                "XHUB_RUST_HTTP_READ_TIMEOUT_MS",
                5_000,
                0,
                300_000,
            ) as u64,
            http_write_timeout_ms: env_u128_in_range(
                "XHUB_RUST_HTTP_WRITE_TIMEOUT_MS",
                5_000,
                0,
                300_000,
            ) as u64,
            http_metrics_recent_limit: env_usize_in_range(
                "XHUB_RUST_HTTP_METRICS_RECENT_LIMIT",
                256,
                0,
                10_000,
            ),
            http_metrics: Mutex::new(HttpMetrics::default()),
            readiness_cache: Mutex::new(ReadinessCache::default()),
            readiness_cache_ttl_ms: env_u128_in_range(
                "XHUB_RUST_READY_CACHE_TTL_MS",
                5_000,
                0,
                30_000,
            ),
            product_kernel_readiness_refresh_in_flight: AtomicBool::new(false),
            memory_snapshot_cache: Mutex::new(MemorySnapshotCache::default()),
            memory_snapshot_cache_ttl_ms: env_u128_in_range(
                "XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS",
                500,
                0,
                10_000,
            ),
            skills_catalog_cache: Mutex::new(SkillsCatalogCache::default()),
            skills_catalog_cache_ttl_ms: env_u128_in_range(
                "XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS",
                500,
                0,
                10_000,
            ),
        }
    }
}
