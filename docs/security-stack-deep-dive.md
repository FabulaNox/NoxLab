# Security Stack - Deep Dive

The mechanics behind the [security-stack overview](security-stack.md): how
telemetry is logged and ranked, how the overnight local-LLM triage works, and
the real problems hit along the way.

## How telemetry is logged

Everything converges on Wazuh as ranked alerts. Three sources feed it, and two
things decide what actually matters.

**Sources**

- **Endpoint agents** on the core host and the client machines (workstation,
  laptop, the Windows lab VM) report auth, process, file-integrity, and Sysmon
  events.
- **Edge syslog.** The router (RouterOS) ships its logs to Wazuh with custom
  decoders and rules, so perimeter events (scans, drops) land next to host events.
- **Suricata** on the core writes network IDS alerts (`eve.json`) that Wazuh
  ingests - host, network, and perimeter detections share one timeline.

**What rises to the top**

- **Rule level.** Wazuh scores every alert; **level 10+** is treated as
  high/critical, and that is what the triage pipeline reads.
- **Threat-intel enrichment.** Public IOC feeds (abuse.ch) are pulled into Wazuh
  CDB lists on a timer, so an alert touching a known-bad IP/domain/hash is
  tagged.

```
endpoint agents  ->
edge syslog      ->   Wazuh SIEM   ->   ranked alerts (level 10+ = high/crit)
suricata (eve)   ->        ^
abuse.ch feeds --(CDB)-----+
```

## Real-time alerts

Not everything waits for the morning digest. Wazuh pushes **level-7-and-up**
alerts straight to a **Telegram bot** (Hermes) the moment they fire - so a scan,
a brute-force attempt, or a positive threat-intel hit reaches my phone in
seconds, with the agent, the rule, and a one-line description.

Severity is the filter, and it is tuned deliberately:

| Level | Treatment |
|---|---|
| 0-5 | Indexed and searchable, but **silent** - no push |
| 7+ | **Telegram alert** (high / critical) |
| 12+ | Emergency - always pushed |

Keeping the bar at level 7 is what makes the channel trustworthy: custom rules
demote known-benign noise *below* 7 (still searchable, just quiet) and promote
what matters *to* 7+. Some alerts are also enriched before they fire - a raw
network detection is correlated with DNS and device data, so the message names
the actual host and domain rather than just an IP.

The custom-rule work was not premature polish - **alert fatigue was real.** Out
of the box the channel was a wall of false positives, and a channel that cries
wolf is one you stop reading - which defeats the entire point of a real-time
alert. So the rule-tuning is not decoration; it is what decides whether a
level-7 ping on my phone actually means *look now*. Most of the gotchas below
came straight out of that fight to make escalations trustworthy.

A narrow class of message **bypasses the severity filter entirely**:
operational-availability alerts. When the LAN's DNS fails over - the core's
resolver goes down and the edge router swaps to public resolvers - and again when
it is restored, Hermes pushes a notification *regardless of level*, because "did
my DNS just fail over?" is something I want to know the instant it happens, not
have demoted as low-severity.

