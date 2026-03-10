#!/usr/bin/env python3
"""Generate XT-L1 machine-readable evidence for SKC-W2-05 runner gate wiring."""

from __future__ import annotations

import datetime as dt
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "x-terminal/.axcoder/reports/skc_w2_05_xt_l1_runner_execute_chain_gate_evidence.v2.json"


def run_capture(args: list[str]) -> dict:
    proc = subprocess.run(
        args,
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    return {
        "cmd": " ".join(args),
        "exit_code": proc.returncode,
        "matches": proc.stdout.strip().splitlines() if proc.stdout else [],
        "stderr": proc.stderr.strip().splitlines() if proc.stderr else [],
    }


def read_rc(path: Path) -> str:
    if not path.exists():
        return "missing"
    return path.read_text(encoding="utf-8").strip()


def main() -> int:
    probe_callsite = run_capture(
        [
            "rg",
            "-n",
            "evaluateSkillExecutionGate\\(|skill_execution_gate_checked|extractSkillExecutionGateBinding|isSkillRunnerToolName",
            "x-hub/grpc-server/hub_grpc_server/src/services.js",
        ]
    )
    probe_log = run_capture(
        [
            "rg",
            "-n",
            "SKC-W1-04/runner execute chain enforces skill execution gate with revoked deny_code|"
            "SKC-W1-04/skills execute fail-closed when package sha binding is missing|grant_pending",
            "build/xt_l1_skc_runner_execute_chain.memory_agent_grant_chain.test.log",
        ]
    )

    rc_memory = read_rc(ROOT / "build/xt_l1_skc_runner_execute_chain.memory_agent_grant_chain.test.rc")
    rc_security = read_rc(ROOT / "build/xt_l1_skc_runner_execute_chain.skills_store_security.test.rc")
    rc_contract = read_rc(ROOT / "build/xt_l1_skc_w2_05_contract.report.rc")

    status = "PASS" if rc_memory == "0" and rc_security == "0" else "FAIL"

    report = {
        "schema_version": "xterminal.skc_w2_05_runner_execute_chain_gate_evidence.v2",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "owner_lane": "XT-L1",
        "scope": ["SKC-W2-05", "SKC-W1-04.unblock_support"],
        "probes": {
            "services_callsites": probe_callsite,
            "runner_gate_log_assertions": probe_log,
            "regression_runs": {
                "memory_agent_grant_chain_test": {
                    "rc_file": "build/xt_l1_skc_runner_execute_chain.memory_agent_grant_chain.test.rc",
                    "rc": rc_memory,
                    "log": "build/xt_l1_skc_runner_execute_chain.memory_agent_grant_chain.test.log",
                },
                "skills_store_security_test": {
                    "rc_file": "build/xt_l1_skc_runner_execute_chain.skills_store_security.test.rc",
                    "rc": rc_security,
                    "log": "build/xt_l1_skc_runner_execute_chain.skills_store_security.test.log",
                },
                "xt_l1_contract_report": {
                    "rc_file": "build/xt_l1_skc_w2_05_contract.report.rc",
                    "rc": rc_contract,
                    "log": "build/xt_l1_skc_w2_05_contract.report.log",
                    "report": "x-terminal/.axcoder/reports/skills_xt_l1_contract_report.json",
                },
            },
        },
        "assessment": {
            "runner_execute_chain_gate_wiring": status,
            "integration_callsites_detected": len(probe_callsite.get("matches", [])),
            "gate_vector_contribution": {
                "SKC-G4": "PASS" if status == "PASS" else "FAIL",
                "SKC-G1": "INSUFFICIENT_EVIDENCE",
                "SKC-G3": "INSUFFICIENT_EVIDENCE",
            },
            "notes": [
                "AgentToolExecute invokes evaluateSkillExecutionGate for skills.execute/skills.run tool names.",
                "SKC-W2-05 remains blocked until require-real samples and upstream SKC-W1-04 dual-green verification complete.",
            ],
        },
        "unblock_signal_for_hub_l3": {
            "blocked_reason_before": "runner_execute_chain_not_integrated.evaluateSkillExecutionGate",
            "current_state": status,
            "required_followups": [
                "Hub-L3 rerun SKC-W1-04 verification with updated callsite evidence",
                "Hub-L5 provide require-real incident samples for SKC-G3/SKC-G4 closeout",
            ],
        },
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

