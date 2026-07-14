# Security and privacy

Relay stores only Host registrations: Host ID, hashed-independent random
secrets/tokens and last activity. Requests and responses are held in memory
until delivered or timed out. Audio is written to a random temporary Host file
and removed in `finally`. Sent and generated images may be cached on Host and
iPhone under configured LRU/age limits.

Treat the iPhone token, Host secret and Relay admin key as passwords. Rotate
them after accidental disclosure. Plain HTTP does not encrypt traffic; use a
trusted VPN or an external TLS reverse proxy. Never expose the local Host port:
it binds to `127.0.0.1` and Relay is the only remote path.
