---
name: agent-browser
version: 1.0.0
description: Governed browser automation for navigation, screenshot capture, structured extraction, and Secret Vault-aware credential handling through X-Terminal execution surfaces.
---

# Agent Browser

Use this skill when the user needs browser work such as:

- opening and navigating websites
- filling forms or clicking through multistep flows
- capturing screenshots
- extracting structured data from a page
- performing sign-in or credential-gated flows without exposing secrets in chat or project files

## Workflow

1. Restate the browsing objective and list the minimum actions needed.
2. Use governed browser control surfaces instead of direct unmanaged automation.
3. Prefer read-only inspection first, then escalate to clicks, form fill, or submission only when necessary.
4. When a page requires a password, token, OTP, payment credential, or other secret, switch to a Secret Vault flow before continuing.
5. Ask for a Hub Secret Vault item or a clear instruction to create one. Never ask the user to paste the secret into chat if Secret Vault can be used.
6. For governed browser typing, prefer `device.browser.control` with `field_role` plus `secret_item_id`, or `secret_scope + secret_name + secret_project_id`, rather than plaintext `text`.
7. Use only Secret Vault references, lease IDs, or future Secret Vault-backed browser fill surfaces for secret material. Do not place plaintext credentials into skill output, project memory, logs, screenshots, or page notes.
8. If the runtime does not yet support Secret Vault-backed credential fill for the required action, stop and report the exact capability gap instead of typing plaintext through X-Terminal.
9. Capture evidence for important steps: page state, extracted fields, and screenshots.
10. Stop and request confirmation before destructive or high-risk actions such as purchase, publish, submit, delete, transfer, or final sign-in submission with real credentials.

## Output

- A short browser action plan
- Key observations and extracted fields
- Evidence refs or screenshots when available
- Secret Vault requirement or secret lease status when credentialed steps are involved
- Any grant or permission that blocked completion

## Guardrails

- Do not bypass Hub or X-Terminal permission gates.
- Do not submit sensitive forms unless policy and user intent are both clear.
- Do not request, echo, or persist plaintext passwords, tokens, cookies, API keys, private keys, OTP codes, or payment credentials in chat unless the user explicitly refuses Secret Vault and the operator policy permits a manual fallback.
- Do not store secrets in the page, screenshots, memory, or skill output.
- Treat login, MFA, password reset, payment, and admin console flows as high-risk unless proven otherwise.
