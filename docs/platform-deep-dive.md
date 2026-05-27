# The Docker Platform - Deep Dive

The mechanics behind the [platform overview](platform.md): how the tiers are laid
out on disk, how systemd sequences them, and the cert-store failure that came out
of running the proxy unprivileged.

## The tiers

On disk the tiers are just directories of compose files that systemd brings up
in order:

```
~/docker/
├── tier0/                 # ingress
│   ├── docker-compose.yml   Traefik (host networking)
│   ├── traefik.yml          static config
│   ├── dynamic.yml          routers + LAN/VPN allowlist middleware
│   └── certs/acme.json      the wildcard cert store (root:600)
└── tier1/                 # stateful, each service on its own bridge
    ├── gitlab/              GitLab CE + the two CI runners
    └── apps/                public-facing static site(s)
```

### Tier 0 - ingress

The reverse proxy (**Traefik**) runs in tier 0 with host networking and comes
up first. It is the single TLS termination point and the **only cert authority**
in the lab: it runs the one ACME (Let's Encrypt) client, holds the wildcard
cert, and fans the renewed cert out to the other TLS consumers (the DoH resolver
and the VPN server) rather than have each run its own ACME - see
[Network](network.md). It runs **unprivileged** (`cap_drop: ALL`); that choice
has a sharp edge, recorded in [Gotchas](#gotchas) below.

### Tier 1 - stateful services

Tier 1 holds the things that depend on tier 0 being up, each on its **own
isolated bridge**:

- **Git/CI** - GitLab CE plus the two CI runners (internal + external). See
  [CI/CD Publishing](ci-publishing.md).
- **Apps** - the public-facing static site(s).

Because the tiers are separate bridges, the apps tier and the Git/CI tier
cannot reach each other directly; both are reached only through tier 0.

## Boot ordering

systemd units sequence the platform so it comes up the same way every time:

```
network/topology setup
        |
        v
docker-tier0  (Traefik, ingress)
        |
        v
docker-tier1-apps  +  docker-tier1-git   (start in parallel once tier 0 is up)
```

This matters because the proxy and DNS have to exist before the apps try to
resolve names or register routes. The whole chain is `Wants=`/`After=`-ordered
and survives a cold reboot (verified by booting the box and watching the tiers
come up in order).

### Self-healing the start path

Deterministic ordering only helps if each unit can actually *start* - and a
leftover container from an earlier layout can dead-end the whole chain (see
[Gotchas](#gotchas)). So each tier unit runs an idempotent **preflight** before
`compose up`: it looks for any container squatting a name the tier manages and,
**only if that container belongs to a different compose project (or none)**,
removes it. The legitimate tier-owned container is never touched, and a second
run with nothing to clean is a silent no-op.

A **tier-aware circuit breaker** stops the preflight fighting a persistent
recreator forever. It retries a bounded number of times; if a squatter keeps
coming back, it stops and logs a `CRITICAL` breadcrumb (the offending project and
image). For the **foundational tier** it then exits *cleanly* rather than
hard-failing the box - LAN internet is protected independently by
[DNS failover](network-deep-dive.md#dns-failover), so a hard tier-0 failure would
be needless and harmful; the `CRITICAL` log is the escalation signal. Leaf tiers
(apps, Git/CI) fail loud instead, since they cannot take the network down with
them.

## Stable endpoints via loopback aliases

The reverse proxy and the DNS resolvers bind to **dedicated loopback aliases**
(e.g. `127.0.0.10`, `127.0.0.11`, `127.0.0.12`) rather than to a NIC address.

The reasoning is lean, not clever. On boot the physical NIC may not be up yet
when something first needs DNS, and binding to a NIC IP makes a service fragile
across link changes. Loopback is always up and it is *there to be used* - so
rather than write logic to track the active NIC or react to link changes, I bind
to something that never moves. `resolv.conf` points at the loopback-alias
resolver, the proxy advertises a loopback-alias endpoint, and none of it cares
which NIC is active or whether the LAN is up. Why re-implement behaviour the OS
already hands you for free?

## Host services (outside Docker)

Not everything is a container. Running directly on the host:

| Service | Role |
|---|---|
| **Unbound** | Recursive DNS resolver (LAN/VPN/containers), blocklisting |
| **dnsproxy** | DNS-over-HTTPS frontend |
| **OpenVPN** | The one inbound service (remote access) |
| **Suricata** | Network IDS, feeds the SIEM |
| **VirtualBox** | Hosts the VMs (SIEM, Windows, Linux labs) |
| **Ollama + Gemma** | Local LLM for first-line SIEM alert triage (GPU) - see [Security Stack](security-stack.md) |
| Scheduled jobs (systemd timers) | Threat-intel feed refresh, backups, audits, housekeeping |

## Gotchas

### The cert store nobody could read

**Symptom.** TLS certificates stopped renewing. The obvious cause was a renewal
*script* failing - but it failed *silently*, and fixing the script did not bring
the certs back.

**What it looked like from the floor.** Not a cert error - a *DNS* one. The DoH
resolver clients use is served over that same wildcard cert, so when the cert
went bad the resolver stopped answering: phones on wi-fi could not resolve
anything, while the wired PCs kept limping along on internet access *purely*
because their DNS cache had not been purged yet. "Down for some devices, fine for
others" is a long way from "a cert file has the wrong owner" - and that gap is
what makes this kind of failure slow to spot.

**Root cause.** Two failures stacked. Going into the renewal path to debug the
script, I found `acme.json` (the proxy's cert store) was owned by my user, not
root. Traefik runs **unprivileged** (`cap_drop: ALL`), so it has no
`CAP_DAC_OVERRIDE` - which means even root *inside* the container honours file
ownership. It could not read its own cert store and was quietly falling back to
a self-signed cert. It would have choked there even if the script had worked.

**Fix.** `acme.json` owned `root`, mode `600`. ("TLS is up but every client
screams" is the tell for a self-signed fallback.)

**Lesson.** A silent failure can hide a second, latent one - the script error
masked a permission problem that was going to bite regardless. And capabilities
you drop are capabilities you then have to honour: once `CAP_DAC_OVERRIDE` is
gone, file ownership is load-bearing and has to be exactly right.

### The reboot that ate itself

**Symptom.** After a routine maintenance reboot the whole stack came up broken:
tier 0 failed to start, and both tier 1 units cascaded into dependency failure -
no proxy, no site, no Git/CI.

**Root cause.** Two faults at once. A **leftover container from a previous
layout**, kept alive by Docker's `restart: unless-stopped` policy, had grabbed
the name tier 0's proxy wanted - so `compose up` hit a name conflict, the tier-0
unit failed, and everything that `Requires=` it refused to start. Separately, an
**unpinned CI runner had raced in and taken the static IP** the forge container
expected - an IPAM collision on the shared bridge.

**Fix.** Two layers. Immediately: remove the squatter, pin the runner IPs, bring
the tiers up by hand. Durably: the tier units now **self-heal on start** (see
[above](#self-healing-the-start-path)) - the preflight clears a foreign squatter
before `compose up`, and the circuit breaker stops it fighting a persistent
recreator - and every container IP that must be stable is pinned, so nothing can
race for it.

**Lesson.** Deterministic boot ordering is not the same as *resilient* boot
ordering - ordering assumes every step can actually start. A single stale
artifact from an old layout can dead-end an otherwise-correct dependency graph,
so the start path has to clean up after the past, not just sequence the present.
And on a shared bridge, "it got the right address last time" is luck until it is
pinned.
