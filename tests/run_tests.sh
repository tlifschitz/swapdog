#!/bin/bash
# Tests swapdog.sh against fake sysctl/date/osascript (see tests/stubs), so they
# run the same on any Mac regardless of its actual memory state or uptime.
T=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$T")
SCRIPT=$ROOT/swapdog.sh
export PATH=$T/stubs:$PATH
pass=0; fail=0

reset_env() {
  export STATE_DIR=$(mktemp -d) NOTIFY_LOG=$(mktemp) STATE_SEEN_BY_DIALOG=$(mktemp)
  export FAKE_BOOT=1000 FAKE_PRESSURE=1 FAKE_TODAY=2026-10-27 ICON=/fake/swapdog.png PLIST=/nonexistent
  unset SWAPDOG_PRESSURE_LIMIT_MIN SWAPDOG_UPTIME_DAYS SWAPDOG_UPTIME_REPEAT_DAYS
  up 1
}
up() { export FAKE_NOW=$((FAKE_BOOT + $1 * 86400 + 3600)); }  # up <days since boot>
run() { local n=${1:-1}; for ((k = 0; k < n; k++)); do bash "$SCRIPT" || echo "SCRIPT FAILED rc=$?"; done; }
acc() { grep '^acc=' "$STATE_DIR/state" | cut -d= -f2; }
barks() { wc -l < "$NOTIFY_LOG" | tr -d ' '; }
uptime_barks() { grep -c "since your last restart" "$NOTIFY_LOG"; }
check() {  # check <description> <actual> <expected>
  if [[ $2 == "$3" ]]; then pass=$((pass + 1)); echo "  ok   $1"
  else fail=$((fail + 1)); echo "  FAIL $1: got '$2', expected '$3'"; fi
}

echo "normal pressure, no previous state"
reset_env; run
check "acc is 0" "$(acc)" 0
check "no bark" "$(barks)" 0

echo "warning (2) and critical (4) pressure fill the bucket"
reset_env; FAKE_PRESSURE=2; run 2; FAKE_PRESSURE=4; run
check "acc = 3 intervals" "$(acc)" 1800

echo "normal pressure drains the bucket, never below 0"
FAKE_PRESSURE=1; run 2
check "acc = 1 interval" "$(acc)" 600
run 3
check "acc stops at 0" "$(acc)" 0

echo "barks after 1 h of high pressure, not before"
reset_env; FAKE_PRESSURE=2; run 5
check "50 min: no bark" "$(barks)" 0
run
check "60 min: one bark" "$(barks)" 1
grep -q "short on memory for 60 minutes" "$NOTIFY_LOG"; check "pressure message" $? 0
grep -q "$ICON" "$NOTIFY_LOG"; check "passes the icon path" $? 0
grep -q '^acc=3600$' "$STATE_SEEN_BY_DIALOG"; check "state is saved before the dialog" $? 0

echo "pressure bark at most once per day"
run 10
check "still one bark" "$(barks)" 1
FAKE_TODAY=2026-10-28; run
check "barks again the next day" "$(barks)" 2

echo "short dips don't erase the progress"
reset_env
FAKE_PRESSURE=2; run 5; FAKE_PRESSURE=1; run 2; FAKE_PRESSURE=2; run 3
check "5 up, 2 down, 3 up = 6 intervals" "$(acc)" 3600
check "barked" "$(barks)" 1

echo "uptime bark at 14 days, then every 7"
reset_env; up 13; run
check "13 days: no bark" "$(barks)" 0
up 14; run
check "14 days: one bark" "$(uptime_barks)" 1
grep -q "it's been 14 days since your last restart. A fresh start and a walk in the park" "$NOTIFY_LOG"
check "uptime message" $? 0
up 15; run; up 20; run
check "15-20 days: no new bark" "$(uptime_barks)" 1
up 21; run
check "21 days: second bark" "$(uptime_barks)" 2

echo "uptime bark waits while pressure is high"
reset_env; up 30; FAKE_PRESSURE=2; run
check "no uptime bark under pressure" "$(uptime_barks)" 0
FAKE_PRESSURE=1; run
check "barks once pressure is normal" "$(uptime_barks)" 1

echo "no uptime bark on a day the pressure bark went off"
reset_env; up 30; FAKE_PRESSURE=2; run 6
check "pressure barked" "$(barks)" 1
FAKE_PRESSURE=1; run 10
check "same day: no uptime bark" "$(uptime_barks)" 0
FAKE_TODAY=2026-10-28; run
check "next day: uptime bark" "$(uptime_barks)" 1

echo "a restart resets everything"
reset_env; up 14; FAKE_PRESSURE=2; run 6
FAKE_BOOT=2000000; up 0; run
check "acc starts over at one interval" "$(acc)" 600
grep -q '^last_pressure_bark=$' "$STATE_DIR/state"; check "pressure bark forgotten" $? 0
grep -q '^last_uptime_bark_days=$' "$STATE_DIR/state"; check "uptime bark forgotten" $? 0
grep -q '^last_boot=2000000$' "$STATE_DIR/state"; check "stores the new boot time" $? 0

echo "settings can be overridden"
reset_env; export SWAPDOG_PRESSURE_LIMIT_MIN=20; FAKE_PRESSURE=2; run 2
check "pressure limit of 20 min" "$(barks)" 1
reset_env; export SWAPDOG_UPTIME_DAYS=3 SWAPDOG_UPTIME_REPEAT_DAYS=1; up 3; run; up 4; run
check "uptime of 3 days, repeating daily" "$(uptime_barks)" 2

