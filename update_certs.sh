#!/bin/bash

if ! command -v mkcert &> /dev/null; then
    echo "mkcert is not installed. Please install it with: brew install mkcert nss && mkcert -install"
    exit 1
fi

extract_domains() {
    grep -oP 'server_name [^;]*' nginx.conf | sed 's/server_name //' | tr ' ' '\n' | grep '\.local$' | grep -v '^\*\.' | sort | uniq
}

extract_cert_name() {
    grep 'ssl_certificate' nginx.conf | head -1 | sed 's/.*\///' | sed 's/;//'
}

extract_key_name() {
    grep 'ssl_certificate_key' nginx.conf | head -1 | sed 's/.*\///' | sed 's/;//'
}

DOMAINS=$(extract_domains)
if [ -z "$DOMAINS" ]; then
    echo "No .local domains found in nginx.conf"
    exit 1
fi

CERT_TARGET=$(extract_cert_name)
KEY_TARGET=$(extract_key_name)
if [ -z "$CERT_TARGET" ] || [ -z "$KEY_TARGET" ]; then
    echo "Could not extract certificate names from nginx.conf"
    exit 1
fi

mkcert $DOMAINS

BASE_DOMAIN=$(echo $DOMAINS | awk '{print $1}')
COUNT=$(echo $DOMAINS | wc -w)
CERT_FILE="${BASE_DOMAIN}+$(($COUNT - 1)).pem"
KEY_FILE="${BASE_DOMAIN}+$(($COUNT - 1))-key.pem"

if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    cp "$CERT_FILE" "$CERT_TARGET"
    cp "$KEY_FILE" "$KEY_TARGET"
    echo "Certificates generated and renamed to $CERT_TARGET and $KEY_TARGET"
else
    echo "Certificate files not found. Check mkcert output."
fi