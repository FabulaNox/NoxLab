# examples/ci — sanitised GitLab → GitHub publishing

Templates for the two-runner, single-commit-squash publish pipeline described
in [docs/ci-publishing.md](../../docs/ci-publishing.md).

## Files

| File | Purpose |
|---|---|
| `gitlab-ci.publish.yml` | Copy to your repo as `.gitlab-ci.yml`. `check` stage (DNS-gapped runner) + manual `publish` stage (egress runner) that force-pushes a single squashed commit to GitHub. |
| `sanitisation-gate.sh` | The gate: scans every tracked file, fails the build if any forbidden pattern appears. Install at `scripts/sanitisation-gate.sh`. |
| `sanitisation-patterns.example` | Starter `.sanitisation-patterns` — replace the examples with your own invariants. |

## Setup

1. **Two runners.** Register two GitLab runners and tag them `internal`
   (DNS-gapped: no resolver, no egress — runs untrusted build steps) and
   `external` (has egress — runs only the publish step).
2. **CI variables.** Set `GITHUB_USERNAME` and `GITHUB_TOKEN` (Protected). The
   token needs `Contents: Write`; add repo-creation scope only if you want the
   publish job to create the GitHub repo itself.
3. **Drop the files in:**
   ```sh
   cp gitlab-ci.publish.yml         <your-repo>/.gitlab-ci.yml
   cp sanitisation-gate.sh          <your-repo>/scripts/sanitisation-gate.sh
   cp sanitisation-patterns.example <your-repo>/.sanitisation-patterns   # then edit
   ```
4. **Edit** the author identity and your `.sanitisation-patterns`.

## Plant-test the gate before trusting it

A gate that has never rejected a known-bad input has not been proven to work.
Verify it fails:

```sh
printf '\nleak: yourdomain.example\n' >> README.md
sh scripts/sanitisation-gate.sh .sanitisation-patterns ; echo "exit=$?"   # expect 1
git checkout README.md
```

## Why it is shaped this way

- **Two runners** so untrusted build code (check stage) has no egress; only the
  narrow, credentialed publish step does.
- **Squash to one orphan commit** so the public repo's history is exactly the
  current sanitised state — a working-tree-only gate cannot catch a secret that
  lived in an older commit, so there must be no older commit.
- **Fixed public commit message**, not the GitLab HEAD message (which can be
  internal noise or leak internal identifiers).

Full reasoning: [docs/ci-publishing.md](../../docs/ci-publishing.md).
