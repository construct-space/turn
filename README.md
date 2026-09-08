# turn - coturn (STUN + TURN) for Construct Meet

Provides the WebRTC relay Meet needs when two peers can't connect directly
(different networks, symmetric NAT, locked-down firewalls). STUN is included
in the same daemon. Runs on the same box as the `tracker` app (46.224.45.43)
but on HOST networking, because TURN needs raw UDP/TCP and a range of UDP
relay ports that nginx can't proxy and Swarm ingress can't publish.

**Proper, long-term auth only:** ephemeral HMAC credentials. The shared
secret lives in CapRover env vars (never in this repo or the image). Clients
fetch short-lived credentials from the `turn-auth` service; coturn validates
them with the same secret. No static password ships in the Meet bundle.

## Deploy (CapRover)

1. Create a CapRover app `turn` (no domain needed - it isn't an HTTP app).

2. Set env vars on the app:
   ```
   TURN_SHARED_SECRET=<the HMAC secret - SAME value set on turn-auth>
   TURN_REALM=turn.lisaos.dev
   TURN_EXTERNAL_IP=46.224.45.43
   ```

3. Deploy this folder:
   ```
   caprover deploy --appName turn
   ```

4. Put the container on HOST networking. App -> Config -> **Service Update
   Override**:
   ```yaml
   TaskTemplate:
     Networks:
       - Target: host
   ```
   Save & Update. Host networking makes the relay port range work without
   publishing thousands of Swarm ports.

5. Open the firewall on the box:
   | Port          | Proto     | Purpose                |
   |---------------|-----------|------------------------|
   | 3478          | UDP + TCP | STUN + TURN            |
   | 49160-49200   | UDP       | relay range            |
   | 5349          | TCP       | TURN over TLS          |

6. TLS (`turns:5349`): get a Let's Encrypt cert for `turn.lisaos.dev`
   via the **DNS-01** challenge (HTTP-01 needs :80, which CapRover holds),
   mount it read-only at `/etc/coturn/certs/{fullchain,privkey}.pem` (App ->
   Config -> add a persistent volume / bind mount). entrypoint.sh auto-enables
   `turns:5349` when both files are present. Add a dedicated A record
   `turn.lisaos.dev -> 46.224.45.43` so the cert/realm are unambiguous.

## Credentials (turn-auth service)

coturn here only *validates* credentials. They're *minted* by the `turn-auth`
service (separate repo), which the gateway exposes (auth-gated) at
`/api/turn/credentials`:

```
username   = <unix-expiry>[:<opaque>]
credential = base64( HMAC-SHA1( TURN_SHARED_SECRET, username ) )
ttl        = e.g. 86400
```

Both services must share the identical `TURN_SHARED_SECRET`. Meet fetches
credentials before each join and feeds them into its ICE config.

## Verify

```
# from another machine
nc -uz turn.lisaos.dev 3478
# Trickle ICE (https://webrtc.github.io/samples/.../trickle-ice/) with creds
# from /api/turn/credentials -> a "relay" candidate must appear.
echo | openssl s_client -alpn h2,http/1.1 -connect turn.lisaos.dev:5349 2>/dev/null | grep ALPN
```
