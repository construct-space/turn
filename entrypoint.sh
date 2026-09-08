#!/bin/sh
# Resolve the turnserver.conf template from env (so no secret is baked into
# the image), optionally enable TLS if a cert is mounted, then exec coturn.
set -eu

: "${TURN_REALM:=turn.lisaos.dev}"
: "${TURN_EXTERNAL_IP:?set TURN_EXTERNAL_IP to the box public IP}"
: "${TURN_SHARED_SECRET:?set TURN_SHARED_SECRET (same value as the turn-auth service)}"

OUT=/tmp/turnserver.conf

# sed, not envsubst, to avoid a base-image package dependency. Values are hex
# secret / IP / hostname, so '|' is a safe delimiter.
sed \
  -e "s|__SECRET__|${TURN_SHARED_SECRET}|g" \
  -e "s|__REALM__|${TURN_REALM}|g" \
  -e "s|__EXTERNAL_IP__|${TURN_EXTERNAL_IP}|g" \
  /etc/coturn/turnserver.conf > "$OUT"

# Auto-enable turns:5349 when a cert is present (mount it read-only).
if [ -f /etc/coturn/certs/fullchain.pem ] && [ -f /etc/coturn/certs/privkey.pem ]; then
  {
    echo "tls-listening-port=5349"
    echo "cert=/etc/coturn/certs/fullchain.pem"
    echo "pkey=/etc/coturn/certs/privkey.pem"
  } >> "$OUT"
  echo '{"service":"turn","msg":"TLS enabled (turns:5349)"}'
else
  echo '{"service":"turn","msg":"no cert mounted - plain turn:3478 only (mount /etc/coturn/certs to enable turns:5349)"}'
fi

echo '{"service":"turn","msg":"starting","realm":"'"${TURN_REALM}"'","external_ip":"'"${TURN_EXTERNAL_IP}"'"}'
# NOTE: no -n. coturn's -n means "ignore the config file and use CLI args
# only" - which silently dropped our auth config and ran an open relay.
exec turnserver -c "$OUT" --log-file=stdout