echo "history keeps one line per check, up to a limit"
reset_env; FAKE_PRESSURE=2; run 2; FAKE_PRESSURE=1; run
check "three lines" "$(wc -l < "$STATE_DIR/history" | tr -d ' ')" 3
check "last line has pressure and acc" "$(tail -1 "$STATE_DIR/history" | cut -d' ' -f3-)" "pressure=1 acc=600"
HISTORY_LINES=2 run
check "trimmed to the limit" "$(wc -l < "$STATE_DIR/history" | tr -d ' ')" 2

fake_history() {  # fake_history <green checks> <yellow checks>, yellow ones peaking at 30 min
  for ((k = 0; k < $1; k++)); do echo "2026-10-27 10:00 pressure=1 acc=0"; done > "$STATE_DIR/history"
  for ((k = 1; k <= $2; k++)); do echo "2026-10-27 11:00 pressure=2 acc=$(( (k % 3 + 1) * 600 ))"; done >> "$STATE_DIR/history"
}
status() { bash "$SCRIPT" status; }

echo "status doesn't change anything"
reset_env; FAKE_PRESSURE=2; run
before=$(cat "$STATE_DIR/state" "$STATE_DIR/history")
status > /dev/null
check "state and history untouched" "$(cat "$STATE_DIR/state" "$STATE_DIR/history")" "$before"

echo "status shows the current readings"
reset_env; up 22; FAKE_PRESSURE=2; run 2
out=$(status)
grep -q "yellow right now, bucket at 20 of 60 minutes" <<< "$out"; check "pressure and bucket" $? 0
grep -q "22 days, restart reminder due once memory pressure is green" <<< "$out"; check "overdue uptime reminder" $? 0
FAKE_PRESSURE=1; FAKE_TODAY=2026-10-28; run
status | grep -q "22 days, next restart reminder at 29 days"; check "next uptime reminder" $? 0

echo "status right after a restart"
reset_env; FAKE_NOW=$((FAKE_BOOT + 5400)); run
status | grep -q "just restarted, 1 hour ago. Good human"; check "uptime in hours" $? 0

echo "status verdicts"
reset_env
status | grep -q "hasn't sniffed anything yet"; check "no checks yet" $? 0
run 2
out=$(status)
grep -q "Watched:         20 minutes awake, 0 minutes of it" <<< "$out"; check "watched time in minutes" $? 0
grep -q "swapdog is new here: it started watching on 20" <<< "$out"; check "just installed" $? 0
reset_env; run; fake_history 200 0
status | grep -q "hasn't struggled with memory all week"; check "all green" $? 0
reset_env; run; fake_history 200 12
out=$(status)
grep -q "Watched:         35 hours awake, 2 hours of it in yellow or red" <<< "$out"; check "counts yellow time" $? 0
grep -q "never got past 30 of 60 minutes" <<< "$out"; check "some yellow, no bark" $? 0
reset_env; FAKE_PRESSURE=2; run 6
status | grep -q "It barked on 2026-10-27"; check "explains a bark" $? 0

echo "status reads settings from the installed plist"
reset_env; run
sed "s|__HOME__|/Users/someone|; s|<string>60</string>|<string>20</string>|" \
  "$ROOT/com.github.tlifschitz.swapdog.plist" > "$STATE_DIR/swapdog.plist"
PLIST=$STATE_DIR/swapdog.plist status | grep -q "of 20 minutes"; check "limit from the plist" $? 0

echo "unknown arguments are rejected"
bash "$SCRIPT" bogus 2> /dev/null; check "exit code 2" $? 2

install() {  # install <answer>, into a fake home with ~/.local/bin off the PATH
  echo "$1" | HOME=$FAKE_HOME SHELL=/bin/zsh PATH=$T/stubs:/usr/bin:/bin bash "$ROOT/install.sh" > /dev/null
}
path_lines() { grep -c '.local/bin' "$FAKE_HOME/.zshrc" 2>/dev/null; }

echo "install offers to add ~/.local/bin to the PATH"
FAKE_HOME=$(mktemp -d); install n
check "answering no leaves .zshrc alone" "$(path_lines)" ""
install y
check "answering yes adds it" "$(path_lines)" 1
install y
check "installing again doesn't duplicate it" "$(path_lines)" 1
FAKE_HOME=$(mktemp -d)
echo y | HOME=$FAKE_HOME SHELL=/bin/zsh PATH=$FAKE_HOME/.local/bin:$T/stubs:/usr/bin:/bin bash "$ROOT/install.sh" > /dev/null
check "doesn't ask when it's already on the PATH" "$(path_lines)" ""
check "installs the script" "$([[ -x $FAKE_HOME/.local/bin/swapdog ]] && echo yes)" yes
check "renders the plist" "$(grep -c "$FAKE_HOME/.local/bin/swapdog" "$FAKE_HOME/Library/LaunchAgents/com.github.tlifschitz.swapdog.plist")" 1

echo "plist template renders to a valid plist"
rendered=$(mktemp)
sed "s|__HOME__|/Users/someone|g" "$ROOT/com.github.tlifschitz.swapdog.plist" > "$rendered"
plutil -lint "$rendered" > /dev/null; check "plutil -lint passes" $? 0
grep -q "__HOME__" "$rendered"; check "no placeholders left" $? 1

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
