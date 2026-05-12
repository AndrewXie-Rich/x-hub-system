# RHM-075 Route Authority Prep Session

RHM-075 applies provider/model route prep and candidate environment to the
current user launchd session with rollback state.

It is not a production authority cutover. It keeps:

- provider route production authority disabled
- model route production authority disabled
- memory writer authority disabled
- skills execution authority disabled

## Commands

```bash
bash tools/route_authority_prep_session.command --status
bash tools/route_authority_prep_session.command --apply
bash tools/route_authority_prep_session.command --rollback
```

The environment only affects newly launched X-Hub/Node processes. Existing
processes continue with their current environment until restarted.

Rollback state is written under:

```text
reports/route_authority_prep/launchctl_session_env_state.json
```
