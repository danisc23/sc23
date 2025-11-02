#!/bin/bash

SERVICE=$1
shift

if [ -z "$SERVICE" ]; then
    echo "Usage: ./logs.sh <service_name> [options]"
    echo "Options: --tail N, --since TIME, -f (follow)"
    echo "Example: ./logs.sh nginx -f --tail 100"
    exit 1
fi

docker-compose logs "$SERVICE" "$@"