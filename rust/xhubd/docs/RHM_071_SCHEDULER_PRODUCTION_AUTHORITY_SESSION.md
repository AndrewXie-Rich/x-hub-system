# RHM-071 Scheduler Production Authority Session

The current X-Hub build runs in single-app Bridge mode. The old Dock Agent
LaunchAgent can be absent, so scheduler production authority must be injected
through the user launchd session before starting `X-Hub.app`.

## Command

```bash
bash tools/scheduler_production_authority_session.command --status
bash tools/scheduler_production_authority_session.command --apply --open-xhub
bash tools/scheduler_production_authority_session.command --rollback
```

The command uses `launchctl setenv` and `launchctl unsetenv`. It does not edit
SwiftUI files, does not enable memory writer authority, does not enable skills
execution authority, and does not enable provider/model authority.
