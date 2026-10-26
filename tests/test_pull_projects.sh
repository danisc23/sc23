#!/usr/bin/env bash
# Exercise project updates without network access or touching real checkouts.
set -Eeuo pipefail
export PULL_TEST_ROOT
PULL_TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$PULL_TEST_ROOT"' EXIT
mkdir -p "$PULL_TEST_ROOT/repo" "$PULL_TEST_ROOT/bin"
cp /workspace/pull_projects.sh "$PULL_TEST_ROOT/repo/"
cat > "$PULL_TEST_ROOT/bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s|%s\n' "$PWD" "$*" >> "$PULL_TEST_ROOT/git.log"
if [[ $1 == clone ]]; then
    mkdir "$(basename "$2" .git)"
elif [[ $1 == -C && $3 == pull && $4 == --ff-only ]]; then
    [[ $2 != "${MOCK_GIT_FAIL:-}" ]] || exit 17
else
    echo "Unexpected Git operation: $*" >&2; exit 1
fi
EOF
chmod +x "$PULL_TEST_ROOT/bin/git"
export PATH="$PULL_TEST_ROOT/bin:$PATH"
cd /tmp
bash "$PULL_TEST_ROOT/repo/pull_projects.sh" > "$PULL_TEST_ROOT/output"
[[ -d "$PULL_TEST_ROOT/repo/projects/hook-rush" ]]
[[ $(wc -l < "$PULL_TEST_ROOT/git.log") == 7 ]]
bash "$PULL_TEST_ROOT/repo/pull_projects.sh" > "$PULL_TEST_ROOT/output"
grep -Fq '|-C hook-rush pull --ff-only' "$PULL_TEST_ROOT/git.log"
if MOCK_GIT_FAIL=hook-rush bash "$PULL_TEST_ROOT/repo/pull_projects.sh" > "$PULL_TEST_ROOT/output"; then
    echo 'Project update ignored a Git failure' >&2; exit 1
fi
if grep -q 'All projects updated' "$PULL_TEST_ROOT/output"; then
    echo 'Project update reported success after a Git failure' >&2; exit 1
fi
echo 'PASS: project clone, fast-forward update, external working directory and Git failure'
