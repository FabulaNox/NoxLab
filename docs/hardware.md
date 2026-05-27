# Hardware

The whole lab runs on modest, deliberately cheap hardware. The point was
never the kit - it was running real systems on whatever was affordable.

## Core server - HP Z420 workstation

Everything (the Docker tiers, the VMs, DNS, the VPN) runs on a single
second-hand HP Z420 workstation. It was chosen for exactly two reasons:

1. **It was cheap.** Z420s are plentiful and inexpensive on the used market.
2. **It takes DDR3 ECC memory.** Error-correcting RAM matters for a box that
   runs a SIEM, several VMs, and services you actually want to trust - and the
   Z420 made ECC affordable on a budget. That combination (cheap + ECC) was the
   whole decision.

The GPU was changed later - that has its own story ([below](#the-gpu-a-reliability-fix-that-unlocked-more)).

| Component | Spec |
|---|---|
| Model | HP Z420 workstation |
| CPU | Intel Xeon E5-1650 v2 - 6 cores / 12 threads |
| RAM | 64 GB DDR3 **ECC** |
| GPU | NVIDIA GTX 1050 Ti (replaced the original Quadro K2000) |
| OS | Ubuntu 24.04 LTS |

### Why Ubuntu 24.04 LTS

The goal was to stay in the **Debian family** - familiar tooling, `apt`, and
the broadest pool of documentation and community answers. Given that, an
**Ubuntu LTS** release was the logical choice: a long support window and
predictable, boring stability, which is exactly what you want under
infrastructure you are going to leave running and forget about.

> ECC + LTS is a theme: the boring, reliability-first choice at each layer,
> because the interesting part is what runs *on top*, not the substrate.

### The GPU: a reliability fix that unlocked more

The Z420 originally shipped with an **NVIDIA Quadro K2000**. On Linux it ran the
open-source `nouveau` driver, and - like clockwork, roughly every three days -
the driver would fall over and take the desktop session with it. The root cause
was a GNOME bug upstream had marked **won't fix**, so no patch was coming.

Swapping in a **GTX 1050 Ti** solved it: it has well-supported proprietary
NVIDIA drivers on Linux and enough headroom to do real work. Stability came
back - and the spare capacity turned a forced fix into an enabler. The box went
from "barely keeping a desktop alive" to two new workloads:

- **Local LLM for first-line (L1) alert review** - running Google's **Gemma**
  via **Ollama** on the GPU to triage SIEM alerts as a first-pass analyst
  before they reach a human. Local inference keeps the telemetry in-house. See
  [Security Stack](security-stack.md).
- **Jellyfin media server (in progress)** - using the GPU for hardware
  transcoding.

The lesson that recurs throughout the lab: a constraint forced a change, and
the change opened a door. Reliability first, capability follows.

### Storage (roadmap)

Cheap, low-power storage is staged for upcoming uses - **about EUR 30 for the
lot**:

- **2x 1 TB 2.5-inch laptop HDDs.** Chosen for the small form factor and low
  power draw. One is earmarked for **long-term local storage**, the other for
  the **Jellyfin library + a Steam cache**.
- **1x 128 GB drive** as a **Jellyfin transcode/cache drive**.

Both Jellyfin and the Steam cache are on the [roadmap](../README.md#roadmap).
The pattern holds: solve it cheaply, with low-power parts, and leave room to
grow.
