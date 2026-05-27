# Backup & Disaster Recovery - Deep Dive

The mechanics behind the [backup & DR overview](backup-dr.md): the backup layers
and how they feed each other, the rebuild playbook, what is deliberately left
out, and the two failures that shaped the design.

## Backup layers

Several independent mechanisms, different cadences, different targets - so no
single failure loses everything.

This is structural by design, for two reasons. First, **recovery milestones**:
distinct layers mean a failure does not take *everything* down at once - I can
get back to a known-good point without a single all-or-nothing restore. Second,
it is a hedge against **my own mistakes** - if I ever push an untested or bad
config, the layered history gives me a clean state to fall back to rather than a
single backup that may already have the breakage baked in.

| Layer | Cadence | Target | Covers |
|---|---|---|---|
| Desktop backup (Déjà Dup) | Weekly | External USB | Home dirs, configs, working files |
| Vault sync | Every 6h (systemd timer) | Self-hosted Git | The documentation vault (this knowledge) |
| Config + secret collection | Weekly (systemd timer) | USB / Git | Service configs, SOPS-encrypted secrets, PKI, tunnel + proxy + DNS config, app source |
| Per-VM | Manual / as needed | USB | The VMs that are not trivially re-provisioned |

Secrets are collected **already SOPS-encrypted**, so the backup of secrets is
safe at rest. The collection script gathers exactly the things a rebuild needs
and nothing it does not.

### How the layers chain

The layers feed each other instead of each needing its own off-box target. The
weekly **collection script** (run as root via a systemd timer) gathers the
system-level, root-owned files the desktop backup can't reach - VPN PKI, the
proxy cert store, audit rules, app source - and writes them *into the home
tree*, so the weekly home backup then sweeps them onto the USB in one pass. The
documentation vault is the exception that gets a fast lane: a 6-hourly git push,
so a note written this afternoon survives even if the box dies before the weekly
run.

VM snapshots are **quiesced, not live-disk copies**: the script saves the VM
state, rsyncs the disk, then resumes - so the backup is transactionally
consistent rather than a copy taken from under a running OS. That distinction was
learned the hard way - see [Gotchas](#gotchas).

## The rebuild playbook

The disaster-recovery runbook is an **Ansible playbook (~20 roles)** that
stands the core server back up from scratch: base hardening (SSH, sysctl, CIS,
firewall, fail2ban, IDS, auditd), the Docker platform and reverse proxy, the
self-hosted Git restore (tarball -> version-detect -> restore), DNS, VPN, the
scheduled jobs, and the supporting services.

Intended DR path:

```
boot a fresh machine  ->  mount the USB (playbook + IN-CASE-OF-REBUILD notes)
                      ->  run the playbook locally  ->  restore data from backups
```

The playbook and a plain-language `IN CASE OF REBUILD` runbook live on the USB
alongside the backups, so recovery does not depend on any of the things being
recovered (no chicken-and-egg: you do not need GitLab up to learn how to bring
GitLab up).

## What is *not* backed up (on purpose)

- Local git clones - recoverable from their remotes
- VM disk images - too large; VMs are re-provisioned or restored from config
- Downloadable artifacts (ISOs, packages) - re-fetchable
- Anything derivable from a single source of truth that *is* backed up

## Gotchas

### The backup that looked fine until I needed it

**Symptom.** A snapshot I went to restore from simply **failed** - the image was
corrupt. The backup had sat there looking like a backup right up until the moment
its only job mattered, and then it had nothing.

**Root cause.** It was a **live-disk copy** - the VM's disk had been copied while
the OS was still running and writing to it. The result is transactionally
inconsistent: half-written state, a filesystem mid-flight, an image that mounts
but does not cleanly restore. A copy taken from under a running OS is a snapshot
of a moving target.

**Fix.** Quiesce first. The backup script now **saves the VM state, rsyncs the
disk, then resumes** - so the bytes on disk are not moving when they are copied,
and the image is consistent. (The deeper fix was philosophical: this is the
incident that made the [Ansible rebuild](backup-dr.md#why-rebuild-not-just-restore)
the real DR artifact, with images demoted to a fast first-try.)

**Lesson.** A backup you have never restored is a hypothesis, not a backup. Two
things have to be true and both have to be *tested*: the copy must be consistent
(quiesce a running system before imaging it), and the restore must actually run.

### GitLab restore is version-locked

**Symptom.** A GitLab backup will not restore onto a freshly pulled image: the
restore refuses unless the GitLab version **exactly matches** the one the backup
was taken on.

**Root cause.** GitLab's backup format is tied to how that specific version
handles its data (schema, migrations). Restore onto a different version and it
balks rather than risk mangling the data - and I do not track the very latest
release every day, so "just pull `latest`" is precisely the wrong move at restore
time.

**Fix.** The rebuild playbook does not assume a version. It **detects the version
the tarball came from and restores onto a matching image** (`tarball ->
version-detect -> restore`), then upgrades *after* the data is safely in. The
backup carries the version it needs, so the restore is never guessing.

**Lesson.** A backup is only as good as your ability to stand up the *exact*
thing that produced it. Versioned, schema-bound data means the runtime version is
part of the backup - capture it, do not assume it.

## Recreate it

The shape, not the secrets - templates land in the public repo (link to follow):

1. **Make config the source of truth.** Put the build in an Ansible playbook
   (base hardening, the container platform, DNS, VPN, the forge restore, the
   scheduled jobs) so the box is reproducible from version control, not from a
   disk you hope restores.
2. **Layer the backups.** Independent mechanisms on different cadences and
   targets - a fast lane for the things that change often (a 6-hourly push of the
   docs vault), a weekly sweep for home/config, and a root-run collector for the
   system files a user-level backup cannot reach. No single failure should lose
   everything.
3. **Chain them instead of multiplying targets.** Have the privileged collector
   write into the home tree so the one home backup sweeps it all to the USB in a
   single pass.
4. **Quiesce VMs before imaging** - save state, copy, resume - so the image is
   consistent, not a copy taken from under a running OS.
5. **Keep the runbook with the backups.** Put the playbook and a plain-language
   `IN CASE OF REBUILD` note on the USB next to the data, so recovery never
   depends on a service you are trying to recover.
6. **Restore-test it.** Actually run the path on a bare machine. An untested
   restore is a guess.

## Tested, not theoretical

The rebuild path is not a paper plan: it has been run **end-to-end and passed** -
a bare machine brought back to running services from the backups and the
playbook.
