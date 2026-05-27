# examples/cti - threat-intel feeds into the SIEM

A timer-driven updater that pulls public IOC feeds (abuse.ch) and builds Wazuh
CDB lists, so alerts can match against current known-bad indicators (see
[../../docs/security-stack.md](../../docs/security-stack.md)).

| File | Purpose |
|---|---|
| `update-cti-feeds.sh` | Fetch feeds, build CDB lists, upload to the Wazuh manager (parse + transport are yours to implement) |
| `cti-feed-update.service` | oneshot that runs the script |
| `cti-feed-update.timer` | Every 6 hours |

## Notes

- **Size guard:** the script refuses to ship a feed under a minimum size, so a
  bad fetch never overwrites a good CDB list with an empty one.
- **Keep keys in your secret store** (SOPS/env), not in the script.
- **Watch for a dead deploy.** A timer that fires but whose target is a dangling
  symlink fails silently (`status=203/EXEC`) and your IOC lists go stale without
  any alert. Point units at canonical paths, and check the timer occasionally:
  `journalctl -u cti-feed-update.service -n 20`.
