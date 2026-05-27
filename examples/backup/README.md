# examples/backup - layered backup + rebuild

Templates behind [../../docs/backup-dr.md](../../docs/backup-dr.md): the DR
artifact is a rebuild playbook, not just snapshots.

| File | Purpose |
|---|---|
| `collect-backup-files.sh` | Gather configs + (already-encrypted) secrets into a staging dir for a weekly sync to USB/Git |
| `ansible/site.yml` | Rebuild-playbook skeleton: ordered roles from base hardening -> platform -> data restore |
| `ansible/roles/` | One dir per role (your real roles live private) |

## The rebuild path

```
boot a fresh machine  ->  mount the USB (playbook + IN-CASE-OF-REBUILD notes)
                      ->  ansible-playbook site.yml  ->  restore data
```

Keep the playbook **and** a plain-language runbook on the USB *with* the
backups, so recovery never depends on a service you are trying to recover.

## Two honest rules

- **A backup you have never restored is a hope, not a backup.** Same for a
  rebuild playbook you have never run cold - schedule a real end-to-end drill.
- **Collect only what a rebuild needs.** Anything recoverable from a remote, or
  derivable from a backed-up source of truth, is excluded on purpose.
