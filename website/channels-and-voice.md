# Channels And Voice

<p class="lead">
You want AI in Slack. On your phone. In voice. Triggered by webhooks, on a schedule, from your team's tools. But you also want one audit trail — not seven. That's what X-Hub does that n8n and Zapier don't.
</p>

<div class="preview-note">
  <strong>We don't beat n8n on channel coverage.</strong>
  <a href="https://n8n.io">n8n</a>, <a href="https://zapier.com">Zapier AI</a>, and <a href="https://make.com">Make</a> do channel integration more smoothly than X-Hub does. Our contribution isn't "more channels" — it's "every channel under the same Hub-governed audit, grant, and signed-receipt chain."
</div>

## The Rule

All external-world events enter the Hub first.

The Hub owns:

- ingress authorization
- replay protection
- grant handling
- audit
- memory truth
- routing
- Supervisor-facing state projection

That also means channels and voice do not become the memory authority by accident: they can surface governed memory context, but they do not choose the memory executor and they do not write durable memory truth directly. That still stays on the Hub control plane through `Writer + Gate`.

## Remote Channels

The active channel direction centers on:

- Slack
- Telegram
- Feishu
- WhatsApp Cloud as an explicit later extension

The important part is not just channel coverage.
It is that these channels stay inside Hub governance instead of becoming direct command runtimes.

## Safe Onboarding

The onboarding direction for new remote ingress is:

1. unknown ingress enters discovery or quarantine
2. local admin approves once on a trusted management surface
3. Hub writes identity and channel binding
4. Hub runs a low-risk first smoke
5. only then does the path become a normal governed ingress

That is a much safer default than allowing every new chat surface to become a live trusted control path immediately.

## Voice As A Paired Surface

X-Terminal voice is not just dictation.
It is the paired high-trust interaction surface that turns Hub-governed state into something the operator can hear, confirm, and continue.

The active preview direction already includes:

- proactive Supervisor briefing
- Hub-issued voice challenge state
- repeat and cancel semantics
- mobile-confirmation latch handling
- source-aware pending-grant targeting
- post-action re-briefing back through the Hub path

The mobile-confirmation latch is the X-Hub implementation of the [agent-2fa](https://github.com/AndrewXie-Rich/agent-2fa) spec — extracted as a standalone protocol so other agent runtimes can implement the same paired-device-confirmation primitive without taking the rest of X-Hub.

## Why Source Awareness Matters

If multiple grants or remote requests are pending, voice should not guess.

That is why the voice flow is moving toward:

- source-aware pending-grant summaries
- remote-channel-aware targeting
- fail-closed behavior when grant selection is ambiguous

This is one of the places where usability and governance have to reinforce each other.

## The Product Shape

The desired operator experience looks like this:

- remote channel triggers a governed request
- Hub classifies and holds the decision path
- X-Terminal voice briefs the operator
- the operator approves or rejects through a guided challenge flow
- the system re-briefs using the same Hub truth path

That makes voice and channels part of one governed interaction chain instead of separate ad hoc surfaces.
