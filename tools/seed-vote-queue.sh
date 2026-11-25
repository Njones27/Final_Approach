#!/bin/sh
# Fills a stage's vote queue in one step. It makes the test account
# test-poster in the stage's user pool, gives it a random password that is
# used once and kept nowhere, and posts a folder of JPEGs from it with
# seed-posts.mjs. Nobody is shown their own photos, so the poster is an
# account of its own. See "Photos to vote on" in docs/backend.md.
#
# Usage: tools/seed-vote-queue.sh <beta|prod> <folder> [name starts, comma separated]
set -eu

stage="${1:-}"
folder="${2:-}"
only="${3:-}"
account="test-poster"
region="us-east-1"

# The user pool of each stage. These are in docs/backend.md and are not secrets.
case "$stage" in
    beta) pool="us-east-1_IhyFdSJ3t" ;;
    prod) pool="us-east-1_fOCqYk7Xe" ;;
    *)
        echo "Usage: tools/seed-vote-queue.sh <beta|prod> <folder> [name starts, comma separated]" >&2
        exit 2
        ;;
esac
if [ ! -d "$folder" ]; then
    echo "Name the folder of photos after the stage." >&2
    exit 2
fi
profile="fa_${stage}"

# The pool asks for a capital, a small letter, a digit, and a symbol.
password="$(openssl rand -base64 24)Aa1!"

# The account may be there from an earlier run, which is fine.
if aws cognito-idp admin-create-user --profile "$profile" --region "$region" \
    --user-pool-id "$pool" --username "$account" --message-action SUPPRESS >/dev/null 2>&1; then
    echo "Made the account ${account} on ${stage}."
else
    echo "Using the account ${account} on ${stage}."
fi
if ! aws cognito-idp admin-set-user-password --profile "$profile" --region "$region" \
    --user-pool-id "$pool" --username "$account" --password "$password" --permanent; then
    echo "The account could not be set up. If the sign in ran out, run: aws login --profile ${profile}" >&2
    exit 1
fi

here="$(cd "$(dirname "$0")" && pwd)"
set -- --stage "$stage" --account "$account" --folder "$folder"
if [ -n "$only" ]; then
    set -- "$@" --only "$only"
fi
FA_TEST_PASSWORD="$password" node "$here/seed-posts.mjs" "$@"
