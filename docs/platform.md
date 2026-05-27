# The Docker Platform

The core server runs two kinds of workload side by side: containerized
services in a **tiered Docker layout**, and a set of **host-level services**
(DNS, VPN, IDS, the VMs, a local LLM) that sit alongside the containers.

## Why tiers, not one flat compose

A single big `docker-compose.yml` has two problems this design avoids:

1. **There is a real order to things.** This box also serves the network's DNS,
   including DoH, so resolution has to come up *first* - everything else depends
   on it. Then the reverse proxy (Traefik): it fronts the public site over the
   outbound tunnel, fronts GitLab, and is the **single cert authority** for the
   whole lab - so it has to be up before the apps it carries. Tiers let systemd
   sequence that dependency graph deterministically instead of leaving it to
   chance.
2. **Isolation.** A flat network lets every container reach every other one.
   Tiers run on separate bridges, so a container in the apps tier cannot talk to
   the Git/CI tier laterally.

## At a glance

- **Tier 0 (ingress)** - Traefik, the single TLS front door and the lab's one
  cert authority, comes up first.
- **Tier 1 (stateful)** - GitLab + CI runners and the public apps, each on its
  **own isolated bridge**, reachable only through tier 0.
- **Boot-ordered and self-healing** - the dependency graph is
  `Wants=`/`After=`-wired and survives a cold reboot, and the start path clears a
  leftover/squatter container that would otherwise dead-end the boot.
- **Stable endpoints** - the proxy and resolvers bind **loopback aliases**, not a
  NIC, so nothing cares which link is up.
- **Host services alongside the containers** - Unbound, dnsproxy, OpenVPN,
  Suricata, VirtualBox, and a local LLM run directly on the box.

[Full mechanics - the tier layout, boot ordering, loopback aliases, host services, and the cert-store gotcha &rarr;](platform-deep-dive.md)
