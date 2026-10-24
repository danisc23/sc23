#!/usr/bin/env bash
# Certificate management for the existing Docker Compose Nginx on Debian 11.
set -Eeuo pipefail
umask 077

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$REPO_DIR"
STATE="$REPO_DIR/certs"
CERT_NAME=sc23-vps
CERTBOT_IMAGE=certbot/certbot:v5.8.0
LINEAGE="$STATE/letsencrypt/live/$CERT_NAME"
ACTION=${1:-help}

die() { echo "Error: $*" >&2; exit 1; }

compose() { docker compose --project-directory "$REPO_DIR" -f "$REPO_DIR/docker-compose.yml" "$@"; }

domains() {
    # Take concrete public names from server_name; never request .local or '*'.
    awk '/^[[:space:]]*server_name[[:space:]]/ {
        sub(/#.*/, ""); gsub(/;/, " ");
        for (i=2; i<=NF; i++) if ($i ~ /\.site$/ && $i !~ /\*/) print $i
    }' nginx.conf | LC_ALL=C sort -u
}

certbot() {
    docker run --rm \
        -v "$STATE/letsencrypt:/etc/letsencrypt" \
        -v "$STATE/work:/var/lib/letsencrypt" \
        -v "$STATE/logs:/var/log/letsencrypt" \
        -v "$STATE/acme-webroot:/var/www/certbot" \
        "$CERTBOT_IMAGE" "$@"
}

nginx_running() {
    local container
    container=$(compose ps -q nginx)
    [[ -n "$container" ]] && [[ $(docker inspect -f '{{.State.Running}}' "$container") == true ]]
}

reload_nginx() {
    compose exec -T nginx nginx -t && compose exec -T nginx nginx -s reload && wait_for_certificate
}

served_fingerprint() {
    local domain=$1 address=$2
    timeout 15 openssl s_client -connect "$address:443" -servername "$domain" </dev/null 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha256
}

wait_for_certificate() {
    local expected actual attempt
    expected=$(openssl x509 -in sc23.crt -noout -fingerprint -sha256)
    for ((attempt=0; attempt<10; attempt++)); do
        actual=$(served_fingerprint "${DOMAINS[0]}" 127.0.0.1) || actual=''
        [[ "$actual" == "$expected" ]] && return 0
        sleep 1
    done
    echo 'Nginx is not serving the installed certificate.' >&2
    return 1
}

check_http() {
    local token domain actual
    token="sc23-$(openssl rand -hex 16)"
    mkdir -p "$STATE/acme-webroot/.well-known/acme-challenge"
    chmod 755 "$STATE/acme-webroot/.well-known" "$STATE/acme-webroot/.well-known/acme-challenge"
    printf '%s' "$token" > "$STATE/acme-webroot/.well-known/acme-challenge/$token"
    chmod 644 "$STATE/acme-webroot/.well-known/acme-challenge/$token"
    for domain in "${DOMAINS[@]}"; do
        actual=$(curl --noproxy '*' --fail --silent --show-error --connect-timeout 10 --max-time 20 \
            "http://$domain/.well-known/acme-challenge/$token") || {
            rm -f -- "$STATE/acme-webroot/.well-known/acme-challenge/$token"
            die "HTTP validation failed for $domain. Check DNS (including AAAA), firewall and port 80."
        }
        if [[ "$actual" != "$token" ]]; then
            rm -f -- "$STATE/acme-webroot/.well-known/acme-challenge/$token"
            die "$domain does not serve this VPS's ACME challenge."
        fi
    done
    rm -f -- "$STATE/acme-webroot/.well-known/acme-challenge/$token"
}

validate_pair() {
    local certificate=$1 key=$2 domain cert_pub key_pub
    openssl x509 -in "$certificate" -noout -checkend 86400 >/dev/null || die 'Certificate is invalid or expires within a day.'
    for domain in "${DOMAINS[@]}"; do
        openssl x509 -in "$certificate" -noout -checkhost "$domain" | grep -q 'does match certificate' \
            || die "Certificate does not cover $domain. Run setup again after adding domains."
    done
    cert_pub=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum)
    key_pub=$(openssl pkey -in "$key" -pubout -outform DER | sha256sum)
    [[ "$cert_pub" == "$key_pub" ]] || die 'Certificate and private key do not match.'
}

