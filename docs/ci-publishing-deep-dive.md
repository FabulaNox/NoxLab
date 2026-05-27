# CI/CD Publishing - Deep Dive

The mechanics behind the [CI/CD overview](ci-publishing.md): the two runners, the
pipeline, the sanitisation gate (and the gotcha that once waved a bad repo
through), and how to rebuild the whole thing.

## Two runners, split by egress

The single most important decision: there are **two CI runners**, and they
have deliberately different network access.

| Runner | Tag | Network | Runs |
|---|---|---|---|
| internal | `internal` | **DNS-gapped, no egress** | checks: lint, tests, sanitisation gate |
| external | `external` | DNS + egress | **only** the publish step |

Jobs are routed by tag. Untrusted code from any repository executes in the
*check* stage - so that runner must not be able to reach the internet. The
*publish* stage is the one credentialed, auditable step that needs egress, and
it is the only thing that gets it.

This is "controlled boundaries, not blanket controls." Rather than trying to
firewall every destination a build might attempt, the design guarantees that
the component which *needs* egress is the one narrow step that has it. And it
is sized to the real threat: a compromised dependency in a build job cannot
phone home. (If the GitLab host itself were compromised, the egress split is
moot - but that is a different, larger problem, and not one a CI control should
pretend to solve.)

It is not about *preventing* a breach - I am not assuming I can. It buys two
things a breach cannot easily undo: a poisoned dependency in a build job has
**nowhere to send anything** (the runner cannot even resolve a name), and the
one runner that *does* have egress is the narrow, audited publish step - so
everything that leaves passes a **logged chokepoint**. If something slips under
the radar there is still a trail to do forensics against afterwards. I would
rather have the log and not need it.

### Runners up close

Both runners use the shell executor and a **custom image with the toolchain
baked in** (shellcheck, bats, git, python) - so no job runs `apt-get` at build
time and the check stage has nothing to fetch. They sit on a dedicated internal
bridge and reach GitLab by its internal service name (`http://gitlab`), never
the public hostname. The split is enforced by DNS + tags:

| | internal runner | external runner |
|---|---|---|
| Tag | `internal` | `external` |
| DNS | none (gapped) | real resolvers |
| Runs | the `check` stage | the `publish` stage only |

The design **fails closed**: a publish job accidentally tagged `internal`
cannot resolve `github.com`, so it errors instead of leaking.

## The pipeline

```
check (tags: internal, every push)
  |- lint            (e.g. shellcheck)
  |- tests           (if any)
  `- sanitisation-gate
        |  (must pass)
        v
publish (tags: external, when: manual)
  `- squash + push a single commit to GitHub
```

## The sanitisation gate

Each repo carries a `.sanitisation-patterns` file (extended-regex, one
invariant per line) and a `scripts/sanitisation-gate.sh` that scans every
tracked file and **fails the build** if any forbidden identifier appears.

### Gotcha: the gate that waved a bad repo through

**Symptom.** The gate went green on a repo I *knew* held a forbidden invariant.

**Root cause.** Patterns were fed to `grep -f -` through `xargs`, which redirects
its child's stdin to `/dev/null` - so the pattern list was silently dropped and
the gate was matching against far less than it claimed.

**How I caught it.** Luck of timing: I pushed `msi-power-profile` and
`zombie-reaper` at the same moment. Both held a forbidden invariant; both should
have been rejected. The gate failed `msi` but waved `zombie-reaper` through -
and that inconsistency is the only reason I looked.

**Lesson.** A control that has never failed on a known-bad input has not been
proven to work. I now **plant-test** every gate: feed it something it *must*
reject and confirm a non-zero exit before trusting it.

## Squash-publish: not a mirror

The publish job does **not** mirror history. It force-pushes the current state
as a **single orphan commit**:

```
clone --depth 1  ->  rm -rf .git  ->  rm .gitlab-ci.yml  ->  git init  ->  one commit  ->  push --force
```

Why: the sanitisation gate validates only the *working tree*. A full-history
mirror would carry any secret that lived in an *earlier* commit, even one since
removed. Squashing to a single commit makes the public history **exactly the
current sanitised state** - there is no earlier commit for anything to hide in.
Each publish is a force-push of one fresh commit. Same blast-radius logic as the
rest of this pipeline: shrink what a single mistake can put in public.

The commit message is a **fixed public string** (`<project>: public snapshot
<date>`), never the GitLab HEAD message - which is often internal CI/chore
noise and once leaked the internal domain into a public commit before this was
fixed.

## Target creation and the token

- The publish job **self-creates the GitHub repo** if it does not exist
  (`POST /user/repos`), so there is no manual pre-step.
- The GitHub token lives in **exactly one place**: a GitLab CI variable. It is
  not duplicated into any secret store - duplicating a credential across two
  stores is a rotation footgun (rotate one, miss the other).
- Publish is **`when: manual`** - a human presses the button when a repo is
  ready to go public.

## Opt-in by construction

There is no central allow/deny list deciding what reaches GitHub. A repo is
published **only if both** of these are true:

1. it has a `publish` stage in its `.gitlab-ci.yml`, and
2. a human presses the manual Play button.

Private-only repositories (the knowledge-base vault, internal tooling) simply
never get a `publish` stage, so nothing *can* push them - protection by
construction, rather than an enforced blocklist that could be mis-edited. The
knowledge-base vault in particular has no publish stage and never will.

## Recreate it

The pieces, anonymised - the real values (domain, token, runner names) are yours
to fill in. Templates will be published in the public repo (link to follow).

1. **Two runners, split by tag.** Register an `internal` runner with **no DNS or
   egress** and an `external` runner with egress. Tag every `check` job
   `[internal]`; tag the `publish` job `[external]` and `when: manual`. Put both
   on a dedicated bridge and point their `clone_url` at the forge's internal
   service name, never its public hostname.
2. **One token, one place.** Store a GitHub PAT (contents-write; repo-creation
   scope only if the job self-creates repos) as a single CI variable. Do not
   copy it into a secret store as well - one source, one rotation.
3. **Per-repo invariants.** Drop a `.sanitisation-patterns` file (one
   extended-regex invariant per line) into each repo and wire the gate script
   into `check`.
4. **The publish job.** `clone --depth 1` -> strip `.gitlab-ci.yml` and `.git`
   -> `git init` -> one orphan commit with a fixed public message -> force-push.
5. **Plant-test the gate** before trusting it: feed it a value it *must* reject
   and confirm a non-zero exit (see the gotcha above).

A repo only ever reaches GitHub if it *has* a publish stage and a human clicks
it.
