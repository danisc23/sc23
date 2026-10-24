FROM debian:11-slim
# The EOL bullseye-security mirror advertises deleted packages. Use the base
# Debian 11 archive for this disposable compatibility fixture, never on the VPS.
RUN sed -i '/debian-security/d' /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl nginx-light openssl shellcheck util-linux \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
CMD ["bash", "tests/test_vps_ssl.sh"]
