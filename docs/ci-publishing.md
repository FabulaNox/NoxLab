# CI/CD Publishing

The self-hosted GitLab is the everyday **forge** and the source of truth -
normal development only ever pushes *there*. GitHub is **not** a mirror: only a
hand-picked few **showpiece** repos are ever published outward, and only by a
deliberate manual step. The job here is to publish those selected repos to public
GitHub **without** leaking the internal domain, secrets, or git history, and
**without** giving untrusted CI jobs a path to the internet. This is the most
deliberate piece of engineering in the lab, so it gets the most detail.

## Why this exists

I make mistakes, and I lean on AI heavily - so the design assumption is that
something *will* slip through. The goal was never a perfect gate; it is a
**small blast radius** for when one does. Everything here verifies locally,
fails closed, and keeps the damage contained and *auditable*.

It lives on my own GitLab rather than straight on GitHub for two reasons:

- **A platform breach makes my own hardening worthless.** Platforms get breached
  (*cough* GitHub *cough*), so if the host goes it does not matter how careful I
  was with my own repos. The source of truth stays on a box I control; GitHub is
  only ever a publish target, never the trust root.
- **CI cost.** Real work through hosted Actions minutes gets expensive fast. My
  own runners are free and I can shape them however I want - which is what makes
  the egress split possible.

## At a glance

- **Two runners, split by egress.** Untrusted build/test jobs run on a
  **DNS-gapped** runner with no route out; only the one credentialed **publish**
  step runs on a runner that has egress.
- **Fails closed.** A publish job accidentally tagged `internal` cannot even
  resolve `github.com`, so it errors instead of leaking.
- **Squash-publish, not a mirror.** Publishing force-pushes a single orphan
  commit, so there is no history - and no old-commit secret - to leak.
- **Opt-in by construction.** A repo reaches GitHub only if it *has* a publish
  stage *and* a human clicks the manual button. The vault and internal tooling
  simply never get one.

[Full mechanics - the two runners up close, the pipeline, the sanitisation gate and the gotcha that waved a bad repo through, squash-publish, and how to recreate it &rarr;](ci-publishing-deep-dive.md)
