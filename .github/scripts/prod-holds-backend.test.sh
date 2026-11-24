#!/bin/bash
# Behavior checks for prod-holds-backend.sh. It builds a small repository
# with a backend and an app, and runs the script for each case. PROD_SHA
# stands in for the answer GitHub would give.

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/prod-holds-backend.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

git init --quiet --bare "${WORK}/origin.git"
# Lets a clone fetch a commit by its id, as GitHub does.
git -C "${WORK}/origin.git" config uploadpack.allowAnySHA1InWant true
git init --quiet "${WORK}/repo"
cd "${WORK}/repo"
git config user.name "Check"
git config user.email "check@example.com"
git remote add origin "${WORK}/origin.git"

commit() {
    git add -A
    git commit --quiet -m "$1"
    git push --quiet origin HEAD:refs/heads/main
    git rev-parse HEAD
}

mkdir -p backend FinalApproach Packages docs
echo one > backend/api.ts
echo one > FinalApproach/App.swift
echo one > Packages/Core.swift
echo one > docs/page.md
first="$(commit "first")"

expect() {
    local wanted="$1" name="$2"
    shift 2
    local status=0
    "$@" > "${WORK}/out.txt" 2>&1 || status=$?
    if [ "${status}" -ne "${wanted}" ]; then
        echo "FAILED: ${name}. Expected exit ${wanted}, got ${status}."
        cat "${WORK}/out.txt"
        exit 1
    fi
    echo "ok: ${name}"
}

# A docs change never waits, even when prod cannot be found.
echo two > docs/page.md
docs="$(commit "docs")"
expect 0 "a docs change does not wait for prod" \
    env PROD_SHA=0000000000000000000000000000000000000000 "${SCRIPT}" "${first}" "${docs}"

# An app change merges while prod holds the backend on main.
echo two > FinalApproach/App.swift
app="$(commit "app")"
expect 0 "an app change merges when prod is up to date" \
    env PROD_SHA="${first}" "${SCRIPT}" "${docs}" "${app}"

# A backend change by itself never waits.
echo two > backend/api.ts
backend="$(commit "backend")"
expect 0 "a backend change does not wait for prod" \
    env PROD_SHA="${first}" "${SCRIPT}" "${app}" "${backend}"

# An app change is stopped while prod is behind main.
echo three > Packages/Core.swift
late="$(commit "core package")"
expect 1 "an app change is stopped while prod is behind" \
    env PROD_SHA="${first}" "${SCRIPT}" "${backend}" "${late}"
grep -q "Prod is behind" "${WORK}/out.txt"

# The same change merges once prod has the backend.
expect 0 "the same change merges once prod has caught up" \
    env PROD_SHA="${backend}" "${SCRIPT}" "${backend}" "${late}"

# Prod deployed from a later commit with the same backend still counts.
expect 0 "a later commit with the same backend counts" \
    env PROD_SHA="${late}" "${SCRIPT}" "${backend}" "${late}"

# The app and the backend never change in one pull request.
echo three > backend/api.ts
echo three > FinalApproach/App.swift
both="$(commit "both")"
expect 1 "the app and the backend cannot change together" \
    env PROD_SHA="${late}" "${SCRIPT}" "${late}" "${both}"
grep -q "together" "${WORK}/out.txt"

# With no deploy to find, an app change is stopped. A stand in for gh that
# finds nothing takes the place of the real one.
mkdir -p "${WORK}/bin"
printf '#!/bin/bash\nexit 1\n' > "${WORK}/bin/gh"
chmod +x "${WORK}/bin/gh"
echo four > FinalApproach/App.swift
unknown="$(commit "app again")"
expect 1 "an app change is stopped when prod cannot be found" \
    env PROD_SHA= GITHUB_REPOSITORY=none/none PATH="${WORK}/bin:${PATH}" "${SCRIPT}" "${both}" "${unknown}"
grep -q "No deploy to prod" "${WORK}/out.txt"

# A docs change still passes when GitHub cannot be asked.
echo three > docs/page.md
quiet="$(commit "docs again")"
expect 0 "a docs change passes when prod cannot be found" \
    env PROD_SHA= GITHUB_REPOSITORY=none/none PATH="${WORK}/bin:${PATH}" "${SCRIPT}" "${unknown}" "${quiet}"

echo "All checks passed."
