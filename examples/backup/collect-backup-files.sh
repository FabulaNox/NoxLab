#!/usr/bin/env bash
# collect-backup-files: gather the things a rebuild needs into one staging dir
# (which a weekly job then syncs to USB / Git). Template - adapt the SOURCES.
# Secrets should already be encrypted at rest (e.g. SOPS); this only copies.
set -euo pipefail

DEST="${BACKUP_DEST:-/mnt/backup/collected}"
mkdir -p "$DEST"

# The exact set a bare-metal rebuild needs - and nothing it does not.
# Adapt these paths to your host. Encrypted secrets are copied as-is.
SOURCES=(
  "/etc/systemd/system"                 # unit files
  "$HOME/services"                      # service configs + SOPS-encrypted secrets
  "$HOME/docker"                        # tiered compose
  "/etc/unbound"                        # DNS config
  # "/path/to/openvpn/pki"              # VPN PKI (already sensitive - keep encrypted)
  # "/path/to/traefik"                  # proxy config
)

for src in "${SOURCES[@]}"; do
  [ -e "$src" ] || { echo "skip (absent): $src" >&2; continue; }
  rsync -a --delete "$src" "$DEST/"
done

# What is deliberately NOT collected (recoverable elsewhere):
#   - local git clones (restore from remotes)
#   - VM disk images (too large; re-provision or restore from config)
#   - downloadable artifacts (ISOs, packages)

logger -t collect-backup-files "collected to $DEST"
echo "collected to $DEST"
