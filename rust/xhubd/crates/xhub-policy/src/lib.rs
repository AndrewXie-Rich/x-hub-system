#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PolicyDecision {
    Allow,
    Queue,
    Deny,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PolicyResult {
    pub decision: PolicyDecision,
    pub reason_code: &'static str,
    pub audit_required: bool,
}

impl PolicyResult {
    pub fn fail_closed(reason_code: &'static str) -> Self {
        Self {
            decision: PolicyDecision::Deny,
            reason_code,
            audit_required: true,
        }
    }
}

pub fn default_fail_closed_policy() -> PolicyResult {
    PolicyResult::fail_closed("rust_hub_policy_not_authoritative")
}
