# SC23

Docker Compose applications behind Nginx: local HTTPS with mkcert and public HTTPS with Let's Encrypt.

## Configuration

- Main site: `html/index.html` and `html/assets/`, served directly by Nginx.
- Projects: `pull_projects.sh` and `projects/`.
- Services: `docker-compose.yml`.
- Domains and routes: `nginx.conf`.
- Application secrets: `.env` (not committed).

## Local development

Requires Homebrew, Git, mkcert, Docker and `docker-compose` for the existing setup script.

```bash
bash dev_init.sh
docker compose up -d --build
```

Open `https://sc23.local` or the configured `.local` subdomains.
On Windows, configure hosts in `C:\Windows\System32\drivers\etc\hosts` and generate certificates with mkcert manually.
Use `update_certs.sh` only for local development; it replaces `sc23.crt` and `sc23.key`.

## VPS deployment

Requires Debian 11-compatible Linux, Docker Compose v2, systemd, Git, curl, OpenSSL and flock.
All public domains must point to the VPS (including any AAAA records); open ports 80 and 443.
Root must have Git access to the application repositories.

After committing and pushing the changes, run on the VPS:

```bash
cd /root/sc23
git pull --ff-only
sudo bash vps_deploy.sh your-email@example.com
```

This updates, builds and deploys the applications, then sets up HTTPS.
Nginx is briefly recreated; application containers remain running during TLS setup.

To configure only HTTPS after the applications are deployed:

```bash
sudo bash vps_ssl.sh setup your-email@example.com
```

- Replace the email with your real contact address. Setup accepts the [Let's Encrypt agreement](https://letsencrypt.org/repository/).
- Covers concrete `.site` names from `nginx.conf`; `.local` names and wildcard names are excluded.
- For a new subdomain, configure DNS, the application and Nginx, then rerun setup.
- Checks renewal twice daily through `sc23-ssl-renew.timer`; renews when due and reloads Nginx. Applications are not updated by the timer.
- Certificates, ACME state, logs and backups stay in `certs/`, ignored by Git. Keep the repository at the same path.
- Existing host Certbot jobs are left unchanged. The Certbot image version is pinned in `vps_ssl.sh`.

## Rope Ruins

`pull_projects.sh` clones/updates `danisc23/hook-rush` into `projects/hook-rush`.
Its `docker/source.Dockerfile` builds the `rope-ruins` dedicated server and
`rope-ruins-web` browser client from the same checkout. No Windows build or
manual extraction of `dist/` is required; the first build downloads the pinned
Godot toolchain. Docker layers cache it for later builds.

SC23 owns the two Compose services, private networking and public routing:

- `https://roperuins.sc23.site` serves the browser client (local name: `roperuins.sc23.local`).
- `wss://sc23.site/rope/` forwards to the server's private TCP port 24567.
- `WEB_ENDPOINT` in `docker-compose.yml` configures the browser's `server.js`.
- `nginx.conf` owns the exact Origin allowlist and connection/handshake limits.

The local SC23 HTTPS setup uses the same public WSS endpoint. To play against
the local SC23 server, override the web build argument with
`WEB_ENDPOINT=wss://sc23.local/rope/` and rebuild the web service. The game's
standalone HTTP preview remains in its own repository.

Publish the game repository, including `docker/source.Dockerfile`, before
deploying this integration. Point the new public subdomain to the VPS before
running `vps_deploy.sh`: the existing TLS automation discovers it in
`nginx.conf` and includes it in issuance/renewal. Do not expose port 24567 or
copy game-provided nginx overlays into this repository.

For an application-only update when the certificate already covers the domain:

```bash
bash pull_projects.sh
docker compose build rope-ruins rope-ruins-web
docker compose up -d --no-deps rope-ruins rope-ruins-web
docker compose exec -T nginx nginx -t
docker compose exec -T nginx nginx -s reload
```

Rebuild both images together for protocol changes; connected games may need
to reconnect after a server restart. To roll back, restore the previous game
revision and rebuild both images. To remove the integration, restore SC23's
previous Compose/nginx configuration and recreate Nginx; leave certificates
intact and stop only the two game services.

## Verify and recover

```bash
sudo bash vps_ssl.sh check
sudo bash vps_ssl.sh dry-run
systemctl list-timers sc23-ssl-renew.timer
journalctl -u sc23-ssl-renew.service -n 50 --no-pager
```

Setup verifies HTTP challenges, trusted HTTPS, the served certificate and a staging renewal before enabling the timer.
For a production trial, back up the running Nginx image, configuration and certificates outside the checkout, then use `vps_ssl.sh setup` to leave applications unchanged.
Check the application pages in a browser too; a successful TLS check does not validate application behavior.

Restore the original certificate and disable automatic renewal:

```bash
sudo bash vps_ssl.sh rollback
```

The original certificate may already be expired. This command restores certificates only; use the deployment backup to recover Nginx configuration or its image.
After HTTPS and renewal checks pass, cancel only the paid SSL add-on according to its contract; keep the VPS and domain active.

## Tests

```bash
docker build -f tests/vps-ssl.Dockerfile -t sc23-ssl-test .
docker run --rm -v "$PWD:/workspace:ro" sc23-ssl-test
```

Debian 11, ShellCheck and real Nginx HTTP/TLS tests. ACME issuance and systemd are simulated; no VPS changes.
The suite also checks project cloning, fast-forward updates and Git failures.

After building the game images, verify the real web and WebSocket routes in
disposable containers (requires Python 3 and OpenSSL):

```bash
docker compose build rope-ruins rope-ruins-web
python3 tests/test_rope_ruins.py
```

This uses the repository's actual nginx configuration with temporary certificates,
an isolated Docker network and a random loopback port. It checks the main site,
game HTML/WASM, configured endpoint, successful WSS upgrades and rejected origins.

## Stop

```bash
docker compose down
```