The failover is also logged with a marker - and that marker powers the real
detection win. A custom rule watches for any change to the router's DNS
configuration and, when the failover marker is **absent**, fires a
**high-severity** alert. The expected operational change identifies itself by its
marker; the *same* change *without* one - something quietly repointing the whole
network's DNS - is flagged as a likely **DNS hijack**. One pair of rules turns a
noisy operational event into a precise tripwire: the benign case is whitelisted by
the marker it emits, so anything that looks like it but does not announce itself
stands out. Failover mechanics in [Network](network-deep-dive.md#dns-failover).

So there are two alerting tiers: **Telegram in real time** for the high-severity
few, and the **overnight LLM digest** (below) for the long tail.

## How the daily report is built

A **scheduled overnight job** runs a report generator that turns the last day of
SIEM data into a single dated Markdown report (one per day, kept in the
knowledge-base vault). The report always has the same skeleton, so the rest of
the pipeline can parse it:

- **Top Wazuh Rules** - what fired most, with counts;
- **High / Critical Alerts** - the level-10+ events, per agent;
- **Top Suricata Signatures** - the loudest network detections.

That skeleton is the substrate the LLM passes read and annotate. A monthly
roll-up runs as well.

## First-line triage with a local LLM

### The problem

A homelab SIEM generates a *lot* of low-value noise - benign-but-loud events,
known false positives, routine churn. The volume is not small: **on a slow day
this box ingests around 160,000 events.** Hand-written scripts close the obvious,
but they only go so far, and finding the few things that actually matter in
what's left meant trimming through it by hand every morning. A lot of that was
being done with an external AI assistant - effective, but it sends telemetry out
of the lab, costs per use, and does not scale to "every single morning."

And I had already paid for a GPU that mostly sat idle overnight. Running a local
model on the long tail is partly just *using all the computer I paid for* - the
hardware was there, the work was there, so I put the two together.

### The moving parts

Triage is split into small pieces, each doing one job - and a model is used only
where judgement is actually needed. It all runs on **Gemma `gemma4:e4b` via
Ollama**, GPU-accelerated, entirely on the box.

1. **A fast triage gate.** A first pass over the report makes a quick posture
   *decision* and annotates the high/critical alerts. It also logs one row to a
   **baseline CSV** - the date, the model's decision, a column left for a later
   Claude verdict, how many sections were flagged, and timings - so L1's calls
   can be measured against L2 over time.
2. **The L1 agent.** The deeper pass classifies each high/critical alert as
   `KNOWN` / `SUSPICIOUS` / `UNKNOWN` with a one-line inference, then assembles
   an overall posture (`NORMAL` / `ELEVATED` / `CRITICAL`), a summary, and an
   action-items table, and injects an "L1 Analysis" block into the report.
   Cheap short-circuits run *before* the model: unconditionally-benign rules are
   closed outright, and a CVE pre-check closes alerts for a package already at
   its latest version.
3. **A correlation memory.** Benign patterns the model identifies are normalised
   (IPs to `/24`) and appended to a memory note the next run loads, so it gets a
   little sharper over time. The agent also does a vault **RAG lookup** per rule,
   so it sees notes like "this rule is expected from the VPN range - benign."

```
scheduled (overnight)
   |
   v
report generator ........ pulls the day from Wazuh + Suricata
   |
   v
daily report (.md)   sections: Top Rules | High/Critical (lvl 10+) | Suricata sigs
   |
   +--> triage gate (Gemma) .... fast posture decision + per-alert annotations
   |                              + baseline CSV row (Gemma decision vs Claude)
   |
   +--> L1 agent (Gemma) ....... classify + inference, posture, action items,
   |                              correlation memory, vault RAG
   |
   v
 unresolved >= threshold ?  --yes-->  L2 review (Claude, on demand) --> human verdict
   |
   no -->  human spot-check
```

### Tiered: L1 -> L2 -> human

- **L1 (Gemma, nightly, free).** Filters and summarises every night, closes the
  obvious, and never adjudicates.
- **L2 (Claude, on demand).** Only ever sees the handful L1 could not resolve;
  its verdict is recorded back in the baseline CSV next to L1's call.
- **Human.** Keeps the final verdict, always.

### Why local, why small, why overnight

- **Local** keeps the telemetry *in the lab*. Alerts never leave the network -
  no cloud, no per-token cost, no third party seeing the security events.
- **Small (`e4b`)** is enough for first-pass triage and runs comfortably on a
  budget GPU. The model is filtering and summarising, not adjudicating.
- **Overnight** uses the GPU when nothing else wants it; the digest is ready
  before the day starts.

### What it is, and what it is not

It is a **noise filter and first-pass summariser**. It is **not** the
decision-maker: escalations and verdicts stay with a human. A small local model
is good at "obviously benign / obviously worth a look," not at adjudicating
incidents - and it is deliberately kept on that side of the line.

This is the same design philosophy as the rest of the lab: the cheap, in-house,
reliability-first option, sized to the actual job. It also closes a loop with
the [hardware story](hardware.md#the-gpu-a-reliability-fix-that-unlocked-more) -
the GPU swap that fixed a crash loop is what made local inference possible.

## Gotchas

Real problems hit while building this, and how they were solved. One concrete
fix is worth a page of theory.

### Windows OpenSSH: keys in the "wrong" file, silently ignored

**Symptom.** Key-based SSH to a Windows endpoint (for managing its Wazuh agent)
kept dropping to a password prompt. The public key sat in the user's
`~/.ssh/authorized_keys` exactly as on Linux - and was simply never read. No
error, no log line pointing at the cause.

**Root cause.** The Windows account is in the local **Administrators** group,
and Windows OpenSSH deliberately reads admin-group keys from a *different* file:
`C:\ProgramData\ssh\administrators_authorized_keys`. The per-user file is
**silently ignored** for any admin account.

**Fix.** Install the key in that file, then lock it down - sshd refuses to use
it unless the ACL is exactly right:

```powershell
# append the key - mind the trailing newline; Add-Content concatenates onto the
# last line if the file does not already end in one, mangling the previous key
Add-Content C:\ProgramData\ssh\administrators_authorized_keys "ssh-ed25519 AAAA... comment"

# ACL: disable inheritance, then grant ONLY SYSTEM and Administrators
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r
icacls C:\ProgramData\ssh\administrators_authorized_keys /grant SYSTEM:F "BUILTIN\Administrators:F"
```

**Lesson.** Two silent-failure traps stacked: the admin-keys file, and an ACL
sshd rejects without telling you. When auth "just doesn't work" and nothing
logs, suspect a security control that fails closed *and quiet* by design - then
go read *its* rules, not your own config.

### The suppression that became a blind spot

**Symptom.** Nothing alerted - which was the problem. To quiet a noisy but
legitimate process (an anti-malware service that fired constantly), I had written
a suppression rule. It worked. It worked *too well.*

**Root cause.** The rule matched the process by **filename alone**
(`win.eventdata.image` ending in the binary's name). That suppresses *any*
process with that name, **wherever it runs from**. An attacker who names their
payload `MBAMService.exe` (or `TrustedInstaller.exe`, `TiWorker.exe`) and drops
it in `%TEMP%` or `AppData` inherits the suppression for free - a living-off-the-land
blind spot I had built into my own detection while trying to cut noise.

**Fix.** Anchor every suppression to the binary's **full install path**, so only
the real thing matches:

```xml
<!-- WRONG - name only, any path matches -->
<field name="win.eventdata.image" type="pcre2">(?i)(MBAMService|mbam)\.exe</field>

<!-- RIGHT - full path anchor, only the real binary matches -->
<field name="win.eventdata.image" type="pcre2">(?i)^C:\\Program Files\\Malwarebytes\\Anti-Malware\\(MBAMService|mbam)\.exe$</field>
```

**Lesson.** A suppression is a hole you punch in your *own* detection. Cut it to
the exact shape of the legitimate thing - anchor to the full path - or you have
handed an attacker a named gap to walk through. Noise reduction and coverage pull
against each other, and the way out is **precision, not breadth**. (PCRE2 in
Wazuh wants doubled backslashes in the path - a second small trap in the same
rule.)

### The "external scan" that was my own router

**Symptom.** The SIEM kept firing on what looked like an inbound scan: packets
hitting the WAN interface on a high UDP port with no matching connection state.
Textbook unsolicited-probe shape, so it scored as a perimeter event.

**Root cause.** It was self-inflicted. The edge router (RouterOS) was still
configured with a static public upstream DNS server, and it queries upstream DNS
from UDP **source** port 5678 (its MNDP port). When the reply came back to
`WAN:5678` there was no NAT state for it, the firewall dropped it, and the drop
logged as an unsolicited inbound packet - which Wazuh dutifully scored as a scan.
The router was tripping its own perimeter alert.

**Fix.** Point the router's DNS at the **internal resolver** and clear the static
public servers, so it stops emitting those upstream queries. The phantom "scan"
vanished. (Worth noting: real internet scanners *do* probe that port once it
looks active - which is exactly why you want the self-inflicted noise gone, so a
genuine probe is not buried under your own.)

**Lesson.** Not every perimeter alert is an attacker - some are your own kit
talking to itself in a way a stateful firewall cannot account for. Trace an alert
to the actual packet and flow before treating it as hostile. A SIEM that cries
wolf at its own router erodes the channel's credibility just as badly as any
other false positive - so this, too, was part of earning back trust in the alerts.

## Recreate it

The shape, not the secrets - templates land in the public repo (link to follow):

1. **SIEM core.** Stand up Wazuh (manager + indexer + dashboard). On modest
   hardware this is the deliberate pick over ELK - it carries the SIEM, agent
   management, and rule engine in a footprint a shared box can actually spare.
2. **Network IDS.** Run Suricata on the host, write `eve.json`, and have Wazuh
   ingest it so host and network detections share one timeline. Raise the
   AF-PACKET `ring-size` past the default if you see kernel drops under load.
3. **Telemetry in.** Install agents on every endpoint; ship the edge router's
   syslog with custom decoders/rules so perimeter events land next to host events.
4. **Cut the noise deliberately.** Demote known-benign rules *below* your alert
   threshold and promote what matters above it - and **anchor every suppression
   to a full path**, never a bare filename (see the gotcha above). Enrich raw
   network alerts with DNS/device data so a message names a host, not an IP.
5. **Threat-intel.** Pull public IOC feeds into Wazuh CDB lists on a timer to tag
   alerts touching known-bad indicators.
6. **Real-time + triage.** Push level-7+ alerts to a chat bot for the few that
   need eyes now; run a local model overnight on the long tail, escalating only
   what it cannot resolve to a human.
