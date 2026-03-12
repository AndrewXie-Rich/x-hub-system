# X-Hub Distributed Secure Interaction System - Product White Paper (MIT License/GitHub Release Version)

# Preface

With the popularization of AI interaction scenarios and the increasing demand for multi-network environment usage, users have put forward higher requirements for system security, scenario adaptability, and interaction fluency — it is necessary to ensure the smooth experience of AI dialogue, adhere to the security of system core and data, and adapt to various usage scenarios such as offline, local area network (LAN), and remote public network access.

This white paper details the product positioning, core architecture, operation modes, security system, and application scenarios of the X-Hub Distributed Secure Interaction System (hereinafter referred to as the "X-Hub System"). It fully presents the core design concept of the system: "X-Hub as the only trusted core, lightweight terminal interaction, security and controllability, and multi-scenario adaptability", providing users, technical partners, and security audit institutions with a complete product understanding and technical reference.

The content of this white paper is based on the current core design of the system and will be continuously updated with product iterations. All technical details and security specifications are real and implementable engineering designs without idealized assumptions. This white paper, along with relevant technical documents and codes of X-Hub, will be released on the GitHub platform under the MIT License for developers' reference, use, and secondary development.

# Executive Summary

The key conclusion of X-Hub is straightforward: consolidate high-risk AI Agent capabilities into one auditable, revocable, and freezable trusted control plane (X-Hub), while preserving fast terminal experience.

Key design points:
- Single trusted source: X-Hub is the source of truth; terminals are untrusted by default, and local terminal state is never used for security decisions.
- No UX sacrifice: default auto-execution; high-risk capabilities rely on one-time grants / pre-grants (default TTL=2h) collected at the right time, not at execution interruption points.
- Verifiable security: high-risk actions use Hub-signed manifests; terminal UI must verify Hub signature and show one-time verification code (SAS). Confirmation terminal B must compute SAS independently after local signature verification.
- Crypto payment first on ETH: amount/address/tx parameters are generated and signed only by Hub (TxManifest). Execution terminal C (X-Wallet) executes only Hub-signed intents.
- Security + outcome: X-Terminal supports multi-project parallel execution and Supervisor mode (one model managing multiple ongoing projects, 15-minute heartbeat by default + change-triggered push). X-Hub five-layer memory + progressive disclosure (PD) reduces token pollution and improves retrieval efficiency.
- Engineering realism: this paper distinguishes implemented capabilities vs roadmap capabilities to keep security audits and delivery predictable.

# Why This Is Exciting Now

This is no longer just a design thesis on paper.

Several of the most compelling ideas are already becoming real in running preview builds:

- One Hub-governed control plane can already carry both local models and paid GPT-class routes.
- X-Terminal can now surface configured model, actual model, and downgrade/fallback truth, so runtime behavior is visible instead of being quietly masked.
- Supervisor and project-coder surfaces are already moving from concept into a usable execution loop for multi-project work.
- Packaging is moving toward copyable app bundles and repeatable operator flows instead of source-only experimentation.
- The system already demonstrates the core claim that fast agent execution and strong trust boundaries do not have to be mutually exclusive.

What makes this exciting is not polish. What makes it exciting is that the architecture is already showing real leverage.

# Public Preview Status And Why Contributions Matter Now

X-Hub is still an early public preview, not a finished production release.

That means:

- some product UX is still rough;
- some runtime and protocol surfaces are still evolving;
- some capabilities are partial, experimental, or not yet fully productized.

But it also means this is the right phase for strong contributors to get involved.

The most valuable contribution window is before the architecture hardens. That is where outside engineers can still influence:

- Hub-first runtime design;
- model routing and provider compatibility;
- Supervisor orchestration and multi-project execution;
- voice, diagnostics, and operator UX;
- packaging, release discipline, and security hardening.

The product is early. The thesis is not. That is exactly why this is a good time to build with it.

# I. Product Overview

## 1.1 Product Positioning

The X-Hub System is a distributed secure interaction system that takes X-Hub as the only trusted core, terminals as lightweight interaction carriers, and integrates centralized AI capabilities with multi-network mode adaptability. Its core positioning is a "Financial-Grade Secure AI Interaction Trusted Control Platform".

The system breaks the dilemma of "mutual exclusion between security and experience". Through the combination of centralized trusted control and distributed lightweight interaction, it achieves a triple balance of AI dialogue fluency, multi-scenario adaptability, and asset security, adapting to various usage scenarios such as families, small and medium-sized enterprises (SMEs), and high-security demand scenarios (e.g., offline AI).

## 1.2 Core Values

- Security and Controllability: X-Hub is the only trusted node, terminals are untrusted by default, with full-link encryption + sandbox isolation to adhere to the financial-grade security bottom line;

- Multi-Scenario Adaptability: Supports 4 operation modes including offline, LAN, and remote public network access to flexibly meet the needs of different network environments;

- Smooth Experience: Centralized AI capabilities provide stable computing power, and X-Terminal's local lightweight caching ensures consistent interaction experience;

- Flexible Expansion: Terminal types can be adapted on demand, encryption connections and security policies can be iteratively upgraded to be compatible with future function expansion;

## 1.3 Core Design Principles

1. X-Hub Centralized Trust Principle: All AI inference, permission approval, memory management, and process forwarding are uniformly controlled by X-Hub, with no decentralized decision-making nodes;

