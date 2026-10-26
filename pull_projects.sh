#!/usr/bin/env bash
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

GITHUB_USER="git@github.com:danisc23"

PROJECTS=(
  "$GITHUB_USER/renting-data-generator.git"
  "$GITHUB_USER/padel-tavernes.git"
  "$GITHUB_USER/padel-radar-app.git"
  "$GITHUB_USER/wise-frog.git"
  "$GITHUB_USER/docker-stats-fastapi.git"
  "$GITHUB_USER/xml-diff-comparator.git"
  "$GITHUB_USER/hook-rush.git"
)

mkdir -p projects
cd projects

for PROJECT in "${PROJECTS[@]}"; do
  PROJECT_NAME=$(basename "$PROJECT" .git)

  if [ -d "$PROJECT_NAME" ]; then
    echo "Pulling: $PROJECT_NAME"
    git -C "$PROJECT_NAME" pull --ff-only
  else
    echo "New project found, Cloning: $PROJECT_NAME"
    git clone "$PROJECT"
  fi
done

echo "All projects updated"
