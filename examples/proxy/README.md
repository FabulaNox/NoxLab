# examples/proxy - Traefik (single TLS ingress)

Templates for the one reverse proxy that fronts everything (see
[../../docs/network.md](../../docs/network.md#ingress)).

| File | Purpose |
|---|---|
| `traefik.yml` | Static config: entrypoints, HTTP->HTTPS redirect, ACME wildcard via DNS-01, file + docker providers |
| `dynamic.yml` | A `lan-vpn-only` ipAllowList middleware + a sample router restricting a sensitive service to LAN/VPN |

## Notes

- **Wildcard cert via DNS-01** means you never open port 80 for HTTP-01
  validation - one less inbound exposure.
- **The allowlist middleware** is how sensitive services stay LAN/VPN-only even
  though the proxy is internet-adjacent: attach `lan-vpn-only` to their routers.
- Put these in your tier-0 compose dir (see [../docker/](../docker/)); Traefik
  watches `dynamic.yml` and reloads on change.

> Bind-mount gotcha: editing a single-file bind mount (`traefik.yml`) in place
> can swap the inode and leave the container pinned to the old file. If edits
> seem ignored, recreate the container (`docker compose up -d --force-recreate`)
> rather than just restarting it.
