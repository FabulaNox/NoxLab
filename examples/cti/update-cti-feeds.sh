#!/usr/bin/env bash
# Pull abuse.ch IOC feeds and build Wazuh CDB lists (template).
# Generalized - implement the parse + the upload transport for your setup.
# Runs on a timer (see the .timer unit). Keep API keys in your secret store.
set -euo pipefail

# Optional: some abuse.ch endpoints accept an Auth-Key. Source from SOPS/env;
# never hardcode.
: "${THREATFOX_API_KEY:=}"

MIN_BYTES=1024
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

log() { logger -t cti-feed-update "$*"; echo "[$(date -Iseconds)] $*" >&2; }

# Guard: refuse to ship a suspiciously tiny feed (avoids overwriting a good
# CDB list with an empty one when an endpoint hiccups).
fetch_check() {
  local url=$1 dest=$2 size
  curl -sSf --max-time 30 --retry 2 -o "$dest" "$url"
  size=$(wc -c < "$dest")
  if [ "$size" -lt "$MIN_BYTES" ]; then
    log "ERROR: $url returned ${size}B (< ${MIN_BYTES}); skipping to avoid an empty CDB"
    return 1
  fi
}

# ThreatFox IOCs by type (ip:port | domain | md5_hash | sha256_hash).
threatfox() {
  local ioc_type=$1 dest=$2
  local hdr=()
  [ -n "$THREATFOX_API_KEY" ] && hdr=(-H "Auth-Key: ${THREATFOX_API_KEY}")
  curl -sSf --max-time 30 -X POST https://threatfox-api.abuse.ch/api/v1/ \
    -H "Content-Type: application/json" "${hdr[@]}" \
    -d "{\"query\":\"get_iocs\",\"ioc_type\":\"${ioc_type}\",\"days\":7}" > "$dest"
}

# 1. Fetch.
threatfox "ip:port"     "$WORK/ip.json"     || true
threatfox "domain"      "$WORK/domain.json"  || true
fetch_check "https://feodotracker.abuse.ch/downloads/ipblocklist.csv" "$WORK/feodo.csv" || true

# 2. Build CDB lists (Wazuh expects "key:value" lines). TODO: parse the JSON/CSV
#    above into one indicator per line, e.g. with jq, into $WORK/*.cdb.
#    A CDB list entry looks like:   1.2.3.4:malicious
log "feeds fetched into $WORK - implement parse to CDB here"

# 3. Upload + reload. TODO: ship the CDB lists to the Wazuh manager and reload.
#    If this runs ON the manager: cp into /var/ossec/etc/lists/ and
#    'wazuh-control reload'. If remote: scp + ssh. Keep the transport explicit.
log "build + upload to the Wazuh manager (implement transport), then reload"
