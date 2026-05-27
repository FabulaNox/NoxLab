# Network - Deep Dive

The mechanics behind the [network overview](network.md): how each path actually
works, and what broke along the way.

## Devices

Most of the "servers" are **VMs hosted on the single core host** - five of them
- not separate machines. Hardware footprint is deliberately small.

| Role | Where it runs | Notes |
|---|---|---|
| Core server | Bare metal | Hosts the Docker tiers, OpenVPN, DNS, Suricata, **and** the VirtualBox VMs |
| SIEM (Wazuh) | **VM on the core** | Bridged to the LAN; the heaviest of the VMs |
| Windows 11 | **VM on the core** | Bridged; Sysmon + Wazuh agent, an endpoint-detection target |
| Ubuntu lab | **VM on the core** | Bridged; general Linux experimentation |
| Fedora lab | **VM on the core** | Bridged; a second distro family (different package manager, SELinux defaults) |
| REMnux | **VM on the core** | **NAT-isolated, not bridged** - malware analysis, kept off the LAN by design |
| Workstation | Wired client | Monitored Windows desktop |
| Laptop (remote room) | Wi-Fi client | Reaches the LAN via a secondary AP -> switch -> powerline link |
| Offensive-security laptop | Wi-Fi / wired client | Training and tooling |
| Mobile | Wi-Fi client | Phone running a Kali chroot |
| Edge router | Bare metal | RouterOS; NAT, firewall, ships syslog to the SIEM |

## Ingress - two paths, neither a wide-open port

A single reverse proxy (Traefik) terminates all inbound TLS with a wildcard
ACME certificate (`*.example.com`). External reachability uses two deliberate
paths, and **no general inbound port is ever opened**:

1. **VPN (the only inbound NAT).** The edge firewall forwards exactly one WAN
   port: the VPN listener. Once on the tunnel you are on the LAN. Sensitive
   services (the forge, dashboards) sit behind allowlist middleware restricting
   them to LAN + VPN ranges, so they are unreachable from the open internet
   even though the proxy is internet-adjacent.
2. **Outbound tunnels for public services.** Select internal services are
   published through an outbound-initiated tunnel, so they are reachable
   publicly with **zero inbound ports** and no port-forwarding: the tunnel
   daemon dials out, nothing dials in. (Several providers offer this model.)

The tunnel is a deliberate trade, not a free lunch: it does put a third-party
provider in the path for the handful of services I publish. I take that trade
with eyes open. I am already trusting my ISP with every packet that leaves the
house, and a public resolver (`1.1.1.1`) as a DNS fallback - so for a couple of
public-facing pages, a provider that lets me keep **zero inbound surface** is the
side of the line I would rather be on. The privacy half of that worry - what my
ISP can see of my *DNS* - is handled separately, by running my own resolver with
DoH (below).

Admin SSH is key-only on per-host non-default ports.

## Certificates - one wildcard, auto-fanned out

