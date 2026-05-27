# Rebuilding the whole lab on a fresh Ubuntu 24.04 LTS

This is the **top-level walkthrough**: someone on a clean install of
**Ubuntu 24.04 LTS (Noble)** rebuilding the entire homelab from scratch. It does not
repeat the per-component detail - instead it lays out the **order of operations** (the
dependency-aware sequence the rebuild playbook uses) and links each phase to the
component repository's own fresh-Ubuntu reproduction guide.

> **The fast path.** The whole lab is captured as a tested Ansible playbook (~24
> roles) that rebuilds the core server end to end with `failed=0`. If you have the
> playbook and the backup set, the real answer is "run the playbook" - see
> **Backup & DR** below. This walkthrough is the *manual* equivalent, phase by phase,
> for understanding or for rebuilding a single component by hand.

> **Conventions.** Abstracted throughout to match every component repo: host `core`
> (`192.0.2.10`), edge router `192.0.2.1`, LAN `192.0.2.0/24`, VPN
> `198.51.100.0/24`, Docker bridges `203.0.113.0/24`, domain `example.com`, and
> placeholder ports (`<SSH_PORT>`, `<VPN_PORT>`). All addresses are RFC 5737
> documentation ranges.

---

## Contents

- [The shape of a rebuild](#the-shape-of-a-rebuild)
- [Phase-by-phase (with links to each component guide)](#phase-by-phase-with-links-to-each-component-guide)
  - [1. Base host hardening](#1-base-host-hardening)
  - [2. Networking, DNS, firewall, VPN, tunnels](#2-networking-dns-firewall-vpn-tunnels)
  - [3. The Docker platform + reverse proxy](#3-the-docker-platform--reverse-proxy)
  - [4. Detection stack (SIEM agent + IDS + scheduled security jobs)](#4-detection-stack-siem-agent--ids--scheduled-security-jobs)
  - [5. Scheduled maintenance jobs](#5-scheduled-maintenance-jobs)
  - [6. Backup & disaster recovery (the meta-layer)](#6-backup--disaster-recovery-the-meta-layer)
- [Doing it the fast way (the playbook)](#doing-it-the-fast-way-the-playbook)
- [Component guide index](#component-guide-index)

---

## The shape of a rebuild

The core server is a single bare-metal Ubuntu 24.04 host. Everything below installs
onto it, in this order:

```
base host hardening  ->  networking + DNS  ->  firewall  ->  VPN (single inbound)
   ->  Docker platform + reverse proxy  ->  self-hosted DNS  ->  outbound tunnels
   ->  apps  ->  SIEM agent + IDS  ->  scheduled jobs  ->  local LLM / SOC agent
```

Two examples where the order bites you in a real run:

- The **VPN SSH firewall rule is added by the OpenVPN phase, not the firewall phase** -
  you cannot allow SSH over a tunnel that does not exist yet, so during the rebuild the
  firewall trusts only the LAN.
- **SSH's port lives in a `ssh.socket` drop-in, not `sshd_config`** - Ubuntu 24.04 uses
  socket activation, so editing `sshd_config` alone does not move the port.

---

## Phase-by-phase (with links to each component guide)

The phases below follow the playbook's role order. Where a component has its own
fresh-Ubuntu reproduction guide, follow that for the actual commands.

### 1. Base host hardening

Set hostname/timezone/groups, add the APT repos (Docker CE, Suricata PPA, Wazuh),
install the core package set, and apply baseline hardening: SSH on a non-default port
(socket drop-in, key-only), kernel sysctls (`rp_filter`, SYN cookies, IP forwarding
for VPN + Docker), and CIS-flavoured lockdown.

→ Kernel hardening (`sysctl`) is covered in the network guide, step 1:
**[homelab-network → REPRODUCE.md](https://github.com/FabulaNox/homelab-network/blob/main/docs/REPRODUCE.md)**.
The SSH socket drop-in and the role-ordering rules are documented in
**[homelab-backup-dr → REPRODUCE.md, Part A](https://github.com/FabulaNox/homelab-backup-dr/blob/main/docs/REPRODUCE.md)**.

### 2. Networking, DNS, firewall, VPN, tunnels

The network layer: host DNS-over-TLS, self-hosted **Unbound** recursive resolver,
**dnsproxy** DoH frontend, **UFW** (deny-inbound / allow-outbound, opened only for the
deliberate paths), **OpenVPN** as the single inbound port, internal **nginx** vhosts,
the **outbound tunnel** for public services, and the weekly **GeoIP** router refresh.

→ Full walkthrough:
**[homelab-network → REPRODUCE.md](https://github.com/FabulaNox/homelab-network/blob/main/docs/REPRODUCE.md)**
(sysctl, dns, unbound, dnsproxy, ufw, openvpn, nginx, cloudflared, geoblock-update).

### 3. The Docker platform + reverse proxy

A tiered Docker compose model (isolated per-tier bridges) behind a single Traefik
reverse proxy terminating all TLS with one wildcard ACME cert (DNS-01, no inbound :80).
Self-hosted GitLab and the secure publish pipeline sit on this platform.

→ The platform itself lives in a separate repo:
**[homelab-docker-platform](https://github.com/FabulaNox/homelab-docker-platform)**
(the tiering, the loopback-alias net-topology step) and
**[gitlab-secure-publish](https://github.com/FabulaNox/gitlab-secure-publish)** (the
two-runner CI). Reference architecture: see this site's
[Docker Tiers](architecture/docker-tiers.md) and
[CI/CD Publishing](operations/ci-publishing.md).

> Note: the network layer's TLS consumers (dnsproxy DoH, OpenVPN) get the wildcard
> cert *fanned out* from Traefik's `acme.json` via systemd path-watchers - so the
> reverse proxy phase precedes the cert-dependent network services in practice.

### 4. Detection stack (SIEM agent + IDS + scheduled security jobs)

On the core host: the **Wazuh agent**, **Suricata** IDS (writing `eve.json`, ingested
by the agent), the **auditd** ruleset, **fail2ban**, and the local **Ollama** runtime
for the overnight triage agent. The Wazuh **manager** stack runs on a separate VM.

→ Full walkthrough:
**[wazuh-suricata-soc → REPRODUCE.md](https://github.com/FabulaNox/wazuh-suricata-soc/blob/main/docs/REPRODUCE.md)**
(wazuh-agent, suricata, auditd, fail2ban, ollama; manager-stack steps in that repo's
README). The custom detection rules and tuning are documented in the same repo.

### 5. Scheduled maintenance jobs

Supporting timers that round out the host: the documentation **vault-sync** push, the
**zombie-reaper** process cleanup, plus `nfcapd`, `lynis`, and `obsidian-vault-mcp`.

→ Process cleanup:
**[zombie-reaper → docs/REPRODUCE.md](https://github.com/FabulaNox/zombie-reaper/blob/main/docs/REPRODUCE.md)**
(homelab deployment note; the repo README is the full install/usage reference).
→ Vault-sync is documented as part of
**[homelab-backup-dr → REPRODUCE.md, Part B](https://github.com/FabulaNox/homelab-backup-dr/blob/main/docs/REPRODUCE.md)**.

### 6. Backup & disaster recovery (the meta-layer)

The DR artifact *is* the rebuild playbook, paired with layered backups (desktop,
vault-sync, weekly config/secret collection, per-VM images) that chain into one off-box
sweep. Image-first as the fast try; the playbook as the guarantee.

→ Full walkthrough:
**[homelab-backup-dr → REPRODUCE.md](https://github.com/FabulaNox/homelab-backup-dr/blob/main/docs/REPRODUCE.md)**
(Part A: run the rebuild; Part B: wire the backups). Reference architecture:
[Backup & DR](operations/backup-dr.md).

---

## Doing it the fast way (the playbook)

If you are actually recovering rather than learning, the manual phases above collapse
into:

```
boot a fresh Ubuntu 24.04 machine
  -> mount the USB (playbook + IN-CASE-OF-REBUILD runbook)
  -> restore the backup set into ~/rebuild-plan/files/
  -> ansible-playbook -i inventory.ini site.yml          # all phases, in order
  -> restore data from backups (incl. the version-locked forge restore)
```

The playbook sequences every phase above automatically. Run a single phase with
`--tags <name>` or skip one with `--skip-tags <name>`. Always `--check` first. See
**[homelab-backup-dr → REPRODUCE.md, Part A](https://github.com/FabulaNox/homelab-backup-dr/blob/main/docs/REPRODUCE.md)**.

---

## Component guide index

| Phase | Component repo | Reproduction guide |
|---|---|---|
| Networking, DNS, VPN, tunnels | homelab-network | `docs/REPRODUCE.md` |
| Detection (SIEM agent, IDS) | wazuh-suricata-soc | `docs/REPRODUCE.md` |
| Backup, DR, rebuild playbook | homelab-backup-dr | `docs/REPRODUCE.md` |
| Process cleanup | zombie-reaper | `docs/REPRODUCE.md` |
| Docker platform + proxy | homelab-docker-platform | (see repo) |
| CI/CD publishing | gitlab-secure-publish | (see repo) |

Each component guide states the playbook role(s) it derives from and ends with verify
steps. Together they reconstruct the lab in the order this page lays out.
