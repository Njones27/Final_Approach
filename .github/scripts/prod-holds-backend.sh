#!/bin/bash
# prod-holds-backend.sh
#
# Keeps the app from getting ahead of the prod backend.
#
# A merge that changes the app starts an Xcode Cloud build, and that build
# goes to TestFlight and talks to prod. The prod backend only changes when
# the owner approves a Release run. So a pull request that changes the
# app may merge only when the backend it would leave on main is the one prod
# already holds. A backend change goes in its own pull request first, and is
# approved to prod, before the app change that needs it.
#
# Usage: prod-holds-backend.sh <base> <head>
#   base  the commit of main the pull request would merge into
#   head  the result of that merge
#
# PROD_SHA names the commit prod was last deployed from. When it is not set,
# the script asks GitHub for the last deploy to the prod environment that
# passed, which needs gh, GH_TOKEN, and GITHUB_REPOSITORY.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: prod-holds-backend.sh <base> <head>" >&2
    exit 2
fi
BASE="$1"
HEAD_COMMIT="$2"

# The folders whose changes start an Xcode Cloud build. Keep these in step
# with the start condition of the TestFlight workflow in docs/ci-cd.md.
APP_PATHS=(FinalApproach Packages)
BACKEND_PATH=backend

say() {
    echo "$1"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "$1" >> "${GITHUB_STEP_SUMMARY}"
    fi
}

# The commit of the newest deploy to prod that passed. GitHub lists deploys
# newest first, and marks an older one inactive once a newer one passes.
find_prod_sha() {
    local id sha state
    while read -r id sha; do
        state="$(gh api "repos/${GITHUB_REPOSITORY}/deployments/${id}/statuses?per_page=1" --jq '.[0].state // "none"')"
        if [ "${state}" = "success" ]; then
            echo "${sha}"
            return 0
        fi
    done < <(gh api "repos/${GITHUB_REPOSITORY}/deployments?environment=prod&per_page=30" --jq '.[] | "\(.id) \(.sha)"')
    return 1
}

app_changed=false
if ! git diff --quiet "${BASE}" "${HEAD_COMMIT}" -- "${APP_PATHS[@]}"; then
    app_changed=true
fi
backend_changed=false
if ! git diff --quiet "${BASE}" "${HEAD_COMMIT}" -- "${BACKEND_PATH}"; then
    backend_changed=true
fi

# 1. A pull request that leaves the app alone starts no app build.
if [ "${app_changed}" = false ]; then
    say "This pull request does not change the app, so it does not wait for prod."
    # Shown for the record. Nothing here depends on it.
    if [ -z "${PROD_SHA:-}" ] && seen="$(find_prod_sha 2>/dev/null)" && [ -n "${seen}" ]; then
        say "Prod was last deployed from ${seen}."
    fi
    exit 0
fi

# 2. The app and the backend never change together.
if [ "${backend_changed}" = true ]; then
    say "This pull request changes the app and the backend together."
    say "Merging it would send the app to TestFlight before prod has the backend it needs."
    say "Move the backend change to its own pull request, merge it, and approve its deploy to prod. Then merge the app change."
    exit 1
fi

# 3. Prod must already hold the backend that is on main.
prod_sha="${PROD_SHA:-}"
if [ -z "${prod_sha}" ]; then
    if ! prod_sha="$(find_prod_sha)" || [ -z "${prod_sha}" ]; then
        say "No deploy to prod that passed was found, so this cannot tell what prod holds."
        say "Run the Release workflow with the stage prod, approve it, and run this check again."
        exit 1
    fi
fi

git fetch --quiet --depth=1 origin "${prod_sha}"
prod_backend="$(git rev-parse "${prod_sha}:${BACKEND_PATH}")"
this_backend="$(git rev-parse "${HEAD_COMMIT}:${BACKEND_PATH}")"

if [ "${prod_backend}" != "${this_backend}" ]; then
    say "Prod is behind. It was last deployed from ${prod_sha}, and main holds a newer backend."
    say "Approve the waiting Release run, or start one with the stage prod. When prod has passed, run this check again."
    exit 1
fi

say "Prod holds the backend that is on main, deployed from ${prod_sha}. This app change can merge."