All TLS in the lab is a single **wildcard certificate** (`*.example.com`). The
reverse proxy obtains and auto-renews it with a **DNS-01 challenge** (proving
control through the DNS provider's API), so renewal needs **no inbound port 80**
- which matters, because the lab opens no HTTP port to the internet at all.

The catch: the VPN server and the DoH resolver also need that cert, and neither
sits behind the proxy. Rather than give each its own ACME client, the renewal is
**fanned out** - when the proxy rewrites its cert store, two **systemd path
watchers** notice and run small extract-and-reload scripts:

```
proxy renews *.example.com  ->  writes its cert store
        |
        |-- path watcher --> extract --> DoH resolver  --> restart (skips if unchanged)
        `-- path watcher --> extract --> OpenVPN server --> reload
```

One renewal keeps every TLS consumer current, with zero manual steps. (VPN
client profiles embed the CA chain rather than the server cert, so they keep
working across renewals - they only need reissuing if the VPN's own PKI changes.)

## Egress

Outbound is treated as carefully as inbound. The worked example is the CI
platform's two runners:

- **internal** runner - DNS-gapped, runs untrusted build/test jobs;
- **external** runner - has egress, runs only the credentialed publish step.

Routed by tag, so untrusted build steps never share an egress path with the
publish step. This is "controlled boundaries, not blanket controls": the only
component with general egress is the one narrow step that needs it. See
[CI/CD Publishing](ci-publishing.md).

## DNS

Self-hosted in two layers on the core server:

- **Unbound** - recursive resolver for LAN, VPN, and containers, with
  blocklisting of known-bad domains;
- **dnsproxy** - a DNS-over-HTTPS frontend for clients that want encrypted
  resolution.

Internal names resolve to internal addresses (split-horizon), so the same
hostname works on-LAN and over VPN without exposing anything publicly. Resolver
endpoints are loopback aliases on the host, decoupled from any single NIC so
DNS survives reboots and link changes.

## DNS failover

Self-hosting DNS on the core server creates a single point of failure: LAN
clients are pointed at the core's resolver, so if the core is down the LAN loses
name resolution - and, in practice, the internet with it. A maintenance reboot
that left the core half-up made that risk concrete rather than theoretical.

The fix deliberately lives on the **edge router, not the core** - failover has to
run on something *other* than the box that fails. The router (RouterOS Netwatch)
probes the core's DoH listener on a short interval and drives a simple up/down
state machine:

- **Down** - the instant the listener stops answering, the router repoints LAN
  DNS at two public resolvers (Quad9 + Cloudflare). This is "do no harm":
  degraded mode loses local names and the core's own filtering, but the LAN
  **keeps working internet**.
- **Up (auto-revert)** - once the probe sees the listener healthy again, the
  router hands DNS back to the core, behind a short debounce so a flapping reboot
  cannot yank it back and forth.

The probe is a bare TCP connection to the port the router already uses for live
DoH, so it adds no new traffic pattern and needs no DNS itself to run. Because
the failover is autonomous and on an independent device, the core can fail, flap,
or sit broken and the LAN is protected regardless - no heroics required from the
core itself.

A DNS-server change *on a router* is also a textbook hijack indicator, so each
failover logs a marker and pushes a dedicated alert the moment it happens - the
operational change leaves a clear trail. See
[Security Stack](security-stack-deep-dive.md#real-time-alerts).

## Monitoring fan-in

Telemetry converges on the SIEM VM:

- **Endpoint agents** on the core server and the client machines report to the SIEM.
- **The edge router ships syslog** to the SIEM (with custom decoders/rules for
  router events).
- **Suricata** runs on the core server and feeds network IDS alerts in.

So a single pane sees host events, network events, and perimeter events. Detail
in [Security Stack](security-stack.md).

## Gotchas

### The port was already taken - by something I did not know was listening

**Symptom.** Standing up my own resolver, it would not start: the bind on port 53
failed. Nothing else *I* had installed was a DNS server, so on the face of it the
port should have been free.

**Root cause.** `systemd-resolved` ships with a **stub listener** on `127.0.0.53:53`
by default, and it had quietly been the box's resolver all along - `/etc/resolv.conf`
pointed at it. So port 53 was occupied by a service I had never consciously
configured. My resolver and the stub were fighting over the same socket.

**Fix.** Take the stub off the port and hand DNS to my own resolver:

```
# /etc/systemd/resolved.conf
DNSStubListener=no
```

then point `/etc/resolv.conf` at the resolver's own (loopback-alias) address
rather than at `127.0.0.53`. The resolver binds cleanly and is now the single
authority for name resolution on the host.

**Lesson.** "Nothing is listening" is an assumption, not a fact - check it
(`ss -tulpn`) before blaming your own config. On a modern systemd box, DNS is
already being handled by something whether you asked for it or not; self-hosting
means first *displacing* the default, not just adding a service next to it.
