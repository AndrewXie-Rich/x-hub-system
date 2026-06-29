mod shared;
pub use shared::{memory_dir_from_env, memory_writer_authority_enabled};
mod snapshot;
pub use snapshot::{readiness_json_from_snapshot_with_config, snapshot_from_dir};
mod gate;
mod projection;
mod read;
pub use read::{retrieve_json_from_request_with_config_and_snapshot, retrieve_request_from_value};
mod write;
pub use write::write_json_from_value;
mod http;
pub use http::{
    memory_gateway_prepare_http_json, object_collection_http_json, object_index_rebuild_http_json,
    object_item_http_json, policy_evaluate_http_json, project_canonical_sync_http_json,
    writeback_candidates_http_json,
};
mod cli;
pub use cli::run;

// The large legacy test module still imports the bridge internals through
// `super::*`. Keep those aggregate imports test-only so runtime builds stay
// explicit and warning-free.
#[cfg(test)]
#[allow(unused_imports)]
use std::collections::{BTreeMap, BTreeSet};
#[cfg(test)]
#[allow(unused_imports)]
use std::fmt::Write as _;
#[cfg(test)]
#[allow(unused_imports)]
use std::path::PathBuf;

#[cfg(test)]
#[allow(unused_imports)]
use serde_json::{json, Value};
#[cfg(test)]
#[allow(unused_imports)]
use xhub_core::HubConfig;
#[cfg(test)]
#[allow(unused_imports)]
use xhub_db::{
    apply_baseline_migrations, create_memory_object_with_event, list_memory_object_index,
    list_memory_objects, read_memory_object, read_memory_object_history,
    read_memory_object_index_summary, read_memory_object_store_summary,
    rebuild_memory_object_index, update_memory_object_with_event, MemoryEventRecord,
    MemoryObjectIndexFilter, MemoryObjectIndexRecord, MemoryObjectIndexSummary,
    MemoryObjectListFilter, MemoryObjectRecord,
};
#[cfg(test)]
#[allow(unused_imports)]
use xhub_memory::{
    retrieve_memory, retrieve_memory_from_snapshot, scan_memory_snapshot, write_memory_entry,
    MemoryIndexSnapshot, MemoryMode, MemoryRetrievalRequest, MemoryWriteRequest,
    MEMORY_RETRIEVAL_RESULT_SCHEMA, MEMORY_WRITE_RESULT_SCHEMA, RUST_MEMORY_SHADOW_SOURCE,
};

#[cfg(test)]
#[allow(unused_imports)]
use cli::{dispatch, object_index_rebuild_cli_json};
#[cfg(test)]
#[allow(unused_imports)]
use gate::*;
#[cfg(test)]
#[allow(unused_imports)]
use projection::*;
#[cfg(test)]
#[allow(unused_imports)]
use read::*;
#[cfg(test)]
#[allow(unused_imports)]
use shared::*;
#[cfg(test)]
#[allow(unused_imports)]
use snapshot::*;
#[cfg(test)]
#[allow(unused_imports)]
use write::candidate::*;
#[cfg(test)]
#[allow(unused_imports)]
use write::canonical::*;
#[cfg(test)]
#[allow(unused_imports)]
use write::object::*;
#[cfg(test)]
#[allow(unused_imports)]
use write::*;

#[cfg(test)]
mod tests;
