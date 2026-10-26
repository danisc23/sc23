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

## Stop

```bash
docker compose down
```
