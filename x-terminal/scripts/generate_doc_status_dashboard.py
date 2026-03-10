#!/usr/bin/env python3
"""Generate a single-source status dashboard for x-terminal markdown docs."""

from __future__ import annotations

import argparse
import datetime as dt
import difflib
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple


DATE_RE = re.compile(r"(20\d{2}-\d{2}-\d{2})")
PHASE_RE = re.compile(r"PHASE(\d+)")


@dataclass
class DocMeta:
    path: Path
    title: str
    phase: Optional[str]
    role: str
    doc_date: Optional[str]
    raw_status: str
    compile_status: str
    dashboard_status: str
    notes: List[str] = field(default_factory=list)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def first_heading(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return "(untitled)"


def extract_field(text: str, labels: List[str]) -> str:
    lines = text.splitlines()
    for line in lines[:80]:
        for label in labels:
            if label in line:
                value = line.split(label, 1)[1].strip()
                return value
    return ""


def extract_date(text: str) -> Optional[str]:
    # Prefer 更新日期 over generic 日期 if both appear.
    priority_labels = [
        "**更新日期**:",
        "**日期**:",
        "**对比日期**:",
        "**规划日期**:",
        "*日期:",
    ]
    lines = text.splitlines()
    for label in priority_labels:
        for line in lines[:120]:
            if label in line:
                m = DATE_RE.search(line)
                if m:
                    return m.group(1)
    # fallback: first date in top section
    m = DATE_RE.search("\n".join(lines[:120]))
    return m.group(1) if m else None


def infer_role(name: str) -> str:
    upper = name.upper()
    if "PENDING" in upper:
        return "pending"
    if "PROGRESS" in upper:
        return "progress"
    if "EXECUTIVE_SUMMARY" in upper:
        return "executive_summary"
    if "SUMMARY" in upper:
        return "summary"
    if "COMPLETE" in upper or "COMPLETION_RECORD" in upper:
        return "completion"
    if "PLAN" in upper:
        return "plan"
    if "STATUS" in upper:
        return "status"
    if "VS " in upper or "DEER" in upper:
        return "comparison"
    return "other"


def infer_dashboard_status(role: str, raw_status: str, title: str) -> str:
    status_text = f"{raw_status} {title}".lower()

    completed_tokens = ["100% 完成", "✅ 完成", "已完成", "完成报告", "完成记录"]
    progress_tokens = ["进行中", "实施中"]
    planned_tokens = ["准备开始", "待开始", "规划完成", "计划"]

    if any(tok in status_text for tok in progress_tokens):
        return "in_progress"
    if any(tok in status_text for tok in completed_tokens):
        return "completed"
    if any(tok in status_text for tok in planned_tokens):
        return "planned"

    role_defaults = {
        "pending": "planned",
        "plan": "planned",
        "completion": "completed",
        "summary": "completed",
        "executive_summary": "in_progress",
        "progress": "in_progress",
        "status": "in_progress",
        "comparison": "completed",
    }
    return role_defaults.get(role, "unknown")


def parse_doc(path: Path) -> DocMeta:
    text = read_text(path)
    title = first_heading(text)
    phase_m = PHASE_RE.search(path.name.upper())
    phase = phase_m.group(1) if phase_m else None
    role = infer_role(path.name)
    doc_date = extract_date(text)
    raw_status = extract_field(text, ["**当前状态**:", "**状态**:"])
    compile_status = extract_field(text, ["**编译状态**:", "**编译**:"])
    dashboard_status = infer_dashboard_status(role, raw_status, title)

    notes: List[str] = []

    # Internal percentage conflict detection for progress docs.
    if role == "progress":
        percentages = set(re.findall(r"(\d+)%", text))
        interesting = {
            p
            for p in percentages
            if p in {"0", "6", "15", "20", "25", "30", "33", "40", "50", "66", "70", "75", "100"}
        }
        # If both 33 and 6 appear it's very likely a conflicting progress signal.
        if "33" in interesting and "6" in interesting:
            notes.append("进度口径冲突: 同文出现 33% 与 6%")

    if role == "plan":
        heading_counts: Dict[str, int] = {}
        for line in text.splitlines():
            if line.startswith("## "):
                heading_counts[line.strip()] = heading_counts.get(line.strip(), 0) + 1
        dupes = [h for h, c in heading_counts.items() if c > 1]
        if dupes:
            notes.append(f"重复二级标题: {len(dupes)} 处")

    return DocMeta(
        path=path,
        title=title,
        phase=phase,
        role=role,
        doc_date=doc_date,
        raw_status=raw_status,
        compile_status=compile_status,
        dashboard_status=dashboard_status,
        notes=notes,
    )


def date_key(value: Optional[str]) -> Tuple[int, str]:
    if not value:
        return (0, "")
    return (1, value)


def apply_cross_doc_rules(docs: List[DocMeta]) -> None:
    # Rule: pending docs are stale if same-phase completion docs exist with same/newer date.
    by_phase: Dict[str, List[DocMeta]] = {}
    for doc in docs:
        if doc.phase:
            by_phase.setdefault(doc.phase, []).append(doc)

    for phase, phase_docs in by_phase.items():
        completed_docs = [
            d
            for d in phase_docs
            if d.dashboard_status == "completed" and d.role in {"completion", "summary"}
        ]
        if not completed_docs:
            continue

        newest_complete = max(completed_docs, key=lambda d: date_key(d.doc_date))
        for doc in phase_docs:
            if doc.role != "pending":
                continue
            # Pending is stale if completion exists on same day or later, or if no date available.
            if not doc.doc_date or not newest_complete.doc_date or doc.doc_date <= newest_complete.doc_date:
                doc.dashboard_status = "stale"
                doc.notes.append(
                    f"已被 {newest_complete.path.name} 覆盖（Phase {phase} 已完成）"
                )

    # Rule: PROJECT_STATUS claims Phase 2 complete but still has legacy run path.
    for doc in docs:
        if doc.path.name == "PROJECT_STATUS.md":
            text = read_text(doc.path)
            if "/x-terminal-legacy/" in text:
                doc.notes.append("启动路径仍指向 legacy 目录，建议改为当前 x-hub-system/x-terminal")


def phase_rollup(docs: List[DocMeta]) -> List[Tuple[str, str, str, str]]:
    """Return list of (phase, status, source, reason)."""
    by_phase: Dict[str, List[DocMeta]] = {}
    for doc in docs:
        if doc.phase:
            by_phase.setdefault(doc.phase, []).append(doc)

    priority_status = {
        "in_progress": 4,
        "completed": 3,
        "planned": 2,
        "unknown": 1,
        "stale": 0,
    }
    priority_role = {
        "progress": 1,
        "completion": 2,
        "summary": 3,
        "status": 4,
        "executive_summary": 5,
        "plan": 6,
        "pending": 7,
        "comparison": 8,
        "other": 9,
    }

    out: List[Tuple[str, str, str, str]] = []
    for phase in sorted(by_phase.keys(), key=int):
        candidates = [d for d in by_phase[phase] if d.dashboard_status != "stale"]
        if not candidates:
            candidates = by_phase[phase]
        best = sorted(
            candidates,
            key=lambda d: (
                priority_status.get(d.dashboard_status, 0),
                -priority_role.get(d.role, 99),
                date_key(d.doc_date),
            ),
            reverse=True,
        )[0]
        reason = best.raw_status or best.title
        out.append((phase, best.dashboard_status, best.path.name, reason))
    return out


def status_label(status: str) -> str:
    return {
        "completed": "completed",
        "in_progress": "in_progress",
        "planned": "planned",
        "stale": "stale",
        "unknown": "unknown",
    }.get(status, status)


def role_label(role: str) -> str:
    return {
        "completion": "completion",
        "summary": "summary",
        "executive_summary": "exec_summary",
        "pending": "pending",
        "progress": "progress",
        "plan": "plan",
        "status": "status",
        "comparison": "comparison",
    }.get(role, role)


def generate_markdown(docs: List[DocMeta], generated_at: str) -> str:
    lines: List[str] = []
    lines.append("# X-Terminal 文档状态面板（Single Source of Truth）")
    lines.append("")
    lines.append("> 自动生成文件；请勿手工编辑。")
    lines.append("")
    lines.append(f"- generated_at: {generated_at}")
    lines.append("- scope: `x-terminal/*.md`（排除本文件）")
    lines.append("- source_script: `scripts/generate_doc_status_dashboard.py`")
    lines.append("")

    counts: Dict[str, int] = {}
    for doc in docs:
        counts[doc.dashboard_status] = counts.get(doc.dashboard_status, 0) + 1

    lines.append("## 总览")
    lines.append(f"- completed: {counts.get('completed', 0)}")
    lines.append(f"- in_progress: {counts.get('in_progress', 0)}")
    lines.append(f"- planned: {counts.get('planned', 0)}")
    lines.append(f"- stale: {counts.get('stale', 0)}")
    lines.append(f"- unknown: {counts.get('unknown', 0)}")
    lines.append("")

    lines.append("## Phase 裁决")
    lines.append("| Phase | 面板状态 | 依据文档 | 依据摘录 |")
    lines.append("|---|---|---|---|")
    for phase, status, source, reason in phase_rollup(docs):
        lines.append(f"| Phase {phase} | {status_label(status)} | `{source}` | {reason} |")
    lines.append("")

    lines.append("## 文档明细")
    lines.append("| 文件 | 类型 | Phase | 文档日期 | 提取状态 | 面板状态 | 备注 |")
    lines.append("|---|---|---:|---|---|---|---|")
    for doc in sorted(docs, key=lambda x: x.path.name.lower()):
        phase = doc.phase or "-"
        date = doc.doc_date or "-"
        raw_status = doc.raw_status or "-"
        notes = "；".join(doc.notes) if doc.notes else "-"
        lines.append(
            f"| `{doc.path.name}` | {role_label(doc.role)} | {phase} | {date} | {raw_status} | {status_label(doc.dashboard_status)} | {notes} |"
        )
    lines.append("")

    warnings: List[str] = []
    for doc in docs:
        for note in doc.notes:
            warnings.append(f"- `{doc.path.name}`: {note}")

    if warnings:
        lines.append("## 冲突与风险")
        lines.extend(warnings)
        lines.append("")

    lines.append("## 维护约定")
    lines.append("- 本文件为唯一状态入口；其它文档允许保留历史叙述，但不再作为进度裁决依据。")
    lines.append("- 每次更新任意 Phase 文档后，执行一次生成脚本刷新状态面板。")
    lines.append("- 若新增文档，请保持文件命名包含 `PHASE{n}`，便于自动归档。")
    lines.append("")

    lines.append("## 刷新命令")
    lines.append("```bash")
    lines.append("cd x-hub-system/x-terminal")
    lines.append("python3 ./scripts/generate_doc_status_dashboard.py")
    lines.append("```")
    lines.append("")

    lines.append("## 校验命令（CI/本地）")
    lines.append("```bash")
    lines.append("cd x-hub-system/x-terminal")
    lines.append("python3 ./scripts/generate_doc_status_dashboard.py --check")
    lines.append("```")
    lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def load_existing_generated_at(out_path: Path) -> Optional[str]:
    if not out_path.exists():
        return None
    for line in out_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if line.startswith("- generated_at: "):
            return line.split(": ", 1)[1].strip()
    return None


def check_up_to_date(out_path: Path, expected: str) -> int:
    if not out_path.exists():
        print(f"[doc-status] missing output: {out_path}", file=sys.stderr)
        print("[doc-status] run: python3 ./scripts/generate_doc_status_dashboard.py", file=sys.stderr)
        return 2

    current = out_path.read_text(encoding="utf-8", errors="ignore")
    if current == expected:
        print(f"[doc-status] up-to-date: {out_path}")
        return 0

    print(f"[doc-status] out-of-date: {out_path}", file=sys.stderr)
    print("[doc-status] run: python3 ./scripts/generate_doc_status_dashboard.py", file=sys.stderr)
    diff = difflib.unified_diff(
        current.splitlines(),
        expected.splitlines(),
        fromfile=f"{out_path.name} (current)",
        tofile=f"{out_path.name} (expected)",
        lineterm="",
    )
    preview = list(diff)[:80]
    if preview:
        print("[doc-status] diff preview:", file=sys.stderr)
        for line in preview:
            print(line, file=sys.stderr)
    return 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=".",
        help="x-terminal root directory (default: current directory)",
    )
    parser.add_argument(
        "--out",
        default="DOC_STATUS_DASHBOARD.md",
        help="output markdown file relative to root",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="check whether dashboard is up-to-date without writing file",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    out_path = root / args.out

    docs = [
        parse_doc(path)
        for path in sorted(root.glob("*.md"))
        if path.name != out_path.name
    ]
    apply_cross_doc_rules(docs)

    generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    if args.check:
        existing_generated_at = load_existing_generated_at(out_path)
        if existing_generated_at:
            generated_at = existing_generated_at

    markdown = generate_markdown(docs, generated_at)
    if args.check:
        return check_up_to_date(out_path, markdown)
    out_path.write_text(markdown, encoding="utf-8")
    print(f"[doc-status] generated: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