publish_certificate() {
    validate_pair "$LINEAGE/fullchain.pem" "$LINEAGE/privkey.pem"
    if cmp -s "$LINEAGE/fullchain.pem" sc23.crt && cmp -s "$LINEAGE/privkey.pem" sc23.key; then
        # Reload even on a retry: issuance may have succeeded before a failed reload.
        reload_nginx
        return
    fi
    mkdir -p "$STATE/last-deployment"
    cp -p sc23.crt "$STATE/last-deployment/sc23.crt"
    cp -p sc23.key "$STATE/last-deployment/sc23.key"
    # Keep the inodes: existing Docker single-file mounts must see the new data.
    cat "$LINEAGE/privkey.pem" > sc23.key
    cat "$LINEAGE/fullchain.pem" > sc23.crt
    chmod 600 sc23.key
    if ! reload_nginx; then
        cat "$STATE/last-deployment/sc23.key" > sc23.key
        cat "$STATE/last-deployment/sc23.crt" > sc23.crt
        reload_nginx || true
        die 'Nginx rejected the new certificate; the previous files have been restored.'
    fi
}

check_https() {
    local domain expected actual
    expected=$(openssl x509 -in sc23.crt -noout -fingerprint -sha256)
    openssl x509 -in sc23.crt -noout -issuer -dates
    for domain in "${DOMAINS[@]}"; do
        # Verify normal public DNS, trust, hostname and expiry. An API root may return 404.
        curl --noproxy '*' --silent --show-error --connect-timeout 10 --max-time 30 \
            --output /dev/null --write-out "$domain: TLS OK, HTTP %{http_code}\n" "https://$domain/"
        actual=$(served_fingerprint "$domain" "$domain")
        [[ "$actual" == "$expected" ]] || die "$domain serves a different certificate from this installation."
    done
}

