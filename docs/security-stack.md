# Security Stack

The lab's reason for existing: run real detection on real telemetry, end to
end - and not drown in the noise that produces.

## Why this stack

Detection is a career path I'm aiming at and it was core to my studies - so
building the stack was the obvious thing to actually *learn the software* on,
rather than read about it. The lab is the place I get my hands on the tools a real shop runs.

It is **Wazuh**, not ELK, for a blunt reason: hardware. I ran an ELK stack first
and liked it - but this is one second-hand workstation that also does development
and everyday work, and ELK was simply too heavy to sit on top of all that. In the
early days, fighting ELK's resource appetite *on top of* everything else the box
was doing was pure frustration. Wazuh gives me a SIEM, agent management, and a
rule engine in a footprint the box can actually carry while still being useful for
everything else. **Suricata** adds the network-IDS half cheaply. The whole design
bends to one constraint - it has to earn its keep on hardware that is also doing
three other jobs.

## The pieces

| Component | Role |
|---|---|
| **Wazuh** | SIEM - log/alert correlation, custom rules, agent management |
| **Suricata** | Network IDS on the core server, feeds Wazuh |
| Endpoint agents | On the server and client machines (workstation, laptop, Windows lab VM), reporting to Wazuh |
| Edge syslog | The router ships logs to Wazuh with custom decoders/rules |
| Threat-intel feeds | Public IOC feeds (e.g. abuse.ch) pulled into Wazuh CDB lists on a timer |
| **Telegram bot (Hermes)** | Real-time push of high-severity (level 7+) alerts |
| **Local LLM (Gemma `gemma4:e4b`)** | Tiered alert triage - an L1 classifier/escalator that runs overnight and escalates only what it cannot resolve to an L2 (Claude) review |

## At a glance

- **Telemetry fans in** - endpoint agents, edge-router syslog, and Suricata all
  converge on Wazuh, so host, network, and perimeter detections share one timeline.
- **Threat-intel enrichment** - public IOC feeds tag any alert that touches a
  known-bad IP, domain, or hash.
- **Real-time** - level-7-and-up alerts push to a Telegram bot the moment they
  fire; everything quieter stays searchable but silent.
- **Overnight triage** - a local Gemma model works the long tail (this box sees
  ~160k events on a *slow* day), closing the obvious and escalating only what it
  cannot resolve to an L2 (Claude) review. A human keeps every verdict.
- **The real work was trust** - out of the box the alert channel was a wall of
  false positives; the custom-rule tuning is what makes a level-7 ping actually
  mean *look now*.
- **Detection engineering** - paired rules mark a known operational DNS failover
  as benign by its log marker, while the *same* DNS change *without* that marker
  fires high-severity as a likely hijack.

[Full mechanics - the telemetry pipeline, the local-LLM triage in depth, and three real gotchas (the Windows ACL trap, a suppression blind spot, and the router that scanned itself) &rarr;](security-stack-deep-dive.md)
