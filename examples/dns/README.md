# examples/dns - recursive resolver + DoH

Two-layer self-hosted DNS (see [../../docs/network.md](../../docs/network.md#dns)).

| File | Purpose |
|---|---|
| `unbound.conf` | Recursive resolver: loopback-alias bind, LAN/VPN/container access-control, blocklist include, split-horizon hint |
| `dnsproxy.md` | DoH frontend wiring (dnsproxy -> Unbound) |

## Why loopback aliases

Binding the resolver to a **loopback alias** (`127.0.0.11`) instead of a NIC
address means DNS is available before the network comes up and does not break
when links change. Point the host's `resolv.conf` at the loopback alias, not a
NIC IP - this avoids the classic "no DNS on boot because the NIC is not up yet"
trap.