2. Terminal Untrusted Principle: Terminals only serve as input and output carriers, without core decision-making and high-risk operation permissions of X-Hub; being compromised will not affect the core security of the system;

3. Security Isolation Principle: AI context is completely isolated from the X-Hub core system, with independent data storage and transmission;

4. Least Privilege Principle: Terminals and each module of X-Hub only open necessary permissions to eliminate security risks caused by redundant permissions;

5. Auditable and Controllable Principle: Full-process operation logs are traceable, and abnormal behaviors can trigger real-time alarms and emergency shutdowns to achieve security and controllability;

6. Memory Core Solidification Principle: The core rules of memory processing (Memory-Core Skill) cannot be dynamically modified, and can only be changed through the X-Hub cold storage Token.

# II. Core Architecture: X-Hub Five-Layer Memory Architecture

The X-Hub memory system adopts a "five-layer progressive" architecture to realize the structured governance of memory from the "evidence layer" to the "injection layer". It not only ensures full-process traceability but also balances the Token efficiency of AI interaction. At the same time, it carries the security constraints of the X-Constitution (value charter), constructing a "dual protection of technical security + value security".

## 2.1 Comprehensive Analysis of the Five-Layer Architecture

|Layer|Positioning|Core Features|Data Source/Processing Logic|
|---|---|---|---|
|1. Raw Vault|Evidence Layer (Unlimited Storage)|Append-only storage, tamper-proof, not injected by default, serving as the only source of truth for auditing/traceability|Complete interaction rounds, tool outputs, file summaries/hashes; archived and compressed by time period to retain a complete evidence chain|
|2. Observations|Searchable Structured Layer|Extract structured memory (facts/preferences/constraints/decisions/experiences) from the Raw Vault, supporting full-text search/vector/timeline search|Automatically extracted by X-Hub's dedicated AI role, isolated by `device/project/thread`, supporting precise search|
|3. Longterm Memory|Document-Type Long-Term Memory Layer|Aggregate content from the Observations layer to form structured documents (goals/architecture/constraints/value charter) with progressive disclosure|Maintained for upgrade/downgrade by AI roles; summaries are injected by default, and details + evidence links are supplemented when queried by users; the value charter never sinks|
|4. Canonical Memory|Simplified Injection Layer|Solidify core key-value pairs (preferences/short-term goals/interface protocols), isolated by scope, injected by default|Upgraded from the Observations/Longterm Memory layer, with a small quantity, high stability, and the highest Token efficiency|
|5. Working Set|Short-Term Context Layer|Cache the latest N rounds of dialogue, injected by default, and discard the oldest content when exceeding the budget|Dual caching on terminal/X-Hub; terminal-side caching is only used for crash recovery, and core content is synchronized to X-Hub, isolated by `device/project/thread`|
## 2.1.1 X-Constitution (Value Charter): Global AI Security and Value Constraints

As the global AI security and value constraint, the X-Constitution (Value Charter) is placed in the 3rd layer (Longterm Memory) of the X-Hub five-layer memory architecture, marked as a fixed resident (pinned), never-sinking, tamper-proof top-level L0 rule entry, which is naturally compatible with the positioning of the Longterm Memory layer as a document-type long-term constraint layer.

The charter is uniformly formulated, stored, and managed by X-Hub, and can only be updated with authorization through the X-Hub cold storage Token. No terminal (including X-Terminal) has the permission to modify, delete, or bypass it. At the same time, the charter only takes effect for X-Terminals that use the X-Hub memory system: when X-Terminals process projects, conduct multi-round AI dialogues, call Skills, and execute AI decisions, they must read and strictly follow the X-Constitution from the Longterm Memory layer of X-Hub, taking it as the global behavioral constraint and insurmountable security bottom line; ordinary general-purpose terminals do not use X-Hub memory or synchronize context to X-Hub, so they will not load or be subject to the constraints of this value charter.

To ensure the efficient operation of the system, the X-Constitution adopts an extremely lightweight and trigger-based injection design: it only retains the core value rules and security constraints, with fixed content and small size; it adopts on-demand trigger injection instead of full resident context, which will not increase the system burden, generate a large number of additional Token consumption, and have no significant impact on AI inference speed, terminal operating performance, and context length.

The X-Constitution is indispensable at the underlying architecture level: first, it prevents humans from inducing AI to perform malicious, non-compliant, and unauthorized operations through instruction construction, context injection, etc.; second, it provides an unshakable value boundary for future AGI autonomous decision-making, multi-project collaboration, and automatic skill upgrade/downgrade and execution; third, it supplements the shortcomings of technical protection from the "value security" level, and together with AI sandbox, permission control, and memory isolation, forms a complete security defense system to fundamentally prevent malicious exploitation and behavioral out-of-control risks.

More precisely, the goal of the X-Constitution is to write the right human values into the "behavioral genome" of an AGI system. "Genome" here is not a slogan. It means a higher-order set of system constraints that stay above any single task objective: pinned by default, updated only through authorization, trigger-injected when needed, policy-checked, auditable, and able to halt execution under high-risk, unauthorized, or uncertain conditions. It is not a late safety patch. It is meant to be part of how the system is born to operate.

For that reason, the X-Constitution is designed to help prevent concrete agent failure cases that are already appearing in the real world:

