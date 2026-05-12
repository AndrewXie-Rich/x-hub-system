# RHM-072 Scheduler Production Authority Session Launchd

RHM-072 adds a reversible user LaunchAgent that reapplies the Rust scheduler
production-authority session environment at login. It is for the single-app
X-Hub runtime where the removed standalone Dock Agent LaunchAgent can no longer
own production authority environment.

The LaunchAgent runs:

```bash
bash tools/scheduler_production_authority_session.command --apply
```

It does not open X-Hub automatically and it does not grant memory writer,
skills execution, provider route, or model route authority.

## Commands

```bash
bash tools/scheduler_production_authority_session_launchd.command --status
bash tools/scheduler_production_authority_session_launchd.command --install
bash tools/scheduler_production_authority_session_launchd.command --uninstall
```

The install path is:

```text
~/Library/LaunchAgents/com.ax.xhub.scheduler-authority-env.plist
```

State and logs are written under:

```text
reports/scheduler_production_authority/
```

## Verification Contract

The tool reports the persistent LaunchAgent separately from current runtime
effectiveness. Current runtime authority is checked by
`scheduler_production_authority_session.command --status`, which inspects the
running X-Hub Node process for managed scheduler keys without printing secret
environment values.

UI product files are not changed.
