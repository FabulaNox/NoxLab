#!/usr/bin/env bash
# soc-l1-triage: pull the day's SIEM alerts, have a local LLM triage them into
# a digest. Generalized template - fill in the SIEM query and the output sink.
# The model filters and summarises; it does NOT decide. Keep it local.
set -euo pipefail

MODEL="${SOC_LLM_MODEL:-gemma:4b}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
PROMPT_FILE="${SOC_LLM_PROMPT:-/usr/local/share/soc-llm/prompt.txt}"
DIGEST="${SOC_LLM_DIGEST:-/var/log/soc-l1-digest-$(date +%F).md}"

# 1. Fetch the day's alerts. REPLACE THIS with your SIEM query (Wazuh API, an
#    indexer query, a log export...). Emit a compact text/JSON of the last 24h.
fetch_alerts() {
  echo "(no alert source configured - implement fetch_alerts)"
}

# 2. Build the prompt = triage instructions + the alerts.
alerts=$(fetch_alerts)
prompt="$(cat "$PROMPT_FILE")

--- ALERTS (last 24h) ---
${alerts}"

# 3. Ask the local model. Nothing leaves the host.
payload=$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1], "prompt": sys.argv[2], "stream": False}))' "$MODEL" "$prompt")
response=$(curl -sf "${OLLAMA_URL}/api/generate" -d "$payload" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("response", ""))')

# 4. Write the digest. REPLACE/extend with your sink (email, chat webhook...).
{
  echo "# SOC L1 digest - $(date +%F)"
  echo
  echo "$response"
} > "$DIGEST"

logger -t soc-l1-triage "wrote digest: $DIGEST"
echo "digest written: $DIGEST"
