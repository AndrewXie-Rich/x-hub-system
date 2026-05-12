# RHM-078 Route Authority Prep Session Launchd

RHM-078 installs a reversible user LaunchAgent that reapplies provider/model
route prep and candidate environment at login.

It does not open X-Hub automatically and it does not enable provider/model
production authority, memory writer authority, or skills execution authority.

## Commands

```bash
bash tools/route_authority_prep_session_launchd.command --status
bash tools/route_authority_prep_session_launchd.command --install
bash tools/route_authority_prep_session_launchd.command --uninstall
```

The install path is:

```text
~/Library/LaunchAgents/com.ax.xhub.route-authority-prep-env.plist
```
