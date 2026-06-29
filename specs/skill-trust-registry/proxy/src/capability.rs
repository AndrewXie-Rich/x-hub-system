//! Capability token parser + decision logic, per protocol v0.1 §5.
//!
//! Token form: `category:action[:scope]`.
//! - `fs:read:/tmp/**`  — POSIX `**` glob over paths.
//! - `net:fetch:api.github.com`  — host; `*` means any.
//! - `shell:exec[:program]`  — program scope, omitted = any.
//! - `secret:read:GITHUB_TOKEN`  — exact name.
//! - `env:read:NAME`  — exact name.
//! - `mcp:call:other-server.tool`  — exact server.tool.

use anyhow::{bail, Result};

#[derive(Debug, PartialEq, Eq)]
pub enum Decision {
    /// Required by the manifest AND granted at install time.
    Allow,
    /// Optional capability — user re-grant required.
    Prompt,
    /// Not declared by the manifest at all — deny by default (§5.6).
    Deny,
}

#[derive(Debug, Clone)]
pub struct Token {
    pub category: String,
    pub action: String,
    pub scope: Option<String>,
}

impl Token {
    pub fn parse(s: &str) -> Result<Self> {
        let mut parts = s.splitn(3, ':');
        let category = parts.next().unwrap_or_default();
        let action = match parts.next() {
            Some(a) if !a.is_empty() => a,
            _ => bail!("capability token missing action: {s}"),
        };
        if category.is_empty() {
            bail!("capability token missing category: {s}");
        }
        let scope = parts.next().filter(|s| !s.is_empty()).map(String::from);
        Ok(Token {
            category: category.into(),
            action: action.into(),
            scope,
        })
    }

    /// Does this declared token cover the requested access?
    pub fn covers(&self, requested: &Token) -> bool {
        if self.category != requested.category || self.action != requested.action {
            return false;
        }
        match (&self.scope, &requested.scope) {
            (None, _) => true,
            (Some(declared), None) => declared == "*",
            (Some(declared), Some(req)) => match self.category.as_str() {
                "fs" => glob_match(declared, req),
                "net" => host_match(declared, req),
                _ => declared == "*" || declared == req,
            },
        }
    }
}

/// Resolve a requested access against required + optional sets.
pub fn decide(required: &[String], optional: &[String], requested: &str) -> Result<Decision> {
    let req = Token::parse(requested)?;
    if matches_any(required, &req)? {
        return Ok(Decision::Allow);
    }
    if matches_any(optional, &req)? {
        return Ok(Decision::Prompt);
    }
    Ok(Decision::Deny)
}

fn matches_any(declared: &[String], requested: &Token) -> Result<bool> {
    for d in declared {
        let dt = Token::parse(d)?;
        if dt.covers(requested) {
            return Ok(true);
        }
    }
    Ok(false)
}

fn glob_match(pattern: &str, candidate: &str) -> bool {
    match glob::Pattern::new(pattern) {
        Ok(p) => p.matches(candidate),
        Err(_) => false,
    }
}

fn host_match(pattern: &str, candidate: &str) -> bool {
    if pattern == "*" {
        return true;
    }
    let (p_host, p_port) = split_host_port(pattern);
    let (c_host, c_port) = split_host_port(candidate);
    if p_host != c_host && p_host != "*" {
        return false;
    }
    match (p_port, c_port) {
        (None, _) => true,
        (Some(pp), Some(cp)) => pp == cp,
        (Some(_), None) => false,
    }
}

fn split_host_port(s: &str) -> (&str, Option<&str>) {
    match s.rsplit_once(':') {
        Some((host, port)) if port.chars().all(|c| c.is_ascii_digit()) => (host, Some(port)),
        _ => (s, None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req(required: &[&str], optional: &[&str]) -> (Vec<String>, Vec<String>) {
        (
            required.iter().map(|s| s.to_string()).collect(),
            optional.iter().map(|s| s.to_string()).collect(),
        )
    }

    #[test]
    fn allow_when_required_glob_covers() {
        let (r, o) = req(&["fs:read:/tmp/**"], &[]);
        assert_eq!(decide(&r, &o, "fs:read:/tmp/screenshots/a.png").unwrap(), Decision::Allow);
    }

    #[test]
    fn prompt_when_only_optional_covers() {
        let (r, o) = req(&[], &["shell:exec"]);
        assert_eq!(decide(&r, &o, "shell:exec:rm").unwrap(), Decision::Prompt);
    }

    #[test]
    fn deny_when_no_declaration() {
        let (r, o) = req(&["fs:read:/tmp/**"], &["shell:exec"]);
        assert_eq!(decide(&r, &o, "secret:read:GITHUB_TOKEN").unwrap(), Decision::Deny);
    }

    #[test]
    fn fs_glob_does_not_overreach() {
        let (r, o) = req(&["fs:read:/tmp/**"], &[]);
        assert_eq!(decide(&r, &o, "fs:read:/etc/passwd").unwrap(), Decision::Deny);
    }

    #[test]
    fn net_host_match_with_wildcard() {
        let (r, o) = req(&["net:fetch:*"], &[]);
        assert_eq!(decide(&r, &o, "net:fetch:api.github.com").unwrap(), Decision::Allow);
    }

    #[test]
    fn net_host_exact_match() {
        let (r, o) = req(&["net:fetch:api.github.com"], &[]);
        assert_eq!(decide(&r, &o, "net:fetch:api.github.com").unwrap(), Decision::Allow);
        assert_eq!(decide(&r, &o, "net:fetch:evil.example").unwrap(), Decision::Deny);
    }

    #[test]
    fn shell_program_scope() {
        let (r, o) = req(&["shell:exec:git"], &[]);
        assert_eq!(decide(&r, &o, "shell:exec:git").unwrap(), Decision::Allow);
        assert_eq!(decide(&r, &o, "shell:exec:rm").unwrap(), Decision::Deny);
    }

    #[test]
    fn secret_exact_only() {
        let (r, o) = req(&[], &["secret:read:GITHUB_TOKEN"]);
        assert_eq!(decide(&r, &o, "secret:read:GITHUB_TOKEN").unwrap(), Decision::Prompt);
        assert_eq!(decide(&r, &o, "secret:read:AWS_KEY").unwrap(), Decision::Deny);
    }
}
