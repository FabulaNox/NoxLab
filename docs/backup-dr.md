# Backup & Disaster Recovery

The principle: **a system you cannot rebuild from version-controlled config and
documentation is a liability.** Snapshots help, but the real DR artifact here is
an **Ansible rebuild playbook** - the lab is meant to come back from a bare
machine, not just from a disk image.

## Why rebuild, not just restore

This is the lesson of a backup that failed when I needed it. Back in the
[unstable-GPU period](hardware.md#the-gpu-a-reliability-fix-that-unlocked-more),
a snapshot I went to recover from turned out to be **corrupted** - the restore
simply failed, and I had to start over from scratch. A backup you have never had
to use is a backup you do not actually know works.

So images did not get thrown out - they got demoted to *first try*. The recovery
order is layered: a disk image/snapshot is the **fast path** the playbook
attempts first, and **if it fails, the playbook rebuilds the box from config**.
The image is the speed; the playbook is the guarantee. One of them not working no
longer means starting from zero.

The playbook itself came out of coursework. We hit the IaC chapter, went deep on
Terraform, and I spent a while *trying to avoid* Ansible before facing the music
and writing the roles - which is exactly how the lab paid that learning back: a
real, tested rebuild path instead of a chapter I read once.

## At a glance

- **Layered backups** - independent mechanisms on different cadences and targets
  (weekly home backup, a 6-hourly vault push, a weekly config + encrypted-secret
  collection, per-VM as needed), so no single failure loses everything.
- **The DR artifact is a playbook** - an Ansible playbook (~20 roles) that stands
  the core server back up from bare metal, not a snapshot you hope restores.
- **Image-first, playbook-as-guarantee** - a disk image is the fast first try;
  the playbook is the fallback that always works.
- **Tested, not theoretical** - the rebuild path has been run end-to-end on a
  bare machine and passed.

[Full mechanics - the backup layers and how they chain, the rebuild playbook, what is deliberately not backed up, and two gotchas (a corrupt backup, and version-locked GitLab restore) &rarr;](backup-dr-deep-dive.md)