- prompt-injection attacks in webpages, emails, or documents that try to trick the agent into leaking local secrets, keys, or sensitive data;
- destructive misoperations where the agent misreads user intent and deletes mail, production data, or important files without clear scope and confirmation;
- poisoned or malicious Skills that try to steal API keys, read private files, plant backdoors, or silently escalate privilege after import;
- security bugs that, once exploited, turn into large-scale data exposure, repository leakage, business disruption, or full-system compromise.

The X-Constitution does not replace all security engineering by itself. Its role is to force these paths to be treated as high-risk and untrusted at the system level: untrusted inputs cannot directly rewrite system goals, destructive actions cannot skip confirmation, imported Skills cannot inherit high privilege by default, and vulnerability paths should be constrained by Hub-first trust, least privilege, audit, kill-switches, and fail-closed execution.

## 2.2 Memory Upgrade/Downgrade Mechanism

The circulation of memory is fully lifecycle-managed by X-Hub's built-in dedicated AI role without manual intervention (unless specially configured). The core rules are as follows:

- Upgrade Path: Raw Vault → Observations (automatic extraction) → Longterm Memory (aggregate documents) → Canonical Memory (solidify core facts);

- Downgrade Rules:
  - Observations/Longterm Memory: Automatically merge, summarize, mark expiration, and retain evidence pointers (turn_id/time range/summary hash);
  - Raw Vault: Only perform storage governance (archive and compress by time), without affecting search, and indexes are permanently traceable;

- Special Rules: As a fixed resident L0 memory, the X-Constitution (Value Charter) never sinks and is injected on demand (in both Chinese and English) only in trigger word/high-risk scenarios.

## 2.3 Memory-Core Skill: The "Core Rule Engine" of the Memory System

The Memory-Core Skill is the only set of guiding rules for X-Hub memory processing, determining the acquisition, generation, and processing logic of memory. The core design is as follows:

- Tamper-Proof: Cannot be dynamically modified during operation, and neither terminals nor ordinary Skills have modification permissions;

- Unique Modification Entry: Can only be modified after authentication through the X-Hub Token stored in the X-Hub cold storage, and all modification records are fully audited;

- Core Responsibilities:
  - Guide the circulation rules (extraction/aggregation/solidification/injection) of the five-layer memory architecture;
  - Control the isolation dimensions of memory (device/project/thread);
  - Define memory desensitization rules (e.g., content with <private> tags is discarded/desensitized by default);
  - Schedule the calling timing and priority of Skills to ensure "seamless calling";
  - Control the injection timing, permissions, and effective scope of the X-Constitution.

# III. Skill Upgrade/Downgrade and Classification System

The core extension of the X-Hub memory system is the "memory → Skill conversion". As reusable units of memory, Skills are managed according to the principles of "classification, isolation, and automatic + manual confirmation", and are subject to the global constraints of the X-Constitution value charter.

## 3.1 Core Isolation Rules for Skills

The isolation granularity of Skills is "one device × one X-Terminal × one project = independent Skill domain". Skills in different domains are completely isolated, cannot be called across domains, and cannot contaminate each other, which is consistent with the three-dimensional isolation principle of the memory system.

## 3.2 Skill Upgrade Rules

Skills are triggered by memory/interaction events to become candidate Skills and are upgraded by confidence level. All upgrade processes must comply with the constraints of the X-Constitution:

1. Automatic Upgrade: If the confidence level of a candidate Skill exceeds a preset threshold (configurable), it is automatically upgraded to an available Skill by X-Hub;

2. Manual Confirmation: Candidate Skills with insufficient confidence are pushed to the terminal user for confirmation and can only be upgraded after user confirmation;

3. Audit and Editing: All Skill audit and editing operations are completed on the X-Terminal side and finally stored on the X-Hub side. Editing records are fully audited, and edited content must comply with the X-Constitution rules.

## 3.3 X-Hub Side Skill Classification System

On the X-Hub side, Skills are divided into three categories according to the scope of reuse to ensure on-demand calling, no redundancy, and no unauthorized access, all subject to the constraints of the X-Constitution:

|Skill Type|Positioning|Management Method|Calling Rules|
|---|---|---|---|
|Memory-Core Skill|System-Level Core Rules|Exclusive to X-Hub, can only be modified through cold storage Token, and universally applicable to the entire X-Hub|Automatically called with the highest priority|
|General Skill|Cross-Project Reuse|Can be imported from external sources through the "Import Button" on X-Terminal and uniformly managed by X-Hub|Can be called after project authorization|
|Single-Project Exclusive Skill|Only Available for the Corresponding Project|Generated from the interaction memory of the project, edited on the X-Terminal side, and stored on the X-Hub|Automatically called only within the affiliated project|
## 3.4 Skill "Seamless Calling" Guarantee Mechanism

To ensure that Skills are accurately called when needed, X-Hub has built-in scheduling logic, while complying with the constraints of the X-Constitution:

1. Calling Trigger Conditions: Automatically matched according to the current interaction context, project identifier, and device/terminal permissions;

2. Priority Rules: Memory-Core Skill > General Skill > Single-Project Exclusive Skill;

3. Conflict-Free Guarantee: Match Skills according to the `device/project/thread` isolation domain, and cross-domain Skills are invisible;

