# DoH frontend (dnsproxy)

A DNS-over-HTTPS frontend for clients that want encrypted resolution, with
Unbound as the upstream. Bind it to its own loopback alias.

Example invocation (systemd `ExecStart` or a container command):

```
dnsproxy \
  --listen=127.0.0.12 \           # dedicated loopback alias for DoH
  --https-port=443 \
  --tls-crt=/etc/dnsproxy/cert.pem \
  --tls-key=/etc/dnsproxy/key.pem \
  --upstream=127.0.0.11:53        # -> Unbound (see unbound.conf)
```

Clients resolve over HTTPS to the DoH endpoint; dnsproxy forwards to Unbound,
which does the recursion + blocklisting. Same answers as plain DNS, encrypted
on the wire.
