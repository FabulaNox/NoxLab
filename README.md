<div align="center">

# NoxLab

**A self-hosted security homelab - design, decisions, and a kit to build your own.**

Segmented network · tiered Docker platform · self-hosted GitLab with a
security-conscious CI/CD publishing pipeline · SIEM + threat-intel · tested
disaster recovery.

[Architecture](docs/architecture.md) ·
[Network](docs/network.md) ·
[Security Stack](docs/security-stack.md) ·
[Replicate it](#replicate-it)

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## Contents

- [What this is](#what-this-is)
- [Component repos](#component-repos)
- [Architecture at a glance](#architecture-at-a-glance)
- [Tech stack](#tech-stack)
- [What it does](#what-it-does)
- [Hardware](#hardware)
- [Replicate it](#replicate-it)
- [Roadmap](#roadmap)
- [Related projects](#related-projects)
- [Documentation](#documentation)
- [License](#license)

---

## What this is

NoxLab documents a single-server security homelab built for hands-on
cybersecurity and infrastructure practice - and packages the reusable parts
so you can build something similar.

It is a **reference architecture, not a copy of someone's secrets**: it uses
generic role names and example addresses (RFC 5737, `example.com`). No real
hostnames, IPs, domains, or credentials appear anywhere. The templates under
[`examples/`](examples/) are written to be adapted, not run blindly.

> **What is a security homelab?** A home server (or three) running the kinds
> of services a small org would run - a Git forge, a SIEM, DNS, a VPN, a
> reverse proxy - so you can operate, break, monitor, and rebuild them
> safely. The value is in running real systems end to end, not in the
> hardware.

## Component repos

Each capability is also its own standalone repo, with the real (anonymised)
configs, scripts, expected output, and the gotchas that shaped it:

| Repo | What it is |
|---|---|
| **[homelab-docker-platform](https://github.com/FabulaNox/homelab-docker-platform)** | Tiered Docker on one host: systemd boot-ordering, a self-healing preflight start, and a hardened Traefik reverse proxy. |
| **[homelab-network](https://github.com/FabulaNox/homelab-network)** | Segmented network: VPN-only ingress, self-hosted DNS (Unbound + DoH), one wildcard cert auto-fanned out, and router-side DNS failover. |
| **[wazuh-suricata-soc](https://github.com/FabulaNox/wazuh-suricata-soc)** | Detection stack: Wazuh SIEM + Suricata IDS with custom MITRE-mapped rules, threat-intel enrichment, and real-time alerting. |
| **[agentic-soc-triage](https://github.com/FabulaNox/agentic-soc-triage)** | A local-LLM SOC analyst: an L1 agent triages SIEM alerts overnight and escalates only what it cannot resolve to L2 / a human. |
| **[homelab-backup-dr](https://github.com/FabulaNox/homelab-backup-dr)** | Bare-metal disaster recovery: an Ansible rebuild playbook plus layered backups, tested end to end. |
| **[gitlab-secure-publish](https://github.com/FabulaNox/gitlab-secure-publish)** | The egress-split, sanitisation-gated CI pipeline that publishes these repos from GitLab to public GitHub. |

The [`examples/`](examples/) templates below are quick-start skeletons; the
component repos above are the full, detailed implementations.

## Architecture at a glance

![NoxLab architecture: an edge router with one inbound VPN port and an outbound tunnel for public services, fronting a management LAN whose core server hosts a tiered Docker platform, a reverse proxy, OpenVPN, self-hosted DNS (Unbound + dnsproxy), Suricata, and bridged VirtualBox VMs - with a NAT-isolated REMnux VM kept off the LAN by design.](assets/topology.svg)

The SIEM and lab VMs run **on** the core server (VirtualBox, bridged onto the
LAN so they get LAN addresses); they are not separate physical machines. The
only inbound NAT is the VPN port (forwarded to OpenVPN on the host); select
internal services are published outward via a tunnel that dials out, so there
is no inbound port for them at all. Full write-up:
[docs/architecture.md](docs/architecture.md) and [docs/network.md](docs/network.md).

## Tech stack

| Area | Tool | Role |
|---|---|---|
| Reverse proxy / ingress | **Traefik** | Single TLS termination, wildcard ACME cert, allowlist middleware |
| Git + CI/CD | **GitLab CE** | Self-hosted forge; two tagged runners (DNS-gapped internal + egress external) |
| SIEM | **Wazuh** | Log/alert correlation, custom rules, threat-intel CDB lists |
| IDS | **Suricata** | Network intrusion detection |
| Host hardening | **auditd, fail2ban, lynis** | Process auditing, brute-force bans, CIS auditing |
| DNS | **Unbound + dnsproxy** | Recursive resolver + DoH frontend, split-horizon, blocklisting |
| VPN | **OpenVPN** | Authenticated remote access (the only inbound service) |
| Secrets | **SOPS + age** | Encrypted at rest, single-source per secret |
| Platform | **Docker (tiered compose)** | Boot-ordered tiers, per-tier isolated bridges |
| DR | **Ansible** | Reproducible rebuild playbook, layered backups |

## What it does

- [x] Single TLS ingress; sensitive services reachable only via LAN/VPN
- [x] Segmented network (management / VPN / per-tier Docker bridges)
- [x] Self-hosted GitLab with a sanitised GitLab→GitHub publishing pipeline
- [x] CI runners split by egress: untrusted builds can't phone home
- [x] SIEM with automated threat-intel feed enrichment
- [x] Self-hosted recursive DNS + DoH with blocklisting
- [x] Layered backups + a tested Ansible rebuild path

## Hardware

One cheap second-hand workstation does almost everything; the "servers" are
mostly VMs running on it.

| Role | Hardware |
|---|---|
| Core server | **HP Z420** - Xeon E5-1650 v2 (6c/12t), 64 GB DDR3 ECC, GTX 1050 Ti, Ubuntu 24.04 LTS |
| Edge router | SOHO router running RouterOS |
| Secondary AP | Wi-Fi AP + switch + powerline link, for a remote-room client |
| Clients | Wired Windows workstation; working + Windows laptops; a phone running a Kali chroot |

The core server hosts the Docker tiers **and** the VirtualBox VMs (SIEM,
Windows, and Linux lab boxes), all bridged onto the LAN. It was picked for one
reason: cheap *and* it takes DDR3 ECC. Full reasoning, including the OS choice,
in [docs/hardware.md](docs/hardware.md).

## Replicate it

The [`examples/`](examples/) tree holds generalized, copy-adaptable configs
and scripts. Each is a starting point to adapt, not a turnkey deploy.

| Area | What's there |
|---|---|
| [`examples/ci/`](examples/ci/) | The GitLab→GitHub sanitised publish pipeline + sanitisation gate |
| [`examples/docker/`](examples/docker/) | Tiered compose templates + boot-order systemd units |
| [`examples/proxy/`](examples/proxy/) | Traefik dynamic config (wildcard TLS via ACME) |
| [`examples/dns/`](examples/dns/) | Unbound + dnsproxy config templates |
| [`examples/cti/`](examples/cti/) | Threat-intel feed updater (abuse.ch → Wazuh CDB) |
| [`examples/backup/`](examples/backup/) | collect-backup-files + Ansible rebuild skeleton |

Full from-scratch walkthrough: **[docs/REPRODUCE.md](docs/REPRODUCE.md)** - rebuild the whole lab on a fresh Ubuntu 24.04 host, phase by phase, linking each component's own reproduction guide.

## Roadmap

Staged or planned, in keeping with the cheap-and-low-power approach:

- **Jellyfin media server** - GPU hardware transcoding on the 1050 Ti; library + cache drives already acquired
- **Steam cache** - local caching of game downloads
- **Long-term local storage** - on the staged 2.5-inch laptop HDDs (~EUR 30 for the storage set, see [docs/hardware.md](docs/hardware.md#storage-roadmap))
- **Full IaC for the Docker tiers** - bring the tiered compose under the rebuild playbook

## Related projects

Standalone tools from this lab, each in its own repo:

- **[zombie-reaper](https://github.com/FabulaNox/zombie-reaper)** - systemd-timer zombie-process reaper
- **[msi-power-profile](https://github.com/FabulaNox/msi-power-profile)** - MSI laptop power-profile suite
- (more as they are published)

## Documentation

- [Hardware](docs/hardware.md) - the boxes and why they were chosen
- [Architecture](docs/architecture.md) - the big picture and design principles
- [Network](docs/network.md) - segments, ingress, controlled egress, DNS
- [Core Platform](docs/platform.md) - tiered Docker, boot ordering, host services
- [Security Stack](docs/security-stack.md) - SIEM, IDS, threat-intel
- [CI/CD Publishing](docs/ci-publishing.md) - the two-runner publish pipeline
- [Backup & DR](docs/backup-dr.md) - backup layers and the rebuild playbook
- [Reproduce it](docs/REPRODUCE.md) - rebuild the whole lab on fresh Ubuntu, phase by phase

## License

[MIT](LICENSE) - the docs, diagrams, and example templates are free to adapt.
