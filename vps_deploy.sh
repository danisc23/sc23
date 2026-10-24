#!/usr/bin/env bash
# Explicit application deployment, followed by TLS setup. Never used by the timer.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ $EUID -eq 0 ]] || { echo 'Run as root: sudo bash vps_deploy.sh you@example.com' >&2; exit 1; }
[[ ${1:-} == *@*.* && ${1:-} != -* ]] || { echo 'Supply the certificate contact email.' >&2; exit 1; }
docker compose version >/dev/null

# Fail on a Git error, even though the original helper predates set -e.
bash -e pull_projects.sh
# Nginx needs certificate files even on an empty VPS; SSL setup bootstraps those.
# Build and start the application services first, leaving the existing proxy running.
services=$(docker compose config --services)
mapfile -t applications < <(printf '%s\n' "$services" | sed '/^nginx$/d')
[[ ${#applications[@]} -gt 0 ]] || { echo 'No application services found.' >&2; exit 1; }
docker compose up -d --build "${applications[@]}"
docker compose build nginx
bash vps_ssl.sh setup "$1"
