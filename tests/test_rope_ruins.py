"""Check real SC23 HTTPS routes against game images in disposable containers."""
import argparse
import json
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed: {result.stdout}\n{result.stderr}')
    return result.stdout.strip()


def main(args):
    config = json.loads(run('docker', 'compose', 'config', '--format', 'json'))
    for service, target in [('rope-ruins', 'server'), ('rope-ruins-web', 'web')]:
        definition = config['services'][service]
        assert definition['build']['target'] == target
        assert definition['build']['dockerfile'] == 'docker/source.Dockerfile'
        assert not definition.get('ports'), 'Game ports must stay private'
    endpoint = config['services']['rope-ruins-web']['build']['args']['WEB_ENDPOINT']
    prefix = 'sc23-rope-check-' + uuid.uuid4().hex[:8]
    containers = []
    run('docker', 'network', 'create', prefix)
    try:
        with tempfile.TemporaryDirectory(prefix=prefix) as folder:
            folder = Path(folder)
            run(args.openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                '-subj', '/CN=sc23.site', '-addext',
                'subjectAltName=DNS:sc23.site,DNS:roperuins.sc23.site',
                '-keyout', str(folder / 'sc23.key'), '-out', str(folder / 'sc23.crt'))

            def start(suffix, *options):
                name = prefix + '-' + suffix
                containers.append(name)
                run('docker', 'run', '-d', '--name', name, '--network', prefix, *options)
                return name

            start('server', '--network-alias', 'rope-ruins', '--read-only',
                  '--tmpfs', '/tmp:size=64m,mode=1777', '--cap-drop=ALL',
                  '--security-opt=no-new-privileges:true', args.server_image)
            start('web', '--network-alias', 'rope-ruins-web', '--read-only',
                  '--tmpfs', '/tmp:size=64m,mode=1777', '--cap-drop=ALL',
                  '--security-opt=no-new-privileges:true', args.web_image)
            hosts = []
            for name in ('renting', 'padel-api', 'padel-radar', 'wise-frog', 'status', 'xml-diff'):
                hosts.extend(['--add-host', name + ':127.0.0.1'])
            proxy = start('proxy', '--publish', '127.0.0.1::443', *hosts,
                          '--mount', f'type=bind,source={ROOT / "nginx.conf"},target=/etc/nginx/conf.d/default.conf,readonly',
                          '--mount', f'type=bind,source={ROOT / "html"},target=/usr/share/nginx/html,readonly',
                          '--mount', f'type=bind,source={folder},target=/etc/nginx/ssl,readonly',
                          args.nginx_image)
            port = int(run('docker', 'port', proxy, '443/tcp').rsplit(':', 1)[1])
            tls = ssl.create_default_context(cafile=str(folder / 'sc23.crt'))

            def request(host, path, origin=None, method='GET'):
                with socket.create_connection(('127.0.0.1', port), timeout=5) as connection:
                    with tls.wrap_socket(connection, server_hostname=host) as secure:
                        headers = f'{method} {path} HTTP/1.1\r\nHost: {host}\r\n'
                        if origin is not None:
                            headers += ('Upgrade: websocket\r\nConnection: Upgrade\r\n'
                                        'Sec-WebSocket-Version: 13\r\n'
                                        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n')
                            if origin:
                                headers += f'Origin: {origin}\r\n'
                        else:
                            headers += 'Connection: close\r\n'
                        secure.sendall((headers + '\r\n').encode())
                        response = b''
                        while b'\r\n\r\n' not in response:
                            chunk = secure.recv(8192)
                            if not chunk:
                                break
                            response += chunk
                        if origin is None and method != 'HEAD':
                            while chunk := secure.recv(8192):
                                response += chunk
                        return int(response.split(b' ', 2)[1]), response

            deadline = time.monotonic() + 30
            while True:
                try:
                    if request('roperuins.sc23.site', '/healthz')[0] == 200:
                        break
                except OSError:
                    pass
                assert time.monotonic() < deadline, 'Web service did not become ready'
                time.sleep(0.2)
            run('docker', 'exec', proxy, 'nginx', '-t')
            assert request('sc23.site', '/')[0] == 200
            status, page = request('roperuins.sc23.site', '/')
            assert status == 200 and b'canvas' in page
            status, settings = request('roperuins.sc23.site', '/server.js')
            assert status == 200 and endpoint.encode() in settings
            assert request('roperuins.sc23.site', '/index.wasm', method='HEAD')[0] == 200
            for origin in ('https://roperuins.sc23.site', 'https://sc23.site',
                           'https://roperuins.sc23.local', 'https://sc23.local',
                           'https://html.itch.zone', 'https://html-classic.itch.zone'):
                assert request('sc23.site', '/rope/', origin)[0] == 101, origin
            for origin in ('https://evil.example', 'null', ''):
                assert request('sc23.site', '/rope/', origin)[0] == 403, origin
            print('PASS: SC23 Compose contract, HTTPS web/WASM, endpoint, real WSS upgrades and Origin rejection')
    finally:
        for container in reversed(containers):
            subprocess.run(['docker', 'rm', '-f', container], capture_output=True)
        subprocess.run(['docker', 'network', 'rm', prefix], capture_output=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openssl', default='openssl')
    parser.add_argument('--server-image', default='sc23-rope-ruins:local')
    parser.add_argument('--web-image', default='sc23-rope-ruins-web:local')
    parser.add_argument('--nginx-image', default='nginx:alpine')
    main(parser.parse_args())
