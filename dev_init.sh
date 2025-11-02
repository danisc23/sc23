#!/bin/bash

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 is not installed. Please install it first."
        echo "For $1: $2"
        exit 1
    fi
}

echo "Checking dependencies..."

check_dependency "brew" "Install Homebrew from https://brew.sh/"
check_dependency "git" "Install Git with: sudo apt install git (on Ubuntu/Debian) or brew install git"
check_dependency "mkcert" "Install mkcert with: brew install mkcert nss && mkcert -install"
check_dependency "docker" "Install Docker from https://docs.docker.com/get-docker/ or brew install docker"
check_dependency "docker-compose" "Install Docker Compose with: sudo apt install docker-compose (or use 'docker compose' if integrated) or brew install docker-compose"

echo "All dependencies are installed. Proceeding..."

echo "Pulling projects..."
if ! ./pull_projects.sh; then
    echo "Error: Failed to pull projects."
    exit 1
fi

echo "Updating /etc/hosts..."
if ! ./update_hosts.sh; then
    echo "Error: Failed to update hosts."
    exit 1
fi

echo "Generating SSL certificates..."
if ! ./update_certs.sh; then
    echo "Error: Failed to generate certificates."
    exit 1
fi

echo "Initialization complete! You can now run 'docker-compose up -d' to start the services."