install_timer() {
    local escaped_path
    # Escape systemd quoted strings and specifiers, including repositories with spaces.
    escaped_path=${REPO_DIR//\\/\\\\}
    escaped_path=${escaped_path//\"/\\\"}
    escaped_path=${escaped_path//%/%%}
    cat > /etc/systemd/system/sc23-ssl-renew.service <<EOF
[Unit]
Description=Renew and deploy SC23 TLS certificate
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory="$escaped_path"
ExecStart=/bin/bash "$escaped_path/vps_ssl.sh" renew
TimeoutStartSec=20min
UMask=0077
EOF
    cat > /etc/systemd/system/sc23-ssl-renew.timer <<'EOF'
[Unit]
Description=Check SC23 TLS renewal twice a day

[Timer]
OnCalendar=*-*-* 03,15:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now sc23-ssl-renew.timer
}

if [[ "$ACTION" == help || "$ACTION" == --help ]]; then
    echo 'Usage: sudo bash vps_ssl.sh setup EMAIL | renew | check | dry-run | rollback'
    exit 0
fi
case "$ACTION" in setup|renew|check|dry-run|rollback) ;; *) die "Unknown action: $ACTION" ;; esac
[[ $EUID -eq 0 ]] || die 'Run this script as root (sudo bash vps_ssl.sh ...).'
for program in docker openssl curl flock systemctl timeout; do
    command -v "$program" >/dev/null || die "Missing prerequisite: $program"
done
docker compose version >/dev/null || die 'Docker Compose v2 is required.'
[[ "$REPO_DIR" != *$'\n'* && "$REPO_DIR" != *$'\r'* ]] || die 'Unsupported repository path.'
mkdir -p "$STATE"
exec 9> "$STATE/vps-ssl.lock"
flock -n 9 || die 'Another SC23 certificate operation is running.'
mapfile -t DOMAINS < <(domains)
[[ ${#DOMAINS[@]} -gt 0 ]] || die 'No public .site domains found in nginx.conf.'

case "$ACTION" in
    setup)
        EMAIL=${2:-}
        [[ "$EMAIL" == *@*.* && "$EMAIL" != -* ]] || die 'Supply a contact email: setup you@example.com'
        mkdir -p "$STATE/letsencrypt" "$STATE/work" "$STATE/logs" "$STATE/acme-webroot" "$STATE/original"
        chmod 755 "$STATE/acme-webroot"
        if [[ -f sc23.crt && -f sc23.key && ! -f "$STATE/original/sc23.crt" ]]; then
            cp -p sc23.crt "$STATE/original/sc23.crt"
            cp -p sc23.key "$STATE/original/sc23.key"
        fi
        if [[ ! -f sc23.crt && ! -f sc23.key ]]; then
            # Temporary bootstrap only. Never treated as a successful public certificate.
            openssl req -x509 -nodes -newkey rsa:2048 -days 1 -subj '/CN=localhost' \
                -keyout sc23.key -out sc23.crt 2>/dev/null
        fi
        [[ -f sc23.crt && -f sc23.key ]] || die 'Both sc23.crt and sc23.key must exist (or neither for a new installation).'
        # Check configuration and upstream resolution before recreating only Nginx.
        compose run --rm --no-deps nginx nginx -t
        compose up -d --no-deps --force-recreate nginx
        nginx_running || die 'Nginx did not start.'
        check_http
        docker pull "$CERTBOT_IMAGE"
        DOMAIN_ARGS=()
        for domain in "${DOMAINS[@]}"; do DOMAIN_ARGS+=(-d "$domain"); done
        ISSUE_ARGS=(certonly --non-interactive --agree-tos --email "$EMAIL"
            --webroot --webroot-path /var/www/certbot --cert-name "$CERT_NAME"
            --keep-until-expiring --renew-with-new-domains "${DOMAIN_ARGS[@]}")
        # Prove issuance against staging before requesting a production certificate.
        certbot "${ISSUE_ARGS[@]}" --dry-run
        certbot "${ISSUE_ARGS[@]}"
        publish_certificate
        # Exercise future ACME validation against staging without deploying a test cert.
        certbot renew --cert-name "$CERT_NAME" --dry-run --non-interactive --no-random-sleep-on-renew
        check_https
        install_timer
        echo 'Ready: trusted HTTPS verified; automatic renewal is enabled.'
        ;;
    renew|dry-run)
        nginx_running || die 'Nginx must be running before renewal.'
        [[ -f "$LINEAGE/fullchain.pem" ]] || die 'Run setup first.'
        RENEW_ARGS=(renew --cert-name "$CERT_NAME" --non-interactive --no-random-sleep-on-renew)
        if [[ "$ACTION" == dry-run ]]; then RENEW_ARGS+=(--dry-run); fi
        certbot "${RENEW_ARGS[@]}"
        if [[ "$ACTION" == renew ]]; then publish_certificate; check_https; fi
        ;;
    check)
        nginx_running || die 'Nginx is not running.'
        check_http
        check_https
        systemctl is-enabled sc23-ssl-renew.timer
        systemctl is-active sc23-ssl-renew.timer
        systemctl list-timers sc23-ssl-renew.timer --no-pager
        ;;
    rollback)
        [[ -f "$STATE/original/sc23.crt" && -f "$STATE/original/sc23.key" ]] || die 'No original certificate backup exists.'
        nginx_running || die 'Nginx must be running for rollback.'
        systemctl disable --now sc23-ssl-renew.timer 2>/dev/null || true
        mkdir -p "$STATE/last-deployment"
        cp -p sc23.crt "$STATE/last-deployment/sc23.crt"
        cp -p sc23.key "$STATE/last-deployment/sc23.key"
        cat "$STATE/original/sc23.key" > sc23.key
        cat "$STATE/original/sc23.crt" > sc23.crt
        if ! reload_nginx; then
            cat "$STATE/last-deployment/sc23.key" > sc23.key
            cat "$STATE/last-deployment/sc23.crt" > sc23.crt
            reload_nginx || true
            die 'Rollback failed; the latest certificate files have been restored. Check the renewal timer.'
        fi
        echo 'Original certificate restored; automatic renewal disabled. It may already be expired.'
        ;;
esac