4. Real-Time Synchronization: Skills edited on the X-Terminal side are synchronized to X-Hub in real time, and the latest version is preferred when calling. The synchronization process is subject to X-Hub security audit.

# IV. Operation Modes

The X-Hub System supports 4 operation modes, covering all scenarios such as offline, LAN, and remote public network access. Ranked by security level from high to low (risk is opposite from low to high), each mode is independently adapted and can run simultaneously, all uniformly controlled by X-Hub, and all comply with core security principles and X-Constitution constraints (only effective for X-Terminals).

## 4.1 Mode 0: Pure Offline LAN (Security Level: Highest)

### 4.1.1 Connection Features

Terminals and X-Hub are in the same private LAN. X-Hub has no public network access capability, and terminals also have no Internet access permission. Communication between terminals and X-Hub can only be realized through the LAN, which is a physical isolation-level scenario.

### 4.1.2 Security Risks

The attack surface is extremely small, and there are only two types of potential risks: physical contact with the device; lateral movement of compromised devices in the internal network. There is no possibility of remote attacks, and context, memory, and communication are all closed-loop within the internal network, which is safe and controllable.

### 4.1.3 Applicable Scenarios

Highest confidentiality scenarios, offline AI interaction scenarios that do not require networking and remote access, such as confidential AI inference, offline voice interaction, etc.

## 4.2 Mode 1: Secure LAN (Security Level: High, Recommended for Daily Use)

### 4.2.1 Connection Features

Terminals and X-Hub are in the same private LAN. Terminals have no public network access capability, and X-Hub can realize controllable public network connection through a Bridge (only for AI networking needs, such as paid model calling, networked inference). Terminals can only communicate with X-Hub through the LAN.

### 4.2.2 Security Risks

The risk is relatively low. After a terminal is compromised, it cannot connect to an external control terminal, download malicious programs, or spread attacks. Even if it obtains the X-Hub internal network IP, it cannot penetrate the attack to the external network, which will not affect the core security of X-Hub.

### 4.2.3 Applicable Scenarios

Daily AI interaction scenarios, such as home AI dialogue and enterprise internal AI office. It requires AI to have networking capabilities but hopes that terminals are safe and controllable to avoid terminals being attacked by the public network.

## 4.3 Mode 2: Ordinary LAN (Security Level: Medium)

### 4.3.1 Connection Features

Terminals and X-Hub are in the same private LAN. X-Hub has public network access capability, and terminals can independently access the public network (for non-AI daily scenarios, such as web browsing and office software use). Terminals can also communicate with X-Hub through the LAN.

### 4.3.2 Security Risks

The risk is medium, and terminals are the main attack entry point — terminals can be compromised through web pages, emails, vulnerabilities, and Trojans. After being compromised, they can scan the internal network to obtain the X-Hub internal network IP and try to launch internal network attacks, replay attacks, and fake requests on X-Hub. The root cause of the risk is the uncontrollability of terminals.

### 4.3.3 Applicable Scenarios

LAN scenarios with low requirements for terminal management, such as SME office and mixed home use (some terminals need public network access). It is necessary to combine firewalls and Virtual Local Area Networks (VLANs) to reduce the attack surface.

## 4.4 Mode 3: Remote Public Network Encrypted Connection (Security Level: Medium-High)

### 4.4.1 Connection Features

Terminals have no physical LAN association with X-Hub. Remote public network interconnection is realized through encrypted dedicated channels such as WireGuard/ZeroTier/Cloudflare Tunnel. X-Hub retains independent public network access capability, and terminals can remotely access the AI capabilities of X-Hub.

### 4.4.2 Security Risks

This mode is one of the most common real-world remote work setups. Compared with LAN modes, the primary risks come from **public exposure**, not from assuming terminals are trustworthy:

- Public visibility: tunnels/relays/domains are reachable on the public Internet and can be scanned/probed, including DDoS and brute-force attempts;

