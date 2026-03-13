# Restore Notes

Current `agent-backup` scope is intentionally narrow.

- It creates local tarball checkpoints under `.ax-backups/` inside the governed project root.
- It does not push artifacts to Hub, cloud object storage, or any remote destination.
- It does not install a scheduler or retention policy.
- Restore is manual today: unpack the selected tarball into a reviewable workspace and compare before replacing current files.

Recommended operator flow:

1. Create a checkpoint before a risky automation run or broad refactor.
2. Review the generated tarball name and timestamp under `.ax-backups/`.
3. If recovery is needed, extract into a separate folder first and diff before restoring files.
