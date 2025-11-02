#!/bin/bash

extract_domains() {
    grep -oP 'server_name [^;]*' nginx.conf | sed 's/server_name //' | tr ' ' '\n' | grep '\.local$' | grep -v '^\*\.' | sort | uniq
}

extract_base_domain() {
    grep -oP 'server_name [^;]*' nginx.conf | sed 's/server_name //' | tr ' ' '\n' | grep '\.local$' | grep -v '^\*\.' | head -1
}

BASE_DOMAIN=$(extract_base_domain)
if [ -z "$BASE_DOMAIN" ]; then
    echo "No base .local domain found in nginx.conf"
    exit 1
fi

DOMAINS=$(extract_domains)

sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

sudo sed -i "/127\.0\.0\.1.*${BASE_DOMAIN}/d" /etc/hosts

for domain in $DOMAINS; do
    echo "127.0.0.1       $domain" | sudo tee -a /etc/hosts > /dev/null
done

echo "Updated /etc/hosts with domains for base $BASE_DOMAIN: $DOMAINS"