# examples/soc-llm — local-LLM first-line alert triage

A generalized template for running a **small local model as an overnight L1
SOC analyst**: pull the day's SIEM alerts, have the model triage them into a
short digest, and have that ready before the day starts. Local inference keeps
the telemetry in-house, costs nothing per run, and is sized for a budget GPU.

> This is a **pattern**, not a turnkey deploy. The model isn't the
> decision-maker — it filters noise and summarises so a human reviews a short
> list, not hundreds of events. Escalations and verdicts stay with a human.

## What's here

| File | Purpose |
|---|---|
| `l1-triage.sh` | Skeleton: pull alerts -> prompt the model -> write a digest |
| `prompt.txt` | Example first-line-triage prompt (adapt to your alert format) |
| `soc-l1-triage.service` | systemd oneshot that runs the script |
| `soc-l1-triage.timer` | Runs it overnight (off-peak GPU time) |

## Prerequisites

- A GPU with **working drivers** (proprietary NVIDIA drivers are the reliable
  path on Linux; an open-driver crash loop is what motivated this whole setup).
- **[Ollama](https://ollama.com)** installed and serving locally.
- A small model pulled, e.g. a ~4B Gemma:
  ```sh
  ollama pull gemma:4b      # or whichever small instruct model you prefer
  ```
- A way to query your SIEM's alerts (Wazuh API, an indexer query, or a log
  export) — the script has a placeholder for this.

## Wiring

1. Adapt `l1-triage.sh`: fill in the SIEM query (how you fetch the day's
   alerts) and the digest destination (a file, an email, a chat webhook).
2. Adapt `prompt.txt` to your alert shape and your "what counts as noise"
   rules.
3. Install the script and units:
   ```sh
   sudo install -m 0755 l1-triage.sh /usr/local/bin/soc-l1-triage
   sudo install -m 0644 soc-l1-triage.service soc-l1-triage.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now soc-l1-triage.timer
   ```

## Design notes

- **Keep it local.** The point is that security telemetry never leaves the
  network. No cloud LLM, no per-token bill, no third party reading your alerts.
- **Small is fine.** First-pass triage does not need a frontier model. A ~4B
  model on a cheap GPU handles "obviously benign vs worth a look."
- **Off-peak.** Schedule it when the GPU is idle (early morning); the digest is
  waiting by the time you look.
- **Filter, don't decide.** Treat the output as a sorted inbox, not a verdict.
