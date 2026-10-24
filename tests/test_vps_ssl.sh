#!/usr/bin/env bash
# Run in the disposable Debian 11 test container, never on a production host.
# Real Nginx, HTTP challenges, TLS trust and reloads; fake ACME issuance/systemd.
set -Eeuo pipefail
[[ -f /.dockerenv ]] || { echo 'Run this test in its Docker container.' >&2; exit 1; }
cd /workspace
bash -n vps_ssl.sh vps_deploy.sh
shellcheck vps_ssl.sh vps_deploy.sh tests/test_vps_ssl.sh
export TEST_ROOT
TEST_ROOT=$(mktemp -d)
trap 'nginx -s quit -c "$TEST_ROOT/nginx.conf" 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/repo/certs" "$TEST_ROOT/bin" "$TEST_ROOT/fixtures" /etc/systemd/system
# Nginx accesses host fixture paths directly; production mounts the webroot leaf.
chmod 755 "$TEST_ROOT"
cp vps_ssl.sh nginx.conf docker-compose.yml "$TEST_ROOT/repo/"
cp -R html "$TEST_ROOT/repo/html"
export CURL_CA_BUNDLE="$TEST_ROOT/fixtures/ca.crt"
openssl req -x509 -nodes -newkey rsa:2048 -days 2 -subj '/CN=SC23 Test CA' \
    -keyout "$TEST_ROOT/fixtures/ca.key" -out "$CURL_CA_BUNDLE" 2>/dev/null

domain_names=(sc23.site renting.sc23.site padel-api.sc23.site padel-radar.sc23.site wise-frog.sc23.site status.sc23.site xml-comparator.sc23.site)
for name in "${domain_names[@]}" renting padel-api padel-radar wise-frog status xml-diff; do
    printf '127.0.0.1 %s\n' "$name" >> /etc/hosts
done
make_cert() {
    local name=$1 san=$2
    openssl req -new -nodes -newkey rsa:2048 -subj '/CN=sc23.site' \
        -keyout "$TEST_ROOT/fixtures/$name.key" -out "$TEST_ROOT/fixtures/$name.csr" 2>/dev/null
    openssl x509 -req -in "$TEST_ROOT/fixtures/$name.csr" -days 2 \
        -CA "$CURL_CA_BUNDLE" -CAkey "$TEST_ROOT/fixtures/ca.key" -CAcreateserial \
        -extfile <(printf 'subjectAltName=%s\n' "$san") -out "$TEST_ROOT/fixtures/$name.crt" 2>/dev/null
}
san=$(printf 'DNS:%s,' "${domain_names[@]}")
for fixture in original issued renewed rejected; do make_cert "$fixture" "${san%,}"; done
make_cert missing-domain DNS:sc23.site
cp "$TEST_ROOT/fixtures/original.crt" "$TEST_ROOT/repo/sc23.crt"
cp "$TEST_ROOT/fixtures/original.key" "$TEST_ROOT/repo/sc23.key"
# Use the actual repository routing, with fixture paths and real Nginx on 80/443.
sed -e "s|/etc/nginx/ssl|$TEST_ROOT/repo|g" \
    -e "s|/usr/share/nginx/html|$TEST_ROOT/repo/html|g" \
    -e "s|/var/www/certbot|$TEST_ROOT/repo/certs/acme-webroot|g" nginx.conf > "$TEST_ROOT/sites.conf"
cat > "$TEST_ROOT/nginx.conf" <<EOF
pid $TEST_ROOT/nginx.pid;
error_log $TEST_ROOT/nginx-error.log;
events {}
http { access_log off; include $TEST_ROOT/sites.conf; }
EOF

cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_ROOT/systemctl.log"
exit 0
EOF
cat > "$TEST_ROOT/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$1" in
    pull) exit 0 ;;
    inspect) echo true; exit 0 ;;
    compose)
        shift
        if [[ $1 == version ]]; then echo 'Docker Compose test adapter'; exit 0; fi
        shift 4 # --project-directory PATH -f PATH
        operation=$1; shift
        case "$operation" in
            ps) [[ -s "$TEST_ROOT/nginx.pid" ]] && echo fixture-nginx; exit 0 ;;
            run) nginx -t -c "$TEST_ROOT/nginx.conf"; exit ;;
            up)
                if [[ -s "$TEST_ROOT/nginx.pid" ]]; then
                    nginx -s reload -c "$TEST_ROOT/nginx.conf"
                else
                    nginx -c "$TEST_ROOT/nginx.conf" 9>&-
                fi
                exit ;;
            exec)
                shift 3 # -T nginx nginx
                if [[ ${MOCK_REJECT:-0} == 1 && $1 == -t ]] && \
                    cmp -s "$TEST_ROOT/repo/sc23.crt" "$TEST_ROOT/fixtures/rejected.crt"; then
                    echo 'Injected nginx validation failure' >&2; exit 1
                fi
                nginx -c "$TEST_ROOT/nginx.conf" "$@"
                exit ;;
        esac
        ;;
    run)
        # The test adapter replaces only Certbot. It never contacts an ACME CA.
        if [[ " $* " == *' --dry-run '* ]]; then
            echo dry-run >> "$TEST_ROOT/certbot.log"; exit 0
        fi
        if [[ ${MOCK_NO_RENEW:-0} != 1 ]]; then
            lineage="$TEST_ROOT/repo/certs/letsencrypt/live/sc23-vps"
            mkdir -p "$lineage"
            cp "$TEST_ROOT/fixtures/${MOCK_CERT:-issued}.crt" "$lineage/fullchain.pem"
            cp "$TEST_ROOT/fixtures/${MOCK_CERT:-issued}.key" "$lineage/privkey.pem"
        fi
        exit 0 ;;