- Credential risk: certificate/Token leakage allows an attacker to access X-Hub *as that device* (impact is bounded by that device's entitlements and visible data);

- Protocol and configuration risk: tunnel protocol vulnerabilities or misconfiguration can expand the attack surface.

X-Hub is designed with the assumption that terminals can be compromised. Therefore, even if a terminal is hacked or the device is hijacked:

- the Hub core is not taken over by terminal state; high-risk actions remain enforced by Hub-side authorization, quotas, audit, and Hub-signed manifests;

- if the terminal uses Hub-provided AI capability, Hub can freeze the device immediately: disable AI calls, disable web/paid capabilities, revoke Grants/Pre-Grants, and trigger device-level or global kill-switch;

- note: stolen credentials can still lead to data exposure within that device's scope, so short-lived credentials, rotation, least privilege, and fast revocation are required.

### 4.4.3 Applicable Scenarios

Daily remote work / travel / multi-site collaboration. Recommended baseline controls: strong identity (client certificate + token), per-device permission isolation, source restrictions (allowed CIDRs / optional geo-fencing), rate limiting and DDoS protection, credential rotation, and one-click revocation (kill-switch).

## 4.5 Mode Risk Ranking (From Low to High)

Mode 0 (Pure Offline LAN) > Mode 1 (Secure LAN) > Mode 2 (Ordinary LAN) > Mode 3 (Remote Public Network)

# V. Terminal Design

As the user interaction entry of the system, terminals are untrusted by default. They are divided into two categories according to functional positioning, both adopting the principles of "lightweight design and least privilege", without X-Hub core security permissions, only responsible for input, output, and basic interaction. The specific design is as follows:

## 5.1 Ordinary General-Purpose Terminals

### 5.1.1 Positioning

Lightweight and general-purpose interaction terminals, suitable for basic AI dialogue scenarios that do not require continuous interaction experience, pursuing extreme lightweight security.

### 5.1.2 Functional Boundaries

- Core Functions: Only receive user input (such as AI dialogue questions), save dialogue context by themselves, call the AI inference capability of X-Hub to obtain inference results and display them to users synchronously; do not forward any dialogue content to X-Hub, and X-Hub only provides AI inference support and does not process dialogues of ordinary terminals;

- Permission Restrictions: No complex local interaction logic; do not execute any AI model inference (only call the AI inference capability of X-Hub, the API key of paid AI is uniformly stored on the X-Hub side, and terminals have no access permission); terminals can independently decide whether to enable high-risk operations such as file reading and writing, system execution, tool execution, and system-level instructions of the device itself. Such operations only act on the terminal itself, have no connection with X-Hub, and X-Hub does not interfere with the terminal's own system operations; in addition, the Token usage method and dosage of ordinary terminals and X-Terminals are uniformly set by X-Hub, and X-Hub can fully control the networking capability of the model, and terminals have no independent control permission.

- Security Features: Only save the context of their own dialogues, no other data residues; do not forward any dialogues to X-Hub, and X-Hub does not process their dialogues. Therefore, after being compromised, only the locally saved context and displayed content can be tampered with, which cannot affect X-Hub or leak historical information of other terminals, and the risk is controllable.

## 5.2 X-Terminal

### 5.2.1 Positioning

An enhanced terminal with continuous AI interaction capabilities, suitable for scenarios that require long-term dialogue, continuous experience, and multi-project management (such as continuous AI consultation, multi-round interaction, and multi-project parallel management). It relies on X-Hub to realize memory management, security control, and project data synchronization. For detailed design, refer to the "X-Terminal White Paper".

### 5.2.2 Functional Boundaries

- Local Caching: Only cache the latest 3-5 rounds of dialogue context, which is only used to improve the fluency of interface display (such as scrolling to view recent dialogues), not as master data, not involved in security decisions, and not permanently stored;

- Context Synchronization: Each time a new dialogue context is generated (such as new user input, new return results from X-Hub), it will try its best to synchronize to X-Hub, which is uniformly stored, cleaned, and processed by X-Hub. Terminals cannot overwrite, tamper with, or insert fake history;

- Memory Dependence: During the dialogue process, it completely relies on the Canonical Memory processed and returned by X-Hub to build continuous interaction, and does not build or modify memory locally; all dialogue memory and project progress are uniformly stored in X-Hub, and terminals only obtain them synchronously without any modification permission; at the same time, when processing projects and executing AI decisions, it is necessary to read the X-Constitution in the Longterm Memory layer of X-Hub and strictly follow the value constraints;

- Seamless Connection Capability: Since core memory and project data are all stored in X-Hub and cannot be tampered with by terminals, if X-Terminal crashes, after restarting, it can seamlessly connect to the previous dialogue process and project progress by resynchronizing data with X-Hub, without losing any core information and without affecting user experience;

- Compromised Security Protection: Even if X-Terminal is compromised, it has no permission to modify the historical memory, dialogue context, and project data stored in X-Hub, and can only tamper with local temporary cache (no core value), which cannot contaminate the core memory of X-Hub or bypass the constraints of the X-Constitution, completely eliminating the risks of historical memory tampering and AI behavioral out-of-control;

- Multi-Project Parallel Processing: Supports simultaneous parallel processing of multiple projects, can independently manage the interaction context and progress records of each project, and the data of each project is isolated from each other without cross-interference, adapting to multi-task collaboration scenarios;

- Project Progress Summary: Equipped with a Home page, which can synchronously display the real-time progress of all projects in X-Hub, support progress voice broadcast, and facilitate users to quickly grasp the progress of all projects (for example, when users are exercising, they can listen to the X-Terminal broadcast the progress of all projects through voice and get guidance on the next step one by one);

- Permission Restrictions: Local interaction behaviors are fully audited and strongly controlled by X-Hub; system-level permissions of X-Hub are not opened, and high-risk operations on X-Hub are not executed (system-level instructions of the device itself can be executed, only acting on the terminal itself, not affecting X-Hub); cache loss/tampering does not affect the core logic of the system, and can be recovered by resynchronizing from X-Hub;

- Security Features: Local status is not involved in security decisions, and being compromised cannot contaminate X-Hub memory or trigger high-risk operations, and the risk is controllable.

## 5.3 General Requirements for Both Types of Terminals

- Both adopt encrypted connection methods; domain-based X-Hub access is recommended, and terminals should not pin or persist plaintext IPs by default (can be enforced by policy);

- Both need to pass X-Hub identity authentication (device UUID + Token, optional client certificate) to access the system;

- Both have no X-Hub operation permissions, file access permissions, or network bypass permissions, only serving as lightweight interaction carriers;

- Both have no high-risk operation permissions or system-level operation permissions of X-Hub, only serving as lightweight interaction carriers; both types of terminals can execute system-level instructions of their own devices, which only act on the terminal itself, and X-Hub does not interfere with the terminal's own system operations; in addition, the Token usage method and dosage of both types of terminals and the networking capability of the model are uniformly set and fully controlled by X-Hub, and terminals have no independent adjustment permission.

# VI. Security System

With verifiability, auditability, and rollback as financial-grade engineering goals, the X-Hub System defines six security dimensions: identity authentication, transmission, storage, operation, Hub-signed manifests with cross-terminal SAS verification, and emergency controls.

## 6.1 Identity Authentication Security

- Three-Factor Authentication Mechanism: When terminals access X-Hub, they need to pass three-factor authentication: "device UUID + exclusive Token + optional client certificate", which is indispensable to prevent unauthorized device access;

- Permission Classification: Different permissions are assigned according to terminal types and usage scenarios (for example, ordinary terminals can only call AI capabilities, and X-Terminals can synchronize context and read X-Hub memory), without redundant permissions;

- Entitlement Granularity: paid-model entitlement is bound at `(device_id, user_id, app_id)` level. Default policy is "first-time manual grant once, then auto-renew", with revocation at any time;

- Pre-Grant Mechanism: high-risk capabilities (network tools, external side-effect actions) can be pre-authorized by X-Hub with TTL/quota constraints (default Pre-Grant TTL=2h), then auto-recovered on expiry;

- Identity Isolation: Permission isolation is realized according to device ID and user identity. Different terminals and users cannot access each other's context, memory, and operation logs without authorization.

## 6.2 Transmission Security

- Full-Link Encryption: All communications between terminals and X-Hub (context synchronization, AI requests) use TLS 1.3. Intermediate nodes cannot eavesdrop or tamper;

- Signed Manifests for High-Risk Actions: payments, outbound actions, and irreversible writes must use Hub-generated and Hub-signed `TxManifest/ActionManifest` objects (`intent_id`, targets, value/parameters, expiry, policy tags). Terminals may only render and execute signed manifests, never trust local assembled payloads;

- SAS One-Time Verification Code: high-risk terminal cards must display `Hub signature status + SAS`. Confirmation terminal B must independently compute SAS locally after signature verification;

- Anti-Replay and Idempotency: all high-risk executions must carry `intent_id + execution_id + expires_at`; duplicated, expired, or signature-mismatched requests are rejected by X-Hub;

- Remote Encryption Enhancement: remote mode should use dedicated encrypted channels (WireGuard/ZeroTier/Cloudflare Tunnel), plus certificate rotation and source restrictions;

- LAN Protection: Reduce the reachable range of X-Hub through VLAN/firewall/allowed_cidrs, limit the permission of internal network devices to access X-Hub, and make up for the shortcoming that IPs in the LAN cannot be completely hidden.

## 6.3 Storage Security

- X-Hub Storage Encryption (phased rollout): Hub `turns.content` / `canonical_memory.value` already use AES-256-GCM at-rest envelope encryption with KEK/DEK rotation, and tampered ciphertext is fail-closed by default; remaining scope includes Raw Vault/Observations/Longterm and terminal-local `raw_log/skills/vault` (with Keychain root-key custody and unified rotation jobs); for detailed memory storage specifications, refer to the "X-Hub Memory White Paper";

- Minimized Storage Permissions: Only the AI capability module of X-Hub can read context and memory. Other modules (such as audit) need to apply for temporary authorization and can only read desensitized data;

- Raw Evidence Policy: connectors write full input/output evidence into Raw Vault with mandatory encryption at rest; optional short-TTL mode can be enabled for large payload full text while still retaining long-lived metadata and hash evidence links (recommended default TTL for full text cache: 24 hours);

- Secrets Policy: keys/passwords/tokens are centrally encrypted in X-Hub; "secrets cannot be sent to remote models" is available as a hard policy switch (local-only consumption);

- Terminal Storage Restrictions: Ordinary terminals save the context of their own dialogues (for AI to read as historical memory) without other permanent storage; X-Terminals only cache the latest few rounds of context without permanent storage, and the cache can be cleaned at any time;

- Memory Security: As a fixed resident entry in the Longterm Memory layer, the X-Constitution is stored separately in encryption and can only be updated through the cold storage Token to ensure it is tamper-proof and never sinks.

## 6.4 Operation Security

- Full-Process Audit: X-Hub records all operation logs, including terminal access, context synchronization, AI requests, permission changes, emergency operations, Skill editing/upgrade, memory upgrade/downgrade, etc. The logs are tamper-proof and retained for a long time, supporting search by terminal, operation type, and time;

- Abnormal Behavior Detection: Real-time monitoring of abnormal system behaviors, such as terminals frequently carrying sensitive words, the same terminal submitting a large number of contexts in a short time, abnormal certificates/Tokens, etc., which will immediately trigger alarms;

- Default Auto-Execution: when authorization and policy checks pass, actions execute automatically (no queue by default). Queued confirmation can be enabled by risk rules at organization policy level;

- Connector Risk Controls: all side-effectful connector actions are audited end-to-end. A 30-second undo window is enabled by default for delay-committable outbound actions (connector policy can override);

- AI Context Protection: Before the context enters X-Hub, it undergoes double cleaning (preliminary filtering on the terminal side and in-depth cleaning on the X-Hub side) to filter malicious instructions and sensitive fields, retaining only pure AI dialogue text;

- Value Constraint Protection: When X-Terminals process projects and execute AI decisions, they are forced to read the X-Constitution to prevent AI behaviors from deviating from the security bottom line and prevent human inducement or AGI out-of-control risks.

## 6.5 Hub-Signed Manifest and Cross-Terminal SAS

To enforce "Hub is the only trusted source", all actions with external side effects are represented as Hub-generated manifests, signed by Hub. Terminals A/B/C must not trust local data (clipboard/cache/UI/system clock) and must trust only Hub-signed manifests.

### 6.5.1 Manifest Object (ETH Transfer Example)

- Hub creates and signs TxManifest; terminals receive/render/execute only. Terminals must not rewrite amount, address, nonce, or fee fields;

- `manifest_hash = SHA-256(CanonicalJSON(manifest))`;

- `hub_sig = Sign_Hub(manifest_hash)`;

- Example core fields: `intent_id, created_at, expires_at, action_type=eth_transfer, chain_id, asset, to, value, data, nonce, fee_params, gas_limit, policy_tags, required_grants, hub_pubkey_id`.

### 6.5.2 Terminal Display Requirements (Hub Signature + SAS)

- UI must display Hub key ID/fingerprint, signature verification status, and SAS. It should also support export/display of `manifest_hash + hub_sig` (copy or QR);

- Suggested SAS algorithm: `SAS = Base32(Truncate60(manifest_hash))` with grouped output (`XXXX-XXXX-XXXX`) and checksum for human verification;

- Independent verification on terminal B: B verifies `hub_sig` locally, then computes SAS with the same algorithm. B must not simply render an SAS string pushed from Hub.

### 6.5.3 Execution Path (A -> Hub -> B -> Hub -> C)

1. A submits an intent request (e.g., "pay 0.5 ETH to Alice"). A-provided address/value is untrusted input, used only for Hub manifest generation;

2. Hub generates and signs TxManifest, then sends it to A and B. A/B render amount, address, Hub signature status, and SAS;

3. User confirms on B (or compares SAS via QR between A and B). Hub issues a grant (TTL/quota/scope). Existing valid Pre-Grant (default TTL=2h) may allow no-interruption execution;

4. Hub sends execution command (`TxManifest + Grant`) to C (X-Wallet). C must re-verify signature, construct transaction exactly matching manifest fields, then sign and broadcast with C wallet keys;

5. C returns `tx_hash` and receipt; Hub writes immutable audit and syncs result to A/B.

### 6.5.4 Residual Risk with Single-Sign Hot Wallet

If C is a single-sign hot wallet, C compromise can still sign malicious transactions outside policy. Mitigations in X-Hub include dedicated device hardening, quota/rate limits, address allowlists, mandatory B confirmation for new recipients/high-value transfers, kill-switch, and roadmap support for hardware wallets/multisig/threshold signing.

## 6.6 Emergency Security

- Global Kill-Switch: Supports one-click shutdown of all terminal access and all AI capabilities, taking effect in seconds to respond to major security risks;

- Permission Recovery: One-click recovery of the access permission and AI calling permission of single/multiple terminals, immediately prohibiting terminals from communicating with X-Hub;

- Data Cleaning: One-click cleaning of all context and memory data stored in X-Hub, or related data of a single terminal, to avoid data leakage;

- Alarm Response: After an abnormal behavior triggers an alarm, the administrator can quickly view the alarm details, locate the abnormal terminal, and take emergency measures (such as shutting down the terminal, recovering permissions) to achieve real-time loss control.

# VII. Technical Implementation Specifications

## 7.1 Core Path and Configuration Specifications

|Functional Module|Core Path/Configuration|
|---|---|
|X-Hub gRPC Service Skeleton|`hub_grpc_server/` (Node + SQLite + MLX runtime IPC)|
|Memory Pipeline|`X-Terminal/XTerminal/Sources/Project/XMemoryPipeline.swift`|
|Short-Term Context Storage (for Crash Recovery)|`<project_root>/.xterminal/recent_context.json` + `.xterminal/X_RECENT.md`|
|Candidate Skills/Automatic Upgrade|`X-Terminal/XTerminal/Sources/Project/XSkillCandidates.swift`|
|Forgotten Vault|`<skills_dir>/_projects/<project>/forgotten-vault/`|
|Global Skill Library|`<skills_dir>/_global/` (Memory-Core Skill: `<skills_dir>/memory-core/`)|
|Project-Specific Skill Library|`<skills_dir>/_projects/<project>/`|
|X-Constitution Storage|`<memory_dir>/longterm/_constitution/` (Separately encrypted, only accessible through cold storage Token)|
## 7.2 Multi-Terminal Continuous Dialogue/New Dialogue Specifications

To ensure the context experience of multi-device terminals, X-Hub defines unified dialogue identification rules:

1. Continuous Dialogue (with Context): Fix `HUB_PROJECT_ID + HUB_THREAD_KEY`, access through the `axhubctl chat` command;

2. New Dialogue (without Context): Replace `HUB_THREAD_KEY`, create through the `axhubctl chat-new` command;

3. Configuration Persistence: Write `HUB_PROJECT_ID/HUB_THREAD_KEY` into `~/.axhub/chat.env` to achieve long-term continuous dialogue.

## 7.3 Memory Health Check Specifications

The X-Terminal side has built-in "memory health" detection to ensure the reliable operation of the memory system, including X-Constitution integrity check:

1. Check Items: Existence/update time/integrity of `.xterminal/raw_log.jsonl` (complete logs), `recent_context.json` (short-term context), `x_memory.json` (structured memory), and X-Constitution files;

2. Downgrade Strategy: When core files are missing, X-Terminal automatically fills in the latest 12 rounds of context from the end of `raw_log.jsonl`; when the X-Constitution file is missing/damaged, it prompts the administrator to re-import it through the cold storage Token to ensure that value constraints take effect.

# VIII. Application Scenarios

With multi-mode adaptability, high security level, and flexible terminal design, the X-Hub System can be widely applied to various scenarios such as families, SMEs, high-security demand scenarios, confidential scientific research, financial institutions, and industrial control, focusing on the technical security guarantee of AI interaction. The details are as follows:

## 8.1 Home Scenarios

Adapt to Modes 0/1/2 to meet home AI interaction needs and balance security and experience:

- AI Interaction: Children use ordinary terminals to call X-Hub AI capabilities for learning consultation. Terminals have no public network access and no cache, which is safe and controllable; parents use X-Terminals for multi-round AI dialogues (such as work consultation and life assistants), and can also view the summary progress of all projects through the Home page of X-Terminals, and even listen to the progress broadcast and get guidance on the next step while exercising; when X-Terminals process related projects, they will automatically follow the constraints of the X-Constitution to avoid AI behavioral out-of-control;

- Security Guarantee: Terminals have no public network access (Mode 1) to avoid children's terminals being attacked by the public network; X-Hub can reduce public exposure via tunnels/relays to keep the home internal network more controllable; context sandbox isolation prevents malicious instructions from attacking the X-Hub core.

## 8.2 SME Scenarios

Adapt to Modes 1/2/3 to meet enterprise AI office needs and balance efficiency and security:

- AI Office: Employees use ordinary terminals to call X-Hub AI capabilities (such as document summary and meeting minutes generation); managers use X-Terminals to achieve continuous AI interaction, can handle multiple work projects at the same time, and view the summary progress of all projects through X-Terminals; when X-Terminals process enterprise-related projects, they are subject to the constraints of the X-Constitution to prevent humans from inducing AI to leak enterprise sensitive information;

- Remote Office: Business travelers call X-Hub AI capabilities through Mode 3 (remote public network encrypted connection), which does not affect office efficiency and ensures data security;

- Security Guarantee: Reduce the reachable range of X-Hub through VLAN and firewall configuration to reduce internal and external network attack risks, and rely on X-Hub full-process audit and abnormal behavior detection to ensure the security of enterprise AI office data.

## 8.3 X-Terminal Multi-Model Supervisor: One AI Manages Multiple Active Projects

Typical target: users only talk to one AI while multiple projects run in parallel, with proactive authorization collection and minimal execution interruption.

- Multi-model role split: X-Terminal orchestrates multiple models via X-Hub in parallel (Model-1 for Project-1, Model-2 for Project-2, Model-3 for Project-3); Model-4 acts as Supervisor for validation, conflict resolution, and progress synthesis;

- Single conversation entry point: users interact only with Supervisor Model-4, which provides a unified project board (status, blockers, next decisions);

- Heartbeat + push: default heartbeat report every 15 minutes; change-triggered push for meaningful events (PR created, tests failed, permission needed, risk escalated);

- No-interruption pre-authorization: Supervisor predicts near-term permission needs (paid model budget, web access, email send, code merge) and requests Pre-Grants in advance (default TTL=2h), so execution can proceed automatically when needed.

## 8.4 ETH Crypto Payment: Hub-Signed TxManifest + SAS + A/B/C Cross-Terminal Verification

Rollout target: ETH first. Core objective: Hub is the only trusted source; terminal compromise does not change amount/address/tx parameters.

- Terminal roles:
  - Terminal A (initiator): submits payment intent and recipient input (untrusted input only);
  - Terminal B (confirmation): independently verifies signature and computes independent SAS for human confirmation;
  - Terminal C (executor): networked X-Wallet (allowed as single-sign hot wallet), executes only Hub-signed intents.

- Core mechanism: Hub generates and signs TxManifest. Terminal display is required to include Hub signature verification status and SAS. Terminal B must compute SAS independently after local verification (see Section 6.5).

- Execution flow:
  1) A submits payment intent to Hub;
  2) Hub generates/signed TxManifest and sends to A/B; A/B display amount, address, signature status, and SAS (QR-supported);
  3) User confirms on B, then Hub issues Grant to C; if valid Pre-Grant exists (default TTL=2h, with allowlist/quota constraints), runtime confirmation may be skipped;
  4) C verifies signature, builds transaction exactly matching manifest fields, signs and broadcasts, then returns `tx_hash` and receipt to Hub;
  5) Hub persists audit and syncs execution result to A/B.

- Residual risk + mitigation: with single-sign hot wallet C, residual compromise risk is reduced via limits/rate controls, address allowlists, mandatory B confirmation for new recipients or large amounts, and kill-switch; roadmap includes hardware wallet/multisig/threshold signing.

# Appendix: MIT License Statement (For GitHub Release)

**Copyright (c) ** **2026** ** Andrew.Xie**

is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
