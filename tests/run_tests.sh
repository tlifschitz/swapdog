#!/bin/bash
# Tests swapdog.sh against fake sysctl/date/osascript (see tests/stubs), so they
# run the same on any Mac regardless of its actual memory state.
T=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$T")
SCRIPT=$ROOT/swapdog.sh
export PATH=$T/stubs:$PATH
pass=0; fail=0

reset_env() {
  export STATE_DIR=$(mktemp -d) NOTIFY_LOG=$(mktemp)
  export FAKE_BOOT=1000 FAKE_SWAP=1000.00M FAKE_PRESSURE=1 FAKE_TODAY=2026-10-27
  export ICON=/fake/swapdog.png STATE_SEEN_BY_DIALOG=$(mktemp)
}
run() { local n=${1:-1}; for ((k = 0; k < n; k++)); do bash "$SCRIPT" || echo "SCRIPT FAILED rc=$?"; done; }
acc() { grep '^acc=' "$STATE_DIR/state" | cut -d= -f2; }
notifs() { wc -l < "$NOTIFY_LOG" | tr -d ' '; }
check() {  # check <description> <actual> <expected>
  if [[ $2 == "$3" ]]; then pass=$((pass + 1)); echo "  ok   $1"
  else fail=$((fail + 1)); echo "  FAIL $1: got '$2', expected '$3'"; fi
}

echo "low swap, no previous state"
reset_env; run
check "acc is 0" "$(acc)" 0
check "no notification" "$(notifs)" 0

echo "swap above 6 GB adds one interval per run"
reset_env; FAKE_SWAP=7694.19M; run 3
check "acc = 3 intervals" "$(acc)" 1800

echo "exactly 6 GB doesn't count (strict threshold)"
reset_env; FAKE_SWAP=6144.00M; run
check "acc is 0" "$(acc)" 0

echo "swap reported in G"
reset_env; FAKE_SWAP=6.50G; run
check "6.50G counts as high" "$(acc)" 600

echo "warning pressure (2) with low swap counts"
reset_env; FAKE_PRESSURE=2; run
check "acc = 600" "$(acc)" 600

echo "critical pressure (4) with low swap counts"
reset_env; FAKE_PRESSURE=4; run
check "acc = 600" "$(acc)" 600

echo "notifies at 4 h, not before"
reset_env; FAKE_SWAP=7000.00M; run 23
check "23 intervals: no notification" "$(notifs)" 0
run
check "24 intervals (4 h): one notification" "$(notifs)" 1
grep -q "Woof! Swap has been at 6 GB for 4 h" "$NOTIFY_LOG"; check "message has GB and hours" $? 0
grep -q "$ICON" "$NOTIFY_LOG"; check "passes the icon path" $? 0
grep -q '^acc=14400$' "$STATE_SEEN_BY_DIALOG"; check "state is saved before the dialog" $? 0

echo "at most one notification per day"
run 10
check "still one notification" "$(notifs)" 1
FAKE_TODAY=2026-10-28; run
check "notifies again the next day" "$(notifs)" 2

echo "hysteresis: between 5 and 6 GB with normal pressure holds"
reset_env; FAKE_SWAP=7000.00M; run 5
FAKE_SWAP=5500.00M; run 3
check "acc holds" "$(acc)" 3000

echo "hysteresis: below 5 GB resets"
FAKE_SWAP=5000.00M; run
check "acc is 0" "$(acc)" 0

echo "below 5 GB but warning pressure doesn't reset"
reset_env; FAKE_SWAP=7000.00M; run 2
FAKE_SWAP=3000.00M FAKE_PRESSURE=2; run
check "acc keeps adding" "$(acc)" 1800

echo "short intermittent sessions add up until it notifies"
reset_env
for s in 1 2 3 4 5 6 7 8 9 10 11 12; do
  FAKE_SWAP=6500.00M; run 2      # 20-minute session above the threshold
  FAKE_SWAP=5800.00M; run        # drops, but not below 5 GB
done
check "12 sessions of 20 min = 4 h" "$(acc)" 14400
check "notified" "$(notifs)" 1

echo "a restart resets the counter and the daily notification"
FAKE_BOOT=2000; FAKE_SWAP=7000.00M; run
check "acc back to one interval" "$(acc)" 600
grep -q '^last_notified=$' "$STATE_DIR/state"; check "last_notified is empty" $? 0
grep -q '^last_boot=2000$' "$STATE_DIR/state"; check "stores the new boot time" $? 0

echo "plist template renders to a valid plist"
rendered=$(mktemp)
sed "s|__HOME__|/Users/someone|g" "$ROOT/com.github.tlifschitz.swapdog.plist" > "$rendered"
plutil -lint "$rendered" > /dev/null; check "plutil -lint passes" $? 0
grep -q "__HOME__" "$rendered"; check "no placeholders left" $? 1

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
