FROM debian:11-slim
# The EOL bullseye-security mirror advertises deleted packages. Use the base
# Debian 11 archive for this disposable compatibility fixture, never on the VPS.
RUN sed -i '/debian-security/d' /etc/apt/sources.list \
    && apt-get update \
    && test_systemd_version="$(apt-cache policy systemd | awk '/Candidate:/ {print $2}')" \
    && apt-get install -y --allow-downgrades --no-install-recommends \
    bash ca-certificates curl nginx-light openssl shellcheck systemd util-linux \
    "libsystemd0=$test_systemd_version" \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
CMD ["bash", "tests/test_vps_ssl.sh"]
