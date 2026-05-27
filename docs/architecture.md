# Architecture

The README has the diagram and the component summary. This page is the
*reasoning*: the principles the design keeps returning to, and the decisions
they drove.

## Design principles

### 1. Single source of truth, derived everywhere else

Every piece of state has one authoritative home; everything else is generated
or synced from it. Configuration, secrets, and documentation each live in one
canonical place, and copies are derived rather than hand-maintained in
parallel. Duplicated state is treated as a bug - it drifts, and the drift is
what bites you later (a stale symlink that silently kills a scheduled job, a
secret rotated in one store but not the other).

### 2. Controlled boundaries, not blanket controls

Trust is segmented and the boundaries are explicit: one ingress point, narrow
and intentional egress, network segments that match trust levels. Inside a
boundary, components are trusted; the effort goes into the boundary itself
rather than into layering redundant controls behind it. The CI runner split
(below) is the clearest example.

### 3. Minimal, reproducible, documented

Prefer boring and rebuildable over clever and bespoke. If it cannot be rebuilt
from version-controlled config and documentation, it is a liability. The
disaster-recovery playbook is a first-class artifact, not an afterthought.

### 4. Defence proportional to the threat model

Controls are sized to the actual risk. If an attacker would already need to
own the trust root for a control to matter, that control is not worth its
fragility. Security theatre below an assumed-compromised root is actively
avoided.

## Decisions these drove

### Two CI runners, split by egress

The self-hosted GitLab runs **two runners**:

- an **internal** runner that is DNS-gapped and runs build/test/lint jobs -
  untrusted code executes here, so it must not be able to reach the internet;
- an **external** runner that has egress and runs *only* the publish step that
  pushes sanitised snapshots to the public Git host.

Jobs are routed by tag. This is principle 2 applied to CI: rather than trying
to firewall every destination a build might attempt, the design ensures the
only component that *needs* egress is the one narrow, auditable step that has
it. See [CI/CD Publishing](ci-publishing.md).

### Publish as a single squashed snapshot

The public mirror is not a full-history mirror. The publish job force-pushes
the current state as a **single orphan commit**, stripping CI config. Rationale
(principle 1 + a real leak class): a sanitisation check that validates only the
working tree cannot catch a secret that lived in an *earlier* commit. Squashing
to one commit makes the public history exactly the current sanitised state, so
nothing historical can leak.

### Tiered Docker, not one flat host

Containers run in boot-ordered tiers on isolated per-tier bridges (reverse
proxy first, then stateful apps), so a container in one tier cannot reach
another laterally. See [docs/network.md](network.md) and the
[Docker Platform](platform.md) deep-dive.

### Secrets single-source in SOPS

Secrets are SOPS-encrypted at rest with one authoritative copy each. A secret
duplicated across two stores is a rotation footgun - rotate one, miss the
other. Where a credential is genuinely needed in two execution contexts, it is
split by role into two narrowly-scoped credentials rather than one shared value.
