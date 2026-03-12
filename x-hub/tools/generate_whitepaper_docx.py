#!/usr/bin/env python3
"""Generate a minimal .docx security whitepaper without external deps.

We avoid python-docx/lxml to keep this repo self-contained.
"""

from __future__ import annotations

import os
import zipfile
from datetime import datetime
from pathlib import Path
from xml.sax.saxutils import escape


def _p(text: str, *, bold: bool = False, monospace: bool = False) -> str:
    rpr = ""
    if bold:
        rpr += "<w:b/>"
    if monospace:
        # Use a common fixed-width font.
        rpr += (
            "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" w:cs=\"Courier New\"/>"
            "<w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/>"
        )
    t = escape(text)
    return (
        "<w:p>"
        "<w:r>"
        f"<w:rPr>{rpr}</w:rPr>"
        f"<w:t xml:space=\"preserve\">{t}</w:t>"
        "</w:r>"
        "</w:p>"
    )


def _blank() -> str:
    return "<w:p/>"


def build_docx(out_path: Path, *, version: str) -> None:
    now = datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

    title = f"AX REL Flow Hub Security Whitepaper (v{version})"

    # Use plain paragraphs + ASCII diagrams; Word will render this fine.
    paras: list[str] = []
    paras.append(_p(title, bold=True))
    paras.append(_p("Author: Andrew Xie (AX)"))
    paras.append(_p(f"Last updated (UTC): {now}"))
    paras.append(_blank())

    paras.append(_p("0. 摘要 (Executive Summary)", bold=True))
    paras.append(_p(
        "X-Hub（以下简称“Hub”）是一个 macOS 本地应用，用于为内部自研应用提供离线 AI 资源调度能力，并充当本机信息提醒中心。\n"
        "Hub 的安全设计采用 Offline-First + Least-Privilege（最小权限）原则：\n"
        "- Hub Core（X-Hub.app）不具备出网能力（无 network client entitlement）。\n"
        "- 所有敏感能力通过 macOS 原生权限体系（TCC/App Sandbox/Code Signing）进行显式授权与隔离。\n"
        "- 需要联网时，使用独立可审计的 Bridge（X-Hub Bridge.app）作为网络边界，默认关闭，可限时启用。\n"
        "- 与卫星应用（FA Tracker 等）的交互默认采用可审计的本地 IPC（文件投递/心跳），避免隐式网络依赖。"
    ))
    paras.append(_blank())

    paras.append(_p("0.1 关键安全目标", bold=True))
    paras.append(_p("- 0.1.1 零出网：Hub Core 不产生任何外向网络连接 (network egress)。"))
    paras.append(_p("- 0.1.2 最小数据：默认只读取“计数/状态信号”（counts-only），避免读取内容本体。"))
    paras.append(_p("- 0.1.3 可审计：关键交互面（IPC/状态文件/权限）可落地为可检查的本地证据。"))
    paras.append(_p("- 0.1.4 可分离：需要联网能力时，在可控边界内显式启用 Bridge。"))
    paras.append(_blank())

    paras.append(_p("1. 威胁模型 (Threat Model)", bold=True))
    paras.append(_p("1.1 主要威胁面", bold=True))
    paras.append(_p("- 网络外泄：通过网络将本机数据发送到外部（首要威胁）。"))
    paras.append(_p("- 过度权限：TCC 权限授予过宽导致读取不必要的数据内容。"))
    paras.append(_p("- IPC 注入：卫星应用/脚本向 Hub 投递恶意或畸形 IPC 请求。"))
    paras.append(_p("- 本地落盘泄漏：日志/状态文件包含敏感信息导致二次泄漏。"))
    paras.append(_p("1.2 非目标 (Non-goals)", bold=True))
    paras.append(_p("- 不对抗 OS/内核完全被入侵后的威胁。"))
    paras.append(_p("- 不保护用户主动复制/粘贴到第三方应用/网页中的敏感内容。"))
    paras.append(_blank())

    paras.append(_p("2. 系统架构与组件边界", bold=True))
    paras.append(_p("2.1 组件", bold=True))
    paras.append(_p("- Hub Core: X-Hub.app（App Sandbox + Offline, 不具备 network client entitlement）"))
    paras.append(_p("- Bridge: X-Hub Bridge.app（可选，具备 network client entitlement，默认关闭，可限时启用）"))
    paras.append(_p("- Dock Agent: X-Hub Dock Agent.app（可选，用于读取 Dock badge 计数，需 Accessibility）"))
    paras.append(_p("- Satellites: 由你控制的自研应用（如 FA Tracker、未来 AX Coder），通过本地 IPC 接入 Hub。"))
    paras.append(_blank())

    paras.append(_p("2.2 高层数据流 (ASCII)", bold=True))
    paras.append(_p(
        "+---------------------+                 +-----------------------+\n"
        "|  Satellite Apps     |  file IPC push  |  AX X-Hub.app          |\n"
        "| (FA Tracker, etc.)  +---------------->+ (Sandbox, no egress)   |\n"
        "+---------+-----------+                 +-----------+-----------+\n"
        "          |                                         |\n"
        "          | local UI / actions                       | EventKit / Accessibility (TCC)\n"
        "          v                                         v\n"
        "+---------------------+                 +-----------------------+\n"
        "| User Interaction    |                 | Local System Services |\n"
        "| (Menu bar, Floating)|                 | (Calendar, Dock, etc) |\n"
        "+---------------------+                 +-----------------------+\n"
        "\n"
        "Optional networking path (isolated):\n"
        "+---------------------+                 +-----------------------+\n"
        "| X-Hub Bridge.app    | <--- local IPC  | AX X-Hub.app          |\n"
        "| (network client)    |                 | (no network client)   |\n"
        "+---------------------+                 +-----------------------+\n",
        monospace=True,
    ))
    paras.append(_blank())

    paras.append(_p("3. 零出网保证 (Network Egress Prevention)", bold=True))
    paras.append(_p("3.1 Hub Core：Entitlement 层面的出网阻断", bold=True))
    paras.append(_p(
        "Hub Core 通过 App Sandbox + Code Signing Entitlements 实现出网阻断：\n"
        "- 不包含 com.apple.security.network.client entitlement\n"
        "- 即使业务代码尝试发起 HTTP/TCP 连接，也会被系统在权限层面拒绝\n"
        "- 该控制点可通过 codesign 工具直接审计（见 3.3）"
    ))
    paras.append(_p("3.2 Bridge：显式网络边界", bold=True))
    paras.append(_p(
        "当且仅当需要联网功能时，启用 Bridge：\n"
        "- Bridge 是独立可执行体，具备 network client entitlement\n"
        "- 默认关闭，且可以按时间窗口启用（例如 30 分钟）\n"
        "- Hub Core 与 Bridge 之间仅通过本地 IPC 交换有限、可审计的数据"
    ))
    paras.append(_blank())

    paras.append(_p("3.3 审计方法（Entitlements / 运行时）", bold=True))
    paras.append(_p(
        "(A) 审计 entitlements：\n"
        "- codesign -d --entitlements :- /Applications/X-Hub.app\n"
        "- codesign -d --entitlements :- /Applications/X-Hub\\ Bridge.app\n"
        "期望结果：X-Hub.app 不存在 network.client；Bridge 可能存在。\n\n"
        "(B) 运行时观测（可选）：\n"
        "- nettop / lsof -i / pfctl 规则（按企业安全策略选择）\n"
        "目标：确认 Hub Core 进程无外向连接，仅 Bridge 进程可见网络活动。\n",
        monospace=True,
    ))
    paras.append(_blank())

    paras.append(_p("4. 权限与数据访问 (Least Privilege)", bold=True))
    paras.append(_p("4.1 Calendar (EventKit)", bold=True))
    paras.append(_p("- 目的：显示当天会议、生成会议提醒、在无其他信息时显示节假日/纪念日（全日事件）。"))
    paras.append(_p("- 访问方式：通过 EventKit API（系统受控访问），需要用户在 TCC 中显式授权。"))
    paras.append(_p("- 数据策略：优先只用于“提醒/标题/时间范围”，不做外传。"))
    paras.append(_p("4.2 Mail / Messages / Slack（counts-only）", bold=True))
    paras.append(_p("- 目的：只显示未读数量/活动信号，用作提醒，不读取内容本体。"))
    paras.append(_p("- 访问方式：读取 Dock badge（Accessibility）。"))
    paras.append(_p("- 风险控制：避免读取数据库、避免 API token，默认不触达消息内容。"))
    paras.append(_p("4.3 Dock Agent（可选）", bold=True))
    paras.append(_p("- 作用：在部分 macOS 版本上帮助读取 Slack/Messages 的 Dock badge 计数。"))
    paras.append(_p("- 权限：需要 Accessibility（仅用于读取 UI badge，不读取内容数据库）。"))
    paras.append(_blank())

    paras.append(_p("5. 本地 IPC 协议与可审计性", bold=True))
    paras.append(_p("5.1 File-based IPC（沙盒友好）", bold=True))
    paras.append(_p(
        "Hub 支持 file dropbox IPC：卫星应用将 JSON 请求写入 ipc_events/，Hub 轮询读取并处理。\n"
        "该模型具有强可审计性：每个请求都是独立文件，可进行取样、归档与审计。"
    ))
    paras.append(_p("5.2 Heartbeat（Hub 状态证据）", bold=True))
    paras.append(_p(
        "Hub 持续写入 hub_status.json（包含 pid/updatedAt/ipcPath/baseDir/appVersion/build/aiReady 等），" 
        "用于卫星应用与排障工具判定 Hub 是否运行、AI 是否就绪。"
    ))
    paras.append(_p("5.3 可审计证据点（示例）", bold=True))
    paras.append(_p("- hub_status.json：进程活性、协议版本、写入路径"))
    paras.append(_p("- ipc_events/：卫星到 Hub 的请求文件（可审计）"))
    paras.append(_p("- dock_agent_status.json：Dock Agent 是否运行/是否自启/是否已授权"))
    paras.append(_p("- ai_runtime_status.json：本地 AI runtime 心跳"))
    paras.append(_blank())

    paras.append(_p("6. 存储与保留策略", bold=True))
    paras.append(_p(
        "Hub 的状态数据优先写入 App Group 目录（可在同一签名团队内跨应用共享），否则回退到沙盒容器目录。\n"
        "默认策略：\n"
        "- 不需要网络凭证即可运行核心功能\n"
        "- counts-only 信息不持久化内容，仅持久化必要状态/去重字段\n"
        "- 可通过日志与状态文件进行排障，但应避免在日志中写入敏感内容"
    ))
    paras.append(_blank())

    paras.append(_p("7. 详细流程图（离线保证与数据调用）", bold=True))
    paras.append(_p("7.1 离线/出网隔离流程", bold=True))
    paras.append(_p(
        "(1) Hub Core 尝试执行任意网络调用\n"
        "    -> (2) App Sandbox / Entitlements 检查 network.client\n"
        "    -> (3) 缺失 entitlement => 系统拒绝 socket/HTTP 出网\n"
        "    -> (4) Hub Core 保持离线\n"
        "\n"
        "(A) 若用户显式启用 Bridge\n"
        "    -> Bridge 进程具备 network.client\n"
        "    -> 网络调用仅发生在 Bridge 边界内\n",
        monospace=True,
    ))
    paras.append(_blank())

    paras.append(_p("7.2 Counts-only 读取流程（Mail/Messages/Slack）", bold=True))
    paras.append(_p(
        "+----------------------+\n"
        "| Hub / DockAgent      |\n"
        "+----------+-----------+\n"
        "           | Accessibility (TCC)\n"
        "           v\n"
        "+----------------------+\n"
        "| Dock UI (badge only) |\n"
        "+----------+-----------+\n"
        "           | parse count\n"
        "           v\n"
        "+----------------------+\n"
        "| Hub card/orb display |\n"
        "+----------------------+\n",
        monospace=True,
    ))
    paras.append(_blank())

    paras.append(_p("8. 附录：运行与审计建议", bold=True))
    paras.append(_p("- 建议从 /Applications 运行，避免 App Translocation 导致权限绑定变化。"))
    paras.append(_p("- 建议定期检查 Bridge 是否处于禁用状态（默认应为禁用）。"))
    paras.append(_p("- 审计时优先检查 entitlements 与本地 IPC/状态文件。"))

    document_xml = (
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
        "<w:body>"
        + "".join(paras)
        + "<w:sectPr/>"
        "</w:body>"
        "</w:document>"
    )

    content_types = (
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
        "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
        "</Types>"
    )

    rels = (
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>"
        "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>"
        "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/>"
        "</Relationships>"
    )

    core = (
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" "
        "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" "
        "xmlns:dcterms=\"http://purl.org/dc/terms/\" "
        "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
        f"<dc:title>{escape(title)}</dc:title>"
        "<dc:creator>Andrew Xie</dc:creator>"
        f"<dcterms:created xsi:type=\"dcterms:W3CDTF\">{now}</dcterms:created>"
        f"<dcterms:modified xsi:type=\"dcterms:W3CDTF\">{now}</dcterms:modified>"
        "</cp:coreProperties>"
    )

    app = (
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" "
        "xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">"
        "<Application>Microsoft Office Word</Application>"
        "</Properties>"
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", rels)
        z.writestr("word/document.xml", document_xml)
        z.writestr("docProps/core.xml", core)
        z.writestr("docProps/app.xml", app)


def main() -> int:
    ver = os.environ.get("AX_REL_FLOW_HUB_VERSION", "1.2.9")
    # Repo layout (GitHub-friendly): docs live at repo-root `docs/`.
    out = Path("docs") / f"AX_RELFlowHub_Security_Whitepaper_v{ver}.docx"
    build_docx(out, version=ver)
    print(str(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
