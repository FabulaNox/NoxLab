# examples/docker - tiered compose + boot ordering

The platform splits Docker into **tiers** so startup is ordered and tiers are
isolated (see [../../docs/platform.md](../../docs/platform.md)).

| Path | Purpose |
|---|---|
| `tier0/docker-compose.yml` | Ingress: the reverse proxy, comes up first |
| `tier1/docker-compose.yml` | An app on its own isolated bridge, fronted by tier 0 |
| `systemd/docker-tier0.service` | Brings tier 0 up on boot |
| `systemd/docker-tier1.service` | Brings tier 1 up *after* tier 0 (`After=`/`Requires=`) |

## Use

```sh
sudo mkdir -p /opt/docker/tier0 /opt/docker/tier1
sudo cp tier0/* /opt/docker/tier0/ ; sudo cp tier1/* /opt/docker/tier1/
sudo cp systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-tier0.service docker-tier1.service
```

The proxy config (`traefik.yml`, `dynamic.yml`) goes in `tier0/` - templates in
[../proxy/](../proxy/). Each tier is a separate bridge: the app tier cannot
reach other tiers directly, only via the proxy.