esac
echo "Unexpected docker arguments: $*" >&2
exit 1
EOF
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$PATH"
run_ssl() { bash "$TEST_ROOT/repo/vps_ssl.sh" "$@"; }
assert_cert() { cmp "$TEST_ROOT/repo/sc23.crt" "$TEST_ROOT/fixtures/$1.crt"; }
expect_failure() {
    if "$@" > "$TEST_ROOT/expected-failure.log" 2>&1; then
        echo "Expected failure: $*" >&2; exit 1
    fi
}

echo 'TEST setup: real HTTP validation, trusted TLS and timer installation'
original_inode=$(stat -c %i "$TEST_ROOT/repo/sc23.crt")
run_ssl setup test@example.com
assert_cert issued
[[ $(stat -c %i "$TEST_ROOT/repo/sc23.crt") == "$original_inode" ]]
cmp "$TEST_ROOT/repo/certs/original/sc23.crt" "$TEST_ROOT/fixtures/original.crt"
grep -q 'enable --now sc23-ssl-renew.timer' "$TEST_ROOT/systemctl.log"
grep -q '^OnCalendar=\*-\*-\* 03,15:00:00$' /etc/systemd/system/sc23-ssl-renew.timer
grep -q '^dry-run$' "$TEST_ROOT/certbot.log"
run_ssl check
echo 'TEST main site: serves the existing repository index.html unchanged'
curl --noproxy '*' --fail --silent --show-error https://sc23.site/ > "$TEST_ROOT/served-index.html"
cmp /workspace/html/index.html "$TEST_ROOT/served-index.html"

echo 'TEST dry-run: no staging certificate is deployed'
MOCK_CERT=renewed run_ssl dry-run
assert_cert issued

echo 'TEST renew: new certificate is served without changing file inodes'
MOCK_CERT=renewed run_ssl renew
assert_cert renewed
[[ $(stat -c %i "$TEST_ROOT/repo/sc23.crt") == "$original_inode" ]]

echo 'TEST validation: missing SAN and mismatched key preserve active certificate'
expect_failure env MOCK_CERT=missing-domain bash "$TEST_ROOT/repo/vps_ssl.sh" renew
assert_cert renewed
cp "$TEST_ROOT/fixtures/issued.key" "$TEST_ROOT/fixtures/rejected.key"
expect_failure env MOCK_CERT=rejected bash "$TEST_ROOT/repo/vps_ssl.sh" renew
assert_cert renewed
make_cert rejected "${san%,}"

echo 'TEST reload failure: restore previous certificate; retry deploys saved issuance'
expect_failure env MOCK_CERT=rejected MOCK_REJECT=1 bash "$TEST_ROOT/repo/vps_ssl.sh" renew
assert_cert renewed
MOCK_NO_RENEW=1 run_ssl renew
assert_cert rejected

echo 'TEST reinstallation: original rollback copy is preserved'
run_ssl setup test@example.com
cmp "$TEST_ROOT/repo/certs/original/sc23.crt" "$TEST_ROOT/fixtures/original.crt"
run_ssl rollback
assert_cert original
grep -q 'disable --now sc23-ssl-renew.timer' "$TEST_ROOT/systemctl.log"

echo 'TEST fresh installation: bootstrap without pre-existing certificate files'
mv "$TEST_ROOT/repo" "$TEST_ROOT/previous-repo"
mkdir -p "$TEST_ROOT/repo/certs"
cp /workspace/vps_ssl.sh /workspace/nginx.conf /workspace/docker-compose.yml "$TEST_ROOT/repo/"
cp -R /workspace/html "$TEST_ROOT/repo/html"
run_ssl setup test@example.com
assert_cert issued
[[ ! -f "$TEST_ROOT/repo/certs/original/sc23.crt" ]]
echo 'PASS: Debian 11 shell checks, HTTP/TLS setup, renewal, rejection, retry, rollback and bootstrap'
