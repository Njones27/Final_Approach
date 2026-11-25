#!/bin/sh
# Behavior checks for seed-vote-queue.sh, with stand-ins for aws and node.
# Run with: sh tools/seed-vote-queue.test.sh
set -eu

script="$(cd "$(dirname "$0")" && pwd)/seed-vote-queue.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/photos"

cat > "$work/bin/aws" <<'AWS'
#!/bin/sh
echo "aws $*" >> "$LOG"
case "$*" in
    *admin-create-user*) exit "${CREATE_STATUS:-0}" ;;
    *admin-set-user-password*) exit "${SET_STATUS:-0}" ;;
esac
AWS
cat > "$work/bin/node" <<'NODE'
#!/bin/sh
echo "node $* password=${FA_TEST_PASSWORD:+set}" >> "$LOG"
NODE
chmod +x "$work/bin/aws" "$work/bin/node"
PATH="$work/bin:$PATH"
LOG="$work/log"
export PATH LOG

fail() { echo "not ok: $1"; exit 1; }

: > "$LOG"
sh "$script" beta "$work/photos" f22-,pax >/dev/null
grep -q "admin-create-user --profile fa_beta --region us-east-1 --user-pool-id us-east-1_IhyFdSJ3t --username test-poster" "$LOG" || fail "beta makes the account in the beta pool"
grep -q -- "--permanent" "$LOG" || fail "the password is permanent"
grep -q "seed-posts.mjs --stage beta --account test-poster --folder $work/photos --only f22-,pax password=set" "$LOG" || fail "the photos are posted with the password handed over"
echo "ok: beta makes the account and posts"

: > "$LOG"
CREATE_STATUS=255 sh "$script" prod "$work/photos" >/dev/null
grep -q "admin-set-user-password --profile fa_prod --region us-east-1 --user-pool-id us-east-1_fOCqYk7Xe" "$LOG" || fail "prod uses the prod pool"
grep -q "seed-posts.mjs --stage prod --account test-poster --folder $work/photos password=set" "$LOG" || fail "an account that is already there is used"
echo "ok: prod goes on when the account is already there"

: > "$LOG"
if SET_STATUS=255 sh "$script" beta "$work/photos" >/dev/null 2>&1; then fail "a failed password stops the run"; fi
if grep -q "^node" "$LOG"; then fail "nothing is posted after a failed password"; fi
echo "ok: a failed password posts nothing"

: > "$LOG"
if sh "$script" live "$work/photos" >/dev/null 2>&1; then fail "an unknown stage is refused"; fi
if sh "$script" beta "$work/missing" >/dev/null 2>&1; then fail "a missing folder is refused"; fi
[ ! -s "$LOG" ] || fail "nothing runs for a refused request"
echo "ok: a wrong stage or folder is refused"

echo "All checks passed."
