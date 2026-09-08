# coturn (STUN + TURN) for Construct Meet.
# Runs alongside CapRover on the same box, but with HOST networking (set via
# the CapRover Service Update Override - see README) because TURN needs raw
# UDP/TCP plus a range of UDP relay ports that can't be reverse-proxied by
# nginx or published through the Swarm ingress mesh.
FROM coturn/coturn:4.6

# Template (placeholders) + entrypoint that resolves it from env at start, so
# the shared secret is never baked into the image.
COPY turnserver.conf /etc/coturn/turnserver.conf
COPY entrypoint.sh   /usr/local/bin/turn-entrypoint.sh
USER root
RUN chmod +x /usr/local/bin/turn-entrypoint.sh

# Documentation only; with host networking the published list is ignored and
# coturn binds the host directly.
EXPOSE 3478/udp 3478/tcp 5349/tcp 49160-49200/udp

ENTRYPOINT ["/usr/local/bin/turn-entrypoint.sh"]
