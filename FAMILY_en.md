# X-Hub-System for Families

> A home Hub that lets the whole family share AI — while parents still hold the boundary.

[中文](FAMILY.md) · [Back to README](README.md) · [Enterprise](ENTERPRISE.md)

## Who this is for

- Families with minors using AI assistants who want parents to set the execution boundary
- Households that want one place to manage both local models and paid APIs (instead of juggling two accounts, two keys, two quotas)
- People who don't want their family's conversations going to third-party clouds for training data
- Anyone wiring up a unified AI entry point across home computers, phones, and smart speakers

## Three roles, one example layout

In a family setting, this split tends to work (both parents can be admins too):

| Role | Who | Can do |
|---|---|---|
| **Admin** | Parents | Pick which models are available, which skills install, set write / read / execute boundaries, review audit log |
| **Adult member** | Spouse / adult relatives | Everyday use of all allowed capabilities; high-risk actions (file writes, installs, sends) need admin mobile confirmation |
| **Minor member** | Kids | Observer by default; execute / write / browse / network access all require explicit admin grant; time-of-day and topic limits available |

> The multi-user role model is on the 90-day P0 roadmap (see [ENTERPRISE.md](ENTERPRISE.md)). The current kernel only supports single-user grants; the three-role family pattern lights up as that work lands.

## Second-factor confirmation for high-risk actions

When a kid or family member asks the AI to do something with **side effects** — write a file, install software, drive a browser to buy something, send a message out — Hub uses your `A-Tier` (execution authority) and `S-Tier` (supervision depth) settings to decide whether to require:

- A push notification on the parent's phone to confirm
- A voice-channel (preview) authentication
- A mobile-confirmation latch unlock before continuing

Low-risk actions (asking questions, reading files, looking things up) don't trigger confirmation — otherwise the AI becomes painful to use.

## Privacy and data sovereignty

- **Models can be 100% local** — your home machine (Mac with 16GB+ recommended, or a Linux box with a GPU) can run Transformers / MLX models locally; conversations never leave your network
- **Paid APIs flow through Hub-held keys** — your Claude / GPT subscription keys stay in Hub; the kid's device never holds a key
- **Memory writes go through `Writer + Gate`** — durable memory has a boundary and an audit trail, so one conversation can't unilaterally pollute it
- **Audit stays local** — who, when, asking which AI, asking what, AI doing what — all recorded in your own Hub database

## 5-step setup (macOS)

```bash
# 1. Clone and build (or grab a DMG from Releases)
git clone https://github.com/AndrewXie-Rich/x-hub-system.git
cd x-hub-system && ./x-hub/tools/build_hub_app.command

# 2. Launch Hub
open build/X-Hub.app

# 3. In Hub, configure your models — local + at least one paid provider
# 4. Install X-Terminal on the kid's machine, pair it with your home Hub
open build/X-Terminal.app

# 5. In Hub, set up the three roles + mobile confirmation for high-risk actions
#    (depends on P0 multi-user landing)
```

Full install / pairing / model setup is in [README.md](README.md) "Quick start" and [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md).

## Free forever

- Family use is permanently free
- MIT-licensed kernel, unlimited devices
- We won't move family-scale features behind a paid tier

## Going further

- Want it for a team or company? See [ENTERPRISE.md](ENTERPRISE.md)
- Want the technical architecture? See [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md) and the [capability matrix](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md)
- Issues: <https://github.com/AndrewXie-Rich/x-hub-system/issues>
