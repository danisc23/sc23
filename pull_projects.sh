#!/bin/bash

GITHUB_USER="git@github.com:danisc23"

PROJECTS=(
  "$GITHUB_USER/renting-data-generator.git"
  "$GITHUB_USER/padel-tavernes.git"
  "$GITHUB_USER/padel-radar-app.git"
  "$GITHUB_USER/wise-frog.git"
  "$GITHUB_USER/docker-stats-fastapi.git"
)

mkdir -p projects
cd projects

for PROJECT in "${PROJECTS[@]}"; do
  PROJECT_NAME=$(basename "$PROJECT" .git)

  if [ -d "$PROJECT_NAME" ]; then
    echo "Pulling: $PROJECT_NAME"
    cd "$PROJECT_NAME"
    git pull
    cd ..
  else
    echo "New project found, Cloning: $PROJECT_NAME"
    git clone "$PROJECT"
  fi
done

echo "All projects updated"